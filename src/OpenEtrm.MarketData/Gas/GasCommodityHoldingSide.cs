using System.Collections.Immutable;
using OpenEtrm.MarketData.Risk;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.MarketData.Gas;

[EconomicDefinition("gas_commodity_holding_side_v1")]
public sealed record GasCommodityHoldingSide:ValueSide
{
    public const string Role="gas_commodity_claim",ModelVersion="gas_commodity_holding_side_pv_v2";
    [IdentityField]public CurveRequest Mark {get;}
    [IdentityField]public ReferenceKey QuantitySpecification {get;}
    [IdentityField]public ReferenceKey PaymentCurrency=>Currency;
    [IdentityField]public DateTimeOffset? ReturnAt {get;}
    [IdentityField]public GasHoldingCarrying Carrying {get;}
    public GasCommodityHoldingSide(Guid id,CurveRequest mark,ReferenceKey quantity,ReferenceKey currency,DateTimeOffset? returnAt,GasHoldingCarrying carrying)
        :base(id,currency,new(ExactDecimal.Parse("1"),quantity),ModelVersion,[new(0,ComponentKind.Holding,null,null,returnAt,null,mark)])
    {
        Money.RequireKey(quantity);
        if(mark.Curve.Revision.CatalogId==Guid.Empty||mark.Curve.Revision.RevisionId==Guid.Empty||string.IsNullOrWhiteSpace(mark.Curve.Code)||
            mark.Contract.Id==Guid.Empty||mark.Contract.Revision!=mark.Curve.Revision||quantity.Revision!=currency.Revision||!Enum.IsDefined(carrying)||
            returnAt is {} at&&!TradingInstant.IsSupported(at)||carrying==GasHoldingCarrying.CurrencyCurve&&returnAt is null)
            throw new MarketDataException("gas_holding_terms","Select exact native mark, quantity/currency and explicit holding carrying terms.");
        Mark=mark;QuantitySpecification=quantity;ReturnAt=returnAt;Carrying=carrying;
    }
    private SidePaymentKey Return=>new(Id,0,ReturnAt!.Value,Currency){Timing=ValueTimingKind.Instant};
    internal void RequireState(IBindingValuationState? state)
    {
        if(state is null)return;
        if(state is not ProjectedGasStockValuation stock||Carrying!=GasHoldingCarrying.Nominal||ReturnAt is not null||stock.Quantity.Specification!=QuantitySpecification)
            throw new MarketDataException("gas_projection_stock","Only an exact projected owned-stock resource state may accompany this gas claim.");
        stock.Validate();
    }
    private void RequireContext(IBindingValuationState? state,bool projection)
    {
        RequireState(state);
        if(state is ProjectedGasStockValuation&&!projection)
            throw new MarketDataException("gas_projection_actual","Hypothetical gas title and supply cannot enter an actual held valuation.");
    }
    internal UnitPricingContract Declare(UnitValuationContext context)
    {
        RequireContext(context.BindingState,context.IsLifecycleProjection);
        var discounted=Carrying==GasHoldingCarrying.CurrencyCurve&&ReturnAt>context.CalculationAt;
        return new(Id,ModelVersion,[Mark],QuantitySpecification,Currency){
            Time=discounted?ValuationTimeDependency.Between(context.CalculationAt,ReturnAt!.Value):ValuationTimeDependency.Independent,
            DiscountInputs=discounted?[new(Return,context.PaymentDiscounting(Id))]:[]};
    }
    protected override ImmutableArray<ScheduleRowValue> Evaluate(SideValuationContext context,IReadOnlyList<ScheduleRow> rows)
    {
        var scope=context.UnitEvaluation;RequireContext(context.BindingState,scope.IsLifecycleProjection);
        var price=context.Inputs.ExactPrice(Mark);
        if(price.Unit.Quantity!=QuantitySpecification||price.Unit.Currency!=Currency)
            throw new MarketDataException("gas_holding_unit","The gas claim mark must retain its exact quantity specification and currency.");
        var amount=price.ExactTimes(UnitQuantity);var pv=amount;SidePaymentFactor? factor=null;
        if(Carrying==GasHoldingCarrying.CurrencyCurve&&ReturnAt>scope.CalculationAt)
        {
            var factors=context.Inputs.Discounts([Return]);
            if(factors.Length!=1||factors[0].Payment!=Return)
                throw new MarketDataException("gas_holding_discount","The return claim requires its exact declared currency discount input.");
            factor=factors[0];pv=amount.Scale(factor.DiscountFactor);
        }
        return [Value(rows[0],amount,pv,ReturnAt??scope.CalculationAt,price,factor)];
    }
}
