using System.Text.Json.Serialization;

namespace OpenEtrm.Api;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PhysicalPowerCatalogRequest([property:JsonRequired]Guid SnapshotId);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PhysicalPowerListRequest([property:JsonRequired]Guid SnapshotId,[property:JsonRequired]string SelectionPolicy);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PhysicalPowerGetRequest([property:JsonRequired]Guid SnapshotId,[property:JsonRequired]Guid FacilityId,[property:JsonRequired]int Version);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PhysicalPowerSaveRequest([property:JsonRequired]Guid SnapshotId,[property:JsonRequired]Guid RequestId,
    [property:JsonRequired]int ExpectedVersion,[property:JsonRequired]StructuredPowerFacilityVersion Facility);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PhysicalPowerStatusRequest([property:JsonRequired]Guid RequestId);
