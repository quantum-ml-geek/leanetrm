using System.Collections.Immutable;

namespace OpenEtrm.MarketData.Power.Structured;

public enum BatteryMeterBoundary { GridSideAc = 1 }
public enum BatteryLossPolicy { ZeroAuxiliaryAndSelfDischarge = 1 }
public enum BatteryCapacityPolicy { Fixed = 1 }
public enum BatterySimultaneousPolicy { Prohibited = 1 }
public enum BatteryChargingOrigin { Grid = 1 }
public enum BatteryThroughputPolicy { Uncapped = 1, GridChargePlusDischarge }

public sealed record BatteryOperatingLimits(Quantity MaximumChargePower, Quantity MaximumDischargePower,
    Quantity MinimumStoredEnergy, Quantity MaximumStoredEnergy);
public sealed record BatteryOperatingPolicy(ExactDecimal ChargeEfficiency, ExactDecimal DischargeEfficiency,
    BatteryMeterBoundary Boundary, BatteryLossPolicy Losses, BatteryCapacityPolicy Capacity,
    BatterySimultaneousPolicy SimultaneousOperation);
public sealed record BatteryResource(DefinitionRevision Definitions, string Code, ReferenceKey Location,
    ReferenceKey Clock, PowerClock OperatingClock, int IntervalMinutes, QuantitySpecification Power,
    QuantitySpecification Energy, BatteryOperatingLimits Limits, BatteryOperatingPolicy Policy);

// Stored energy is measured inside the device; charge/discharge power is measured
// at the grid-side AC boundary. Throughput retains that boundary across segments.
public sealed record BatteryState(DateTimeOffset At, ExactQuantity StoredEnergy, ExactQuantity CumulativeGridThroughput);
public sealed record BatteryTerminalConstraint(Quantity MinimumStoredEnergy, Quantity MaximumStoredEnergy);
public sealed record BatteryThroughputConstraint(BatteryThroughputPolicy Policy, Quantity? MaximumCumulative);
// AvailableFraction derates the two MW limits; it does not change the selected
// fixed MWh capacity or select a contractual availability-payment convention.
public sealed record BatteryDispatchInterval(DeliveryInterval Interval, Quantity ChargePower, Quantity DischargePower,
    ExactDecimal AvailableFraction, BatteryChargingOrigin ChargingOrigin);
public sealed record BatteryIntervalResult(BatteryDispatchInterval Dispatch, ExactQuantity GridChargeEnergy,
    ExactQuantity GridDischargeEnergy, ExactQuantity OpeningStoredEnergy, ExactQuantity ClosingStoredEnergy,
    ExactQuantity CumulativeGridThroughput);
public sealed record BatteryPlanResult(string Implementation, BatteryResource Resource, BatteryState OpeningState,
    BatteryTerminalConstraint TerminalConstraint, BatteryThroughputConstraint ThroughputConstraint,
    ImmutableArray<BatteryIntervalResult> Intervals, ExactQuantity TotalGridCharge,
    ExactQuantity TotalGridDischarge, BatteryState ClosingState);

// Feasibility and energy conservation for a supplied immutable plan. This operation
// performs no pricing, optimization, data selection, financial netting or mutation.
public static class BatteryOperatingPlans
{
    public const string Implementation = "battery_supplied_plan_v1";
    public const int MaximumIntervals = 35_136;
    private static readonly ExactDecimal One = ExactDecimal.Parse("1");
    private static readonly ExactDecimal NegativeOne = ExactDecimal.Parse("-1");

