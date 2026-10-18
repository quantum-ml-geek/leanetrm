using System.Collections.Immutable;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;
using OpenEtrm.MarketData.Risk;

internal static class IndependentSideChecks
{
    public static int Run()
    {
        var passed = 0;
        void Check(string name, Action test) { test(); passed++; Console.WriteLine("PASS independent sides: " + name); }
        void Equal(string actual, string expected) { if (actual != expected) throw new Exception($"Expected {expected}, got {actual}"); }
        void Reject(string code, Action test)
        { try { test(); } catch (MarketDataException e) when (e.Code == code) { return; } throw new Exception("Expected " + code); }
        var f = new Fixture(); var quote = f.Quotes[0]; var unit = new Quantity(ExactDecimal.Parse("1"), quote.Quantity);
        var contract = f.Contracts[1]; var snapshot = f.Snapshot();
        var fixedAt = Fixture.Utc("2041-02-02T12:00:00Z"); var floatAt = fixedAt.AddMonths(1);
        var fixedSide = new FixedSide(Guid.NewGuid(), new UnitPrice(ExactDecimal.Parse("3"), quote), unit,
            contract.DeliveryFrom, contract.DeliveryTo, fixedAt, FixedSide.Implementation,quote);
        var floating = new FloatingSide(Guid.NewGuid(), f.R("index"), quote, unit, contract.DeliveryFrom, contract.DeliveryTo,
            Fixture.Utc("2040-12-19T00:00:00Z"), floatAt, FloatingAveraging.MonthlyIndexPrice,
            [new(new(f.C("base_forward"), contract.Key), contract)], FloatingSide.Implementation);
        var market = f.Model().Build(snapshot, floating.Dependencies);
        Check("composed instruments require explicit nonempty valid memberships", () =>
        {
            Reject("instrument_definition",()=>new TestInstrument([],quote.Currency,unit));
            Reject("instrument_definition",()=>new TestInstrument(default,quote.Currency,unit));
            Reject("instrument_definition",()=>new TestInstrument([null!],quote.Currency,unit));
            Reject("instrument_definition",()=>new TestInstrument([new(null!,ExactDecimal.Parse("1"))],quote.Currency,unit));
        });
        Check("absolute holding quantities cannot enter reusable fixed or floating sides", () =>
        {
            var holdingQuantity = new Quantity(ExactDecimal.Parse("3"), quote.Quantity);
            Reject("swap_definition", () => new FixedSide(Guid.NewGuid(), fixedSide.Price, holdingQuantity,
                contract.DeliveryFrom, contract.DeliveryTo, fixedAt, "independent_fixed_quantity_v2",quote));
            Reject("swap_definition", () => new FloatingSide(Guid.NewGuid(), f.R("index"), quote, holdingQuantity,
                contract.DeliveryFrom, contract.DeliveryTo, Fixture.Utc("2040-12-19T00:00:00Z"), floatAt,
                FloatingAveraging.MonthlyIndexPrice, floating.Projections, "independent_floating_quantity_v2"));
            Reject("swap_definition", () => new FixedSide(Guid.NewGuid(), fixedSide.Price, holdingQuantity,
                contract.DeliveryFrom, contract.DeliveryTo, fixedAt, FixedSide.Implementation,quote));
            Reject("swap_definition", () => new FloatingSide(Guid.NewGuid(), f.R("index"), quote, holdingQuantity,
                contract.DeliveryFrom, contract.DeliveryTo, Fixture.Utc("2040-12-19T00:00:00Z"), floatAt,
                FloatingAveraging.MonthlyIndexPrice, floating.Projections, FloatingSide.Implementation));
        });
        var source = new TestDiscounting((schedule, context) => schedule.Payments.Select(p => new SidePaymentFactor(p.Key,
            ExactDecimal.Parse(p.PaymentAt == fixedAt ? "0.5" : "0.8"), context, DiscountFactorSource.Explicit)).ToImmutableArray());
        var context = new SideValuationContext(market, source);
        FinancialSwapInstrument Swap(string fixedSign) => new(Guid.NewGuid(), [new(fixedSide, ExactDecimal.Parse(fixedSign)),
            new(floating, ExactDecimal.Parse(fixedSign == "-1" ? "1" : "-1"))], FinancialSwapInstrument.Implementation, true);
        Check("each side independently prices its own schedule and payment date without a trade quantity", () =>
        {
            var a = fixedSide.PV(context); var b = floating.PV(context);
            Equal(a.PresentValue.ToMoney().Amount.ToString(), "1.5"); Equal(b.PresentValue.ToMoney().Amount.ToString(), "2.48");
            if (a.Payments.Single().Plan.PaymentAt != fixedAt || b.Payments.Single().Plan.PaymentAt != floatAt ||
                a.Payments.Single().Plan.Key.SideId != fixedSide.Id || b.Payments.Single().Plan.Key.SideId != floating.Id ||
                a.Payments.Single().CashAmount.ToMoney().Amount.ToString() != "3" ||
                b.Payments.Single().CashAmount.ToMoney().Amount.ToString() != "3.1") throw new Exception("Lost independent schedules");
        });
        Check("instrument signs already-valued sides and trade scaling occurs once afterward", () =>
        {
            var value = Swap("-1").PV(context);
            Equal(value.PresentValue.ToMoney().Amount.ToString(), "0.98");
            Equal(value.PresentValue.Scale(ExactDecimal.Parse("100")).ToMoney().Amount.ToString(), "98");
            Equal(value.Sides[0].Value.PresentValue.ToMoney().Amount.ToString(), "1.5");
            Equal(value.Sides[0].Contribution.ToMoney().Amount.ToString(), "-1.5");
            Equal(Swap("1").PV(context).PresentValue.Scale(ExactDecimal.Parse("100")).ToMoney().Amount.ToString(), "-98");
            Equal(fixedSide.PV(context).PresentValue.ToMoney().Amount.ToString(), "1.5");
        });
        Check("fixed side can value without commodity market data while floating side requires its declared lookups", () =>
        {
            var noCommodity = new SideValuationContext(snapshot, source);
            Equal(fixedSide.PV(noCommodity).PresentValue.ToMoney().Amount.ToString(), "1.5");
            Reject("side_market_inputs", () => floating.PV(noCommodity));
        });
        Check("each side validates complete factor ownership and full context", () =>
        {
            var key = fixedSide.GenerateSchedule().Payments.Single().Key;
            var valid = new SidePaymentFactor(key, ExactDecimal.Parse("0.5"), snapshot, DiscountFactorSource.Explicit);
            void Bad(ImmutableArray<SidePaymentFactor> factors, string code = "side_payment_factors") =>
                Reject(code, () => fixedSide.PV(new SideValuationContext(market, new TestDiscounting((_, _) => factors))));
            Bad([]); Bad([valid, valid]); Bad([valid, valid with { Payment = key with { Ordinal = 1 } }]);
            Bad([valid with { Payment = key with { SideId = floating.Id } }]);
            Bad([valid with { Payment = key with { PaymentAt = fixedAt.AddMinutes(1) } }]);
            Bad([valid with { Payment = key with { Currency = f.R("other") } }]);
            Bad([valid with { DiscountFactor = default }]);
            Bad([valid with { Source = (DiscountFactorSource)0 }]);
            Bad([valid with { Source = DiscountFactorSource.Undiscounted }]);
            Bad([valid with { Snapshot = null! }]);
            Bad([valid with { Snapshot = snapshot with { MarketCutoff = snapshot.MarketCutoff.AddMinutes(-1) } }]);
            Bad([valid with { Snapshot = snapshot with { Selections = snapshot.Selections.SetItem(0,
                snapshot.Selections[0] with { Observation = snapshot.Selections[0].Observation with { Value = ExactDecimal.Parse("4") } }) } }]);
        });
        Check("instrument refuses a cached side PV from different full inputs even with the same snapshot identity", () =>
        {
            var current = fixedSide.PV(context);
            var oldSnapshot = snapshot with { ValuationAt = snapshot.ValuationAt.AddMinutes(1) };
            var stale = fixedSide.PV(new SideValuationContext(oldSnapshot, source));
            var wrong = new RecordedSide(stale);
            var instrument = new TestInstrument([new(wrong, ExactDecimal.Parse("1"))], quote.Currency, unit);
            Reject("instrument_context", () => instrument.PV(context));
            var changedInputs = snapshot with { Selections = snapshot.Selections.SetItem(0,
                snapshot.Selections[0] with { Observation = snapshot.Selections[0].Observation with { Value = ExactDecimal.Parse("4") } }) };
            var changedValue = fixedSide.PV(new SideValuationContext(changedInputs, source));
            var changedInstrument = new TestInstrument([new(new RecordedSide(changedValue), ExactDecimal.Parse("1"))], quote.Currency, unit);
            Reject("instrument_context", () => changedInstrument.PV(context));
            var valid = new TestInstrument([new(new RecordedSide(current), ExactDecimal.Parse("1"))], quote.Currency, unit);
            Equal(valid.PV(context).PresentValue.ToMoney().Amount.ToString(), "1.5");
        });
        Check("instrument refuses cached PVs from different discount inputs or shared-snapshot scenarios", () =>
        {
            var half = new SideValuationContext(market, new ExplicitDiscounting(ExactDecimal.Parse("0.5"), DiscountFactorSource.Explicit));
            var whole = new SideValuationContext(market, new ExplicitDiscounting(ExactDecimal.Parse("1"), DiscountFactorSource.Explicit));
            var cached = new TestInstrument([new(new RecordedSide(fixedSide.PV(half)), ExactDecimal.Parse("1"))], quote.Currency, unit);
            Reject("instrument_context", () => cached.PV(whole));
            var bump = new QuoteBump(new(f.S(1), InputUse.Variable), quote.Key, PriceUnit.FromQuote(quote),
                ExactDecimal.Parse("0.1"), QuoteBump.Convention);
            var scenarios = f.Model().BuildScenarios(snapshot, floating.Dependencies, [bump]);
            var discounting = new ExplicitDiscounting(ExactDecimal.Parse("1"), DiscountFactorSource.Undiscounted);
            var baseContext = new SideValuationContext(scenarios.Base, discounting);
            var upContext = new SideValuationContext(scenarios.Factors[0].Up, discounting);
            var baseValue = floating.PV(baseContext); var upValue = floating.PV(upContext);
            if (baseValue.PresentValue == upValue.PresentValue) throw new Exception("The selected factor did not affect the side");
            var cachedBase = new TestInstrument([new(new RecordedSide(baseValue), ExactDecimal.Parse("1"))], quote.Currency, unit);
            Reject("instrument_context", () => cachedBase.PV(upContext));
        });
        Check("standalone context rejects conflicting contents for one observation identity", () =>
        {
            var a = snapshot.Selections[0]; var b = snapshot.Selections[1];
            var conflict = snapshot with { Selections = snapshot.Selections.SetItem(1,
                b with { Observation = b.Observation with { Key = a.Observation.Key } }) };
            Reject("side_context", () => fixedSide.PV(new SideValuationContext(conflict, source)));
        });
        Check("side quote multipliers normalize independently before instrument aggregation", () =>
        {
            var scaled = new FixedSide(Guid.NewGuid(), new UnitPrice(ExactDecimal.Parse("3"),
                new PriceUnit(quote.Currency, quote.Quantity, ExactDecimal.Parse("0.01"))), unit,
                contract.DeliveryFrom, contract.DeliveryTo, fixedAt, FixedSide.Implementation,quote with {Multiplier=ExactDecimal.Parse("0.01")});
            var instrument = new FinancialSwapInstrument(Guid.NewGuid(), [new(scaled, ExactDecimal.Parse("-1")),
                new(floating, ExactDecimal.Parse("1"))], FinancialSwapInstrument.Implementation, false);
            var undiscounted = new SideValuationContext(market, new ExplicitDiscounting(ExactDecimal.Parse("1"), DiscountFactorSource.Undiscounted));
            Equal(instrument.PV(undiscounted).PresentValue.Scale(ExactDecimal.Parse("100")).ToMoney().Amount.ToString(), "307");
        });
        return passed;
    }

    private sealed class TestDiscounting(Func<SidePaymentSchedule, MarketSnapshot, ImmutableArray<SidePaymentFactor>> resolve) : ISideDiscounting
    {
        public ImmutableArray<SidePaymentFactor> Resolve(SidePaymentSchedule schedule, MarketSnapshot snapshot) => resolve(schedule, snapshot);
    }
    private sealed record RecordedSide(SideValuation Value) : Side(Value.SideId)
    {
        public override ImmutableArray<CurveRequest> Dependencies => Value.Schedule.Dependencies;
        public override SidePaymentSchedule GenerateSchedule() => Value.Schedule;
        public override SideValuation PV(SideValuationContext context) => Value;
    }
    private sealed record TestInstrument : SidedInstrument
    {
        public override ReferenceKey Currency { get; }
        public override Quantity UnitQuantity { get; }
        public TestInstrument(ImmutableArray<SideMembership> sides, ReferenceKey currency, Quantity unit) : base(Guid.NewGuid(), sides)
        { Currency = currency; UnitQuantity = unit; }
    }
}
