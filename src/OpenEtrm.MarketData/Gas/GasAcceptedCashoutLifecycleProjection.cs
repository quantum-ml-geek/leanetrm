using System.Collections.Immutable;
using OpenEtrm.MarketData.Risk;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.MarketData.Gas;

public sealed record GasAcceptedCashoutSettlement(Guid Id,Quantity Quantity,DateTimeOffset At,int PublicationOrder,DateTimeOffset KnownAt);

// Accepted quantity and cash are separate native facts. This component only
// discharges the original commodity owner; each cash membership has its own
// source-known cash component and retains its gross amount and bank history.
public sealed class GasAcceptedCashoutLifecycleProjection:ILifecycleProjection
{
    public string Implementation=>"gas_accepted_cashout_quantity_projection_v1";
    public AccountingPositionKey Owner{get;}
    public ReferenceKey Currency=>instrument.Currency;
    public MarketSnapshot SourceSnapshot{get;}
    public ImmutableArray<CurveRequest> Dependencies=>[instrument.Mark];
    public LifecycleProjectionState Opening{get;}
    public ImmutableArray<LifecycleProjectionEvent> Events{get;}
    private readonly GasCommodityHoldingInstrument instrument;
    private readonly Quantity opening;
    private readonly ImmutableDictionary<Guid,(LifecycleProjectionEvent Event,ExactDecimal Before,ExactDecimal After)> transitions;
    private readonly DateTimeOffset dischargedAt;
    private readonly ISideDiscounting? discounting;
    public GasAcceptedCashoutLifecycleProjection(AccountingPositionKey owner,GasCommodityHoldingInstrument instrument,Quantity opening,
        GasQuantityProjectionPolicy policy,ImmutableArray<GasAcceptedCashoutSettlement> settlements,ISideDiscounting? discounting,MarketSnapshot source)
    {
        if(!owner.IsValid||instrument is null||opening is null||opening.Amount==default||opening.Specification!=instrument.QuantitySpecification||
            policy is null||policy.Implementation!=GasQuantityProjectionPolicy.KnownVersion||policy.Disposition!=GasQuantityProjectionPolicy.Retain||
            source?.Knowledge is not {} knowledge||settlements.IsDefaultOrEmpty||settlements.Any(s=>s is null||s.Id==Guid.Empty||s.Quantity is null||
                s.Quantity.Specification!=opening.Specification||s.Quantity.Amount.CompareTo(default)<0||s.PublicationOrder<1||
                !TradingInstant.IsSupported(s.At)||s.At<=source.ValuationAt||!TradingInstant.IsSupported(s.KnownAt)||s.KnownAt>knowledge.KnownAt)||
            settlements.Select(s=>s.Id).Distinct().Count()!=settlements.Length)
            throw Error();
        var magnitude=opening.Amount.CompareTo(default)<0?-opening.Amount:opening.Amount;
        if(settlements.Aggregate(default(ExactDecimal),(a,s)=>a+s.Quantity.Amount)!=magnitude)throw Error();
        if(instrument.Carrying==GasHoldingCarrying.CurrencyCurve&&instrument.ReturnAt>source.ValuationAt)
        {
            if(discounting is not IProjectionCurrencyCurve curve||curve.Currency!=instrument.Currency||
                !curve.SourceSnapshot.HasSameInputs(source)||curve.TimingPolicy!=RateDiscountTiming.Version)throw Error();
        }
        else if(discounting is not null)throw Error();
        Owner=owner;this.instrument=instrument;this.opening=opening;this.discounting=discounting;SourceSnapshot=source;
        var events=ImmutableArray.CreateBuilder<LifecycleProjectionEvent>();
        var steps=ImmutableDictionary.CreateBuilder<Guid,(LifecycleProjectionEvent Event,ExactDecimal Before,ExactDecimal After)>();
        var remaining=opening.Amount;var sign=remaining.CompareTo(default)<0?ExactDecimal.Parse("-1"):ExactDecimal.Parse("1");
        foreach(var settlement in settlements.OrderBy(s=>s.At).ThenBy(s=>s.PublicationOrder).ThenBy(s=>s.Id))
        {
            var id=LifecycleProjectionEvent.ScopedId(owner,settlement.Id);
            var occurrence=new LifecycleProjectionEvent(id,settlement.At,events.Count==0?[]:[events[^1].Id],"known_gas_cashout_quantity");
            var after=remaining-sign*settlement.Quantity.Amount;
            steps.Add(id,(occurrence,remaining,after));remaining=after;events.Add(occurrence);
        }
        dischargedAt=events.First(e=>steps[e.Id].After==default).At;
        transitions=steps.ToImmutable();Events=events.ToImmutable();Opening=new([Portfolio(opening.Amount)],[]);
    }
    public ImmutableArray<LifecycleMarketUse> MarketUsesFor(DateTimeOffset horizon)=>
        [new(instrument.Mark,dischargedAt<=horizon?SourceSnapshot.ValuationAt:horizon)];
    public ImmutableArray<LifecycleProjectionEvent> EventsFor(DateTimeOffset horizon)=>[..Events.Where(e=>e.At<=horizon)];
    public LifecycleProjectionState Apply(LifecycleProjectionEvent occurrence,LifecycleProjectionState state,LifecycleProjectionContext context)
    {
        if(!transitions.TryGetValue(occurrence.Id,out var step)||step.Event!=occurrence||context.CalculationAt!=occurrence.At||!SourceSnapshot.HasSameInputs(context.SourceSnapshot)||
            !state.Members.IsEmpty||!state.Cash.IsEmpty)throw Error();
        if(step.Before==default)
        {
            if(!state.Residuals.IsEmpty)throw Error();
            return state;
        }
        if(state.Residuals.Length!=1||state.Residuals[0].Instruments is not [{} heldInstrument]||heldInstrument!=instrument||
            state.Residuals[0].Positions is not [{} held]||held.Owner!=Owner.Owner||held.BindingId!=Owner.BindingId||held.BookId!=Owner.BookId||
            held.ValuationId!=instrument.Id)throw Error();
        if(held.Quantity!=new Quantity(step.Before,opening.Specification))throw Error();
        return state with{Residuals=step.After==default?[]:[Portfolio(step.After)]};
    }
    private ValuationPortfolio Portfolio(ExactDecimal quantity)=>new([instrument],[new(Owner.Owner,Owner.BindingId,Owner.BookId,instrument.Id,
        new(quantity,opening.Specification),new(new Money(default,Currency),opening.Specification),new(default,Currency))],
        new(ValuationMeasure.PresentValue,ImmutableDictionary<Guid,FuturesMarketBinding>.Empty,discounting));
    private static MarketDataException Error()=>new("gas_projection_known_cashout",
        "Retain the exact source-known settlement prefix and an explicitly selected accepted-quantity policy; an uncovered claim requires its selected cashout expectation.");
}
