using System.Collections.Immutable;
using OpenEtrm.Shared.Numerics;

namespace OpenEtrm.MarketData.Power.Structured;

public readonly record struct SolarRightKey(DefinitionRevision Definitions, Guid Id);
public enum SolarDeliveryBasis { AsProduced = 1, FixedProfile }
public enum SolarPaymentBasis { ProducedOnly = 1, ProducedPlusDeemed, DeliveryObligation }
public sealed record SolarOutputTerms(SolarRightKey Right, AssetKey Asset, ReferenceKey Clock, int IntervalMinutes,
    QuantitySpecification Energy, QuantityStage Stage, ExactRatio EntitlementFraction,
    SolarDeliveryBasis DeliveryBasis, SolarPaymentBasis PaymentBasis, string Implementation);
public sealed record SolarOutputContext(DefinitionRevision Definitions, ReferenceRevision References,
    DateTimeOffset ValuationAt, DateTimeOffset KnownAt, PendingActualsPolicy PendingActuals);
public sealed record SolarOutputInput(DeliveryInterval Interval, Quantity Production, VolumeState State,
    Quantity Deemed, Quantity? RequiredDelivery, QuantityStage Stage, Guid ProductionRevision,
    DateTimeOffset ProductionKnownAt, Guid? DeemedRevision, DateTimeOffset? DeemedKnownAt,
    DateTimeOffset MeterDueAt);
// EligibleActualEnergy is metered entitled energy at the selected stage. A
// certificate product/registry still has to qualify and confirm any issuance.
public sealed record SolarOutputRow(SolarOutputInput Input, ExactQuantity PhysicalEnergy,
    ExactQuantity PaymentEnergy, ExactQuantity EligibleActualEnergy, ExactQuantity DeliveryObligation,
    ExactQuantity ReplacementEnergy, ExactQuantity SurplusEnergy);
public sealed record SolarOutputPlan(SolarOutputTerms Terms, SolarOutputContext Context,
    ImmutableArray<SolarOutputRow> Rows);
public sealed record SolarScenarioInput(DeliveryInterval Interval, Quantity Production,
    Quantity? RequiredDelivery, QuantityStage Stage);
public sealed record SolarScenarioRow(SolarScenarioInput Input, ExactQuantity PhysicalEnergy,
    ExactQuantity PaymentEnergy, ExactQuantity EligibleActualEnergy, ExactQuantity DeliveryObligation,
    ExactQuantity ReplacementEnergy, ExactQuantity SurplusEnergy);
public sealed record SolarScenarioPlan(SolarOutputTerms Terms, SolarOutputContext Context,
    ImmutableArray<SolarScenarioRow> Rows, string Implementation);