    public static BatteryPlanResult Evaluate(BatteryResource resource, BatteryState opening,
        BatteryTerminalConstraint terminal, BatteryThroughputConstraint throughput,
        ImmutableArray<BatteryDispatchInterval> dispatch, string implementation)
    {
        if (implementation != Implementation)
            throw Error("battery_implementation", "Select the supported supplied-plan implementation explicitly.");
        ValidateResource(resource);
        ValidateGrid(resource, dispatch);
        ValidateState(resource, opening, dispatch[0].Interval.Start);
        ValidateTerminal(resource, terminal);
        ValidateThroughput(resource, throughput, opening.CumulativeGridThroughput);

        var stored = opening.StoredEnergy;
        var cumulative = opening.CumulativeGridThroughput;
        var chargeTotal = Zero(resource.Energy.Key);
        var dischargeTotal = Zero(resource.Energy.Key);
        var rows = ImmutableArray.CreateBuilder<BatteryIntervalResult>(dispatch.Length);
        foreach (var row in dispatch)
        {
            RequireQuantity(row.ChargePower, resource.Power.Key);
            RequireQuantity(row.DischargePower, resource.Power.Key);
            if (row.ChargePower.Amount.CompareTo(default) < 0 || row.DischargePower.Amount.CompareTo(default) < 0)
                throw Error("battery_dispatch", "Charge and discharge power must be independently nonnegative.");
            if (row.ChargePower.Amount.CompareTo(default) > 0 && row.DischargePower.Amount.CompareTo(default) > 0)
                throw Error("battery_simultaneous", "The selected policy prohibits simultaneous charging and discharging.");
            if (row.AvailableFraction.CompareTo(default) < 0 || row.AvailableFraction.CompareTo(One) > 0)
                throw Error("battery_availability", "Every interval requires an explicit available fraction in [0,1].");
            if (row.ChargingOrigin != BatteryChargingOrigin.Grid)
                throw Error("battery_charging_origin", "This version requires explicit grid charging origin.");

            var chargePower = ExactQuantity.FromQuantity(row.ChargePower);
            var dischargePower = ExactQuantity.FromQuantity(row.DischargePower);
            if (Compare(chargePower, ExactQuantity.FromQuantity(resource.Limits.MaximumChargePower).Scale(row.AvailableFraction)) > 0 ||
                Compare(dischargePower, ExactQuantity.FromQuantity(resource.Limits.MaximumDischargePower).Scale(row.AvailableFraction)) > 0)
                throw Error("battery_power_limit", "The supplied dispatch exceeds available charge or discharge power.");

            var ticks = (row.Interval.End - row.Interval.Start).Ticks;
            ExactQuantity Energy(Quantity power) => new(power.Amount.ScaledValue * ticks,
                ExactDecimal.WorkingScale * TimeSpan.TicksPerHour, resource.Energy.Key);
            var charge = Energy(row.ChargePower);
            var discharge = Energy(row.DischargePower);
            var next = stored.Add(charge.Scale(resource.Policy.ChargeEfficiency)).Add(discharge
                .ScaleFraction(ExactDecimal.WorkingScale, resource.Policy.DischargeEfficiency.ScaledValue).Scale(NegativeOne));
            RequireEnergyBounds(resource, next);
            cumulative = cumulative.Add(charge).Add(discharge);
            RequireThroughput(throughput, cumulative);
            rows.Add(new(row, charge, discharge, stored, next, cumulative));
            chargeTotal = chargeTotal.Add(charge);
            dischargeTotal = dischargeTotal.Add(discharge);
            stored = next;
        }

        if (Compare(stored, ExactQuantity.FromQuantity(terminal.MinimumStoredEnergy)) < 0 ||
            Compare(stored, ExactQuantity.FromQuantity(terminal.MaximumStoredEnergy)) > 0)
            throw Error("battery_terminal", "The supplied plan does not meet its selected terminal stored-energy constraint.");
        return new(Implementation, resource, opening, terminal, throughput, rows.MoveToImmutable(), chargeTotal,
            dischargeTotal, new(dispatch[^1].Interval.End, stored, cumulative));
    }

