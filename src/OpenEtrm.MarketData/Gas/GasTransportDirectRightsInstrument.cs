using OpenEtrm.MarketData.Calculation;
using OpenEtrm.MarketData.Risk;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.MarketData.Gas;

[EconomicDefinition("gas_transport_direct_rights_expiry_v1")]
public sealed record GasTransportDirectRightsExpiry([property:IdentityField]Guid Id,
    [property:IdentityField]GasTransportDirectRightsState State,[property:IdentityField]Guid PreviousLiveStateId,
    [property:IdentityField]DateTimeOffset Through,[property:IdentityField]DateTimeOffset EffectiveAt,[property:IdentityField]DateTimeOffset KnownAt);

// The native adapter authenticates financial-state/expiry lineage and authority.
// This pricer never turns an elapsed window or an absent mark into expiry.
[EconomicDefinition("gas_transport_direct_rights_instrument_v2")]
public sealed record GasTransportDirectRightsInstrument:SidedInstrument
{
    public const string ModelVersion="gas_transport_direct_rights_whole_position_side_pv_v2";
    [IdentityField]public GasTransportDirectRightsTerms Terms{get;}
    [IdentityField]public GasTransportDirectRightsState State{get;}
    [IdentityField]public DateTimeOffset Through{get;}
    [IdentityField]public string ExpiryPolicy{get;}
    [IdentityField]public GasTransportDirectRightsExpiry? Expiry{get;}
    public CapturedPriceSource? Source{get;}
    public GasTransportDirectRightsMark? Mark{get;}
    public GasTransportDirectRightsEvaluation? Evaluation{get;}
    public override bool SupportsWholePosition=>true;
    public override bool SupportsQuantityScaling=>false;
    internal override bool SupportsSettlement=>false;
    public GasTransportDirectRightsSide RightsSide=>(GasTransportDirectRightsSide)Sides[0].Side;
    public override ReferenceKey Currency=>Terms.Currency;
    public override Quantity UnitQuantity=>new(ExactDecimal.Parse("1"),Terms.PackageQuantity);
    public override DefinitionIdentity? PricingBindingIdentity=>RightsSide.PricingBindingIdentity;

    public static GasTransportDirectRightsSide DefineSide(Guid instrumentId,GasTransportDirectRightsTerms terms,GasTransportDirectRightsState state,
        DateTimeOffset through,string expiryPolicy,GasTransportDirectRightsExpiry? expiry)=>
        GasTransportDirectRightsSide.Definition(instrumentId,terms,state,through,expiryPolicy,expiry);

    public GasTransportDirectRightsInstrument(Guid id,GasTransportDirectRightsTerms terms,GasTransportDirectRightsState state,
        DateTimeOffset through,string expiryPolicy,GasTransportDirectRightsExpiry? expiry,CapturedPriceSource? source,
        GasTransportDirectRightsMark? mark,GasTransportDirectRightsEvaluation? evaluation)
        :base(id,[new(DefineSide(id,terms,state,through,expiryPolicy,expiry).Bind(source,mark,evaluation),ExactDecimal.Parse("1"))])
    {
        Terms=terms;State=state;Through=through;ExpiryPolicy=expiryPolicy;Expiry=expiry;Source=source;Mark=mark;Evaluation=evaluation;
    }
    public override UnitPricingContract Declare(UnitValuationContext context)
    {
        if(context is null||context.Measure!=ValuationMeasure.PresentValue)
            throw new MarketDataException("valuation_measure","A whole service-rights position implements present value only.");
        RightsSide.RequireContext(context.Snapshot,context.CalculationAt,context.IsLifecycleProjection);
        return new(Id,ModelVersion,RightsSide.Dependencies,Terms.PackageQuantity,Currency){Time=ValuationTimeDependency.Pinned};
    }
    public override void ValidateValuationState(IBindingValuationState? state)
    {
        if(state is not null)throw new MarketDataException("settlement_scope","The current rights Instrument has no external settlement-state interpretation.");
    }
    internal override UnitPricingContract DeclareScope(UnitValuationContext context,bool lifecycle)=>Declare(context);
}
