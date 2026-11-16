using System.Collections.Immutable;
using OpenEtrm.MarketData.Calculation;
using OpenEtrm.MarketData.Options;
using OpenEtrm.MarketData.Risk;

namespace OpenEtrm.MarketData.Trading;

// What one calculation selects: the price bump and the agreement its estimates must reach (as a trading P&L report
// selects them), and the volatility bump. First derivatives are held to Delta, the second to Gamma.
public sealed record OptionSensitivitySelection(PnlFactorBump Bump,FiniteDifferenceTolerance Delta,FiniteDifferenceTolerance Gamma,ExactDecimal VolatilityBump);

// A figure, or the code of why there is none. Exactly one is stated.
public sealed record OptionMeasure(ExactDecimal? Value,string? Missing);

// One listed series per unit of quote: the value of one contract divided by its multiplier. Delta is per 1.00 of the
// underlying futures price and gamma per 1.00 squared, vega is per volatility point and theta is the change over the
// selected day, later minus earlier. PriceBump is the nominal futures bump, absent where no price sample was taken.
public sealed record OptionSeriesSensitivities(Guid InstrumentId,ExactDecimal Value,ExactDecimal? PriceBump,
    OptionMeasure Delta,OptionMeasure Gamma,OptionMeasure Vega,OptionMeasure Theta);

// Sensitivities of listed option series from ordinary instrument PV under the shared price, volatility and clock layers,
// through the common finite-difference sampler. Each series is a one-contract holding; nothing is priced here.
public static class FuturesOptionSensitivities
{
    public const string Policy="option_sensitivities_layers_v1";
    public const string AtIntrinsic="option_at_intrinsic",Unstable="sensitivity_unstable",NoClock="option_sensitivity_clock";
    public static readonly ExactDecimal VolatilityPoint=ExactDecimal.Parse("0.01");
    private static readonly ExactDecimal One=ExactDecimal.Parse("1");
    // A reported figure is its exact rational rounded once, half-even, to the 18-digit working scale.
    private static readonly AmountFormat Reported=new(18,CashTieRule.ToEven,false,false);

    // One contract of each series under identities derived from the series, so the same series give the same holdings.
    public static ImmutableArray<Trade> UnitHoldings(IEnumerable<FuturesOptionInstrument> options)=>
    [
        ..(options??throw Error("Supply the option series.")).Select(option=>new Trade(UnitTrade(option.Id),ContractIdentity.FromCanonical("option_sensitivity_book_v1"),
            [new TradeInstrument(ContractIdentity.FromCanonical($"option_sensitivity_binding_v1:{option.Id:D}"),option,new Quantity(One,option.UnitQuantity.Specification))]))
    ];
    private static Guid UnitTrade(Guid instrument)=>ContractIdentity.FromCanonical($"option_sensitivity_unit_v1:{instrument:D}");

