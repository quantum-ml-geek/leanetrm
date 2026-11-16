using System.Collections.Immutable;
using System.Text.Json.Serialization;

namespace OpenEtrm.Api;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredPowerTradeReadRequest([property:JsonRequired]Guid SnapshotId,[property:JsonRequired]Guid TradeId);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredPowerTradeDirectoryRequest([property:JsonRequired]Guid SnapshotId,
    [property:JsonRequired]ImmutableArray<Guid> BookIds,[property:JsonRequired]int Offset,[property:JsonRequired]int Limit);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredPowerTradeStatusRequest([property:JsonRequired]Guid OperationId);
