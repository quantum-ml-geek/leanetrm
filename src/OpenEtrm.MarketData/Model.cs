using System.Collections.Immutable;

namespace OpenEtrm.MarketData;

public readonly record struct ReferenceRevision(Guid CatalogId, Guid RevisionId);
public readonly record struct ReferenceKey(ReferenceRevision Revision, string Code);
public readonly record struct DefinitionRevision(Guid CatalogId, Guid RevisionId);
public readonly record struct ContractKey(DefinitionRevision Revision, Guid Id);
public readonly record struct CurveKey(DefinitionRevision Revision, string Code);
public readonly record struct SeriesKey(DefinitionRevision Revision, Guid Id);
public readonly record struct ObservationKey(Guid CatalogId, Guid Id);

public enum ContractKind { Future = 1, Forward }
public enum QuoteKind { Outright = 1, Basis }
public enum CurveRule { Direct = 1, Add, ScaleAdd }
public enum InputSlot { Base = 1, Spread }
public enum SourceExpiryRule { RequireLive = 1, FreezeFinalFuture }
public enum ObservationRole { TraderMark = 1, DailySettlement, FinalContractSettlement, Parameter }
public enum PublicationState { Preliminary = 1, Final }
public enum InputUse { Variable = 1, FrozenFact }
public enum InputSelectionPolicy { ExactPinnedFinalObservationsNoAgeFiltering = 1 }
public enum SettlementKind { FutureSeries = 1, Index, IndexDifference }
public enum LotBasis { FixedTotal = 1, PerDeliveryDay, PerDeliveryHour }

public sealed record QuantitySpecification(
    ReferenceKey Key, ReferenceKey Commodity, ReferenceKey MeasurementBasis,
    ReferenceKey Unit, ReferenceKey Dimension);

public sealed record QuoteSpecification(
    ReferenceKey Key, QuoteKind Kind, ReferenceKey Currency,
    ReferenceKey Quantity, ExactDecimal Multiplier, ExactDecimal TradingTick,
    ExactDecimal ClearingIncrement, ExactDecimal Minimum, ExactDecimal Maximum);

public sealed record SettlementTarget(
    SettlementKind Kind, ReferenceKey? IndexA, ReferenceKey? IndexB);

public sealed record MarketContract(
    ContractKey Key, ContractKind Kind, DateOnly DeliveryFrom, DateOnly DeliveryTo,
    DateTimeOffset Expiry, ReferenceKey? FuturesSeries);

// Resolved from the exact dated series/product/milestone reference links. This
// preserves the authoritative specification when constructing an in-memory model.
public sealed record FuturesSeriesSpecification(
    ReferenceKey Key, ReferenceKey QuoteQuantity, ReferenceKey Currency,
    ExactDecimal Multiplier, ExactDecimal TradingTick, ReferenceKey Location,
    ReferenceKey DeliveryProfile, DateOnly DeliveryFrom, DateOnly DeliveryTo,
    DateTimeOffset LastTradingAt, ReferenceKey LotQuantity,
    ExactDecimal ContractSize, LotBasis LotBasis);

// Identity mapping is the first supported delivery mapping. Explicitly named
// pairs are required even where source and target delivery periods are equal.
public sealed record ConstituentMapping(ContractKey Target, ContractKey Source);
public sealed record CurveInput(
    InputSlot Slot, CurveKey Source, SourceExpiryRule ExpiryRule,
    ImmutableArray<ConstituentMapping> Mappings);

public enum NumericKind { QuantityRatio = 1, Dimensionless }
public sealed record ValueSpecification(
    ReferenceKey Key, NumericKind Kind, ReferenceKey? NumeratorQuantity,
    ReferenceKey? DenominatorQuantity, ExactDecimal Minimum, ExactDecimal Maximum);
public sealed record MarketSeries(
    SeriesKey Key, ContractKey? Contract, ReferenceKey? Quote, ReferenceKey? ValueSpecification);
// Exactly one of a dated series or an explicitly typed constant.
public sealed record NumericInput(
    SeriesKey? Series, ReferenceKey? ConstantSpecification, ExactDecimal? Constant,
    ObservationRole? Role, ReferenceKey? Source);

public sealed record Curve(
    CurveKey Key, ReferenceKey Quote, ReferenceKey Location,
    ReferenceKey DeliveryProfile, SettlementTarget Settlement,
    CurveRule Rule, ImmutableArray<ContractKey> Constituents,
    ImmutableArray<CurveInput> Inputs, ObservationRole? DirectRole,
    ReferenceKey? DirectSource, NumericInput? Multiplier);

public sealed record MarketObservation(
    ObservationKey Key, SeriesKey Series,
    ReferenceKey Source, ObservationRole Role, PublicationState State,
    DateTimeOffset ObservedAt, ExactDecimal Value);

public readonly record struct InputKey(SeriesKey Series, InputUse Use);
public sealed record SelectedObservation(InputKey Input, MarketObservation Observation);

// These are explicitly selected inputs, not a "latest" or wall-clock historical
// resolver. Snapshot identities supplied here have no authorization meaning.
public sealed record MarketSnapshot(
    Guid Id, DefinitionRevision Definitions, DateTimeOffset ValuationAt,
    DateTimeOffset MarketCutoff, InputSelectionPolicy SelectionPolicy,
    ImmutableArray<SelectedObservation> Selections);

public readonly record struct CurveRequest(CurveKey Curve, ContractKey Contract);
public sealed record BuiltValue(
    CurveRequest Request, ReferenceKey Quote, ExactDecimal Value,
    ImmutableHashSet<ObservationKey> Lineage);
public sealed record CurveEvaluationInput(InputSlot Slot, CurveRequest Source, InputUse Use);
public sealed record CurveEvaluation(BuiltValue Result, InputUse Use,
    ImmutableArray<CurveEvaluationInput> Inputs, ExactDecimal? Multiplier, ObservationKey? MultiplierObservation);
public sealed record CurveBuild(
    Guid SnapshotId, DefinitionRevision Definitions, string NumericalPolicy,
    ImmutableArray<BuiltValue> Values, int EvaluatedConstituents, ImmutableArray<CurveEvaluation> Evaluations);
