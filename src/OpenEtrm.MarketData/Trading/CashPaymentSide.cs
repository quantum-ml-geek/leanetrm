using System.Collections.Immutable;
using OpenEtrm.MarketData.Risk;

namespace OpenEtrm.MarketData.Trading;

[EconomicDefinition("cash_payment_side_v1")]
public sealed record CashPaymentSide:ValueSide
{
    public const string Role="cash_payment";
    [IdentityField]public ReferenceKey PaymentCurrency=>Currency;
    [IdentityField]public DateTimeOffset PaymentAt {get;}
    [IdentityField]public ValueTimingKind Timing {get;}
    public SidePaymentKey Payment=>new(Id,0,PaymentAt,Currency){Timing=Timing};
    public bool Due(DateTimeOffset at)=>Timing==ValueTimingKind.UtcPaymentDay?PaymentDatePolicy.IsDue(PaymentAt,at):at>=PaymentAt;
    public CashPaymentSide(Guid id,ReferenceKey currency,DateTimeOffset at,ValueTimingKind timing)
        :base(id,currency,new(ExactDecimal.Parse("1"),currency),CashPaymentInstrument.ModelVersion,
            [new(0,ComponentKind.Payment,null,null,at,new(id,0,at,currency){Timing=timing},null)])
    {
        if(!TradingInstant.IsSupported(at)||at.Year is <1901 or >2199||!Enum.IsDefined(timing))
            throw new MarketDataException("cash_payment_definition","Retain the exact dated or instant cash timing law.");
        PaymentAt=at;Timing=timing;
    }
    internal void RequireState(IBindingValuationState? state)
    {
        if(state is not ICashPaymentValuation cash||cash.InstrumentId!=Id||cash.Quantity.Specification!=Currency)
            throw new MarketDataException("payment_state","A cash Side requires its exact recorded paid-state projection.");
    }
    internal UnitPricingContract Declare(UnitValuationContext context)
    {
        RequireState(context.BindingState);
        var remaining=Outstanding(context.BindingState,context.Snapshot,context.CalculationAt,context.IsLifecycleProjection);
        var needsDiscount=remaining.Numerator!="0"&&!Due(context.CalculationAt);
        var events=((ICashPaymentValuation)context.BindingState!).FutureChanges(context.Snapshot).Where(at=>at>context.CalculationAt).ToList();
        if(needsDiscount)events.Add(PaymentAt);
        return new(Id,CashPaymentInstrument.ModelVersion,[],Currency,Currency){
            Time=events.Count>0?ValuationTimeDependency.Between(context.CalculationAt,events.Min()):ValuationTimeDependency.Independent,
            DiscountInputs=needsDiscount?[new(Payment,context.PaymentDiscounting(Id))]:[]};
    }
    protected override ImmutableArray<ScheduleRowValue> Evaluate(SideValuationContext context,IReadOnlyList<ScheduleRow> rows)
    {
        var scope=context.UnitEvaluation;
        var remaining=Outstanding(context.BindingState,context.Snapshot,scope.CalculationAt,scope.IsLifecycleProjection);
        var amount=ExactMoney.Parse("1",Currency);SidePaymentFactor? factor=null;var pv=remaining;
        if(remaining.Numerator!="0"&&!Due(scope.CalculationAt))
        {
            var factors=context.Inputs.Discounts([Payment]);
            if(factors.IsDefault||factors.Length!=1||factors[0] is null||factors[0].Payment!=Payment)
                throw new MarketDataException("cash_payment_discount","The cash Side requires its exact declared discount factor.");
            factor=factors[0];pv=remaining.Scale(factor.DiscountFactor);
        }
        var paid=amount.Subtract(remaining);var zero=remaining.Numerator=="0";var hasPaid=paid.Numerator!="0";var due=Due(scope.CalculationAt);
        var balance=new CashPaymentBalance(null,paid,remaining,zero?CashPaymentState.Paid:hasPaid?
            due?CashPaymentState.PartPaidOverdue:CashPaymentState.PartPaid:due?CashPaymentState.Overdue:CashPaymentState.FixedUnpaid);
        return [Value(rows[0],amount,pv,PaymentAt,discount:factor,cash:balance)];
    }
    private ExactMoney Outstanding(IBindingValuationState? state,MarketSnapshot snapshot,DateTimeOffset at,bool projected)
    {
        RequireState(state);
        if(state is IProjectedCashPaymentValuation&&!projected)
            throw new MarketDataException("projection_cash_state","A forecast cash obligation cannot be valued as an actual holding.");
        return ((ICashPaymentValuation)state!).UnitOutstanding(snapshot,at);
    }
}
