using System.Collections.Immutable;
using System.Text.Json.Nodes;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Calculation;
using OpenEtrm.MarketData.Options;
using OpenEtrm.MarketData.Risk;
using OpenEtrm.MarketData.Trading;
using Market=FuturesOptionChecks.OptionMarket;

// Listed option series as one-contract holdings: value, delta, gamma, vega and one-day theta from ordinary PV under
// the shared price, volatility and clock layers. Expected figures come from direct tree prices and from Black-76.
internal static class OptionSensitivityChecks
{
    private const int Call=11,Put=12,AtIntrinsic=13;
    private static readonly OptionNumericalPolicy Policy=OptionNumericalPolicies.Require(OptionNumericalPolicies.CoxRossRubinstein);
    private static readonly OptionSensitivitySelection Selection=new(new PnlFactorBump(1,2),
        new(ExactDecimal.Parse("0.000001"),ExactDecimal.Parse("0.15")),new(ExactDecimal.Parse("0.000001"),ExactDecimal.Parse("0.1")),ExactDecimal.Parse("0.01"));
    private static readonly ClockChange NextDay=new(Market.At.AddDays(1),ClockChange.FrozenInputs);

    public static void Run()
    {
        Check("option sensitivities equal differences of direct tree prices", EqualDirectTreeDifferences);
        Check("a call and a put of one strike share gamma and vega at a unit discount", CallAndPutAgree);
        Check("option sensitivities agree with Black-76 at a unit discount", AgreeWithBlack76);
        Check("an option valued at intrinsic has a value and no sensitivities", IntrinsicHasNoSensitivities);
        Check("an option whose next day reaches expiry has no theta and keeps the rest", LastDayHasNoTheta);
        Check("without a clock there is no theta", NoClockNoTheta);
        Check("a long option loses value over a day", LongOptionsDecay);
        Check("unit holdings and their sensitivities are reproducible", Reproducible);
    }

    private sealed record Case(Market Market,PreparedConnectedPortfolioRisk Prepared,ImmutableDictionary<Guid,FuturesOptionMarketBinding> Bindings)
    {
        public OptionSeriesSensitivities Of(int contract,ClockChange? day)=>
            FuturesOptionSensitivities.Calculate(Prepared,Bindings,Selection,day,CancellationToken.None).Single(s=>s.InstrumentId==Market.Option(contract).Id);
        public LatticeDecimal Volatility(int contract)=>((SolvedVolatility)Bindings[Market.Option(contract).Id].Calibration).Volatility;
    }

    // Every series of the fixture calibrated at a unit discount; the prepared portfolio holds one contract of each solved one.
    private static Case Prepare()
    {
        var market=new Market();var source=market.Snapshot();var model=market.Model();
        var options=Market.Options.Select(o=>market.Option(o.Contract)).ToArray();
        var requests=options.Select(o=>FuturesOptionPricing.Requests(model,o.Series,FuturesOptionPricing.DailySettlement)).ToArray();
        var built=model.Build(source,[..requests.SelectMany(r=>new[]{r.Underlying,r.Settlement}).Distinct()]);
        var discount=new ExplicitDiscounting(ExactDecimal.Parse("1"),DiscountFactorSource.Undiscounted);
        var bindings=options.ToImmutableDictionary(o=>o.Id,o=>FuturesOptionPricing.Prepare(o,built,source,discount,FuturesOptionPricing.DailySettlement,Policy,true,CancellationToken.None));
        var solved=options.Where(o=>bindings[o.Id].Calibration is SolvedVolatility).ToArray();
        var holdings=ValuationPortfolio.FromTrades(FuturesOptionSensitivities.UnitHoldings(solved),new(ValuationMeasure.PresentValue,
            ImmutableDictionary<Guid,FuturesMarketBinding>.Empty,null){OptionBindings=bindings});
        return new(market,RiskEngine.PrepareConnected(built.Connected,built.PricingBindings,[holdings],built),bindings);
    }

    private static LatticeDecimal Tree(Case c,int contract,LatticeDecimal futures,LatticeDecimal volatility,DateTimeOffset at)=>
        AmericanFuturesOptionModel.UnitPrice(c.Market.Option(contract).Series.Terms,futures,volatility,L("1"),at,Policy,CancellationToken.None);

    private static void EqualDirectTreeDifferences()
    {
        var c=Prepare();var actual=c.Of(Call,NextDay);
        var f=L(Market.Futures);var iv=c.Volatility(Call);var h=LatticeDecimal.From(actual.PriceBump??throw new Exception("A solved series reports its price bump."));
        var step=AmericanFuturesOptionModel.PriceStep(c.Market.Option(Call).Series.Terms,f,iv,L("1"),Market.At,Policy)??throw new Exception("The rebuilt tree declares a price step.");
        if(h.CompareTo(step+step)<0)throw new Exception($"The bump {h} is under two price steps of {step}.");
        var basis=Tree(c,Call,f,iv,Market.At);var up=Tree(c,Call,f+h,iv,Market.At);var down=Tree(c,Call,f-h,iv,Market.At);
        var point=L("0.01");
        Near(actual.Value,basis,"value");
        Near(Value(actual.Delta),(up-down)/(h+h),"delta");
        Near(Value(actual.Gamma),(up+down-basis-basis)/(h*h),"gamma");
        Near(Value(actual.Vega),(Tree(c,Call,f,iv+point,Market.At)-Tree(c,Call,f,iv-point,Market.At))/L("2"),"vega");
        Near(Value(actual.Theta),Tree(c,Call,f,iv,NextDay.At)-basis,"theta");
    }

