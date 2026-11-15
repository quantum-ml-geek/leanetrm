using System.Collections.Immutable;
using OpenEtrm.MarketData.Risk;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.MarketData.Gas;

// A certified future native membership has no opening value. Its existing
// cash adapter takes over at the actual membership instant, without changing
// its due date, allocation revisions or selected payment policy.
public sealed class GasKnownCashLifecycleProjection:ILifecycleProjection
{
    public string Implementation=>"gas_source_known_cash_projection_v1";
    public AccountingPositionKey Owner=>cash.Owner;
    public ReferenceKey Currency=>cash.Currency;
    public MarketSnapshot SourceSnapshot=>cash.SourceSnapshot;
    public ImmutableArray<CurveRequest> Dependencies=>[];
    public LifecycleProjectionState Opening{get;}
    public ImmutableArray<LifecycleProjectionEvent> Events{get;}
    private readonly CashLifecycleProjection cash;
    private readonly LifecycleProjectionEvent birth;
    public GasKnownCashLifecycleProjection(AccountingPositionKey owner,TimedCashPayment instrument,RecordedCashValuation state,
        DateTimeOffset effectiveAt,DateTimeOffset knownAt,int publicationOrder,ISideDiscounting? discounting,MarketSnapshot source)
    {
        if(instrument is null||source?.Knowledge is not {} knowledge||!TradingInstant.IsSupported(effectiveAt)||effectiveAt<=source.ValuationAt||
            !TradingInstant.IsSupported(knownAt)||knownAt>knowledge.KnownAt||publicationOrder<1||state is null||
            state.Allocations.Any(p=>p.EffectiveAt<effectiveAt||p.KnownAt<knownAt))
            throw new MarketDataException("gas_projection_known_cash","Retain the exact certified future native cash membership, original effective and knowledge times, and complete bank history.");
        cash=new(owner,instrument,state,discounting,source);
        birth=new(LifecycleProjectionEvent.ScopedId(owner,owner.BindingId),effectiveAt,[],"known_gas_cash_membership");
        Opening=new([],[]){KnownResidualOwners=[owner],KnownCashSources=[state],KnownPayments=cash.Opening.KnownPayments};
        // A cash membership born overdue activates unpaid at its real origin.
        // A due date before membership cannot create a projected payment.
        Events=[birth,..cash.Events.Where(e=>e.At>=effectiveAt).Select(e=>e with{Requires=[birth.Id]})];
    }
    public ImmutableArray<LifecycleProjectionEvent> EventsFor(DateTimeOffset horizon)=>[..Events.Where(e=>e.At<=horizon)];
    public LifecycleProjectionState Apply(LifecycleProjectionEvent occurrence,LifecycleProjectionState state,LifecycleProjectionContext context)
    {
        if(!Events.Contains(occurrence)||context.CalculationAt!=occurrence.At||!SourceSnapshot.HasSameInputs(context.SourceSnapshot))
            throw new MarketDataException("gas_projection_known_cash","Apply only this exact retained cash membership or due event under its original source.");
        if(occurrence==birth)
        {
            if(!state.Residuals.IsEmpty)throw new MarketDataException("gas_projection_known_cash","A future native cash membership can activate only once.");
            return state with{Residuals=cash.Opening.Residuals};
        }
        return cash.Apply(cash.Events.Single(e=>e.Id==occurrence.Id),state,context);
    }
}
