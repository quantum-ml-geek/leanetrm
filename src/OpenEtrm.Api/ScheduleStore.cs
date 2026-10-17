using System.Collections.Immutable;
using System.Text.Json;
using Npgsql;
using OpenEtrm.Shared.Temporal;

namespace OpenEtrm.Api;

public sealed class ScheduleStore(Guid catalog)
{
    private static readonly JsonSerializerOptions Json=new(JsonSerializerDefaults.Web);
    internal static NpgsqlCommand Command(NpgsqlConnection connection,string sql,params object[] args)
    {
        var command=new NpgsqlCommand(sql,connection);
        foreach(var arg in args)command.Parameters.Add(new NpgsqlParameter{Value=arg});return command;
    }
    public async Task<ImmutableArray<ScheduleVersion>> Read(NpgsqlConnection connection,CancellationToken ct)
    {
        await using var command=Command(connection,"SELECT schedule_id,version,generation,state,definition::text,selection,effective_from,effective_to,publication_order,published_at,engine_version FROM market_data.date_schedule_versions WHERE catalog_id=$1 ORDER BY schedule_id,version",catalog);
        await using var reader=await command.ExecuteReaderAsync(ct);var result=ImmutableArray.CreateBuilder<ScheduleVersion>();
        while(await reader.ReadAsync(ct))result.Add(new(reader.GetGuid(0),reader.GetInt32(1),reader.GetInt32(2),reader.GetString(3),
            JsonSerializer.Deserialize<MonthlyDraft>(reader.GetString(4),Json)!,reader.GetString(5),reader.GetFieldValue<DateOnly>(6),reader.GetFieldValue<DateOnly>(7),
            reader.IsDBNull(8)?null:reader.GetInt32(8),reader.IsDBNull(9)?null:reader.GetFieldValue<DateTimeOffset>(9),reader.GetString(10)));
        return result.ToImmutable();
    }
    public async Task<ImmutableArray<ScheduleVersion>> ReadAt(NpgsqlConnection connection,ScheduleContext context,CancellationToken ct)
    {
        await using var command=Command(connection,"SELECT schedule_id,version,generation,state,definition::text,selection,effective_from,effective_to,publication_order,published_at,engine_version,known_from,known_to FROM market_data.date_schedule_facts_at($1,$4) WHERE catalog_id=$1 AND effective_from<=$2 AND $2<effective_to AND known_from<=$3 AND $3<known_to ORDER BY schedule_id,version",
            catalog,DateWorkspace.Date(context.EffectiveOn),SchedulePreview.ParseAt(context.KnownAt),context.KnownThrough!.Value);
        await using var reader=await command.ExecuteReaderAsync(ct);var result=ImmutableArray.CreateBuilder<ScheduleVersion>();
        while(await reader.ReadAsync(ct))
        {
            var from=reader.GetFieldValue<DateOnly>(6);var to=reader.GetFieldValue<DateOnly>(7);
            result.Add(new(reader.GetGuid(0),reader.GetInt32(1),reader.GetInt32(2),reader.GetString(3),
                JsonSerializer.Deserialize<MonthlyDraft>(reader.GetString(4),Json)!,reader.GetString(5),from,to,reader.GetInt32(8),
                reader.GetFieldValue<DateTimeOffset>(9),reader.GetString(10),new(from,to,reader.GetFieldValue<DateTimeOffset>(11),reader.GetFieldValue<DateTimeOffset>(12))));
        }
        return result.ToImmutable();
    }
    public async Task<int> Capture(NpgsqlConnection connection,CancellationToken ct)
    {
        await using(var gate=Command(connection,"SELECT pg_advisory_xact_lock(730849102)"))await gate.ExecuteNonQueryAsync(ct);
        await using var command=Command(connection,"SELECT coalesce(max(publication_order),0) FROM market_data.date_schedule_versions WHERE catalog_id=$1",catalog);
        return (int)(await command.ExecuteScalarAsync(ct))!;
    }
    public async Task<ScheduleVersion> Save(NpgsqlConnection connection,ScheduleSaveRequest body,CancellationToken ct)
    {
        PublishedSchedules.Validate(body);
        // One catalog lock serializes create/fork and quota admission across sessions.
        await using(var gate=Command(connection,"SELECT pg_advisory_xact_lock(730849103)"))await gate.ExecuteNonQueryAsync(ct);
        var all=await Read(connection,ct);Guid id;int version,generation;
        if(body.Id is null)
        {
            if(body.Version is not null || body.Generation is not null || body.ExpectedState is not null || all.Select(v=>v.Id).Distinct().Count()>=32)
                throw Error("schedule_conflict","Create a new schedule without an existing version; maximum 32 schedules.");
            id=Guid.NewGuid();version=1;generation=1;
            await using var insert=Command(connection,"INSERT INTO market_data.date_schedules VALUES($1,$2,$3)",catalog,id,body.Definition.Symbol!);
            await insert.ExecuteNonQueryAsync(ct);
        }
        else
        {
            id=body.Id.Value;var old=all.SingleOrDefault(v=>v.Id==id&&v.Version==body.Version);
            if(old is null || old.State!=body.ExpectedState || old.Generation!=body.Generation || old.Definition.Symbol!=body.Definition.Symbol)
                throw Error("schedule_conflict","The selected version changed or its reference identity differs. Reload before editing.");
            if(old.State=="published")
            {
                if(all.Any(v=>v.Id==id&&v.State=="draft"))throw Error("schedule_conflict","This schedule already has a draft. Open that draft.");
                version=all.Where(v=>v.Id==id).Max(v=>v.Version)+1;generation=1;
            }
            else {version=old.Version;generation=old.Generation+1;}
        }
        if(version>64)throw Error("preview_limit","A schedule can have at most 64 versions in this preview.");
        var definition=JsonSerializer.Serialize(body.Definition,Json);
        if(body.Id is not null && all.Any(v=>v.Id==id&&v.Version==version&&v.State=="draft"))
        {
            await using var update=Command(connection,"UPDATE market_data.date_schedule_versions SET generation=$1,definition=$2::jsonb,selection=$3,effective_from=$4,effective_to=$5 WHERE catalog_id=$6 AND schedule_id=$7 AND version=$8 AND generation=$9 AND state='draft'",
                generation,definition,body.Selection!,DateWorkspace.Date(body.EffectiveFrom),DateWorkspace.Date(body.EffectiveTo),catalog,id,version,body.Generation!.Value);
            if(await update.ExecuteNonQueryAsync(ct)!=1)throw Error("schedule_conflict","The draft changed. Reload it.");
        }
        else
        {
            await using var insert=Command(connection,"INSERT INTO market_data.date_schedule_versions(catalog_id,schedule_id,version,generation,state,definition,selection,effective_from,effective_to,engine_version,publication_order,published_at) VALUES($1,$2,$3,$4,'draft',$5::jsonb,$6,$7,$8,'date_schedule_v1',NULL,NULL)",
                catalog,id,version,generation,definition,body.Selection!,DateWorkspace.Date(body.EffectiveFrom),DateWorkspace.Date(body.EffectiveTo));
            await insert.ExecuteNonQueryAsync(ct);
        }
        return (await Read(connection,ct)).Single(v=>v.Id==id&&v.Version==version);
    }
    public async Task<ScheduleVersion> Publish(NpgsqlConnection connection,SchedulePublishRequest body,CancellationToken ct)
    {
        var row=(await Read(connection,ct)).SingleOrDefault(v=>v.Id==body.Id&&v.Version==body.Version);
        if(row is null || row.Generation!=body.Generation)throw Error("schedule_conflict","Reload the changed schedule before publishing.");
        PublishedSchedules.Validate(new(row.Id,row.Version,row.Generation,row.Definition,row.Selection,row.EffectiveFrom.ToString("yyyy-MM-dd"),row.EffectiveTo.ToString("yyyy-MM-dd")));
        await using var command=Command(connection,"SELECT security.publish_date_schedule($1,$2,$3,$4)",catalog,body.Id,body.Version,body.Generation);
        await command.ExecuteScalarAsync(ct);
        return (await Read(connection,ct)).Single(v=>v.Id==body.Id&&v.Version==body.Version);
    }
    private static TemporalException Error(string code,string message)=>new(code,message);
}
