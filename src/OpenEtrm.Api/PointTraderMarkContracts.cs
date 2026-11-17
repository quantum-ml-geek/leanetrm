using System.Text.Json.Serialization;

namespace OpenEtrm.Api;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PointTraderMarkTarget([property:JsonRequired]Guid DefinitionRevisionId,[property:JsonRequired]Guid ReferenceCatalogId,
    [property:JsonRequired]Guid ReferenceRevisionId,[property:JsonRequired]string CurveCode,[property:JsonRequired]Guid ContractId,
    [property:JsonRequired]Guid SeriesId,[property:JsonRequired]string Source,[property:JsonRequired]string Quote,
    [property:JsonRequired]string ObservedAt,[property:JsonRequired]string SourceEventId,[property:JsonRequired]string SourceRevisionToken,
    [property:JsonRequired]Guid? ExpectedPreviousObservationId);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PointTraderMarkOriginalInputs([property:JsonRequired]Guid SnapshotId,[property:JsonRequired]string Fingerprint);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
internal sealed record PointTraderMarkCommand([property:JsonRequired]string Policy,[property:JsonRequired]PointTraderMarkTarget Target,
    [property:JsonRequired]string Value,[property:JsonRequired]string Evidence,[property:JsonRequired]PointTraderMarkOriginalInputs? OriginalInputs);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PointTraderMarkContext([property:JsonRequired]Guid ContextId,[property:JsonRequired]DateTimeOffset AsOf,
    [property:JsonRequired]DateOnly BusinessDate,Guid? SnapshotId=null);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PointTraderMarkSetupRequest([property:JsonRequired]PointTraderMarkContext Context,
    [property:JsonRequired]CatalogueSource Source,[property:JsonRequired]string? CurveCode,[property:JsonRequired]Guid? ContractId,
    [property:JsonRequired]string Search,[property:JsonRequired]int Offset,[property:JsonRequired]int Limit,
    [property:JsonRequired]System.Text.Json.JsonElement? QuoteFilter,[property:JsonRequired]string? Eligibility);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PointTraderMarkWriteRequest([property:JsonRequired]Guid OperationId,[property:JsonRequired]string OwnerId,
    [property:JsonRequired]PointTraderMarkContext Context,[property:JsonRequired]string Policy,[property:JsonRequired]PointTraderMarkTarget Target,
    [property:JsonRequired]string Value,[property:JsonRequired]string Evidence,[property:JsonRequired]PointTraderMarkOriginalInputs? OriginalInputs);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PointTraderMarkStatusRequest([property:JsonRequired]string OwnerId,[property:JsonRequired]Guid OperationId);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PointTraderMarkInputsRequest([property:JsonRequired]string OwnerId,[property:JsonRequired]Guid OperationId,
    [property:JsonRequired]Guid SelectionId,[property:JsonRequired]Guid OriginalSnapshotId,[property:JsonRequired]string Fingerprint);
