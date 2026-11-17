using System.Collections.Immutable;
using OpenEtrm.MarketData.Trading;
using OpenEtrm.Shared.Commands;

namespace OpenEtrm.MarketData.Gas;

// Native carrying keys are pricing inputs, separate from the reusable Side's
// economic terms and from any later independently owned bank payment.
[EconomicDefinition("gas_delivery_carrying_binding_v1")]
internal sealed record GasDeliveryCarryingBinding([property:IdentityField]Guid Owner,
    [property:IdentityField]int Ordinal,[property:IdentityField]DateTimeOffset At,
    [property:IdentityField]ReferenceKey Currency,[property:IdentityField]GasHoldingCarrying Carrying);

[EconomicDefinition("gas_delivery_exchange_carrying_binding_v1")]
internal sealed record GasDeliveryExchangeBinding([property:IdentityField]Guid Owner,
    [property:IdentityField]DateTimeOffset DeliveryAt,[property:IdentityField]DateTimeOffset CashDueAt,
    [property:IdentityField]ReferenceKey Currency,[property:IdentityField]GasHoldingCarrying Carrying);

public abstract record GasDeliveryValueSide:ValueSide
{
    public SidePaymentKey CarryingKey {get;}
    [IdentityField]public ReferenceKey QuantitySpecification=>UnitQuantity.Specification;
    [IdentityField]public ReferenceKey PaymentCurrency=>Currency;
    [IdentityField]public GasHoldingCarrying Carrying {get;}
    [IdentityField]public DateTimeOffset ValueAt=>CarryingKey.PaymentAt;
    [IdentityField]public PriceUnit NativePriceUnit {get;}
    public override DefinitionIdentity PricingBindingIdentity=>DefinitionIdentity.For(new GasDeliveryCarryingBinding(
        CarryingKey.SideId,CarryingKey.Ordinal,CarryingKey.PaymentAt,CarryingKey.Currency,Carrying));
    protected GasDeliveryValueSide(Guid id,GasPhysicalDeliveryTerms terms,PriceUnit unit,SidePaymentKey key,string implementation,ValueSideTerm row)
        :base(id,terms.Currency,new(ExactDecimal.Parse("1"),terms.Quantity),implementation,[row])
    {Carrying=terms.Carrying;NativePriceUnit=unit;CarryingKey=key;}
    protected ImmutableArray<ScheduleRowValue> Carried(SideValuationContext context,IReadOnlyList<ScheduleRow> rows,ExactUnitPrice price)
    {
        if(context.BindingState is not null)
            throw new MarketDataException("settlement_scope","The physical exchange Side has no external paid-state interpretation before title performance.");
        if(price.Unit!=NativePriceUnit)
            throw new MarketDataException("gas_delivery_unit","Retain the exact native quotation; any conversion requires its explicit supported contract.");
        var amount=price.ExactTimes(UnitQuantity);var pv=amount;SidePaymentFactor? factor=null;
        if(Carrying==GasHoldingCarrying.CurrencyCurve&&CarryingKey.PaymentAt>context.UnitEvaluation.CalculationAt)
        {
            var factors=context.Inputs.Discounts([CarryingKey]);
            if(factors.IsDefault||factors.Length!=1||factors[0] is null||factors[0].Payment!=CarryingKey)
                throw new MarketDataException("gas_delivery_discount","Select the exact carrying input for this Side.");
            factor=factors[0];pv=amount.Scale(factor.DiscountFactor);
        }
        return [Value(rows[0],amount,pv,CarryingKey.PaymentAt,price,factor)];
    }
}

[EconomicDefinition("gas_delivery_asset_side_v1")]
public sealed record GasDeliveryAssetSide:GasDeliveryValueSide
{
    public const string Role="physical_delivery_value";
    [IdentityField]public CurveRequest Mark {get;}
    [IdentityField]public ReferenceKey Location {get;}
    [IdentityField]public DateTimeOffset From {get;}
    [IdentityField]public DateTimeOffset To {get;}
    internal GasDeliveryAssetSide(Guid owner,GasPhysicalDeliveryTerms terms,PriceUnit unit)
        :base(OperationIdentity.For("gas_delivery_asset_side_v1",owner),terms,unit,GasDeliveryExchange.Physical(owner,terms),
            "gas_delivery_asset_side_pv_v1",new(0,ComponentKind.Delivery,terms.From,terms.To,terms.From,null,terms.Mark))
    {Mark=terms.Mark;Location=terms.Location;From=terms.From;To=terms.To;}
    protected override ImmutableArray<ScheduleRowValue> Evaluate(SideValuationContext context,IReadOnlyList<ScheduleRow> rows)=>
        Carried(context,rows,context.Inputs.ExactPrice(Mark));
}

