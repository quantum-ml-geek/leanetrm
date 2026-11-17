using System.Collections.Immutable;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Risk;

namespace OpenEtrm.MarketData.Trading;

public interface ICashPaymentValuation:IBindingValuationState
{
    Guid InstrumentId{get;}
    ExactMoney UnitOutstanding(MarketSnapshot source);
    ExactMoney UnitOutstanding(MarketSnapshot source,DateTimeOffset calculationAt);
    ImmutableArray<DateTimeOffset> FutureChanges(MarketSnapshot source);
}
public interface IProjectedCashPaymentValuation:ICashPaymentValuation;

// Shared paid-state and valuation rules for dated premiums and exact-instant
// margin/settlement cash. Ownership and payment history remain binding state.
public abstract record CashPaymentInstrument:SidedInstrument
{
    public const string ModelVersion="cash_payment_side_paid_state_v3";
    public abstract ReferenceKey PaymentCurrency{get;}
    public abstract DateTimeOffset PaymentAt{get;}
    public abstract ValueTimingKind Timing{get;}
    public override ReferenceKey Currency=>PaymentCurrency;
    public override Quantity UnitQuantity=>new(ExactDecimal.Parse("1"),PaymentCurrency);
    public override bool SupportsQuantityScaling=>true;
    public CashPaymentSide CashPaymentSide=>(CashPaymentSide)Sides[0].Side;
    public SidePaymentKey Payment=>CashPaymentSide.Payment;
    public bool Due(DateTimeOffset at)=>CashPaymentSide.Due(at);
    internal override bool SupportsSettlement=>false;
    protected CashPaymentInstrument(Guid id,ReferenceKey currency,DateTimeOffset at,ValueTimingKind timing)
        :base(id,[new(new CashPaymentSide(id,currency,at,timing),ExactDecimal.Parse("1"))]){}

    public override void ValidateBinding(Quantity quantity, DeliveryCoverage? coverage)
    {
        base.ValidateBinding(quantity, coverage);
        if (quantity.Specification != PaymentCurrency)
            throw new MarketDataException("cash_payment_quantity", "Hold cash as a quantity of its own currency.");
    }

    public override void ValidateValuationState(IBindingValuationState? state)=>CashPaymentSide.RequireState(state);
    public override UnitPricingContract Declare(UnitValuationContext context)=>CashPaymentSide.Declare(context);
    internal override UnitPricingContract DeclareScope(UnitValuationContext context,bool lifecycle)=>Declare(context);
}

// Date-only cash retains its original identity and midnight-UTC convention.
[EconomicDefinition("CashPayment_v2")]
public sealed record CashPayment:CashPaymentInstrument
{
    [IdentityField] public override ReferenceKey PaymentCurrency{get;}
    [IdentityField] public DateOnly PaymentDate{get;}
    public override ValueTimingKind Timing=>ValueTimingKind.UtcPaymentDay;
    public override DateTimeOffset PaymentAt=>new(PaymentDate.ToDateTime(TimeOnly.MinValue),TimeSpan.Zero);
    public CashPayment(ReferenceKey currency,DateOnly paymentDate):base(ContractIdentity.CashPayment(currency,paymentDate),currency,
        new(paymentDate.ToDateTime(TimeOnly.MinValue),TimeSpan.Zero),ValueTimingKind.UtcPaymentDay)
    {
        if(paymentDate.Year is <1901 or >2199)
            throw new MarketDataException("cash_payment_definition","A unit cash instrument needs a supported payment date.");
        PaymentCurrency=currency;PaymentDate=paymentDate;
    }
}

[EconomicDefinition("TimedCashPayment_v2")]
public sealed record TimedCashPayment:CashPaymentInstrument
{
    [IdentityField] public override ReferenceKey PaymentCurrency{get;}
    [IdentityField] public override DateTimeOffset PaymentAt{get;}
    public override ValueTimingKind Timing=>ValueTimingKind.Instant;
    public TimedCashPayment(ReferenceKey currency,DateTimeOffset paymentAt):base(Identity(currency,paymentAt),currency,paymentAt,ValueTimingKind.Instant)
    {
        PaymentCurrency=currency;PaymentAt=paymentAt;
    }
    static Guid Identity(ReferenceKey currency,DateTimeOffset at)
    {
        Money.RequireKey(currency);
        if(!TradingInstant.IsSupported(at)||at.Year is <1901 or >2199)
            throw new MarketDataException("cash_payment_definition","Supply an exact supported UTC cash due instant.");
        return ContractIdentity.FromCanonical($"timed_cash_payment_v1:{currency.Revision.CatalogId:D}:{currency.Revision.RevisionId:D}:{currency.Code}:{at:O}");
    }
}