// Quantity evaluation only. It neither issues certificates nor records an
// operator instruction; a caller supplies the exact admitted source evidence.
public static class SolarOutputRights
{
    public const string Implementation = "solar_output_right_v1";
    public const string ScenarioImplementation = "hypothetical_supplied_forecast_v1";
    public const int MaximumIntervals = 35136;
    // A manually supplied what-if volume is not an observation. This version
    // contains no deemed-generation assumption and no actual-energy entitlement.
    public static SolarScenarioPlan EvaluateScenario(SolarOutputTerms terms, SolarOutputContext context,
        ImmutableArray<SolarScenarioInput> inputs, string implementation)
    {
        ValidateTerms(terms, context);
        if (implementation != ScenarioImplementation || terms.PaymentBasis == SolarPaymentBasis.ProducedPlusDeemed)
            throw Error("solar_scenario_policy", "Select the explicit supplied hypothetical forecast version and a payment basis without an unsupported deemed input.");
        RequireGridSize(inputs);
        var rows = ImmutableArray.CreateBuilder<SolarScenarioRow>(inputs.Length);
        var zero = ExactQuantity.FromQuantity(new(default, terms.Energy.Key));
        var noDeemed = new Quantity(default, terms.Energy.Key);
        DateTimeOffset? priorEnd = null;
        foreach (var input in inputs)
        {
            if (input is null) throw Error("solar_grid", "Every supplied scenario interval must be explicit.");
            priorEnd = ValidateInterval(terms, input.Interval, priorEnd);
            if (input.Stage != terms.Stage) throw Error("solar_quantity", "A hypothetical volume must use the selected exact measurement stage.");
            var quantity = ResolveQuantities(terms, input.Production, noDeemed, input.RequiredDelivery);
            rows.Add(new(input, quantity.Physical, quantity.Payment, zero, quantity.Obligation, quantity.Replacement, quantity.Surplus));
        }
        return new(terms, context, rows.MoveToImmutable(), ScenarioImplementation);
    }
    public static SolarOutputPlan Evaluate(SolarOutputTerms terms, SolarOutputContext context,
        ImmutableArray<SolarOutputInput> inputs)
    {
        ValidateTerms(terms, context);
        RequireGridSize(inputs);
        var rows = ImmutableArray.CreateBuilder<SolarOutputRow>(inputs.Length);
        var zero = ExactQuantity.FromQuantity(new(default, terms.Energy.Key));
        DateTimeOffset? priorEnd = null;
        foreach (var input in inputs)
        {
            if (input is null) throw Error("solar_grid", "Every supplied production interval must be explicit.");
            priorEnd = ValidateInterval(terms, input.Interval, priorEnd);
            var interval = input.Interval;
            if (input.Stage != terms.Stage || input.State is not (VolumeState.Metered or VolumeState.Forecast))
                throw Error("solar_quantity", "Supply the exact selected measurement stage and forecast or metered production state.");
            var quantity = ResolveQuantities(terms, input.Production, input.Deemed, input.RequiredDelivery);
            if (input.ProductionRevision == Guid.Empty || !Utc(input.ProductionKnownAt) || input.ProductionKnownAt > context.KnownAt ||
                !Utc(input.MeterDueAt) || input.MeterDueAt < interval.End ||
                input.State == VolumeState.Forecast && input.ProductionKnownAt > context.ValuationAt ||
                input.State == VolumeState.Metered && (interval.End > context.ValuationAt || input.ProductionKnownAt < interval.End))
                throw Error("solar_evidence", "Production requires eligible selected revision evidence, knowledge and an explicit meter deadline.");
            var deemedPositive = input.Deemed.Amount.CompareTo(default) > 0;
            var deemedEvidence = input.DeemedRevision is { } id && id != Guid.Empty && input.DeemedKnownAt is { } known && Utc(known) && known <= context.KnownAt;
            if (deemedPositive && (!deemedEvidence || input.State != VolumeState.Metered) ||
                !deemedPositive && (input.DeemedRevision is not null || input.DeemedKnownAt is not null) && !deemedEvidence)
                throw Error("solar_evidence", "Nonzero deemed energy requires its own eligible evidence and ended metered production.");
            if (input.State == VolumeState.Forecast && interval.End <= context.ValuationAt &&
                (context.PendingActuals != PendingActualsPolicy.EstimateUntilActual || context.ValuationAt >= input.MeterDueAt))
                throw Error("solar_actual_missing", "Ended production needs an eligible meter at the deadline or under the require-actuals policy.");

            rows.Add(new(input, quantity.Physical, quantity.Payment, input.State == VolumeState.Metered ? quantity.Physical : zero,
                quantity.Obligation, quantity.Replacement, quantity.Surplus));
        }
        return new(terms, context, rows.MoveToImmutable());
    }

