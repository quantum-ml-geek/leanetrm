using System.Collections.Immutable;
using OpenEtrm.MarketData.Risk;

namespace OpenEtrm.MarketData.Trading;

// Open mark sensitivity and execution-P&L scenarios only; never settlement PV.
public static class FuturesRisk
{
    public const string Implementation="unprocessed_futures_execution_pnl_risk_v1";
    public static RiskRun Calculate(ImmutableArray<FuturesTrade> trades,MarketSnapshot snapshot,CurveModel model,
        ImmutableArray<QuoteBump> bumps,string implementation,string numericalPolicy,CancellationToken cancellation=default)
    {
        if(implementation!=Implementation)throw new MarketDataException("risk_convention","Select the supported unprocessed-futures execution-P&L risk convention.");
        if(trades.IsDefaultOrEmpty || trades.Any(t=>t is null))throw new MarketDataException("risk_position","Select explicit live holdings before running risk.");
        var sides=trades.SelectMany(t=>t.Instruments).Select(p=>p.MarketBinding).ToArray();
        var requests=sides.Select(s=>s.Market).Distinct().ToImmutableArray();
        if(requests.IsEmpty)throw new MarketDataException("risk_position","Select at least one live holding for risk.");
        var markets=model.BuildScenarios(snapshot,requests,bumps,cancellation);
        // Reuse the complete immutable-definition, lifecycle and manifest validation.
        var holdings=FuturesHoldings.Price(trades,snapshot,markets.Base,FuturesMarketBinding.GeneralImplementation);
        var unique=sides.DistinctBy(s=>s.Id).ToDictionary(s=>s.Id);
        var pricers=unique.Values.Select(s=>(IUnitPricer)new MarkPricer(s)).ToImmutableArray();
        var positions=holdings.Select(h=>new RiskPosition(h.TradeId,h.BindingId,h.BookId,h.PricingBindingId,h.Quantity,
            new UnitMoney(h.ExecutionPrice.ExactTimes(new Quantity(ExactDecimal.Parse("1"),h.Quantity.Specification)),h.Quantity.Specification),new Money(default,h.ExecutionPnl.Currency))).ToImmutableArray();
        return RiskEngine.Calculate(markets,pricers,positions,numericalPolicy,cancellation);
    }
    private sealed class MarkPricer:IUnitPricer
    {
        private readonly FuturesMarketBinding side;
        public UnitPricingContract Contract{get;}
        public MarkPricer(FuturesMarketBinding side)
        {
            this.side=side;Contract=new(side.Id,side.Series.LotBasis==LotBasis.FixedTotal&&side.SettlementMethod=="cash"?"fixed_total_open_mark_v1":"contract_unit_open_mark_v2",side.Dependencies,side.Quote.Quantity,side.Quote.Currency,QuantityBehavior.Scalable);
        }
        public ExactMoney Evaluate(PricingInputs inputs)=>inputs.Price(side.Market).ExactTimes(new Quantity(ExactDecimal.Parse("1"),side.Quote.Quantity));
    }
}
