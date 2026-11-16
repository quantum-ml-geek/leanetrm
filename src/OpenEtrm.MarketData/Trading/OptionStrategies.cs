using System.Collections.Immutable;
using System.Numerics;
using OpenEtrm.MarketData.Calculation;
using OpenEtrm.MarketData.Options;
using OpenEtrm.MarketData.Risk;
using OpenEtrm.Shared.Numerics;

namespace OpenEtrm.MarketData.Trading;

// One leg of a strategy: a listed series, its signed whole lots (bought positive, sold negative) and the price it was
// entered at, per unit of quote.
public sealed record OptionStrategyLeg(FuturesOptionInstrument Option,ExactDecimal Lots,ExactDecimal EntryPrice);

// The strategy's profit and loss at one futures price: what the legs are worth there less the premium paid for them.
public sealed record OptionStrategyPoint(ExactDecimal Price,SignedRatio ProfitAndLoss);
// A dated point also states the legs' value itself, which is ordinary PV.
public sealed record OptionStrategyValuePoint(ExactDecimal Price,SignedRatio Value,SignedRatio ProfitAndLoss);
public sealed record OptionStrategyDatedCurve(DateTimeOffset At,ImmutableArray<OptionStrategyValuePoint> Points);

// Where the expiry payoff is zero: one price (Upper equals Lower), a range of prices, or every price from Lower upward
// (no Upper).
public sealed record OptionStrategyBreakeven(SignedRatio Lower,SignedRatio? Upper);

// The largest or smallest profit and loss at expiry over futures prices from zero upward, or none where it has no bound.
public sealed record OptionStrategyExtreme(SignedRatio? Amount)
{
    public bool Bounded=>Amount is not null;
}

// A strategy at expiry under Rule. NetPremium is the premium paid for the legs (negative when it is received). The curve
// is exact at every price point asked for and at every strike between the lowest and the highest of them, so straight
// lines between its points are the payoff itself.
public sealed record OptionStrategyExpiry(string Rule,SignedRatio NetPremium,OptionStrategyExtreme MaximumProfit,OptionStrategyExtreme MaximumLoss,
    ImmutableArray<OptionStrategyBreakeven> Breakevens,ImmutableArray<OptionStrategyPoint> Curve);

// Why a strategy has no dated curve, with the refusing code: a leg has no volatility to value it at, or the valuation
// refused a sample. It is a statement about the strategy's inputs, never a fault in how the curves were asked for.
public sealed class OptionStrategyCurveRefusal(string code,string message,Exception? inner=null):MarketDataException(code,message,inner);

// Option legs on one expiry and one underlying future, combined. At expiry a leg is worth its exercise value and the
// strategy's payoff is piecewise linear in the futures price, so its extremes and breakevens are solved exactly. Before
// expiry the legs are valued by ordinary instrument PV under the shared price, clock and volatility layers; nothing is
// priced here.
public static class OptionStrategies
{
    // An option in the money at expiry is exercised or assigned and is worth its intrinsic value; any other is worth
    // nothing. The payoff is stated over futures prices from zero upward. No lifecycle event is implied.
    public const string ExerciseRule="option_expiry_exercise_value_v1";
    public const string Uncalibrated="strategy_leg_uncalibrated";
    private const string CurveSet="option_strategy_dated_curve",CurveSetVersion="v1";