    private static (ExactQuantity Physical, ExactQuantity Payment, ExactQuantity Obligation, ExactQuantity Replacement, ExactQuantity Surplus)
        ResolveQuantities(SolarOutputTerms terms, Quantity production, Quantity deemed, Quantity? requiredDelivery)
    {
        RequireEnergy(production, terms.Energy.Key); RequireEnergy(deemed, terms.Energy.Key);
        if (deemed.Amount.CompareTo(default) > 0 && terms.PaymentBasis != SolarPaymentBasis.ProducedPlusDeemed)
            throw Error("solar_quantity", "This payment basis does not admit deemed energy.");
        var physical = ExactQuantity.FromQuantity(production).Scale(terms.EntitlementFraction);
        ExactQuantity obligation;
        if (terms.DeliveryBasis == SolarDeliveryBasis.FixedProfile)
        {
            RequireEnergy(requiredDelivery, terms.Energy.Key);
            // Fixed delivery is already the right's contractual quantity;
            // the asset entitlement must not scale it a second time.
            obligation = ExactQuantity.FromQuantity(requiredDelivery!);
        }
        else
        {
            if (requiredDelivery is not null) throw Error("solar_quantity", "An as-produced right has no independent fixed delivery amount.");
            obligation = physical;
        }
        var payment = terms.PaymentBasis switch
        {
            SolarPaymentBasis.ProducedOnly => physical,
            SolarPaymentBasis.ProducedPlusDeemed => physical.Add(ExactQuantity.FromQuantity(deemed).Scale(terms.EntitlementFraction)),
            SolarPaymentBasis.DeliveryObligation => obligation,
            _ => throw Error("solar_terms", "Select an implemented payment basis.")
        };
        var zero = ExactQuantity.FromQuantity(new(default, terms.Energy.Key));
        var difference = obligation.Add(physical.Scale(ExactDecimal.Parse("-1")));
        return (physical, payment, obligation, difference.NumeratorValue.Sign > 0 ? difference : zero,
            difference.NumeratorValue.Sign < 0 ? difference.Scale(ExactDecimal.Parse("-1")) : zero);
    }
    private static void RequireGridSize<T>(ImmutableArray<T> inputs)
    {
        if (inputs.IsDefaultOrEmpty || inputs.Length > MaximumIntervals) throw Error("solar_grid", "Supply a nonempty bounded native interval grid.");
    }
    private static DateTimeOffset ValidateInterval(SolarOutputTerms terms, DeliveryInterval interval, DateTimeOffset? priorEnd)
    {
        if (interval is null || !Utc(interval.Start) || !Utc(interval.End) || interval.Start >= interval.End ||
            interval.End - interval.Start != TimeSpan.FromMinutes(terms.IntervalMinutes) || interval.Start.Ticks % TimeSpan.TicksPerMinute != 0 ||
            interval.HourBeginning is < 0 or > 23 || interval.Minute is < 0 or > 59 || interval.Minute % terms.IntervalMinutes != 0 ||
            interval.Occurrence is < 1 or > 2 || priorEnd is { } previous && previous != interval.Start)
            throw Error("solar_grid", "Intervals must preserve an ordered contiguous native UTC grid and explicit local labels.");
        return interval.End;
    }

    public static void ValidateTerms(SolarOutputTerms terms, SolarOutputContext context)
    {
        if (terms is null || context is null || terms.Energy is null || terms.EntitlementFraction is null ||
            terms.Implementation != Implementation || terms.Right.Id == Guid.Empty || !Definitions(context.Definitions) ||
            terms.Right.Definitions != context.Definitions || terms.Asset is null || terms.Asset.Revision != context.Definitions ||
            string.IsNullOrWhiteSpace(terms.Asset.Code) || context.References.CatalogId == Guid.Empty || context.References.RevisionId == Guid.Empty ||
            !Utc(context.ValuationAt) || !Utc(context.KnownAt) || !Enum.IsDefined(context.PendingActuals) ||
            !Enum.IsDefined(terms.Stage) || !Enum.IsDefined(terms.DeliveryBasis) || !Enum.IsDefined(terms.PaymentBasis) ||
            terms.IntervalMinutes is not (15 or 60) || terms.EntitlementFraction.Numerator > terms.EntitlementFraction.Denominator ||
            terms.Energy.Dimension.Code != "energy" ||
            terms.DeliveryBasis == SolarDeliveryBasis.FixedProfile && terms.PaymentBasis != SolarPaymentBasis.DeliveryObligation ||
            terms.DeliveryBasis == SolarDeliveryBasis.AsProduced && terms.PaymentBasis == SolarPaymentBasis.DeliveryObligation)
            throw Error("solar_terms", "Supply an exact right/asset/context and implemented delivery, quantity and payment policies.");
        foreach (var key in new[] { terms.Clock, terms.Energy.Key, terms.Energy.Commodity, terms.Energy.MeasurementBasis, terms.Energy.Unit, terms.Energy.Dimension })
            if (key.Revision != context.References || string.IsNullOrWhiteSpace(key.Code))
                throw Error("solar_terms", "Every quantity and clock reference must retain the selected exact reference revision.");
    }
    private static bool Definitions(DefinitionRevision revision) => revision.CatalogId != Guid.Empty && revision.RevisionId != Guid.Empty;
    private static bool Utc(DateTimeOffset at) => at.Offset == TimeSpan.Zero && at.Ticks % 10 == 0 && at < new DateTimeOffset(9999, 12, 31, 0, 0, 0, TimeSpan.Zero);
    private static void RequireEnergy(Quantity? value, ReferenceKey specification)
    {
        if (value is null || value.Specification != specification || value.Amount.CompareTo(default) < 0)
            throw Error("solar_quantity", "Supply explicit nonnegative quantities in the selected exact energy specification.");
    }
    private static MarketDataException Error(string code, string message) => new(code, message);
}
