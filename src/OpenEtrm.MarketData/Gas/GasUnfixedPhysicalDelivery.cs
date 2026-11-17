using System.Collections.Immutable;
using OpenEtrm.MarketData.Risk;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.MarketData.Gas;

// A declared physical exchange before its principal is fixed. The selected
// marks and carrying inputs are valuation terms, never accepted final evidence.
[EconomicDefinition("gas_unfixed_delivery_exchange_v2")]
public sealed record GasUnfixedPhysicalDeliveryInstrument:SidedInstrument
{
    public const string Version="gas_unfixed_delivery_exchange_side_pv_v2";
    // This published identity domain remains stable; execution is versioned above.
    private const string IdentityDomain="gas_unfixed_delivery_exchange_pv_v1";
    [IdentityField]public GasPhysicalDeliveryTerms Terms{get;}
    [IdentityField]public CurveRequest PrincipalMark{get;}
    [IdentityField]public PriceUnit PriceUnit{get;}
    public override ReferenceKey Currency=>Terms.Currency;
    public override Quantity UnitQuantity=>new(ExactDecimal.Parse("1"),Terms.Quantity);
    public override bool SupportsQuantityScaling=>true;
    internal override bool SupportsSettlement=>false;
    public override DefinitionIdentity PricingBindingIdentity=>GasDeliveryExchangeSides.Binding(Id,Terms);
    public GasUnfixedPhysicalDeliveryInstrument(Guid id,GasPhysicalDeliveryTerms terms,CurveRequest principalMark,PriceUnit priceUnit)
        :base(id,GasDeliveryExchangeSides.Unfixed(id,terms,principalMark,priceUnit))
    {
        Terms=terms;PrincipalMark=principalMark;PriceUnit=priceUnit;
    }
    private static void Require(GasPhysicalDeliveryTerms terms,CurveRequest principalMark,PriceUnit priceUnit)
    {
        GasDeliveryExchangeSides.RequireUnfixed(terms,principalMark,priceUnit);
    }
    public static GasUnfixedPhysicalDeliveryInstrument Create(GasPhysicalDeliveryTerms terms,CurveRequest principalMark,PriceUnit priceUnit)
    {
        Require(terms,principalMark,priceUnit);
        return new(ContractIdentity.FromCanonical(DefinitionIdentity.CanonicalTerm(new object?[]{IdentityDomain,terms,principalMark,priceUnit})),terms,principalMark,priceUnit);
    }
    public ImmutableArray<SidePaymentKey> RequiredDiscounts(DateTimeOffset calculationAt)=>
        GasDeliveryExchange.RequiredDiscounts(Id,Terms,calculationAt);
    public override UnitPricingContract Declare(UnitValuationContext context)
    {
        var discounted=RequiredDiscounts(context.CalculationAt);
        return new(Id,Version,[..new[]{Terms.Mark,PrincipalMark}.Distinct()],Terms.Quantity,Currency){
            Time=discounted.IsEmpty?ValuationTimeDependency.Independent:ValuationTimeDependency.Between(context.CalculationAt,discounted.Min(p=>p.PaymentAt)),
            DiscountInputs=[..discounted.Select(p=>new DiscountInput(p,context.PaymentDiscounting(Id)))]};
    }
    public override void ValidateValuationState(IBindingValuationState? state)=>GasDeliveryExchangeSides.RequireState(state);
    internal override UnitPricingContract DeclareScope(UnitValuationContext context,bool lifecycle)=>Declare(context);
    internal ExactMoney ExchangeValue(UnitValuationContext context)
    {
        // The enclosing future has already admitted its own margin state.
        // That state is not a paid-state input to either delivery Side.
        return base.PV(context.SideContextWithoutBindingState()).PresentValue;
    }
}

// One carrying calculation serves the unfixed and fixed principal contracts.
internal static class GasDeliveryExchange
{
    internal static SidePaymentKey Cash(Guid id,GasPhysicalDeliveryTerms terms)=>new(id,0,terms.CashDueAt,terms.Currency){Timing=ValueTimingKind.Instant};
    internal static SidePaymentKey Physical(Guid id,GasPhysicalDeliveryTerms terms)=>new(id,1,terms.From,terms.Currency){Timing=ValueTimingKind.Instant};
    internal static ImmutableArray<SidePaymentKey> RequiredDiscounts(Guid id,GasPhysicalDeliveryTerms terms,DateTimeOffset calculationAt)
    {
        if(!TradingInstant.IsSupported(calculationAt))throw new MarketDataException("gas_delivery_discount","Select an exact supported calculation instant.");
        return terms.Carrying==GasHoldingCarrying.CurrencyCurve?[..new[]{Physical(id,terms),Cash(id,terms)}.Where(p=>p.PaymentAt>calculationAt)]:[];
    }
}
