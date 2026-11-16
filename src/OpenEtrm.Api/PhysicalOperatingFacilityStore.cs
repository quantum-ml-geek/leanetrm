using System.Text.Json;
using System.Text.Json.Serialization;
using Npgsql;
using OpenEtrm.MarketData;

namespace OpenEtrm.Api;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PhysicalOperatingFacilitySaveRequest(
    [property:JsonRequired]Guid RequestId,
    [property:JsonRequired]int ExpectedVersion,
    [property:JsonRequired]StructuredPowerFacilityVersion Facility);

public sealed record PhysicalOperatingFacilityReceipt(Guid RequestId,bool Changed,StructuredPowerFacilityVersion Facility);

// An operating extension of a reference location, not another facility master.
// Connections must already carry the ordinary authorized request transaction.
// SQL retains exact relationship columns and commit-certified append-only versions.
public sealed class PhysicalOperatingFacilityStore(Guid catalog)
{
    private static readonly JsonSerializerOptions Json=new(JsonSerializerDefaults.Web);

    public async Task<PhysicalOperatingFacilityReceipt> Save(NpgsqlConnection connection,PreviewData data,
        PhysicalOperatingFacilitySaveRequest request,CancellationToken ct)
    {
        if(request is null||request.RequestId==Guid.Empty||request.ExpectedVersion is <0 or int.MaxValue||request.Facility is not {} candidate||
            candidate.Id==Guid.Empty||candidate.Version<1)
            throw new MarketDataException("power_facility_request","Supply a request identity, facility identity and explicit expected version.");
        if(data.DefinitionRevision.CatalogId!=catalog)
            throw new MarketDataException("power_facility_reference","The authorized bundle must belong to this operating catalog.");
        var from=IntervalSeriesStore.ParseInstant(candidate.EffectiveFrom);var to=IntervalSeriesStore.ParseInstant(candidate.EffectiveTo);
        var resolved=StructuredPowerPreview.ResolveTerms(data,candidate.Terms,from,to);
        var canonical=candidate with{Terms=resolved.CanonicalTerms};
        await using var command=ScheduleStore.Command(connection,
            "SELECT physical.save_power_operating_facility($1,$2,$3,$4::jsonb)::text",catalog,request.RequestId,
            request.ExpectedVersion,JsonSerializer.Serialize(canonical,Json));
        return JsonSerializer.Deserialize<PhysicalOperatingFacilityReceipt>((string)(await command.ExecuteScalarAsync(ct))!,Json)!;
    }

    public async Task<StructuredPowerFacilityVersion> ReadExact(NpgsqlConnection connection,Guid facilityId,int version,
        Guid contextId,DateTimeOffset asOf,DateOnly businessOn,CancellationToken ct)
    {
        RequireRead(facilityId,version,contextId,asOf);
        await using var command=ScheduleStore.Command(connection,
            "SELECT physical.read_power_operating_facility($1,$2,$3,$4,$5,$6)::text",catalog,facilityId,version,contextId,asOf,businessOn);
        return JsonSerializer.Deserialize<StructuredPowerFacilityVersion>((string)(await command.ExecuteScalarAsync(ct))!,Json)!;
    }

    // Future effective versions remain available through all_known_versions_v1.
    // Active-as-of selection is an explicit directory policy, never a pricing fallback.
    public async Task<StructuredPowerFacilityVersion[]> List(NpgsqlConnection connection,Guid contextId,DateTimeOffset asOf,DateOnly businessOn,
        string selectionPolicy,CancellationToken ct)
    {
        if(contextId==Guid.Empty||!StructuredPowerPreview.Utc(asOf))
            throw new MarketDataException("power_facility_context","Supply a certified context and an explicit UTC as-of instant.");
        if(selectionPolicy is not("all_known_versions_v1" or "active_asof_latest_v1"))
            throw new MarketDataException("power_facility_selection_policy","Select an explicit known-version or active-as-of directory policy.");
        await using var command=ScheduleStore.Command(connection,
            "SELECT physical.list_power_operating_facilities($1,$2,$3,$4,$5)::text",catalog,contextId,asOf,businessOn,selectionPolicy);
        return JsonSerializer.Deserialize<StructuredPowerFacilityVersion[]>((string)(await command.ExecuteScalarAsync(ct))!,Json)!;
    }

    // Command recovery uses current control state and the original actor's receipt.
    public async Task<PhysicalOperatingFacilityReceipt?> RequestStatus(NpgsqlConnection connection,Guid requestId,CancellationToken ct)
    {
        if(requestId==Guid.Empty)throw new MarketDataException("power_facility_request","Supply the saved request identity.");
        await using var command=ScheduleStore.Command(connection,
            "SELECT physical.power_operating_facility_request_status($1,$2)::text",catalog,requestId);
        return await command.ExecuteScalarAsync(ct) is string value?JsonSerializer.Deserialize<PhysicalOperatingFacilityReceipt>(value,Json):null;
    }

    // The immutable actor receipt proves this is a retry before any new bundle
    // is resolved. The native operation compares the complete canonical command;
    // status alone cannot authorize a conflicting reuse of the request identity.
    public async Task<PhysicalOperatingFacilityReceipt?> Replay(NpgsqlConnection connection,
        PhysicalOperatingFacilitySaveRequest request,CancellationToken ct)
    {
        if(request is null||await RequestStatus(connection,request.RequestId,ct) is null)return null;
        await using var command=ScheduleStore.Command(connection,
            "SELECT physical.save_power_operating_facility($1,$2,$3,$4::jsonb)::text",catalog,request.RequestId,
            request.ExpectedVersion,JsonSerializer.Serialize(request.Facility,Json));
        return JsonSerializer.Deserialize<PhysicalOperatingFacilityReceipt>((string)(await command.ExecuteScalarAsync(ct))!,Json)!;
    }

    private static void RequireRead(Guid id,int version,Guid context,DateTimeOffset asOf)
    {
        if(id==Guid.Empty||version<1||context==Guid.Empty||!StructuredPowerPreview.Utc(asOf))
            throw new MarketDataException("power_facility_context","Supply an exact facility version, certified context and UTC as-of instant.");
    }
}
