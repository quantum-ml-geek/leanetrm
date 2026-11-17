using System.Collections.Immutable;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Risk;
using OpenEtrm.MarketData.Trading;

// Actual current-value Side used by API test consumers. Work/admission probes
// put their deliberate no-valuation refusal here rather than on an Instrument.
[EconomicDefinition("synthetic_api_formula_side_v1")]
internal sealed record ApiFormulaSide : ValueSide
{
    [IdentityField] public string Model { get; }
    [IdentityField] public ImmutableArray<CurveRequest> Markets { get; }
    private readonly Func<SideValuationContext,ExactMoney> calculate;
    private ApiFormulaSide(Guid id,ReferenceKey currency,ReferenceKey quantity,ImmutableArray<CurveRequest> markets,
        Func<SideValuationContext,ExactMoney> calculate,string model)
        :base(id,currency,new(ExactDecimal.Parse("1"),quantity),model,[new(0,ComponentKind.Holding,null,null,null,null,null)])
    {Model=model;Markets=markets;this.calculate=calculate;}
    public override ImmutableArray<CurveRequest> Dependencies=>Markets;
    protected override ImmutableArray<ScheduleRowValue> Evaluate(SideValuationContext context,IReadOnlyList<ScheduleRow> rows)
    {var amount=calculate(context);return [Value(rows[0],amount,amount,context.Snapshot.ValuationAt)];}
    internal static ImmutableArray<SideMembership> One(Guid id,ReferenceKey currency,ReferenceKey quantity,ImmutableArray<CurveRequest> markets,
        Func<SideValuationContext,ExactMoney> calculate,string model)=>[new(new ApiFormulaSide(id,currency,quantity,markets,calculate,model),ExactDecimal.Parse("1"))];
}
internal abstract record ApiSidedProbe : SidedInstrument
{
    protected ApiSidedProbe(Guid id,ReferenceKey currency,ReferenceKey quantity,ImmutableArray<CurveRequest> inputs,
        Func<SideValuationContext,ExactMoney> calculate,string model):base(id,ApiFormulaSide.One(id,currency,quantity,inputs,calculate,model)) { }
}
