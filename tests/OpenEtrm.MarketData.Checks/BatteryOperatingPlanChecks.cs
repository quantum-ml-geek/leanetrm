using System.Collections.Immutable;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Power.Structured;

internal static class BatteryOperatingPlanChecks
{
    public static int Run()
    {
        var fixture = new Fixture();
        var passed = 0;
        void Check(string label, Action action)
        {
            action();
            passed++;
            Console.WriteLine("PASS battery supplied plan: " + label);
        }

        Check("grid-side round trip retains energy losses and the complete state trajectory", () =>
        {
            var dispatch = fixture.Rows([("10", "0"), ("0", "8.1")]);
            var result = fixture.Evaluate(dispatch, terminalMinimum: "0", terminalMaximum: "0");
            Equal(result.TotalGridCharge, "10");
            Equal(result.TotalGridDischarge, "8.1");
            Equal(result.Intervals[0].OpeningStoredEnergy, "0");
            Equal(result.Intervals[0].ClosingStoredEnergy, "9");
            Equal(result.Intervals[1].OpeningStoredEnergy, "9");
            Equal(result.ClosingState.StoredEnergy, "0");
            Equal(result.ClosingState.CumulativeGridThroughput, "18.1");
            if (result.Implementation != BatteryOperatingPlans.Implementation ||
                result.Resource != fixture.Resource || result.ClosingState.At != dispatch[^1].Interval.End)
                throw new Exception("The plan result lost its selected implementation, resource or end-state instant.");
            // Independent cash arithmetic: 81/10 MWh at 100 minus 10 MWh at 20.
            var prices = new PriceUnit(fixture.R("usd"), fixture.Energy.Key, D("1"));
            var cash = result.TotalGridDischarge.Times(new UnitPrice(D("100"), prices))
                .Add(result.TotalGridCharge.Times(new UnitPrice(D("-20"), prices)));
            if (cash.ToMoney().Amount != D("610")) throw new Exception("The independent grid-energy cash check differs.");
        });

        Check("rational stored energy survives a continuation without decimal rounding", () =>
        {
            var resource = fixture.Resource with { Policy = fixture.Resource.Policy with { DischargeEfficiency = D("0.6") } };
            var all = fixture.Rows([("0", "1"), ("0", "2")]);
            var first = fixture.Evaluate(all[..1], resource, openingEnergy: "5");
            Fraction(first.ClosingState.StoredEnergy, "10", "3");
            var second = BatteryOperatingPlans.Evaluate(resource, first.ClosingState,
                fixture.Terminal("0", "0"), fixture.Uncapped(), all[1..], BatteryOperatingPlans.Implementation);
            Equal(second.ClosingState.StoredEnergy, "0");
            Equal(second.ClosingState.CumulativeGridThroughput, "3");
        });

        Check("opening inventory remains usable physical energy without a fabricated purchase", () =>
        {
            var resource = fixture.Resource with { Policy = fixture.Resource.Policy with { DischargeEfficiency = D("1") } };
            var result = fixture.Evaluate(fixture.Rows([("0", "4")]), resource, openingEnergy: "4",
                terminalMinimum: "0", terminalMaximum: "0");
            Equal(result.TotalGridCharge, "0");
            Equal(result.TotalGridDischarge, "4");
        });

        Check("power and available fractions bind each interval rather than clipping dispatch", () =>
        {
            var row = fixture.Rows([("5", "0")]);
            fixture.Evaluate([row[0] with { AvailableFraction = D("0.5") }]);
            Reject("battery_power_limit", () => fixture.Evaluate([row[0] with
            { ChargePower = fixture.PowerQuantity("5.000000000000000001"), AvailableFraction = D("0.5") }]));
            Reject("battery_power_limit", () => fixture.Evaluate([row[0] with { AvailableFraction = D("0") }]));
            Reject("battery_availability", () => fixture.Evaluate([row[0] with { AvailableFraction = D("1.01") }]));
            Reject("battery_availability", () => fixture.Evaluate([row[0] with { AvailableFraction = D("-0.1") }]));
        });

        Check("stored energy limits apply after every transition", () =>
        {
            var resource = fixture.Resource with { Policy = fixture.Resource.Policy with
            { ChargeEfficiency = D("1"), DischargeEfficiency = D("1") } };
            Reject("battery_energy_limit", () => fixture.Evaluate(fixture.Rows([("10", "0"), ("10", "0"), ("0", "10")]), resource));
            Reject("battery_energy_limit", () => fixture.Evaluate(fixture.Rows([("0", "1"), ("1", "0")]), resource));
            var limited = resource with { Limits = resource.Limits with { MinimumStoredEnergy = fixture.EnergyQuantity("2") } };
            Reject("battery_energy_limit", () => fixture.Evaluate(fixture.Rows([("0", "1")]), limited, openingEnergy: "2", terminalMinimum: "2"));
        });

        Check("explicit grid-throughput cap includes prior state and both directions", () =>
        {
            var rows = fixture.Rows([("10", "0"), ("0", "8.1")]);
            var cap = new BatteryThroughputConstraint(BatteryThroughputPolicy.GridChargePlusDischarge,
                fixture.EnergyQuantity("21.1"));
            var result = fixture.Evaluate(rows, openingThroughput: "3", throughput: cap);
            Equal(result.ClosingState.CumulativeGridThroughput, "21.1");
            Reject("battery_throughput_limit", () => fixture.Evaluate(rows, openingThroughput: "3",
                throughput: cap with { MaximumCumulative = fixture.EnergyQuantity("21") }));
            Reject("battery_throughput", () => fixture.Evaluate(rows,
                throughput: new(BatteryThroughputPolicy.Uncapped, fixture.EnergyQuantity("99"))));
            Reject("battery_throughput", () => fixture.Evaluate(rows,
                throughput: new(BatteryThroughputPolicy.GridChargePlusDischarge, null)));
        });

        Check("the state carries across operating midnight", () =>
        {
            var rows = fixture.Rows([("5", "0"), ("0", "4.05")], skip: 23);
            var result = fixture.Evaluate(rows, terminalMinimum: "0", terminalMaximum: "0");
            if (rows[0].Interval.OperatingDate == rows[1].Interval.OperatingDate)
                throw new Exception("The fixture must cross operating midnight.");
            Equal(result.Intervals[1].OpeningStoredEnergy, "4.5");
            Equal(result.ClosingState.StoredEnergy, "0");
        });

        Check("native 23 and 25 hour grids conserve actual elapsed energy", () =>
        {
            var clock = PowerClock.Capture(TimeZoneInfo.FindSystemTimeZoneById("America/New_York"));
            foreach (var (day, expected) in new[] { (new DateOnly(2027, 3, 14), "23"), (new DateOnly(2026, 11, 1), "25") })
            {
                var resource = fixture.Resource with
                {
                    OperatingClock = clock,
                    Limits = fixture.Resource.Limits with { MaximumStoredEnergy = fixture.EnergyQuantity("30") },
                    Policy = fixture.Resource.Policy with { ChargeEfficiency = D("1") }
                };
                var intervals = PowerHours.Compile(day, day.AddDays(1), clock, TimeOfUse.All(60), [], 60);
                var rows = intervals.Select(p => new BatteryDispatchInterval(p.Delivery,
                    fixture.PowerQuantity("1"), fixture.PowerQuantity("0"), D("1"), BatteryChargingOrigin.Grid)).ToImmutableArray();
                var result = fixture.Evaluate(rows, resource, terminalMinimum: expected, terminalMaximum: expected);
                Equal(result.TotalGridCharge, expected);
                Equal(result.ClosingState.StoredEnergy, expected);
                if (expected == "25" && result.Intervals.Count(r => r.Dispatch.Interval.HourBeginning == 1) != 2)
                    throw new Exception("The repeated local hour must retain both UTC intervals.");
            }
        });

        Check("short intervals retain exact energy below the decimal boundary", () =>
        {
            var resource = fixture.Resource with { IntervalMinutes = 5 };
            var rows = fixture.Rows([("1", "0")], minutes: 5);
            var result = fixture.Evaluate(rows, resource);
            Fraction(result.TotalGridCharge, "1", "12");
            Equal(result.ClosingState.StoredEnergy, "0.075");
            Reject("precision_loss", () => result.TotalGridCharge.ToQuantity());
        });

        Check("simultaneous cycling is prohibited independently of price incentives", () =>
        {
            Reject("battery_simultaneous", () => fixture.Evaluate(fixture.Rows([("1", "1")]), openingEnergy: "5"));
            var rows = fixture.Rows([("0", "0")]);
            fixture.Evaluate(rows);
            Reject("battery_dispatch", () => fixture.Evaluate([rows[0] with { ChargePower = fixture.PowerQuantity("-1") }]));
            Reject("battery_dispatch", () => fixture.Evaluate([rows[0] with { DischargePower = fixture.PowerQuantity("-1") }]));
            Reject("battery_policy", () => fixture.Evaluate(rows, fixture.Resource with
            { Policy = fixture.Resource.Policy with { SimultaneousOperation = (BatterySimultaneousPolicy)99 } }));
        });

        Check("efficiencies and every selected operating policy are explicit", () =>
        {
            var rows = fixture.Rows([("0", "0")]);
            foreach (var value in new[] { "0", "-0.1", "1.000000000000000001" })
            {
                Reject("battery_efficiency", () => fixture.Evaluate(rows, fixture.Resource with
                { Policy = fixture.Resource.Policy with { ChargeEfficiency = D(value) } }));
                Reject("battery_efficiency", () => fixture.Evaluate(rows, fixture.Resource with
                { Policy = fixture.Resource.Policy with { DischargeEfficiency = D(value) } }));
            }
            Reject("battery_policy", () => fixture.Evaluate(rows, fixture.Resource with
            { Policy = fixture.Resource.Policy with { Boundary = (BatteryMeterBoundary)0 } }));
            Reject("battery_policy", () => fixture.Evaluate(rows, fixture.Resource with
            { Policy = fixture.Resource.Policy with { Losses = (BatteryLossPolicy)0 } }));
            Reject("battery_policy", () => fixture.Evaluate(rows, fixture.Resource with
            { Policy = fixture.Resource.Policy with { Capacity = (BatteryCapacityPolicy)0 } }));
            Reject("battery_implementation", () => BatteryOperatingPlans.Evaluate(fixture.Resource, fixture.State(rows[0].Interval.Start),
                fixture.Terminal("0", "10"), fixture.Uncapped(), rows, "unqualified"));
        });

        Check("reference versions and physical quantity definitions cannot be substituted", () =>
        {
            var rows = fixture.Rows([("0", "0")]);
            var foreign = new ReferenceRevision(Guid.NewGuid(), Guid.NewGuid());
            foreach (var changed in new[]
            {
                fixture.Resource with { Clock = new(foreign, "clock") },
                fixture.Resource with { Location = new(foreign, "location") },
                fixture.Resource with { Energy = fixture.Energy with { Unit = new(foreign, "megawatt_hour") } },
                fixture.Resource with { Power = fixture.Power with { Dimension = fixture.R("energy") } },
                fixture.Resource with { Energy = fixture.Energy with { Commodity = fixture.R("another_commodity") } },
                fixture.Resource with { Code = "" },
                fixture.Resource with { Definitions = default }
            }) Reject("battery_resource", () => fixture.Evaluate(rows, changed));
            Reject("battery_quantity", () => fixture.Evaluate([rows[0] with { ChargePower = fixture.EnergyQuantity("0") }]));
            Reject("battery_quantity", () => fixture.Evaluate(rows, fixture.Resource with
            { Limits = fixture.Resource.Limits with { MaximumChargePower = fixture.EnergyQuantity("10") } }));
            Reject("battery_quantity", () => fixture.Evaluate(rows, opening: fixture.State(rows[0].Interval.Start) with
            { StoredEnergy = ExactQuantity.FromQuantity(fixture.PowerQuantity("0")) }));
            var collapsed = fixture.Resource with
            {
                Energy = fixture.Energy with { Key = fixture.Power.Key },
                Limits = fixture.Resource.Limits with
                { MinimumStoredEnergy = fixture.PowerQuantity("0"), MaximumStoredEnergy = fixture.PowerQuantity("10") }
            };
            var zero = ExactQuantity.FromQuantity(fixture.PowerQuantity("0"));
            Reject("battery_resource", () => BatteryOperatingPlans.Evaluate(collapsed,
                new(rows[0].Interval.Start, zero, zero), new(fixture.PowerQuantity("0"), fixture.PowerQuantity("10")),
                fixture.Uncapped(), rows, BatteryOperatingPlans.Implementation));
        });

        Check("grid gaps, overlap, ordering, offsets and false native labels refuse", () =>
        {
            var rows = fixture.Rows([("0", "0"), ("0", "0"), ("0", "0")]);
            foreach (var invalid in new[]
            {
                ImmutableArray<BatteryDispatchInterval>.Empty,
                ImmutableArray<BatteryDispatchInterval>.Empty.Add(rows[0]).Add(rows[2]),
                rows.Add(rows[0]),
                rows.Reverse().ToImmutableArray(),
                rows.SetItem(0, rows[0] with { Interval = rows[0].Interval with { End = rows[0].Interval.End.AddMinutes(1) } }),
                rows.SetItem(0, rows[0] with { Interval = rows[0].Interval with { Start = rows[0].Interval.Start.ToOffset(TimeSpan.FromHours(1)) } }),
                rows.SetItem(0, rows[0] with { Interval = rows[0].Interval with { HourBeginning = 7 } }),
                rows.SetItem(0, rows[0] with { Interval = rows[0].Interval with { Occurrence = 2 } })
            }) Reject("battery_grid", () => fixture.Evaluate(invalid));
            Reject("battery_opening_state", () => fixture.Evaluate(rows, opening: fixture.State(rows[0].Interval.Start.AddHours(-1))));
        });

        Check("opening and terminal state bounds are required and enforced", () =>
        {
            var rows = fixture.Rows([("1", "0")]);
            Reject("battery_energy_limit", () => fixture.Evaluate(rows, openingEnergy: "-1"));
            Reject("battery_energy_limit", () => fixture.Evaluate(rows, openingEnergy: "11"));
            Reject("battery_terminal", () => fixture.Evaluate(rows, terminalMinimum: "1", terminalMaximum: "1"));
            Reject("battery_terminal", () => fixture.Evaluate(rows, terminalMinimum: "2", terminalMaximum: "1"));
            Reject("battery_terminal", () => fixture.Evaluate(rows, terminalMinimum: "-1", terminalMaximum: "10"));
            Reject("battery_opening_state", () => fixture.Evaluate(rows, openingThroughput: "-1"));
            Reject("battery_charging_origin", () => fixture.Evaluate([rows[0] with { ChargingOrigin = (BatteryChargingOrigin)0 }]));
            Reject("battery_resource", () => BatteryOperatingPlans.Evaluate(null!, fixture.State(rows[0].Interval.Start),
                fixture.Terminal("0", "10"), fixture.Uncapped(), rows, BatteryOperatingPlans.Implementation));
        });

        Check("forged distant local labels refuse within the bounded input-validation budget", () =>
        {
            var resource=fixture.Resource with{IntervalMinutes=5};
            var rows=fixture.Rows([("0","0"),("0","0")],minutes:5);
            var forged=rows.SetItem(1,rows[1] with{Interval=rows[1].Interval with{OperatingDate=new DateOnly(2031,12,31)}});
            Reject("battery_grid",()=>fixture.Evaluate(rows.SetItem(1,rows[1] with{Interval=rows[1].Interval with{HourBeginning=7}}),resource));
            var before=GC.GetAllocatedBytesForCurrentThread();
            Reject("battery_grid",()=>fixture.Evaluate(forged,resource));
            var allocated=GC.GetAllocatedBytesForCurrentThread()-before;
            if(allocated>1_000_000)throw new Exception($"A two-row forged plan allocated {allocated} bytes before rejection; local labels must not expand a native year.");
        });

        Check("identical retained inputs have deterministic immutable outputs", () =>
        {
            var rows = fixture.Rows([("2", "0"), ("0", "1.62")]);
            var first = fixture.Evaluate(rows);
            var second = fixture.Evaluate(rows);
            if (!first.Intervals.SequenceEqual(second.Intervals) || first.ClosingState != second.ClosingState ||
                first.TotalGridCharge != second.TotalGridCharge || first.TotalGridDischarge != second.TotalGridDischarge)
                throw new Exception("Identical supplied plans must produce identical exact results.");
            if (rows[0].ChargePower.Amount != D("2") || rows[1].DischargePower.Amount != D("1.62"))
                throw new Exception("Evaluation mutated the admitted dispatch plan.");
        });

        return passed;
    }