    // The legs of one strategy: at least one, each series once, whole nonzero lots, an entry price that is not negative,
    // and one expiry, underlying future and currency between them. A relationship between futures months is never inferred.
    public static void Require(ImmutableArray<OptionStrategyLeg> legs)
    {
        if(legs.IsDefaultOrEmpty||legs.Any(l=>l?.Option is null)||legs.Select(l=>l.Option.Id).Distinct().Count()!=legs.Length)
            throw Error("strategy_legs","Supply at least one leg, with each option series on one leg.");
        if(legs.Any(l=>l.Lots==default||!l.Lots.IsMultipleOf(One)))throw Error("strategy_leg_lots","Each leg needs a whole number of lots, bought or sold.");
        if(legs.Any(l=>l.EntryPrice.CompareTo(default)<0))throw Error("strategy_leg_entry","A leg's entry price cannot be negative.");
        var first=legs[0].Option.Series;
        if(legs.Any(l=>l.Option.Series.Terms.ExpiryAt!=first.Terms.ExpiryAt))
            throw Error("strategy_expiry","Every leg of a strategy expires at the same instant; legs of different expiries are not combined.");
        if(legs.Any(l=>l.Option.Series.UnderlyingSeries!=first.UnderlyingSeries||l.Option.Currency!=legs[0].Option.Currency))
            throw Error("strategy_underlying","Every leg of a strategy is an option on the same underlying future, in one currency.");
    }

    // Evenly spaced futures prices from lower to upper inclusive, each an exact decimal. A positive lower bound, a higher
    // upper bound and at least two points are required; a range whose spacing is not an exact decimal is refused, never moved.
    public static ImmutableArray<ExactDecimal> Prices(ExactDecimal lower,ExactDecimal upper,int points)
    {
        var range=upper.ScaledValue-lower.ScaledValue;
        if(lower.CompareTo(default)<=0||range.Sign<=0||points<2||range%(points-1)!=0)
            throw Error("strategy_price_range","Choose a positive lower bound, a higher upper bound and at least two points whose even spacing is an exact decimal.");
        var step=range/(points-1);
        return [..Enumerable.Range(0,points).Select(n=>ExactDecimal.FromScaled(lower.ScaledValue+n*step))];
    }

    // The instant dated curves stop before: the earliest, over the series, of the instruction cutoff still ahead of the
    // valuation instant, or else the expiry. The option model values a series up to there and refuses a later clock.
    public static DateTimeOffset CurveHorizon(IEnumerable<FuturesOptionSeriesSpecification> series,DateTimeOffset valuationAt)=>
        (series??throw Error("strategy_legs","Supply the series.")).Select(s=>s.InstructionCutoffAt is {} cutoff&&cutoff>valuationAt?cutoff:s.Terms.ExpiryAt).DefaultIfEmpty(valuationAt).Min();

    // The instants dated curves are drawn at: from the valuation instant to before the horizon, each once, in order.
    public static void RequireInstants(ImmutableArray<DateTimeOffset> instants,DateTimeOffset valuationAt,DateTimeOffset horizon)
    {
        if(instants.IsDefault||instants.Any(at=>!TradingInstant.IsSupported(at)||at<valuationAt||at>=horizon)||instants.Zip(instants.Skip(1)).Any(pair=>pair.First>=pair.Second))
            throw Error("strategy_curve_instant",$"Each dated curve needs its own instant from the valuation instant to before {horizon:O}, where the legs' instruction cutoff or expiry ends their valuation, in increasing order.");
    }

