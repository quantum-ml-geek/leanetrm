using System.Collections.Immutable;

namespace OpenEtrm.MarketData.Risk;

public enum QuantityBehavior { Scalable=1 }
public sealed record UnitPricingContract(Guid Id,string ModelVersion,ImmutableArray<CurveRequest> Dependencies,
    ReferenceKey Quantity,ReferenceKey Currency,QuantityBehavior QuantityBehavior);
public interface IUnitPricer
{
    UnitPricingContract Contract{get;}
    ExactMoney Evaluate(PricingInputs inputs);
}

// A pricer sees only its declared inputs. No ambient market lookup or services.
public sealed class PricingInputs
{
    private readonly IReadOnlyDictionary<CurveRequest,BuiltValue> values;
    private readonly ImmutableHashSet<CurveRequest> permitted;
    public Guid SnapshotId{get;}
    public DateTimeOffset ValuationAt{get;}
    public DateTimeOffset MarketCutoff{get;}
    public string NumericalPolicy=>CurveModel.NumericalPolicy;
    internal PricingInputs(CurveBuild market,UnitPricingContract contract,IReadOnlyDictionary<CurveRequest,BuiltValue> values)
    {SnapshotId=market.SnapshotId;ValuationAt=market.Snapshot.ValuationAt;MarketCutoff=market.Snapshot.MarketCutoff;
        this.values=values;permitted=contract.Dependencies.ToImmutableHashSet();}
    public UnitPrice Price(CurveRequest request)=>permitted.Contains(request) && values.TryGetValue(request,out var value)?value.Price:
        throw new MarketDataException("risk_dependency","A pricer requested an undeclared or unavailable market input.");
}
public sealed record UnitMoney(ExactMoney Money,ReferenceKey Quantity)
{
    public UnitMoney(Money money,ReferenceKey quantity):this(ExactMoney.FromMoney(money),quantity){}
}
public sealed record RiskPosition(Guid TradeId,Guid BindingId,Guid BookId,Guid ValuationId,Quantity Quantity,UnitMoney UnitBasis,Money FixedBasis);
public sealed record DerivativeUnit(ReferenceKey Currency,PriceUnit Factor,int Order);
public sealed record RiskDerivative(ExactDecimal Value,DerivativeUnit Unit);
public sealed record RiskValues(Money Base,Money Up,Money Down,Money UpPnl,Money DownPnl,RiskDerivative Delta,RiskDerivative Gamma);
public sealed record RiskPositionResult(Guid TradeId,Guid BindingId,Guid BookId,Guid ValuationId,
    Money Base,Money Up,Money Down,Money UpPnl,Money DownPnl,RiskDerivative Delta,RiskDerivative Gamma);
public sealed record RiskBookTotal(Guid BookId,ReferenceKey Currency,Money Base,Money Up,Money Down,Money UpPnl,Money DownPnl,RiskDerivative Delta,RiskDerivative Gamma);
public sealed record ScenarioWork(int RebuiltCurveNodes,int ReusedCurveNodes,int UnitPricerCalls,int ReusedUnitValues);
public sealed record RiskFactorResult(QuoteBump Bump,ImmutableArray<RiskPositionResult> Positions,
    ImmutableArray<RiskBookTotal> Totals,ScenarioWork UpWork,ScenarioWork DownWork);
public sealed record RiskWork(int PositionCount,int UniqueValuations,int UniqueMarketContracts,int ScenarioCount,int UnitPricerCalls,int RebuiltCurveNodes,int ReusedCurveNodes);
public sealed record RiskRun(Guid SnapshotId,string NumericalPolicy,ImmutableArray<UnitPricingContract> Contracts,
    ImmutableArray<RiskFactorResult> Factors,RiskWork Work);