    private static void CallAndPutAgree()
    {
        var c=Prepare();var call=c.Of(Call,NextDay);var put=c.Of(Put,NextDay);var tolerance=L("0.000000001");
        Within(Value(call.Gamma),Value(put.Gamma),tolerance,"gamma");
        Within(Value(call.Vega),Value(put.Vega),tolerance,"vega");
        Within(Value(call.Delta)-Value(put.Delta),L("1"),tolerance,"delta difference");
    }

    private static void AgreeWithBlack76()
    {
        var oracle=JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"fixtures","futures-option-oracle.json")))!["black76_greeks"]!.AsArray().Single()!;
        LatticeDecimal Field(string name)=>L(oracle[name]!.GetValue<string>());
        var seconds=(long)(Market.Expiry-Market.At).TotalSeconds;
        if(oracle["futures"]!.GetValue<string>()!=Market.Futures||oracle["strike"]!.GetValue<string>()!="3"||oracle["call"]!.GetValue<string>()!="0.08"||oracle["seconds"]!.GetValue<long>()!=seconds)
            throw new Exception("The oracle's sensitivity case is not the fixture's at-the-money call.");
        var c=Prepare();var call=c.Of(Call,NextDay);var put=c.Of(Put,NextDay);
        Within(Value(call.Delta),Field("delta_call"),L("0.01"),"call delta");
        Within(Value(put.Delta),Field("delta_put"),L("0.01"),"put delta");
        Within(Value(call.Gamma),Field("gamma"),Field("gamma")*L("0.1"),"gamma");
        // The oracle's vega is per 1.00 of volatility; a sensitivity states it per volatility point.
        Within(Value(call.Vega),Field("vega")*L("0.01"),Field("vega")*L("0.01")*L("0.02"),"vega");
    }

    private static void IntrinsicHasNoSensitivities()
    {
        var c=Prepare();var held=c.Of(AtIntrinsic,NextDay);
        Equal(held.Value.ToString(),"1");
        if(held.PriceBump is not null)throw new Exception("An option at intrinsic states no price bump.");
        foreach(var measure in new[]{held.Delta,held.Gamma,held.Vega,held.Theta})
            if(measure.Value is not null||measure.Missing!=FuturesOptionSensitivities.AtIntrinsic)throw new Exception($"Expected a missing measure at intrinsic; got {measure}.");
    }

    private static void LastDayHasNoTheta()
    {
        var c=Prepare();var last=c.Of(Call,new(Market.Expiry,ClockChange.FrozenInputs));
        if(last.Theta.Value is not null||last.Theta.Missing!="valuation_time_coverage")throw new Exception($"Expected no theta at expiry; got {last.Theta}.");
        var whole=c.Of(Call,NextDay);
        if(last.Delta!=whole.Delta||last.Gamma!=whole.Gamma||last.Vega!=whole.Vega||last.Value!=whole.Value)throw new Exception("A missing theta changed another measure.");
    }

    private static void NoClockNoTheta()
    {
        var theta=Prepare().Of(Call,null).Theta;
        if(theta.Value is not null||theta.Missing!="option_sensitivity_clock")throw new Exception($"Expected no theta without a clock; got {theta}.");
    }

    private static void LongOptionsDecay()
    {
        var c=Prepare();
        foreach(var contract in new[]{Call,Put})
            if(Value(c.Of(contract,NextDay).Theta).CompareTo(L("0"))>=0)throw new Exception($"Option {contract} did not lose value over a day.");
    }

    private static void Reproducible()
    {
        var market=new Market();var options=new[]{market.Option(Call),market.Option(Put)};
        var first=FuturesOptionSensitivities.UnitHoldings(options);var second=FuturesOptionSensitivities.UnitHoldings(options);
        if(!first.Select(t=>t.Id).SequenceEqual(second.Select(t=>t.Id))||first.Select(t=>t.Id).Distinct().Count()!=2)throw new Exception("Unit holdings need stable, distinct identities.");
        var a=Prepare();var b=Prepare();
        if(!FuturesOptionSensitivities.Calculate(a.Prepared,a.Bindings,Selection,NextDay,CancellationToken.None)
            .SequenceEqual(FuturesOptionSensitivities.Calculate(b.Prepared,b.Bindings,Selection,NextDay,CancellationToken.None)))
            throw new Exception("Two calculations from the same inputs differ.");
    }

    private static LatticeDecimal L(string value)=>LatticeDecimal.Parse(value);
    private static LatticeDecimal Value(OptionMeasure measure)=>LatticeDecimal.From(measure.Value??throw new Exception($"Expected a value; missing {measure.Missing}."));
    private static LatticeDecimal Abs(LatticeDecimal value)=>LatticeDecimal.Max(value,L("0")-value);
    // The layers round a contract's PV to 18 digits before a difference is taken, so a direct tree difference agrees to
    // well inside this, not to the last digit.
    private static void Near(LatticeDecimal actual,LatticeDecimal expected,string label)=>Within(actual,expected,L("0.000000000001"),label);
    private static void Near(ExactDecimal actual,LatticeDecimal expected,string label)=>Near(LatticeDecimal.From(actual),expected,label);
    private static void Within(LatticeDecimal actual,LatticeDecimal expected,LatticeDecimal tolerance,string label)
    { if(Abs(actual-expected).CompareTo(tolerance)>0)throw new Exception($"{label}: expected {expected} within {tolerance}; got {actual}."); }
    private static void Check(string label,Action run){run();Console.WriteLine($"PASS {label}");}
    private static void Equal(string actual,string expected){if(actual!=expected)throw new Exception($"Expected {expected}; got {actual}.");}
}
