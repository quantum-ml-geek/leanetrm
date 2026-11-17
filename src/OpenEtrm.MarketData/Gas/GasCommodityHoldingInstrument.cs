using System.Collections.Immutable;
using OpenEtrm.MarketData.Risk;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.MarketData.Gas;

public enum GasHoldingCarrying { Nominal=1,CurrencyCurve }

// A reusable unit claim on gas, not its owner's title or performance history.
// Native owned holdings apply signed quantities outside this ordinary pricer.
[EconomicDefinition("gas_commodity_holding_v2")]
public sealed record GasCommodityHoldingInstrument:SidedInstrument,IGasQuantityInstrument
{
    [IdentityField]public CurveRequest Mark{get;}
    [IdentityField]public ReferenceKey QuantitySpecification{get;}
    [IdentityField]public ReferenceKey PaymentCurrency{get;}
    [IdentityField]public DateTimeOffset? ReturnAt{get;}
    [IdentityField]public GasHoldingCarrying Carrying{get;}
    public override Quantity UnitQuantity=>new(ExactDecimal.Parse("1"),QuantitySpecification);
    public override ReferenceKey Currency=>PaymentCurrency;
    public override bool SupportsQuantityScaling=>true;
    public GasCommodityHoldingSide HoldingSide=>(GasCommodityHoldingSide)Sides[0].Side;
    internal override bool SupportsSettlement=>false;
    Instrument IGasQuantityInstrument.ValuationInstrument=>this;
    public static Guid SelectedNativeMarkIdentity(Guid position,CurveRequest mark,int revision)
    {
        if(position==Guid.Empty||mark.Curve.Revision.CatalogId==Guid.Empty||mark.Curve.Revision.RevisionId==Guid.Empty||
            string.IsNullOrWhiteSpace(mark.Curve.Code)||mark.Contract.Id==Guid.Empty||mark.Contract.Revision!=mark.Curve.Revision||revision<0)
            throw new MarketDataException("gas_owned_mark","Select the exact owned holding and retained mark revision.");
        return ContractIdentity.FromCanonical($"gas_owned_selected_mark_v1:{position:D}:{mark.Curve.Revision.CatalogId:D}:{mark.Curve.Revision.RevisionId:D}:{mark.Curve.Code}:{mark.Contract.Id:D}:{revision}");
    }
    public GasCommodityHoldingInstrument(Guid id,CurveRequest mark,ReferenceKey quantity,ReferenceKey currency,
        DateTimeOffset? returnAt,GasHoldingCarrying carrying):base(id,
            [new(new GasCommodityHoldingSide(id,mark,quantity,currency,returnAt,carrying),ExactDecimal.Parse("1"))])
    {
        Mark=mark;QuantitySpecification=quantity;PaymentCurrency=currency;ReturnAt=returnAt;Carrying=carrying;
    }
    public override void ValidateValuationState(IBindingValuationState? state)=>HoldingSide.RequireState(state);
    public override UnitPricingContract Declare(UnitValuationContext context)=>HoldingSide.Declare(context);
    internal override UnitPricingContract DeclareScope(UnitValuationContext context,bool lifecycle)=>Declare(context);
}
