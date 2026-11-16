using System.Text.Json.Serialization;

namespace OpenEtrm.Api;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record RecInventoryDateContext(
    [property:JsonRequired]string EffectiveOn,
    [property:JsonRequired]string KnowledgeMode,
    [property:JsonRequired]ScheduleContext? Retained,
    [property:JsonRequired]string Convention);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record RecInventoryDirectoryRequest([property:JsonRequired]RecInventoryDateContext Context);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record RecInventoryReadRequest([property:JsonRequired]RecInventoryDateContext Context,
    [property:JsonRequired]Guid AccountId);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record RecInventoryStatusRequest([property:JsonRequired]Guid RequestId,
    [property:JsonRequired]string OwnerId);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record RecInventoryAccountRequest([property:JsonRequired]RecInventoryDateContext Context,
    [property:JsonRequired]Guid RequestId,[property:JsonRequired]string OwnerId,
    [property:JsonRequired]Guid AccountId,[property:JsonRequired]Guid BookId,
    [property:JsonRequired]Guid LegalEntityId,[property:JsonRequired]int LegalEntityRevision,
    [property:JsonRequired]Guid ReferenceCatalogId,[property:JsonRequired]Guid ReferenceRevisionId,
    [property:JsonRequired]string RegistryCode,[property:JsonRequired]string RegistryAccountReference,
    [property:JsonRequired]string EffectiveAt);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record RecInventoryDestinationRequest([property:JsonRequired]RecInventoryDateContext Context,
    [property:JsonRequired]Guid RequestId,[property:JsonRequired]string OwnerId,
    [property:JsonRequired]Guid DestinationId,[property:JsonRequired]Guid CounterpartyId,
    [property:JsonRequired]int CounterpartyRevision,[property:JsonRequired]Guid ReferenceCatalogId,
    [property:JsonRequired]Guid ReferenceRevisionId,[property:JsonRequired]string RegistryCode,
    [property:JsonRequired]string RegistryAccountReference,[property:JsonRequired]string EffectiveAt);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record RecInventoryWriteRequest([property:JsonRequired]RecInventoryDateContext Context,
    [property:JsonRequired]Guid RequestId,[property:JsonRequired]string OwnerId,
    [property:JsonRequired]Guid AccountId,[property:JsonRequired]Guid BusinessId,
    [property:JsonRequired]int ExpectedGeneration,[property:JsonRequired]string EffectiveAt,
    [property:JsonRequired]RecInventoryActionInput Action);

// These commands record supplied evidence. They do not request a registry action.
// Serial sequences are exact half-open ranges, expressed as integer strings.
[JsonPolymorphic(TypeDiscriminatorPropertyName="kind")]
[JsonDerivedType(typeof(RecInventoryReceiptInput),"receipt")]
[JsonDerivedType(typeof(RecInventoryAllocationInput),"allocate")]
[JsonDerivedType(typeof(RecInventoryReleaseInput),"release")]
[JsonDerivedType(typeof(RecInventoryTransferInput),"transfer")]
[JsonDerivedType(typeof(RecInventoryRetirementInput),"retire")]
public abstract record RecInventoryActionInput;
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record RecInventoryReceiptInput([property:JsonRequired]Guid LotId,
    [property:JsonRequired]string ProductCode,[property:JsonRequired]string RegistryLotReference,
    [property:JsonRequired]string VintageFrom,[property:JsonRequired]string VintageTo,
    [property:JsonRequired]string From,[property:JsonRequired]string To,
    [property:JsonRequired]string ReceiptKind,[property:JsonRequired]string EvidenceSource,
    [property:JsonRequired]string EvidenceReference):RecInventoryActionInput;
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record RecInventoryAllocationInput([property:JsonRequired]Guid LotId,
    [property:JsonRequired]string From,[property:JsonRequired]string To,
    [property:JsonRequired]Guid DeliveryId):RecInventoryActionInput;
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record RecInventoryReleaseInput([property:JsonRequired]Guid LotId,
    [property:JsonRequired]string From,[property:JsonRequired]string To,
    [property:JsonRequired]Guid AllocationId,[property:JsonRequired]int AllocationRevision):RecInventoryActionInput;
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record RecInventoryTransferInput([property:JsonRequired]Guid LotId,
    [property:JsonRequired]string From,[property:JsonRequired]string To,
    [property:JsonRequired]Guid AllocationId,[property:JsonRequired]int AllocationRevision,
    [property:JsonRequired]Guid DestinationId,[property:JsonRequired]string EvidenceSource,
    [property:JsonRequired]string EvidenceReference):RecInventoryActionInput;
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record RecInventoryRetirementInput([property:JsonRequired]Guid LotId,
    [property:JsonRequired]string From,[property:JsonRequired]string To,
    [property:JsonRequired]string BeneficiaryKind,[property:JsonRequired]Guid BeneficiaryId,[property:JsonRequired]int BeneficiaryRevision,
    [property:JsonRequired]string PurposeCode,[property:JsonRequired]string EvidenceSource,
    [property:JsonRequired]string EvidenceReference):RecInventoryActionInput;