    public static OptionStrategyExpiry AtExpiry(ImmutableArray<OptionStrategyLeg> legs,ImmutableArray<ExactDecimal> prices)
    {
        Require(legs);
        if(prices.IsDefaultOrEmpty||prices.Any(p=>p.CompareTo(default)<0))throw Error("strategy_price_range","Supply the futures prices the expiry curve is stated at.");
        var premium=NetPremium(legs);
        SignedRatio Payoff(SignedRatio futures)=>SignedRatio.Sum(legs.Select(leg=>
        {
            var strike=Ratio(leg.Option.Series.Terms.Strike);
            var intrinsic=leg.Option.Series.Terms.Right==OptionRight.Call?futures-strike:strike-futures;
            return Scale(leg)*(intrinsic.CompareTo(SignedRatio.Zero)>0?intrinsic:SignedRatio.Zero);
        }))-premium;

        // The payoff is linear between zero and the lowest strike, between neighbouring strikes, and above the highest,
        // where only the calls still move with the price.
        var corners=legs.Select(l=>l.Option.Series.Terms.Strike).Distinct().Order().Select(Ratio).Prepend(SignedRatio.Zero).ToArray();
        var values=corners.Select(Payoff).ToArray();
        var tail=SignedRatio.Sum(legs.Where(l=>l.Option.Series.Terms.Right==OptionRight.Call).Select(Scale));
        var last=corners.Length-1;
        var zeros=new List<(SignedRatio Lower,SignedRatio? Upper)>();
        for(var n=0;n<last;n++)
        {
            var (from,to)=(values[n],values[n+1]);
            if(Sign(from)==0)zeros.Add((corners[n],Sign(to)==0?corners[n+1]:corners[n]));
            else if(Sign(from)*Sign(to)<0)zeros.Add(Point(corners[n]+(corners[n+1]-corners[n])*Quotient(from,from-to)));
        }
        if(Sign(values[last])==0)zeros.Add((corners[last],Sign(tail)==0?null:corners[last]));
        else if(Sign(values[last])*Sign(tail)<0)zeros.Add(Point(corners[last]-Quotient(values[last],tail)));
        // A corner that is zero ends one zero range and begins the next: the ranges that touch are one.
        var breakevens=new List<OptionStrategyBreakeven>();
        foreach(var zero in zeros)
            if(breakevens.Count>0&&breakevens[^1].Upper is {} upper&&zero.Lower.CompareTo(upper)<=0)
                breakevens[^1]=breakevens[^1] with{Upper=zero.Upper is {} end?(end.CompareTo(upper)>0?end:upper):null};
            else if(breakevens.Count==0||breakevens[^1].Upper is not null)breakevens.Add(new(zero.Lower,zero.Upper));

        var (lowest,highest)=(prices.Min(),prices.Max());
        var stated=prices.Concat(legs.Select(l=>l.Option.Series.Terms.Strike).Where(strike=>strike.CompareTo(lowest)>0&&strike.CompareTo(highest)<0)).Distinct().Order();
        return new(ExerciseRule,premium,new(Sign(tail)>0?null:values.Max()),new(Sign(tail)<0?null:values.Min()),[..breakevens],
            [..stated.Select(price=>new OptionStrategyPoint(price,Payoff(Ratio(price))))]);
    }