    public static void ValidateResource(BatteryResource? resource)
    {
        if (resource is null || resource.Definitions.CatalogId == Guid.Empty || resource.Definitions.RevisionId == Guid.Empty ||
            string.IsNullOrWhiteSpace(resource.Code) || resource.OperatingClock is null ||
            resource.IntervalMinutes is not (5 or 15 or 30 or 60) || !Coherent(resource.Power) || !Coherent(resource.Energy) ||
            resource.Power.Key == resource.Energy.Key || resource.Power.Key.Revision != resource.Energy.Key.Revision || resource.Location.Revision != resource.Energy.Key.Revision ||
            resource.Clock.Revision != resource.Energy.Key.Revision || !ValidKey(resource.Location) || !ValidKey(resource.Clock) ||
            resource.Power.Unit.Code != "megawatt" || resource.Power.Dimension.Code != "power" ||
            resource.Energy.Unit.Code != "megawatt_hour" || resource.Energy.Dimension.Code != "energy" ||
            resource.Power.Commodity != resource.Energy.Commodity || resource.Limits is null)
            throw Error("battery_resource", "Supply the exact resource version, clock, compatible MW/MWh definitions and operating limits.");
        var policy = resource.Policy;
        if (policy is null || policy.Boundary != BatteryMeterBoundary.GridSideAc ||
            policy.Losses != BatteryLossPolicy.ZeroAuxiliaryAndSelfDischarge || policy.Capacity != BatteryCapacityPolicy.Fixed ||
            policy.SimultaneousOperation != BatterySimultaneousPolicy.Prohibited)
            throw Error("battery_policy", "Select grid-side AC, zero auxiliary/self-discharge, fixed capacity and prohibited simultaneous operation explicitly.");
        if (policy.ChargeEfficiency.CompareTo(default) <= 0 || policy.ChargeEfficiency.CompareTo(One) > 0 ||
            policy.DischargeEfficiency.CompareTo(default) <= 0 || policy.DischargeEfficiency.CompareTo(One) > 0)
            throw Error("battery_efficiency", "Separate charge and discharge efficiencies must each be in (0,1].");
        var limits = resource.Limits;
        RequireQuantity(limits.MaximumChargePower, resource.Power.Key);
        RequireQuantity(limits.MaximumDischargePower, resource.Power.Key);
        RequireQuantity(limits.MinimumStoredEnergy, resource.Energy.Key);
        RequireQuantity(limits.MaximumStoredEnergy, resource.Energy.Key);
        if (limits.MaximumChargePower.Amount.CompareTo(default) < 0 || limits.MaximumDischargePower.Amount.CompareTo(default) < 0 ||
            limits.MaximumChargePower.Amount == default && limits.MaximumDischargePower.Amount == default ||
            limits.MinimumStoredEnergy.Amount.CompareTo(default) < 0 || limits.MaximumStoredEnergy.Amount.CompareTo(default) <= 0 ||
            limits.MinimumStoredEnergy.Amount.CompareTo(limits.MaximumStoredEnergy.Amount) > 0)
            throw Error("battery_resource", "Power limits must be nonnegative with a usable direction, and stored-energy limits must be coherent and positive.");
    }

    private static void ValidateGrid(BatteryResource resource, ImmutableArray<BatteryDispatchInterval> dispatch)
    {
        if (dispatch.IsDefaultOrEmpty || dispatch.Length > MaximumIntervals)
            throw Error("battery_grid", "Supply a nonempty native dispatch grid within the declared interval bound.");
        DateTimeOffset? previousEnd = null;
        var duration = TimeSpan.FromMinutes(resource.IntervalMinutes);
        foreach (var row in dispatch)
        {
            if (row?.Interval is not { } interval || interval.Start.Offset != TimeSpan.Zero || interval.End.Offset != TimeSpan.Zero ||
                interval.End - interval.Start != duration || previousEnd is { } end && interval.Start != end ||
                interval.OperatingDate.Year is < 2000 or > 2099 ||
                Math.Abs(interval.OperatingDate.DayNumber - DateOnly.FromDateTime(interval.Start.UtcDateTime).DayNumber) > 1)
                throw Error("battery_grid", "Intervals must be ordered, contiguous and distinct on the selected native UTC grid.");
            previousEnd = interval.End;
        }
        if (dispatch[^1].Interval.End - dispatch[0].Interval.Start > TimeSpan.FromDays(366))
            throw Error("battery_grid", "The actual UTC plan span must not exceed 366 days.");
        // Untrusted local labels cannot expand a short UTC plan into a year of
        // native cells. Validate only each bounded supplied operating day.
        var days = new Dictionary<DateOnly, Dictionary<DateTimeOffset, DeliveryInterval>>();
        foreach (var row in dispatch)
        {
            var interval = row.Interval;
            if (!days.TryGetValue(interval.OperatingDate, out var native))
            {
                try
                {
                    native = PowerHours.Compile(interval.OperatingDate, interval.OperatingDate.AddDays(1), resource.OperatingClock,
                        TimeOfUse.All(resource.IntervalMinutes), [], resource.IntervalMinutes).ToDictionary(p => p.Start, p => p.Delivery);
                }
                catch (Exception e) when (e is MarketDataException or ArgumentOutOfRangeException)
                {
                    throw Error("battery_grid", "The operating dates must resolve to the selected captured clock's supported native grid.");
                }
                days.Add(interval.OperatingDate, native);
            }
            if (!native.TryGetValue(interval.Start, out var expected) || expected != interval)
                throw Error("battery_grid", "Every interval must retain its captured clock's exact UTC bounds and local occurrence labels.");
        }
    }

