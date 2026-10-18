using System.Text.Json;
using System.Text.Json.Serialization;
using Npgsql;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PartyReadRequest(Guid SnapshotId,string Kind);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PartySaveRequest(Guid OperationId,string Kind,Guid? Id,int? ExpectedRevision,string Code,string Name,string EffectiveAt);

public static class PartyEditors
{
    public static void Validate(PartySaveRequest body)
    {
        if(body.Kind is not("legal_entity" or "counterparty") || body.OperationId==Guid.Empty ||
            (body.Id is null)!=(body.ExpectedRevision is null) || body.ExpectedRevision is <=0 ||
            body.Id==Guid.Empty || body.Name is null || body.Name!=body.Name.Trim() || body.Name.Any(char.IsControl))
            throw new MarketDataException("party_input","Choose a party type, stable code, name, effective time and exact revision for an edit.");
        var key=new PartyKey(Guid.NewGuid(),body.Id??Guid.NewGuid(),body.ExpectedRevision??1);
        if(body.Kind=="legal_entity")_=new LegalEntity(key,body.Code,body.Name);
        else _=new Counterparty(key,body.Code,body.Name);
        var effective=SchedulePreview.ParseAt(body.EffectiveAt);
        if(effective.Year is <1901 or >2199)throw new MarketDataException("party_input","Choose an effective instant within 1901–2199.");
    }
    public static async Task<JsonElement> Read(NpgsqlConnection connection,Guid catalog,string kind,DateTimeOffset asOf,CancellationToken ct)
    {
        await using var command=ScheduleStore.Command(connection,"SELECT security.trade_party_versions($1,$2,$3)::text",catalog,kind,asOf);
        return JsonSerializer.Deserialize<JsonElement>((string)(await command.ExecuteScalarAsync(ct))!);
    }
    public static async Task<JsonElement> Save(NpgsqlConnection connection,Guid catalog,PartySaveRequest body,CancellationToken ct)
    {
        Validate(body);
        await using var command=ScheduleStore.Command(connection,"SELECT security.save_trade_party($1,$2,$3,$4,$5,$6,$7,$8)::text",
            catalog,body.OperationId,body.Kind,body.Id is {} id?id:DBNull.Value,
            body.ExpectedRevision is {} revision?revision:DBNull.Value,body.Code,body.Name,SchedulePreview.ParseAt(body.EffectiveAt));
        return JsonSerializer.Deserialize<JsonElement>((string)(await command.ExecuteScalarAsync(ct))!);
    }
}
