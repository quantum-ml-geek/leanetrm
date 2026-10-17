using System.Collections.Immutable;
using Npgsql;
using OpenEtrm.MarketData;

namespace OpenEtrm.Api;

public sealed record MarketContextRequest(string? EffectiveOn,string? KnownAt,string? Mode,string? Selection);

// Selection is deliberately separate from certification. A certified timestamp
// does not authorize choosing a source, filling a gap or rolling a contract.
public static class MarketContextStore
{
    public static async Task Bind(NpgsqlConnection connection,Guid catalog,ScheduleContext context,CancellationToken ct)
    {
        await using var command=ScheduleStore.Command(connection,"SELECT security.use_market_context($1,$2)",catalog,context.ContextId!);
        await command.ExecuteNonQueryAsync(ct);
    }

    public static InputFrame Select(InputFrame seed,PreviewData data,ScheduleContext context)
    {
        var selected=seed.ObservationIds.Select(id=>
        {
            var current=data.Observation(id);
            while(true)
            {
                var successors=data.Observations.Where(o=>o.OptionalId("corrects_id")==current.Id("id")).ToArray();
                if(successors.Length==0)return current.Id("id");
                if(successors.Length!=1)throw new MarketDataException("revision_conflict","An observation has conflicting correction successors.");
                current=successors[0];
            }
        }).ToImmutableArray();
        return seed with {Id=Guid.NewGuid(),Name="Certified market inputs",ObservationIds=selected,ContextId=context.ContextId};
    }
}