    // One curve per instant: at each futures price, the legs' ordinary PV under a scenario that moves the underlying
    // future to that price, the calculation clock to the instant and every leg's held volatility by the shift, less the
    // premium paid. The prepared portfolio holds one contract of each leg's series (FuturesOptionSensitivities.UnitHoldings);
    // a holding's value is scaled by its leg's signed lots outside the PV. Every leg must be solved for a volatility: a
    // strategy with a leg valued at intrinsic, or one that did not calibrate, has no dated curve, and a sample the
    // valuation refuses refuses the curves with its code; both are an OptionStrategyCurveRefusal. Anything else wrong
    // with what was asked is an ordinary error. One call values at most RiskEngine.MaxJointScenarios prices.
    public static ImmutableArray<OptionStrategyDatedCurve> Dated(PreparedConnectedPortfolioRisk? prepared,ImmutableDictionary<Guid,FuturesOptionMarketBinding> bindings,
        ImmutableArray<OptionStrategyLeg> legs,ImmutableArray<ExactDecimal> prices,ImmutableArray<DateTimeOffset> instants,ExactDecimal volatilityShift,CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        Require(legs);
        if(bindings is null||prices.IsDefaultOrEmpty||prices.Length>RiskEngine.MaxJointScenarios)
            throw Error("strategy_price_range",$"Supply the legs' bindings and from one to {RiskEngine.MaxJointScenarios} futures prices the curves are stated at.");
        var held=new Dictionary<Guid,(OptionStrategyLeg Leg,FuturesOptionMarketBinding Binding)>();
        foreach(var leg in legs)
        {
            if(!bindings.TryGetValue(leg.Option.Id,out var binding))throw new OptionStrategyCurveRefusal(Uncalibrated,$"Option series {leg.Option.SeriesKey.Code} did not calibrate, so the strategy has no dated curve.");
            if(binding.Calibration is not SolvedVolatility)
                throw new OptionStrategyCurveRefusal(FuturesOptionSensitivities.AtIntrinsic,$"Option series {leg.Option.SeriesKey.Code} is valued at intrinsic and has no volatility, so the strategy has no dated curve.");
            held.Add(FuturesOptionSensitivities.UnitTrade(leg.Option.Id),(leg,binding));
        }
        if(prepared?.Factors is not [{} future]||!held.Keys.All(prepared.Holdings.Select(h=>h.TradeId).ToHashSet().Contains))
            throw Error("option_sensitivity_input","The prepared portfolio must hold one contract of each leg's series, priced from their one underlying future.");
        var valuationAt=prepared.Valuation.Snapshot.ValuationAt;
        RequireInstants(instants,valuationAt,CurveHorizon(legs.Select(l=>l.Option.Series),valuationAt));
        var basis=held.Values.Select(h=>h.Binding.BaseFutures).Distinct().ToArray();
        if(basis is not [var futures])throw Error("option_context","The legs of one strategy are calibrated at one futures price.");
        var premium=NetPremium(legs);
        ImmutableArray<VolatilityShift> volatility=volatilityShift==default?[]:[..held.Values.Select(h=>new VolatilityShift(h.Binding.Id,volatilityShift,VolatilityShift.ParentAdditive))];

        var curves=ImmutableArray.CreateBuilder<OptionStrategyDatedCurve>(instants.Length);
        foreach(var at in instants)
        {
            var clock=at==valuationAt?null:new ClockChange(at,ClockChange.FrozenInputs);
            var samples=prices.Select((price,n)=>
            {
                var move=price-futures.ToExact();
                ImmutableArray<CurveShift> shifts=move==default?[]:[new(CurveShockCoordinate.MarketQuote,new ContractCurveTarget(future.Curves[0],future.Contract),future.Unit,move,CurveShift.ParentAdditive)];
                return new ConnectedRiskScenario($"price_{n}",price.ToString(),shifts){Clock=clock,Volatility=volatility,Unchanged=shifts.IsEmpty&&clock is null&&volatility.IsEmpty};
            }).ToImmutableArray();
            ConnectedScenarioRiskRun run;
            try{run=RiskEngine.CalculateScenarios(prepared,new(CurveSet,CurveSetVersion,ConnectedRiskScenarioSet.Independent,samples),RiskEngine.ExactNumericalPolicy,ct,RiskDetail.Holdings);}
            catch(MarketDataException refused){throw new OptionStrategyCurveRefusal(refused.Code,refused.Message,refused);}
            curves.Add(new(at,[..run.Scenarios.Select((sample,n)=>
            {
                var value=SignedRatio.Sum(sample.Groups.SelectMany(g=>g.Positions).Where(p=>held.ContainsKey(p.TradeId)).Select(p=>p.Values.Value.Ratio*Ratio(held[p.TradeId].Leg.Lots)));
                return new OptionStrategyValuePoint(prices[n],value,value-premium);
            })]));
        }
        return curves.MoveToImmutable();
    }

    // The premium paid for the legs at their entry prices: bought legs add to it and sold legs take from it.
    public static SignedRatio NetPremium(ImmutableArray<OptionStrategyLeg> legs)=>SignedRatio.Sum(legs.Select(leg=>Scale(leg)*Ratio(leg.EntryPrice)));

    private static readonly ExactDecimal One=ExactDecimal.Parse("1");
    // One unit of a leg's quote in currency: its signed lots times its series' multiplier.
    private static SignedRatio Scale(OptionStrategyLeg leg)=>Ratio(leg.Lots)*Ratio(leg.Option.Series.Multiplier);
    private static SignedRatio Ratio(ExactDecimal value)=>new(value.ScaledValue,ExactDecimal.WorkingScale);
    private static int Sign(SignedRatio value)=>value.Numerator.Sign;
    private static SignedRatio Quotient(SignedRatio numerator,SignedRatio divisor)=>
        numerator*new SignedRatio(divisor.Denominator*divisor.Numerator.Sign,BigInteger.Abs(divisor.Numerator));
    private static (SignedRatio Lower,SignedRatio? Upper) Point(SignedRatio price)=>(price,price);
    private static MarketDataException Error(string code,string message)=>new(code,message);
}

