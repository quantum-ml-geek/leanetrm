using System.Collections.Immutable;
using OpenEtrm.MarketData.Calculation;
using OpenEtrm.MarketData.Trading;
using OpenEtrm.Shared.Commands;

namespace OpenEtrm.MarketData.Gas;

[EconomicDefinition("gas_transport_direct_rights_side_v1")]
public sealed record GasTransportDirectRightsSide:ValueSide
{
    public const string Role="remaining_service_rights";
    [IdentityField]public GasTransportDirectRightsTerms RightsTerms {get;}
    [IdentityField]public GasTransportDirectRightsState State {get;}
    [IdentityField]public DateTimeOffset Through {get;}
    [IdentityField]public string ExpiryPolicy {get;}
    [IdentityField]public GasTransportDirectRightsExpiry? Expiry {get;}
    public CapturedPriceSource? Source {get;}
    public GasTransportDirectRightsMark? Mark {get;}
    public GasTransportDirectRightsEvaluation? Evaluation {get;}
    public override DefinitionIdentity? PricingBindingIdentity=>Source is null?null:DefinitionIdentity.For(new PriceBinding(
        Source.Market,Source.Snapshot.Id,Evaluation!.BaseScenarioId,Evaluation.Context.ManifestId,Mark!.Observation.Id));
    internal GasTransportDirectRightsSide(Guid id,GasTransportDirectRightsTerms terms,GasTransportDirectRightsState state,
        DateTimeOffset through,string policy,GasTransportDirectRightsExpiry? expiry,CapturedPriceSource? source,
        GasTransportDirectRightsMark? mark,GasTransportDirectRightsEvaluation? evaluation)
        :base(id,terms.Currency,new(ExactDecimal.Parse("1"),terms.PackageQuantity),GasTransportDirectRightsInstrument.ModelVersion,
            [new(0,ComponentKind.Holding,null,null,expiry?.EffectiveAt,null,source?.Market)])
    {
        RightsTerms=terms;State=state;Through=through;ExpiryPolicy=policy;Expiry=expiry;Source=source;Mark=mark;Evaluation=evaluation;
    }
    internal static GasTransportDirectRightsSide Definition(Guid instrument,GasTransportDirectRightsTerms terms,GasTransportDirectRightsState state,
        DateTimeOffset through,string policy,GasTransportDirectRightsExpiry? expiry)
    {
        GasTransportDirectRightsValuation.RequireContract(terms,state);
        if(instrument==Guid.Empty||policy!=GasTransportDirectRightsPolicy.ExpiryAtThrough||!TradingInstant.IsSupported(through))
            throw Error("expiry","Select the exact installed fixed-window expiry law, identity and contractual rights horizon.");
        if(expiry is not null&&(expiry.Id==Guid.Empty||expiry.PreviousLiveStateId==Guid.Empty||expiry.Id==expiry.PreviousLiveStateId||expiry.State!=state||
            expiry.Through!=through||expiry.EffectiveAt!=through||!TradingInstant.IsSupported(expiry.KnownAt)||expiry.KnownAt<through))
            throw Error("expiry","A closed rights Side requires its exact accepted expiry, state, prior live lineage and horizon.");
        return new(OperationIdentity.For("gas_transport_direct_rights_side_v1",instrument),terms,state,through,policy,expiry,null,null,null);
    }
    internal GasTransportDirectRightsSide Bind(CapturedPriceSource? source,GasTransportDirectRightsMark? mark,GasTransportDirectRightsEvaluation? evaluation)
    {
        if(Expiry is not null)
        {
            if(source is not null||mark is not null||evaluation is not null)throw Error("expiry","Accepted expiry cannot carry a live mark.");
            return this;
        }
        if(source is null||mark is null||evaluation is null||source.Point!=mark.Point||
            !source.Valuation.Scenario.Plan.Points.TryGetValue(source.Point,out var point)||point.Expression is not ConnectedSource direct||
            direct.Request!=source.Market||point.Contract?.Key!=source.Market.Contract)
            throw Error("mark","The live rights Side requires its exact captured current rights mark.");
        _=GasTransportDirectRightsValuation.PV(RightsTerms,State,mark,evaluation,source.Valuation.Scenario);
        if(evaluation.Context.ValuationAt>=Through)
            throw Error("expiry_required","The live rights window has ended. An explicit accepted expiry is required; the date alone supplies no zero value.");
        return new(Id,RightsTerms,State,Through,ExpiryPolicy,Expiry,source,mark,evaluation);
    }
    internal void RequireContext(MarketSnapshot snapshot,DateTimeOffset calculationAt,bool lifecycle)
    {
        if(lifecycle||calculationAt!=snapshot.ValuationAt)
            throw Error("time","The current rights profile has no projected or shifted-clock valuation.");
        if(Expiry is {} expiry)
        {
            if(snapshot.Knowledge is not {} known||snapshot.ValuationAt<expiry.EffectiveAt||known.KnownAt<expiry.KnownAt)
                throw Error("expiry","This read does not cover the exact accepted expiry fact.");
        }
        else
        {
            if(Source is null||Mark is null||Evaluation is null)throw Error("mark","The rights Side is unpriced until an exact current mark is selected.");
            if(calculationAt>=Through)throw Error("expiry_required","A live rights position at its horizon requires explicit accepted expiry.");
        }
    }
    protected override ImmutableArray<ScheduleRowValue> Evaluate(SideValuationContext context,IReadOnlyList<ScheduleRow> rows)
    {
        var scope=context.UnitEvaluation;RequireContext(context.Snapshot,scope.CalculationAt,scope.IsLifecycleProjection);
        if(context.BindingState is not null)throw new MarketDataException("settlement_scope","The current rights Side has no external settlement-state interpretation.");
        if(Expiry is not null)
        {
            var zero=ExactMoney.Parse("0",Currency);return [Value(rows[0],zero,zero,scope.CalculationAt)];
        }
        context.Inputs.RequireSource(Source!);
        var price=context.Inputs.ExactPrice(Source!.Market);var value=price.ExactTimes(UnitQuantity);
        return [Value(rows[0],value,value,scope.CalculationAt,price)];
    }
    internal static MarketDataException Error(string suffix,string message)=>new("gas_transport_rights_"+suffix,message);
    [EconomicDefinition("gas_transport_direct_rights_side_price_binding_v1")]
    sealed record PriceBinding([property:IdentityField]CurveRequest Market,[property:IdentityField]Guid Snapshot,
        [property:IdentityField]string BaseScenario,[property:IdentityField]string Manifest,[property:IdentityField]Guid Observation);
}
