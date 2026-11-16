using Npgsql;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

public sealed record RetainedSideSource(Guid SnapshotId,Guid ContextId,DateTimeOffset AsOf,DateOnly BusinessDate,DateTimeOffset KnownAt)
{
    internal static RetainedSideSource From(InputFrame frame,ScheduleContext context)
    {
        if(frame.ContextId is not {} id||id!=context.ContextId||frame.BusinessDate!=DateWorkspace.Date(context.EffectiveOn))throw PinnedContext.Missing();
        return new(frame.Id,id,frame.At,frame.BusinessDate,TradingInstant.Parse(context.KnownAt!,"position_context"));
    }
}

// The exact operating-terms path preserves its original physical authority
// alongside the common financial-read authority, through the final commit.
internal sealed record OperatingSideReadAdmission(DateTimeOffset Until):ICommitAdmission
{
    internal static async Task Capture(NpgsqlConnection connection,PreviewDatabase database,CancellationToken ct)
    {
        await using var query=ScheduleStore.Command(connection,"""
            SELECT min(until_at) FROM(VALUES(security.authority_until('ReadPhysical')),
              (security.authority_until('ReadTrades')),(security.authority_until('ReadMarketData')))v(until_at)
            HAVING count(until_at)=3 AND bool_and(isfinite(until_at) AND until_at>clock_timestamp())
            """);
        if(await query.ExecuteScalarAsync(ct) is not DateTime until)throw new PreviewDeniedException();
        var admission=new OperatingSideReadAdmission(new DateTimeOffset(until));database.RegisterCommitAdmission(connection,admission);
        await admission.RequireCommit(connection,ct);
    }
    public async Task RequireCommit(NpgsqlConnection connection,CancellationToken ct)
    {
        await using var query=ScheduleStore.Command(connection,"""
            SELECT clock_timestamp()<$1 AND security.has_permission('ReadPhysical')
              AND security.has_permission('ReadTrades') AND security.has_permission('ReadMarketData')
            """,Until);
        if(!Equals(await query.ExecuteScalarAsync(ct),true))throw new PreviewDeniedException();
    }
}