    // The series of one underlying future. The prepared portfolio holds UnitHoldings of exactly the bindings solved for a
    // volatility; a binding valued at intrinsic takes no layer and reports its settlement with no sensitivities. A sample
    // the valuation refuses leaves its measures missing, with the refusing code, for every series; a first or second
    // difference that does not agree across half, whole and double bumps is missing as unstable. Day is the instant one
    // day later, or null where no clock was selected.
    public static ImmutableArray<OptionSeriesSensitivities> Calculate(PreparedConnectedPortfolioRisk prepared,
        ImmutableDictionary<Guid,FuturesOptionMarketBinding> bindings,OptionSensitivitySelection selection,ClockChange? day,CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        if(prepared is null||bindings is null||selection?.Bump is null||selection.Delta is null||selection.Gamma is null||selection.VolatilityBump.CompareTo(default)<=0)
            throw Error("Supply the prepared unit holdings, their bindings and an explicit selection.");
        var solved=bindings.Values.Where(b=>b.Calibration is SolvedVolatility).ToDictionary(b=>UnitTrade(b.Instrument.Id));
        if(!prepared.Holdings.Select(h=>h.TradeId).ToHashSet().SetEquals(solved.Keys)||prepared.Holdings.Length!=solved.Count)
            throw Error("The prepared portfolio must hold one contract of each solved series and nothing else.");
        OptionMeasure Absent(string code)=>new(null,code);
        var results=bindings.Values.Where(b=>b.Calibration is IntrinsicFallback).Select(b=>new OptionSeriesSensitivities(b.Instrument.Id,
            b.BaseSettlement.ToExact(),null,Absent(AtIntrinsic),Absent(AtIntrinsic),Absent(AtIntrinsic),Absent(AtIntrinsic))).ToList();
        if(solved.Count==0)return Ordered(results);
        if(prepared.Factors is not [{} future])throw Error("The series of one calculation are priced from one underlying future.");

        ExactDecimal Unit(Guid trade,ExactMoney contract)=>contract.DivideBy(solved[trade].Instrument.Series.Multiplier).ToMoney(Reported).Amount;
        ConnectedFiniteDifferenceRun Sample(ImmutableArray<ConnectedSensitivityAxis> axes,ImmutableArray<ConnectedRiskScenario> scenarios)=>
            RiskEngine.CalculateFiniteDifferences(prepared,new(ConnectedFiniteDifferenceRequest.HalfNominalDouble,axes,[]){AdditionalScenarios=scenarios},
                RiskEngine.ExactNumericalPolicy,ct,RiskDetail.Holdings);
        // One figure per holding from one derivative of a run, scaled before it is divided by the multiplier.
        Dictionary<Guid,OptionMeasure> Estimates(ConnectedFiniteDifferenceRun run,string axis,string formula,ExactDecimal scale)=>
            run.Derivatives.Single(d=>d.Formula==formula&&d.Axes.Single()==axis).Groups.SelectMany(g=>g.Positions).ToDictionary(p=>p.TradeId,
                p=>p.Estimate.Stable?new OptionMeasure(Unit(p.TradeId,p.Estimate.Nominal.Scale(scale)),null):Absent(Unstable));
        Dictionary<Guid,OptionMeasure> All(string code)=>solved.Keys.ToDictionary(trade=>trade,_=>Absent(code));

        var values=RiskEngine.CalculateExact(prepared,[],RiskEngine.ExactNumericalPolicy,ct,RiskDetail.Holdings).Groups.SelectMany(g=>g.BasePositions)
            .ToDictionary(p=>p.TradeId,p=>Unit(p.TradeId,p.Value));

        ExactDecimal? bump=null;Dictionary<Guid,OptionMeasure> delta,gamma,vega,theta;
        try
        {
            bump=selection.Bump.Size(future.TradingTick,prepared.DeclaredPriceSteps.TryGetValue(future.Input,out var step)?step:null);
            var run=Sample([new("price",new PriceSensitivityInput(new(CurveShockCoordinate.MarketQuote,new ContractCurveTarget(future.Curves[0],future.Contract),
                future.Unit,bump.Value,ConnectedRiskBump.Convention)),selection.Delta,selection.Gamma)],[]);
            delta=Estimates(run,"price",RiskEngine.CentralDelta,One);gamma=Estimates(run,"price",RiskEngine.CentralGamma,One);
        }
        catch(MarketDataException refused){bump=null;delta=All(refused.Code);gamma=All(refused.Code);}
        try
        {
            // A scenario carries a bounded number of shifts, so the series' volatility inputs are bumped in bounded sets.
            var axes=solved.Chunk(RiskEngine.MaxJointScenarioShifts).Select((set,n)=>(Id:"volatility_"+n,Trades:set.Select(s=>s.Key).ToArray(),
                Input:new VolatilitySensitivityInput([..set.Select(s=>new VolatilityWeight(s.Value.Id,One))],selection.VolatilityBump,VolatilitySensitivityInput.Convention))).ToArray();
            var run=Sample([..axes.Select(a=>new ConnectedSensitivityAxis(a.Id,a.Input,selection.Delta,selection.Gamma))],[]);
            vega=axes.SelectMany(a=>{var estimates=Estimates(run,a.Id,RiskEngine.CentralDelta,VolatilityPoint);return a.Trades.Select(trade=>(trade,estimates[trade]));})
                .ToDictionary(v=>v.trade,v=>v.Item2);
        }
        catch(MarketDataException refused){vega=All(refused.Code);}
        if(day is null)theta=All(NoClock);
        else try
        {
            const string sample="one_day";
            theta=Sample([],[new(sample,"One day later",[]){Clock=day}]).Repricing.Scenarios.Single(s=>s.Id==sample).Groups.SelectMany(g=>g.Positions)
                .ToDictionary(p=>p.TradeId,p=>new OptionMeasure(Unit(p.TradeId,p.Values.Pnl),null));
        }
        catch(MarketDataException refused){theta=All(refused.Code);}

        results.AddRange(solved.Select(s=>new OptionSeriesSensitivities(s.Value.Instrument.Id,values[s.Key],bump,delta[s.Key],gamma[s.Key],vega[s.Key],theta[s.Key])));
        return Ordered(results);
    }

    private static ImmutableArray<OptionSeriesSensitivities> Ordered(IEnumerable<OptionSeriesSensitivities> results)=>[..results.OrderBy(r=>r.InstrumentId)];
    private static MarketDataException Error(string message)=>new("option_sensitivity_input",message);
}
