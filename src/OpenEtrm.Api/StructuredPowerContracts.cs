using System.Text.Json.Serialization;

namespace OpenEtrm.Api;

// Saved operating parameters contain only supported physical/model inputs.
// Contractual price, entitlement, guarantees, dispatch and state are preview inputs.
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredPowerFacilityTerms(
    [property:JsonRequired]string Kind,
    [property:JsonRequired]Guid DefinitionCatalogId,
    [property:JsonRequired]Guid DefinitionRevisionId,
    [property:JsonRequired]Guid ReferenceCatalogId,
    [property:JsonRequired]Guid ReferenceRevisionId,
    [property:JsonRequired]string FacilityCode,
    [property:JsonRequired]string ClockCode,
    [property:JsonRequired]int IntervalMinutes,
    [property:JsonRequired]string? PowerQuantityCode,
    [property:JsonRequired]string EnergyQuantityCode,
    [property:JsonRequired]string? FuelQuantityCode,
    [property:JsonRequired]StructuredBatteryParameters? Battery,
    [property:JsonRequired]StructuredThermalParameters? Thermal,
    [property:JsonRequired]StructuredSolarParameters? Solar,
    [property:JsonRequired]string Implementation);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredBatteryParameters(
    [property:JsonRequired]string MaximumChargeMw,
    [property:JsonRequired]string MaximumDischargeMw,
    [property:JsonRequired]string MinimumStoredMwh,
    [property:JsonRequired]string MaximumStoredMwh,
    [property:JsonRequired]string ChargeEfficiency,
    [property:JsonRequired]string DischargeEfficiency,
    [property:JsonRequired]string MeterBoundary,
    [property:JsonRequired]string LossPolicy,
    [property:JsonRequired]string CapacityPolicy,
    [property:JsonRequired]string SimultaneousPolicy,
    [property:JsonRequired]string ChargingOrigin,
    [property:JsonRequired]string ThroughputPolicy,
    [property:JsonRequired]string? MaximumThroughputMwh);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredThermalParameters(
    [property:JsonRequired]string MinimumOutputMw,
    [property:JsonRequired]string MaximumOutputMw,
    [property:JsonRequired]string RampUpMwPerHour,
    [property:JsonRequired]string RampDownMwPerHour,
    [property:JsonRequired]string StartupMaximumOutputMw,
    [property:JsonRequired]string ShutdownMaximumOutputMw,
    [property:JsonRequired]int MinimumUpMinutes,
    [property:JsonRequired]int MinimumDownMinutes,
    [property:JsonRequired]int StartupLeadMinutes,
    [property:JsonRequired]int MaximumStarts,
    [property:JsonRequired]string ConsumptionHeatRate,
    [property:JsonRequired]string ConsumptionNoLoadFuelPerHour,
    [property:JsonRequired]string ConsumptionStartupFuel);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredSolarParameters(
    [property:JsonRequired]string Stage);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredPowerFacilityVersion(
    [property:JsonRequired]Guid Id,
    [property:JsonRequired]int Version,
    [property:JsonRequired]string EffectiveFrom,
    [property:JsonRequired]string EffectiveTo,
    [property:JsonRequired]StructuredPowerFacilityTerms Terms);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredPowerGridInput(
    [property:JsonRequired]string OperatingDate,
    [property:JsonRequired]int FirstInterval);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredBatteryStateInput(
    [property:JsonRequired]string At,
    [property:JsonRequired]string StoredMwh,
    [property:JsonRequired]string CumulativeGridThroughputMwh,
    [property:JsonRequired]string TerminalMinimumMwh,
    [property:JsonRequired]string TerminalMaximumMwh);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredBatteryDispatchInput(
    [property:JsonRequired]string ChargeMw,
    [property:JsonRequired]string DischargeMw,
    [property:JsonRequired]string AvailablePowerFraction);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredThermalStateInput(
    [property:JsonRequired]string At,
    [property:JsonRequired]string Commitment,
    [property:JsonRequired]int ElapsedMinutes,
    [property:JsonRequired]string PreviousOutputMw,
    [property:JsonRequired]int StartsUsed,
    [property:JsonRequired]string GuaranteedHeatRate,
    [property:JsonRequired]string GuaranteedNoLoadFuelPerHour,
    [property:JsonRequired]string GuaranteedStartupFuel,
    [property:JsonRequired]string TerminalPolicy,
    [property:JsonRequired]string NumericalPolicy);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredThermalDispatchInput(
    [property:JsonRequired]string Commitment,
    [property:JsonRequired]string OutputMw,
    [property:JsonRequired]string AvailableMw,
    [property:JsonRequired]string? StartupInstructionAt);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredSolarRightInput(
    [property:JsonRequired]string ForecastAssumption,
    [property:JsonRequired]string EntitlementNumerator,
    [property:JsonRequired]string EntitlementDenominator,
    [property:JsonRequired]string DeliveryBasis,
    [property:JsonRequired]string PaymentBasis);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredSolarDispatchInput(
    [property:JsonRequired]string ProductionMwh,
    [property:JsonRequired]string? RequiredDeliveryMwh);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredPowerPriceInput(
    [property:JsonRequired]string Mode,
    [property:JsonRequired]string QuoteCode,
    [property:JsonRequired]string? FixedPrice,
    [property:JsonRequired]string? CurveCode,
    [property:JsonRequired]Guid? ContractId);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredPowerValuationInput(
    [property:JsonRequired]string Perspective,
    [property:JsonRequired]string Measure,
    [property:JsonRequired]string CurrencyCode,
    [property:JsonRequired]string RightQuantityCode,
    [property:JsonRequired]bool Discounting,
    [property:JsonRequired]PpaPaymentInput PaymentRule,
    [property:JsonRequired]StructuredPowerPriceInput EnergyPrice,
    [property:JsonRequired]StructuredPowerPriceInput? ChargingPrice,
    [property:JsonRequired]StructuredPowerPriceInput? FuelPrice,
    [property:JsonRequired]string? FuelQuantityBasis,
    [property:JsonRequired]string? AccessQuoteCode,
    [property:JsonRequired]string? AccessPrice,
    [property:JsonRequired]string? AccessFeeBasis,
    [property:JsonRequired]string? VariablePrice,
    [property:JsonRequired]string? VariableQuantityBasis,
    [property:JsonRequired]string? StartupQuoteCode,
    [property:JsonRequired]string? StartupPrice,
    [property:JsonRequired]string? StartupFeeBasis);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredPowerPreviewRequest(
    [property:JsonRequired]Guid SnapshotId,
    [property:JsonRequired]Guid FacilityId,
    [property:JsonRequired]int FacilityVersion,
    [property:JsonRequired]StructuredPowerGridInput Grid,
    [property:JsonRequired]StructuredBatteryStateInput? BatteryState,
    [property:JsonRequired]StructuredBatteryDispatchInput[] BatteryDispatch,
    [property:JsonRequired]StructuredThermalStateInput? ThermalState,
    [property:JsonRequired]StructuredThermalDispatchInput[] ThermalDispatch,
    [property:JsonRequired]StructuredSolarRightInput? SolarRight,
    [property:JsonRequired]StructuredSolarDispatchInput[] SolarDispatch,
    [property:JsonRequired]StructuredPowerValuationInput? Valuation);