    private static ExactDecimal D(string value) => ExactDecimal.Parse(value);
    private static void Equal(ExactQuantity actual, string expected)
    {
        if (actual.ToQuantity().Amount != D(expected)) throw new Exception($"Expected {expected}; got {actual.Numerator}/{actual.Denominator}.");
    }
    private static void Fraction(ExactQuantity actual, string numerator, string denominator)
    {
        if (actual.Numerator != numerator || actual.Denominator != denominator)
            throw new Exception($"Expected {numerator}/{denominator}; got {actual.Numerator}/{actual.Denominator}.");
    }
    private static void Reject(string code, Action action)
    {
        try { action(); }
        catch (MarketDataException e) when (e.Code == code) { return; }
        throw new Exception("Expected " + code);
    }

    private sealed class Fixture
    {
        private readonly ReferenceRevision reference = new(Guid.NewGuid(), Guid.NewGuid());
        public ReferenceKey R(string code) => new(reference, code);
        public QuantitySpecification Power { get; }
        public QuantitySpecification Energy { get; }
        public BatteryResource Resource { get; }
        public Fixture()
        {
            Power = new(R("power_quantity"), R("electricity"), R("grid_ac_power"), R("megawatt"), R("power"));
            Energy = new(R("energy_quantity"), R("electricity"), R("grid_ac_energy"), R("megawatt_hour"), R("energy"));
            Resource = new(new(Guid.NewGuid(), Guid.NewGuid()), "synthetic_battery", R("connection"), R("clock"),
                PowerClock.Capture(TimeZoneInfo.Utc), 60, Power, Energy,
                new(PowerQuantity("10"), PowerQuantity("10"), EnergyQuantity("0"), EnergyQuantity("10")),
                new(D("0.9"), D("0.9"), BatteryMeterBoundary.GridSideAc, BatteryLossPolicy.ZeroAuxiliaryAndSelfDischarge,
                    BatteryCapacityPolicy.Fixed, BatterySimultaneousPolicy.Prohibited));
        }
        public Quantity PowerQuantity(string value) => new(D(value), Power.Key);
        public Quantity EnergyQuantity(string value) => new(D(value), Energy.Key);
        public BatteryState State(DateTimeOffset at, string energy = "0", string throughput = "0") =>
            new(at, ExactQuantity.FromQuantity(EnergyQuantity(energy)), ExactQuantity.FromQuantity(EnergyQuantity(throughput)));
        public BatteryTerminalConstraint Terminal(string minimum, string maximum) => new(EnergyQuantity(minimum), EnergyQuantity(maximum));
        public BatteryThroughputConstraint Uncapped() => new(BatteryThroughputPolicy.Uncapped, null);
        public ImmutableArray<BatteryDispatchInterval> Rows((string Charge, string Discharge)[] amounts, int skip = 0, int minutes = 60)
        {
            var intervals = PowerHours.Compile(new(2031, 1, 1), new(2031, 1, 3), Resource.OperatingClock, TimeOfUse.All(minutes), [], minutes);
            return amounts.Select((amount, i) => new BatteryDispatchInterval(intervals[skip + i].Delivery,
                PowerQuantity(amount.Charge), PowerQuantity(amount.Discharge), D("1"), BatteryChargingOrigin.Grid)).ToImmutableArray();
        }
        public BatteryPlanResult Evaluate(ImmutableArray<BatteryDispatchInterval> rows, BatteryResource? resource = null,
            string openingEnergy = "0", string openingThroughput = "0", string terminalMinimum = "0", string terminalMaximum = "10",
            BatteryState? opening = null, BatteryThroughputConstraint? throughput = null)
        {
            var at = rows.IsDefaultOrEmpty ? new DateTimeOffset(2031, 1, 1, 0, 0, 0, TimeSpan.Zero) : rows[0].Interval.Start;
            return BatteryOperatingPlans.Evaluate(resource ?? Resource, opening ?? State(at, openingEnergy, openingThroughput),
                Terminal(terminalMinimum, terminalMaximum), throughput ?? Uncapped(), rows, BatteryOperatingPlans.Implementation);
        }
    }
}
