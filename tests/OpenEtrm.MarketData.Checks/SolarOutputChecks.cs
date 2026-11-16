using System.Collections.Immutable;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Power.Structured;
using OpenEtrm.Shared.Numerics;

internal static class SolarOutputChecks
{
    public static int Run()
    {
        var f = new Fixture();
        var row = SolarOutputRights.Evaluate(f.Terms, f.Context, [f.Input]).Rows.Single();
        Amount(row.PhysicalEnergy, "8"); Amount(row.PaymentEnergy, "10");
        Amount(row.EligibleActualEnergy, "8"); Amount(row.DeliveryObligation, "8");
        Amount(row.ReplacementEnergy, "0"); Amount(row.SurplusEnergy, "0");
        var half = SolarOutputRights.Evaluate(f.Terms with { EntitlementFraction = new(1, 2) }, f.Context, [f.Input]).Rows.Single();
        Amount(half.PhysicalEnergy, "4"); Amount(half.PaymentEnergy, "5"); Amount(half.EligibleActualEnergy, "4");
        var third = SolarOutputRights.Evaluate(f.Terms with { EntitlementFraction = new(1, 3) }, f.Context, [f.Input]).Rows.Single();
        if (third.PaymentEnergy.Numerator != "10" || third.PaymentEnergy.Denominator != "3")
            throw new Exception("An entitlement fraction retains exact quantity rather than rounding each contribution.");
        var firm = f.Terms with { DeliveryBasis = SolarDeliveryBasis.FixedProfile, PaymentBasis = SolarPaymentBasis.DeliveryObligation };
        var firmRow = SolarOutputRights.Evaluate(firm, f.Context, [f.Input with { RequiredDelivery = f.Q("10"), Deemed = f.Q("0"), DeemedRevision = null, DeemedKnownAt = null }]).Rows.Single();
        Amount(firmRow.PhysicalEnergy, "8"); Amount(firmRow.PaymentEnergy, "10"); Amount(firmRow.ReplacementEnergy, "2");
        var surplus = SolarOutputRights.Evaluate(firm, f.Context, [f.Input with { RequiredDelivery = f.Q("6"), Deemed = f.Q("0"), DeemedRevision = null, DeemedKnownAt = null }]).Rows.Single();
        Amount(surplus.SurplusEnergy, "2");
        var forecast = f.Input with { State = VolumeState.Forecast, ProductionKnownAt = f.Input.Interval.Start.AddMinutes(-1), Deemed = f.Q("0"), DeemedRevision = null, DeemedKnownAt = null };
        var future = f.Context with { ValuationAt = f.Input.Interval.Start };
        Amount(SolarOutputRights.Evaluate(f.Terms, future, [forecast]).Rows.Single().EligibleActualEnergy, "0");
        Reject("solar_evidence", () => SolarOutputRights.Evaluate(f.Terms, future, [forecast with { ProductionKnownAt = f.Input.Interval.Start.AddMinutes(1) }]));
        var pending = f.Context with { PendingActuals = PendingActualsPolicy.EstimateUntilActual };
        Amount(SolarOutputRights.Evaluate(f.Terms, pending, [forecast]).Rows.Single().PhysicalEnergy, "8");
        Reject("solar_actual_missing", () => SolarOutputRights.Evaluate(f.Terms, pending with { ValuationAt = f.Input.MeterDueAt }, [forecast]));
        Reject("solar_actual_missing", () => SolarOutputRights.Evaluate(f.Terms, f.Context, [forecast]));
        Reject("solar_evidence", () => SolarOutputRights.Evaluate(f.Terms, future, [f.Input]));
        Reject("solar_evidence", () => SolarOutputRights.Evaluate(f.Terms, f.Context with { KnownAt = f.Input.ProductionKnownAt.AddTicks(-10) }, [f.Input]));
        Reject("solar_evidence", () => SolarOutputRights.Evaluate(f.Terms, f.Context, [f.Input with { DeemedRevision = null }]));
        Reject("solar_evidence", () => SolarOutputRights.Evaluate(f.Terms, f.Context, [f.Input with { ProductionKnownAt = f.Input.Interval.Start }]));
        Reject("solar_quantity", () => SolarOutputRights.Evaluate(f.Terms, f.Context, [f.Input with { Production = f.Q("-1") }]));
        Reject("solar_quantity", () => SolarOutputRights.Evaluate(f.Terms, f.Context, [f.Input with { Stage = QuantityStage.Delivered }]));
        Reject("solar_quantity", () => SolarOutputRights.Evaluate(f.Terms, f.Context, [f.Input with { Production = new(ExactDecimal.Parse("8"), new(f.References, "other_energy")) }]));
        Reject("solar_terms", () => SolarOutputRights.Evaluate(f.Terms with { EntitlementFraction = new(3, 2) }, f.Context, [f.Input]));
        Reject("solar_terms", () => SolarOutputRights.Evaluate(f.Terms with { DeliveryBasis = (SolarDeliveryBasis)0 }, f.Context, [f.Input]));
        Reject("solar_terms", () => SolarOutputRights.Evaluate(f.Terms with { Implementation = "unknown" }, f.Context, [f.Input]));
        Reject("solar_terms", () => SolarOutputRights.Evaluate(f.Terms, f.Context with { Definitions = new(Guid.NewGuid(), Guid.NewGuid()) }, [f.Input]));
        Reject("solar_grid", () => SolarOutputRights.Evaluate(f.Terms, f.Context, [f.Input, f.Input]));
        Reject("solar_grid", () => SolarOutputRights.Evaluate(f.Terms, f.Context, default));
        Reject("solar_grid", () => SolarOutputRights.Evaluate(f.Terms, f.Context, [f.Input with { Interval = f.Input.Interval with { Start = f.Input.Interval.Start.ToOffset(TimeSpan.FromHours(1)) } }]));
        Reject("solar_quantity", () => SolarOutputRights.Evaluate(firm, f.Context, [f.Input]));
        Reject("solar_quantity", () => SolarOutputRights.Evaluate(f.Terms, f.Context, [f.Input with { RequiredDelivery = f.Q("8") }]));
        var again = SolarOutputRights.Evaluate(f.Terms, f.Context, [f.Input]).Rows.Single();
        if (again != row) throw new Exception("Equal selected inputs must reproduce the exact immutable output.");
        SolarOutputRights.ValidateTerms(f.Terms, f.Context);
        var quarter = f.Input with { Interval = f.Input.Interval with { End = f.Input.Interval.Start.AddMinutes(15) }, Production = f.Q("3"), Deemed = f.Q("0"), DeemedRevision = null, DeemedKnownAt = null };
        Amount(SolarOutputRights.Evaluate(f.Terms with { IntervalMinutes = 15 }, f.Context, [quarter]).Rows.Single().PhysicalEnergy, "3");
        var scenarioTerms = f.Terms with { PaymentBasis = SolarPaymentBasis.ProducedOnly };
        var manual = new SolarScenarioInput(f.Input.Interval, f.Q("8"), null, QuantityStage.Generated);
        var scenario = SolarOutputRights.EvaluateScenario(scenarioTerms, future, [manual], SolarOutputRights.ScenarioImplementation);
        var manualRow = scenario.Rows.Single();
        Amount(manualRow.PhysicalEnergy, "8"); Amount(manualRow.PaymentEnergy, "8"); Amount(manualRow.EligibleActualEnergy, "0");
        if (scenario.Implementation != SolarOutputRights.ScenarioImplementation || scenario.Context != future || manualRow.Input != manual)
            throw new Exception("A hypothetical scenario retains its own explicit contract and supplied inputs without published evidence.");
        var manualFirm = SolarOutputRights.EvaluateScenario(firm, future, [manual with { RequiredDelivery = f.Q("10") }], SolarOutputRights.ScenarioImplementation).Rows.Single();
        Amount(manualFirm.PhysicalEnergy, "8"); Amount(manualFirm.PaymentEnergy, "10"); Amount(manualFirm.ReplacementEnergy, "2"); Amount(manualFirm.EligibleActualEnergy, "0");
        var manualFraction = SolarOutputRights.EvaluateScenario(scenarioTerms with { EntitlementFraction = new(1, 3) }, future, [manual], SolarOutputRights.ScenarioImplementation).Rows.Single();
        if (manualFraction.PhysicalEnergy.Numerator != "8" || manualFraction.PhysicalEnergy.Denominator != "3")
            throw new Exception("A hypothetical source uses the same exact entitlement arithmetic.");
        Reject("solar_scenario_policy", () => SolarOutputRights.EvaluateScenario(f.Terms, future, [manual], SolarOutputRights.ScenarioImplementation));
        Reject("solar_scenario_policy", () => SolarOutputRights.EvaluateScenario(scenarioTerms, future, [manual], "unknown"));
        Reject("solar_quantity", () => SolarOutputRights.EvaluateScenario(scenarioTerms, future, [manual with { Stage = QuantityStage.Delivered }], SolarOutputRights.ScenarioImplementation));
        Reject("solar_grid", () => SolarOutputRights.EvaluateScenario(scenarioTerms, future, default, SolarOutputRights.ScenarioImplementation));
        Console.WriteLine("PASS solar output rights: physical/payment/REC quantity separation, exact entitlements, residuals and explicit evidence policies");
        return 1;
    }

