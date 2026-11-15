using System.Collections.Immutable;
using System.Globalization;
using System.Text;
using System.Text.Json;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power;
using Npgsql;

namespace OpenEtrm.Api;

public sealed record ClockCaptureRequest(Guid ReferenceCatalogId,Guid ReferenceRevisionId,DateOnly From,DateOnly To,ClockRule[] Clocks);

// Reference publication preparation, never a booking-time inference. The caller
// supplies the exact source release and coverage before sealing its revision.
public static class ClockCapturePublication
{
    public static string Render(ClockCaptureRequest request)
    {
        if(request.ReferenceCatalogId==Guid.Empty||request.ReferenceRevisionId==Guid.Empty||request.Clocks is null||request.Clocks.Length is <1 or >64||
            request.Clocks.Any(c=>c is null)||request.Clocks.Select(c=>c.Code).Distinct(StringComparer.Ordinal).Count()!=request.Clocks.Length)
            throw new MarketDataException("clock_capture","Publish distinct exact clock references and explicit bounded coverage.");
        static string Literal(string? value)=>value is null?"NULL":"'"+value.Replace("'","''",StringComparison.Ordinal)+"'";
        var sql=new StringBuilder();
        foreach(var rule in request.Clocks)
        {
            var clock=PowerClock.FromRule(rule,TimeZoneDatabase.Installed()).CaptureForDelivery(request.From,request.To);
            sql.Append(CultureInfo.InvariantCulture,$"SELECT ref_data.publish_clock_capture('{request.ReferenceCatalogId}','{request.ReferenceRevisionId}',{Literal(rule.Code)},'{request.From:yyyy-MM-dd}','{request.To:yyyy-MM-dd}',{Literal(clock.Rules)},decode('{clock.Fingerprint}','hex'),{Literal(rule.TzdbVersion)});\n");
        }
        return sql.ToString();
    }
    public static void Run(string input,string output)
    {
        var request=JsonSerializer.Deserialize<ClockCaptureRequest>(File.ReadAllText(input),new JsonSerializerOptions(JsonSerializerDefaults.Web))??
            throw new MarketDataException("clock_capture","Supply an explicit reference publication request.");
        using var file=new FileStream(output,FileMode.CreateNew,FileAccess.Write);
        using var writer=new StreamWriter(file);writer.Write(Render(request));
    }
}

internal static class PublishedClocks
{
    internal static async Task<PowerClock> Read(NpgsqlConnection connection,ReferenceKey reference,CancellationToken ct)
    {
        await using var command=ScheduleStore.Command(connection,"""
            SELECT row_to_json(k)::text,row_to_json(c)::text FROM ref_data.clock_rules k
            JOIN ref_data.clock_captures c ON(c.catalog_id,c.revision_id,c.clock_code)=(k.catalog_id,k.revision_id,k.code)
            JOIN ref_data.revisions r ON(r.catalog_id,r.id,r.state)=(k.catalog_id,k.revision_id,'sealed')
            WHERE(k.catalog_id,k.revision_id,k.code)=($1,$2,$3)
            """,reference.Revision.CatalogId,reference.Revision.RevisionId,reference.Code);
        await using var reader=await command.ExecuteReaderAsync(ct);
        if(!await reader.ReadAsync(ct))throw Invalid();
        return Resolve([JsonSerializer.Deserialize<JsonElement>(reader.GetString(1))],ReferenceClockJson.Read(JsonSerializer.Deserialize<JsonElement>(reader.GetString(0))));
    }
    internal static PowerClock Resolve(PreviewData data,string code)
    {
        var rules=data.References["clock_rules"].Where(row=>row.Text("code")==code).ToArray();
        if(rules.Length!=1)throw Invalid();
        return Resolve(data.References.GetValueOrDefault("clock_captures",[]),ReferenceClockJson.Read(rules[0]));
    }

    internal static PowerClock Resolve(ImmutableArray<JsonElement> captures,ClockRule rule)
    {
        var found=captures.Where(row=>row.Text("clock_code")==rule.Code).ToArray();
        if(found.Length!=1)throw new MarketDataException("clock_reference","Select one exact published clock capture; no current timezone substitution is permitted.");
        var capture=found[0];
        try
        {
            var digest=capture.Text("definition_digest");
            // PostgreSQL bytea JSON uses its explicit hexadecimal wire encoding.
            if(!digest.StartsWith("\\x",StringComparison.Ordinal))throw Invalid();
            var clock=PowerClock.Restore(capture.Text("payload"),digest[2..]);
            var from=DateWorkspace.Date(capture.Text("coverage_from"));var to=DateWorkspace.Date(capture.Text("coverage_to"));
            if(from>=to||clock.Id!=(rule.Kind=="iana"?rule.IanaZone:rule.Code)||capture.OptionalText("tzdb_version")!=rule.TzdbVersion)throw Invalid();
            using var grid=JsonDocument.Parse(capture.Text("payload"));
            if(clock.StartOfDay(from).ToUniversalTime()!=grid.RootElement.GetProperty("From").GetDateTimeOffset()||
                clock.StartOfDay(to).ToUniversalTime()!=grid.RootElement.GetProperty("To").GetDateTimeOffset())throw Invalid();
            return clock;
        }
        catch(Exception error)when(error is KeyNotFoundException or InvalidOperationException or FormatException)
        {throw Invalid();}
    }
    private static MarketDataException Invalid()=>new("clock_reference","The published clock payload, release and coverage must match its exact reference.");
}