public static class RiskEngine
{
    public const string NumericalPolicy="exact_18_fractional_symmetric_repricing_v1";
    private static MarketDataException Error(string code,string text)=>new(code,text);
    public static RiskRun Calculate(CurveModel model,MarketSnapshot snapshot,ImmutableArray<IUnitPricer> pricers,
        ImmutableArray<RiskPosition> positions,ImmutableArray<QuoteBump> bumps,string numericalPolicy,CancellationToken cancellation=default)
    {
        Validate(pricers,positions,numericalPolicy);
        var requests=pricers.SelectMany(p=>p.Contract.Dependencies).Distinct().ToImmutableArray();
        return Calculate(model.BuildScenarios(snapshot,requests,bumps,cancellation),pricers,positions,numericalPolicy,cancellation);
    }
    internal static RiskRun Calculate(CurveScenarioSet markets,ImmutableArray<IUnitPricer> pricers,
        ImmutableArray<RiskPosition> positions,string numericalPolicy,CancellationToken cancellation=default)
    {
        Validate(pricers,positions,numericalPolicy);
        // Stable ordering fixes aggregation and failure ordering independently of caller enumeration.
        var ordered=pricers.OrderBy(p=>p.Contract.Id).ToArray();
        var held=positions.OrderBy(p=>p.TradeId).ThenBy(p=>p.BindingId).ToArray();
        var baseValues=Evaluate(markets.Base,null,null,out var baseCalls);
        var factors=ImmutableArray.CreateBuilder<RiskFactorResult>();
        var totalCalls=baseCalls;var rebuilt=markets.Base.EvaluatedConstituents;var reused=0;
        foreach(var factor in markets.Factors)
        {
            var up=Evaluate(factor.Up,markets.Base,baseValues,out var upCalls);
            var down=Evaluate(factor.Down,markets.Base,baseValues,out var downCalls);
            var results=ImmutableArray.CreateBuilder<RiskPositionResult>();
            foreach(var position in held)
            {
                cancellation.ThrowIfCancellationRequested();
                var id=position.ValuationId;var size=position.Quantity.Amount;
                var fixedBasis=ExactMoney.FromMoney(position.FixedBasis);
                var b=baseValues[id].Subtract(position.UnitBasis.Money).Scale(size).Subtract(fixedBasis).ToMoney();
                var u=up[id].Subtract(position.UnitBasis.Money).Scale(size).Subtract(fixedBasis).ToMoney();
                var d=down[id].Subtract(position.UnitBasis.Money).Scale(size).Subtract(fixedBasis).ToMoney();
                var v=Measure(b,u,d,factor.Bump);
                results.Add(new(position.TradeId,position.BindingId,position.BookId,position.ValuationId,b,u,d,
                    v.UpPnl,v.DownPnl,v.Delta,v.Gamma));
            }
            var rows=results.ToImmutable();
            var totals=rows.GroupBy(p=>(p.BookId,p.Base.Currency)).OrderBy(g=>g.Key.BookId).ThenBy(g=>g.Key.Currency.Code,StringComparer.Ordinal).Select(g=>
            {
                Money Sum(Func<RiskPositionResult,Money> pick)=>g.Select(pick).Aggregate((a,b)=>a.Add(b));
                RiskDerivative SumD(Func<RiskPositionResult,RiskDerivative> pick)=>new(g.Select(p=>pick(p).Value).Aggregate((a,b)=>a+b),pick(g.First()).Unit);
                return new RiskBookTotal(g.Key.BookId,g.Key.Currency,Sum(p=>p.Base),Sum(p=>p.Up),Sum(p=>p.Down),Sum(p=>p.UpPnl),Sum(p=>p.DownPnl),SumD(p=>p.Delta),SumD(p=>p.Gamma));
            }).ToImmutableArray();
            factors.Add(new(factor.Bump,rows,totals,new(factor.Up.EvaluatedConstituents,factor.Up.ReusedConstituents,upCalls,ordered.Length-upCalls),
                new(factor.Down.EvaluatedConstituents,factor.Down.ReusedConstituents,downCalls,ordered.Length-downCalls)));
            totalCalls+=upCalls+downCalls;rebuilt+=factor.Up.EvaluatedConstituents+factor.Down.EvaluatedConstituents;
            reused+=factor.Up.ReusedConstituents+factor.Down.ReusedConstituents;
        }
        return new(markets.Base.SnapshotId,NumericalPolicy,ordered.Select(p=>p.Contract).ToImmutableArray(),factors.ToImmutable(),
            new(held.Length,ordered.Length,ordered.SelectMany(p=>p.Contract.Dependencies).Select(r=>r.Contract).Distinct().Count(),1+2*factors.Count,totalCalls,rebuilt,reused));

        Dictionary<Guid,ExactMoney> Evaluate(CurveBuild market,CurveBuild? prior,Dictionary<Guid,ExactMoney>? previous,out int calls)
        {
            var values=market.Values.ToDictionary(v=>v.Request);var before=prior?.Values.ToDictionary(v=>v.Request);
            var results=new Dictionary<Guid,ExactMoney>();calls=0;
            foreach(var pricer in ordered)
            {
                cancellation.ThrowIfCancellationRequested();
                var contract=pricer.Contract;
                var affected=before is null || contract.Dependencies.Any(r=>!ReferenceEquals(before[r],values[r]));
                var value=affected?pricer.Evaluate(new(market,contract,values)):previous![contract.Id];
                if(value.Currency!=contract.Currency)throw Error("risk_currency","Pricer output must retain its declared currency.");
                results.Add(contract.Id,value);if(affected)calls++;
            }
            return results;
        }
    }
    private static RiskValues Measure(Money b,Money u,Money d,QuoteBump bump)
    {
        var up=u.Subtract(b);var down=d.Subtract(b);
        var delta=ExactDecimal.CentralDifferenceExact(b.Amount,u.Amount,d.Amount,bump.Size,1);
        var gamma=ExactDecimal.CentralDifferenceExact(b.Amount,u.Amount,d.Amount,bump.Size,2);
        return new(b,u,d,up,down,new(delta,new(b.Currency,bump.Unit,1)),new(gamma,new(b.Currency,bump.Unit,2)));
    }
    private static void Validate(ImmutableArray<IUnitPricer> pricers,ImmutableArray<RiskPosition> positions,string numericalPolicy)
    {
        if(numericalPolicy!=NumericalPolicy)throw Error("risk_policy","Select the exact symmetric repricing numerical policy explicitly.");
        if(pricers.IsDefaultOrEmpty || pricers.Length>4096 || positions.IsDefaultOrEmpty || positions.Length>100000 ||
            pricers.Select(p=>p.Contract.Id).Distinct().Count()!=pricers.Length)
            throw Error("risk_contract","Use one explicit unit-pricer contract per valuation identity and a bounded nonempty portfolio.");
        foreach(var p in pricers)
        {
            var c=p.Contract;Money.RequireKey(c.Currency);Money.RequireKey(c.Quantity);
            if(c.Id==Guid.Empty || string.IsNullOrWhiteSpace(c.ModelVersion) || c.Dependencies.IsDefaultOrEmpty ||
                c.Dependencies.Distinct().Count()!=c.Dependencies.Length || c.Currency.Revision!=c.Quantity.Revision)
                throw Error("risk_contract","Each unit valuation requires exact identity, model, dependencies, currency and quantity basis.");
            if(c.QuantityBehavior!=QuantityBehavior.Scalable)throw Error("risk_scaling","This engine requires explicitly declared scalable quantities; size-dependent models are unsupported.");
        }
        var byId=pricers.ToDictionary(p=>p.Contract.Id,p=>p.Contract);
        if(positions.Select(p=>(p.TradeId,p.BindingId)).Distinct().Count()!=positions.Length ||
            positions.GroupBy(p=>p.TradeId).Any(g=>g.Select(p=>p.BookId).Distinct().Count()!=1))
            throw Error("risk_position","Obligation occurrences cannot repeat or assign one trade to conflicting books.");
        foreach(var p in positions)
            if(p.TradeId==Guid.Empty || p.BindingId==Guid.Empty || p.BookId==Guid.Empty || !byId.TryGetValue(p.ValuationId,out var c) ||
                p.Quantity.Specification!=c.Quantity || p.UnitBasis.Quantity!=c.Quantity || p.UnitBasis.Money.Currency!=c.Currency || p.FixedBasis.Currency!=c.Currency)
                throw Error("risk_position","Positions require exact occurrence/book/valuation identities and compatible quantity and fixed-basis units.");
        var heldIds=positions.Select(p=>p.ValuationId).ToHashSet();
        if(byId.Keys.Any(id=>!heldIds.Contains(id)))throw Error("risk_contract","Every unit valuation requires a held consumer.");
    }
}