    private static void Amount(ExactQuantity actual, string expected)
    {
        if (actual.ToQuantity().Amount != ExactDecimal.Parse(expected)) throw new Exception($"Expected {expected}; received {actual.Numerator}/{actual.Denominator}.");
    }
    private static void Reject(string code, Action action)
    {
        try { action(); } catch (MarketDataException e) when (e.Code == code) { return; }
        throw new Exception("Expected " + code);
    }
    private sealed class Fixture
    {
        public ReferenceRevision References { get; } = new(Guid.NewGuid(), Guid.NewGuid());
        public DefinitionRevision Definitions { get; } = new(Guid.NewGuid(), Guid.NewGuid());
        public SolarOutputTerms Terms { get; }
        public SolarOutputContext Context { get; }
        public SolarOutputInput Input { get; }
        public Quantity Q(string value) => new(ExactDecimal.Parse(value), Terms.Energy.Key);
        public Fixture()
        {
            ReferenceKey R(string code) => new(References, code);
            Terms = new(new(Definitions, Guid.NewGuid()), new(Definitions, "synthetic_solar"), R("market_clock"), 60,
                new(R("power_energy"), R("power"), R("net_generation"), R("megawatt_hour"), R("energy")),
                QuantityStage.Generated, ExactRatio.One, SolarDeliveryBasis.AsProduced, SolarPaymentBasis.ProducedPlusDeemed, SolarOutputRights.Implementation);
            var start = DateTimeOffset.Parse("2035-06-01T12:00:00Z");
            Context = new(Definitions, References, start.AddHours(2), start.AddHours(3), PendingActualsPolicy.RequireActuals);
            Input = new(new(start, start.AddHours(1), new(2035, 6, 1), 12, 0, 1), Q("8"), VolumeState.Metered,
                Q("2"), null, QuantityStage.Generated, Guid.NewGuid(), start.AddMinutes(65), Guid.NewGuid(), start.AddMinutes(70), start.AddHours(3));
        }
    }
}