// A listed option series of one expiry, as a template chooses among them.
public sealed record ListedOptionSeries(string Code,OptionRight Right,ExactDecimal Strike);
// One leg of a template: its right, its strike as a number of listed strikes above (or, negative, below) the
// at-the-money strike, and its signed lots.
public sealed record OptionStrategyTemplateLeg(OptionRight Right,int StrikeOffset,int Lots);
public sealed record OptionStrategyTemplate(string Id,string Name,ImmutableArray<OptionStrategyTemplateLeg> Legs);
public sealed record OptionStrategyTemplateSeries(string Series,OptionRight Right,ExactDecimal Strike,int Lots);

// Strategies by name. A template is a definition, not a recommendation: it names the legs and where their strikes lie
// among the strikes an expiry lists, counted from its at-the-money strike.
public static class OptionStrategyTemplates
{
    public const string Rule="listed_strike_offsets_from_at_the_money_v1";
    private const OptionRight Call=OptionRight.Call,Put=OptionRight.Put;
    public static ImmutableArray<OptionStrategyTemplate> All{get;}=
    [
        new("call_spread","Call spread",[new(Call,0,1),new(Call,2,-1)]),
        new("put_spread","Put spread",[new(Put,0,1),new(Put,-2,-1)]),
        new("straddle","Straddle",[new(Call,0,1),new(Put,0,1)]),
        new("strangle","Strangle",[new(Call,2,1),new(Put,-2,1)]),
        new("iron_condor","Iron condor",[new(Put,-2,-1),new(Put,-4,1),new(Call,2,-1),new(Call,4,1)]),
        new("butterfly","Butterfly",[new(Call,-2,1),new(Call,0,-2),new(Call,2,1)]),
        new("risk_reversal","Risk reversal",[new(Call,2,1),new(Put,-2,-1)]),
    ];

    // The template's legs among one expiry's listed series. Offsets count the distinct strikes the expiry lists, of
    // either right. A strike that far from the money that is not listed, or a right not listed at it, refuses the
    // template: no nearer strike is substituted.
    public static ImmutableArray<OptionStrategyTemplateSeries> Resolve(OptionStrategyTemplate template,ExactDecimal atTheMoney,IEnumerable<ListedOptionSeries> listed)
    {
        var series=(listed??throw new MarketDataException("strategy_template","Supply the expiry's listed series.")).ToArray();
        var strikes=series.Select(s=>s.Strike).Distinct().Order().ToArray();
        var money=Array.IndexOf(strikes,atTheMoney);
        if(money<0)throw new MarketDataException("strategy_template_strike",$"The at-the-money strike {atTheMoney} is not among the expiry's listed strikes.");
        return [..template.Legs.Select(leg=>
        {
            var at=money+leg.StrikeOffset;
            if(at<0||at>=strikes.Length)
                throw new MarketDataException("strategy_template_strike",$"{template.Name} needs a {Name(leg.Right)} {Math.Abs(leg.StrikeOffset)} listed strikes "+
                    $"{(leg.StrikeOffset<0?"below":"above")} {atTheMoney}, and the expiry lists none there.");
            var found=series.Where(s=>s.Right==leg.Right&&s.Strike==strikes[at]).ToArray();
            return found is [{} one]?new OptionStrategyTemplateSeries(one.Code,one.Right,one.Strike,leg.Lots):
                throw new MarketDataException("strategy_template_series",$"{template.Name} needs the {Name(leg.Right)} at {strikes[at]}, which the expiry does not list.");
        })];
    }
    private static string Name(OptionRight right)=>right==Call?"call":"put";
}
