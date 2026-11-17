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
[EconomicDefinition("gas_transport_direct_rights_instrument_v1")]
public sealed record GasTransportDirectRightsInstrument:Instrument
{
    public const string ModelVersion="gas_transport_direct_rights_whole_position_pv_v1";
    [IdentityField]public GasTransportDirectRightsTerms Terms{get;}
    [IdentityField]public GasTransportDirectRightsState State{get;}
    [IdentityField]public DateTimeOffset Through{get;}
    [IdentityField]public string ExpiryPolicy{get;}
    [IdentityField]public GasTransportDirectRightsExpiry? Expiry{get;}
    public CapturedPriceSource? Source{get;}
    public GasTransportDirectRightsMark? Mark{get;}
    public GasTransportDirectRightsEvaluation? Evaluation{get;}
    public override bool SupportsWholePosition=>true;
    public override ReferenceKey Currency=>Terms.Currency;
    public override Quantity UnitQuantity=>new(ExactDecimal.Parse("1"),Terms.PackageQuantity);
    public override DefinitionIdentity PricingBindingIdentity=>DefinitionIdentity.For(new PriceBinding(Source?.Market,
        Source?.Snapshot.Id,Evaluation?.BaseScenarioId,Evaluation?.Context.ManifestId,Mark?.Observation.Id));

    public GasTransportDirectRightsInstrument(Guid id,GasTransportDirectRightsTerms terms,GasTransportDirectRightsState state,
        DateTimeOffset through,string expiryPolicy,GasTransportDirectRightsExpiry? expiry,CapturedPriceSource? source,
        GasTransportDirectRightsMark? mark,GasTransportDirectRightsEvaluation? evaluation):base(id)
    {
        GasTransportDirectRightsValuation.RequireContract(terms,state);
        if(expiryPolicy!=GasTransportDirectRightsPolicy.ExpiryAtThrough||!TradingInstant.IsSupported(through))
            throw Error("expiry","Select the exact installed fixed-window expiry law and contractual rights horizon.");
        if(expiry is not null)
        {
            if(expiry.Id==Guid.Empty||expiry.PreviousLiveStateId==Guid.Empty||expiry.Id==expiry.PreviousLiveStateId||expiry.State!=state||
                expiry.Through!=through||expiry.EffectiveAt!=through||!TradingInstant.IsSupported(expiry.KnownAt)||expiry.KnownAt<through||
                source is not null||mark is not null||evaluation is not null)
                throw Error("expiry","A closed whole position requires its exact accepted expiry, state, prior live lineage and horizon, without a live mark.");
        }
        else
        {
            if(source is null||mark is null||evaluation is null||source.Point!=mark.Point||
                !source.Valuation.Scenario.Plan.Points.TryGetValue(source.Point,out var point)||
                point.Expression is not ConnectedSource direct||direct.Request!=source.Market||point.Contract?.Key!=source.Market.Contract)
                throw Error("mark","The live whole position requires its exact captured current rights mark.");
            _=GasTransportDirectRightsValuation.PV(terms,state,mark,evaluation,source.Valuation.Scenario);
            if(evaluation.Context.ValuationAt>=through)
                throw Error("expiry_required","The live rights window has ended. An explicit accepted expiry is required; the date alone supplies no zero value.");
        }
        Terms=terms;State=state;Through=through;ExpiryPolicy=expiryPolicy;Expiry=expiry;Source=source;Mark=mark;Evaluation=evaluation;
    }

    public override UnitPricingContract Declare(UnitValuationContext context)
    {
        RequireContext(context);
        return new(Id,ModelVersion,Source is {} source?[source.Market]:[],Terms.PackageQuantity,Currency){Time=ValuationTimeDependency.Pinned};
    }
    public override UnitValuation PV(UnitValuationContext context)
    {
        RequireContext(context);
        ValidateValuationState(context.BindingState);
        if(Expiry is not null)return new(context,ExactMoney.Parse("0",Currency),Terms.PackageQuantity);
        context.Inputs.RequireSource(Source!);
        return new(context,context.Inputs.ExactPrice(Source!.Market).ExactTimes(UnitQuantity),Terms.PackageQuantity);
    }
    private void RequireContext(UnitValuationContext context)
    {
        if(context is null||context.Measure!=ValuationMeasure.PresentValue)
            throw new MarketDataException("valuation_measure","A whole service-rights position implements present value only.");
        if(context.IsLifecycleProjection||context.CalculationAt!=context.Snapshot.ValuationAt)
            throw Error("time","The current rights profile has no projected or shifted-clock valuation.");
        if(Expiry is {} expiry)
        {
            if(context.Snapshot.Knowledge is not {} known||context.Snapshot.ValuationAt<expiry.EffectiveAt||known.KnownAt<expiry.KnownAt)
                throw Error("expiry","This read does not cover the exact accepted expiry fact.");
        }
        else if(context.CalculationAt>=Through)
            throw Error("expiry_required","A live rights position at its horizon requires explicit accepted expiry.");
    }
    static MarketDataException Error(string suffix,string message)=>new("gas_transport_rights_"+suffix,message);
    [EconomicDefinition("gas_transport_direct_rights_price_binding_v1")]
    sealed record PriceBinding([property:IdentityField]CurveRequest? Market,[property:IdentityField]Guid? Snapshot,
        [property:IdentityField]string? BaseScenario,[property:IdentityField]string? Manifest,[property:IdentityField]Guid? Observation);
}