    private static void ValidateState(BatteryResource resource, BatteryState? opening, DateTimeOffset first)
    {
        if (opening is null || opening.At.Offset != TimeSpan.Zero || opening.At != first || opening.StoredEnergy is null ||
            opening.CumulativeGridThroughput is null || opening.CumulativeGridThroughput.NumeratorValue.Sign < 0)
            throw Error("battery_opening_state", "Supply the opening state at the first interval and nonnegative retained cumulative throughput.");
        RequireQuantity(opening.StoredEnergy, resource.Energy.Key);
        RequireQuantity(opening.CumulativeGridThroughput, resource.Energy.Key);
        RequireEnergyBounds(resource, opening.StoredEnergy);
    }

    private static void ValidateTerminal(BatteryResource resource, BatteryTerminalConstraint? terminal)
    {
        if (terminal is null)
            throw Error("battery_terminal", "Supply an explicit terminal range; an exact target uses equal bounds.");
        RequireQuantity(terminal.MinimumStoredEnergy, resource.Energy.Key);
        RequireQuantity(terminal.MaximumStoredEnergy, resource.Energy.Key);
        if (terminal.MinimumStoredEnergy.Amount.CompareTo(resource.Limits.MinimumStoredEnergy.Amount) < 0 ||
            terminal.MaximumStoredEnergy.Amount.CompareTo(resource.Limits.MaximumStoredEnergy.Amount) > 0 ||
            terminal.MinimumStoredEnergy.Amount.CompareTo(terminal.MaximumStoredEnergy.Amount) > 0)
            throw Error("battery_terminal", "The terminal range must be ordered within the resource's stored-energy limits.");
    }

    private static void ValidateThroughput(BatteryResource resource, BatteryThroughputConstraint? throughput, ExactQuantity opening)
    {
        if (throughput is null || !Enum.IsDefined(throughput.Policy) ||
            throughput.Policy == BatteryThroughputPolicy.Uncapped && throughput.MaximumCumulative is not null ||
            throughput.Policy == BatteryThroughputPolicy.GridChargePlusDischarge && throughput.MaximumCumulative is null)
            throw Error("battery_throughput", "Select an explicit uncapped policy or a typed cumulative grid-energy limit.");
        if (throughput.MaximumCumulative is { } maximum)
        {
            RequireQuantity(maximum, resource.Energy.Key);
            if (maximum.Amount.CompareTo(default) < 0)
                throw Error("battery_throughput", "The maximum cumulative grid throughput cannot be negative.");
        }
        RequireThroughput(throughput, opening);
    }

    private static void RequireThroughput(BatteryThroughputConstraint throughput, ExactQuantity value)
    {
        if (throughput.MaximumCumulative is { } maximum && Compare(value, ExactQuantity.FromQuantity(maximum)) > 0)
            throw Error("battery_throughput_limit", "The supplied plan exceeds its retained cumulative grid-throughput limit.");
    }

    private static void RequireEnergyBounds(BatteryResource resource, ExactQuantity energy)
    {
        if (Compare(energy, ExactQuantity.FromQuantity(resource.Limits.MinimumStoredEnergy)) < 0 ||
            Compare(energy, ExactQuantity.FromQuantity(resource.Limits.MaximumStoredEnergy)) > 0)
            throw Error("battery_energy_limit", "A supplied state transition exceeds the resource's stored-energy bounds.");
    }

    private static void RequireQuantity(Quantity? quantity, ReferenceKey expected)
    {
        if (quantity is null || quantity.Specification != expected)
            throw Error("battery_quantity", "Every amount must use its selected exact power or energy specification.");
    }
    private static void RequireQuantity(ExactQuantity quantity, ReferenceKey expected)
    {
        if (quantity.Specification != expected)
            throw Error("battery_quantity", "Every amount must use its selected exact power or energy specification.");
    }
    private static bool ValidKey(ReferenceKey key) => key.Revision.CatalogId != Guid.Empty &&
        key.Revision.RevisionId != Guid.Empty && !string.IsNullOrWhiteSpace(key.Code);
    private static bool Coherent(QuantitySpecification? quantity) => quantity is not null &&
        new[] { quantity.Key, quantity.Commodity, quantity.MeasurementBasis, quantity.Unit, quantity.Dimension }
            .All(key => ValidKey(key) && key.Revision == quantity.Key.Revision);
    private static int Compare(ExactQuantity left, ExactQuantity right) =>
        (left.NumeratorValue * right.DenominatorValue).CompareTo(right.NumeratorValue * left.DenominatorValue);
    private static ExactQuantity Zero(ReferenceKey specification) => new(0, 1, specification);
    private static MarketDataException Error(string code, string message) => new(code, message);
}