[EconomicDefinition("gas_delivery_principal_side_v1")]
public sealed record GasDeliveryPrincipalSide:GasDeliveryValueSide
{
    public const string Role="delivery_principal_payment";
    [IdentityField]public CurveRequest? PrincipalMark {get;}
    [IdentityField]public ExactUnitPrice? FinalPrice {get;}
    internal GasDeliveryPrincipalSide(Guid owner,GasPhysicalDeliveryTerms terms,PriceUnit unit,CurveRequest? principal,ExactUnitPrice? final)
        :base(OperationIdentity.For("gas_delivery_principal_side_v1",owner),terms,unit,GasDeliveryExchange.Cash(owner,terms),
            "gas_delivery_principal_side_pv_v1",new(0,ComponentKind.Payment,null,null,terms.CashDueAt,GasDeliveryExchange.Cash(owner,terms),principal))
    {PrincipalMark=principal;FinalPrice=final;}
    protected override ImmutableArray<ScheduleRowValue> Evaluate(SideValuationContext context,IReadOnlyList<ScheduleRow> rows)=>
        Carried(context,rows,FinalPrice??context.Inputs.ExactPrice(PrincipalMark??throw new MarketDataException("gas_delivery_terms","Select the principal's exact price input.")));
}

internal static class GasDeliveryExchangeSides
{
    internal static void RequireUnfixed(GasPhysicalDeliveryTerms terms,CurveRequest principal,PriceUnit unit)
    {
        if(terms is null||unit is null||unit.Currency!=terms.Currency||unit.Quantity!=terms.Quantity||
            principal.Curve.Revision.CatalogId==Guid.Empty||principal.Curve.Revision.RevisionId==Guid.Empty||
            string.IsNullOrWhiteSpace(principal.Curve.Code)||principal.Contract.Id==Guid.Empty||principal.Contract.Revision!=principal.Curve.Revision)
            throw new MarketDataException("gas_unfixed_delivery_terms","Select exact physical terms, principal mark and native quotation units.");
    }
    internal static ImmutableArray<SideMembership> Unfixed(Guid owner,GasPhysicalDeliveryTerms terms,CurveRequest principal,PriceUnit unit)
    {RequireUnfixed(terms,principal,unit);return Compose(owner,terms,unit,principal,null);}
    internal static ImmutableArray<SideMembership> Fixed(Guid owner,GasPhysicalDeliveryTerms terms,ExactUnitPrice price)
    {
        if(terms is null||price is null||price.Unit.Currency!=terms.Currency||price.Unit.Quantity!=terms.Quantity)
            throw new MarketDataException("gas_delivery_terms","A physical obligation requires its exact accepted or path-local final quotation.");
        return Compose(owner,terms,price.Unit,null,price);
    }
    private static ImmutableArray<SideMembership> Compose(Guid owner,GasPhysicalDeliveryTerms terms,PriceUnit unit,CurveRequest? principal,ExactUnitPrice? final)=>
        [new(new GasDeliveryAssetSide(owner,terms,unit),ExactDecimal.Parse("1")),
         new(new GasDeliveryPrincipalSide(owner,terms,unit,principal,final),ExactDecimal.Parse("-1"))];
    internal static void RequireState(IBindingValuationState? state)
    {
        if(state is not null)throw new MarketDataException("settlement_scope","This physical exchange does not accept an external binding valuation state.");
    }
    internal static DefinitionIdentity Binding(Guid owner,GasPhysicalDeliveryTerms terms)=>
        DefinitionIdentity.For(new GasDeliveryExchangeBinding(owner,terms.From,terms.CashDueAt,terms.Currency,terms.Carrying));
}
