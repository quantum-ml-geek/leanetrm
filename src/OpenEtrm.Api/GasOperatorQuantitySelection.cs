using System.Collections.Immutable;
using System.Text.Json.Serialization;

namespace OpenEtrm.Api;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record GasOperatorSettlementQuantityCorrection(
    [property:JsonRequired]Guid SettlementId,[property:JsonRequired]int ExpectedRevision,
    [property:JsonRequired]string Quantity,[property:JsonRequired]Guid EvidenceId,
    [property:JsonRequired]Guid? SourceObservationId,[property:JsonRequired]int? ExpectedReceiptRevision,
    [property:JsonRequired]int? ExpectedConsumptionRevision,[property:JsonRequired]Guid? LotId,
    [property:JsonRequired]Guid? ReservationId,[property:JsonRequired]string SourceAllocation);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record GasOperatorClaimQuantityCorrection(
    [property:JsonRequired]Guid ClaimId,[property:JsonRequired]int ExpectedRevision,
    [property:JsonRequired]string Quantity,[property:JsonRequired]Guid EvidenceId,
    [property:JsonRequired]string SourceAllocation,
    [property:JsonRequired]ImmutableArray<GasOperatorSettlementQuantityCorrection> Settlements);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record GasOperatorCashoutCorrection(
    [property:JsonRequired]string Ordering,[property:JsonRequired]DateTimeOffset? AdjustmentDueAt);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record GasOperatorQuantitySelection(
    [property:JsonRequired]string Implementation,[property:JsonRequired]Guid RootClaimId,
    [property:JsonRequired]ImmutableArray<GasOperatorClaimQuantityCorrection> Claims,
    [property:JsonRequired]ImmutableArray<GasOwnedConsumptionQuantityCorrection> Consumptions,
    [property:JsonRequired]GasOperatorCashoutCorrection Cashout,[property:JsonRequired]string Evidence);
