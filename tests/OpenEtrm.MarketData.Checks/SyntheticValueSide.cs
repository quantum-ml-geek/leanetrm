using System.Collections.Immutable;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Risk;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Trading;
using OpenEtrm.Shared.Numerics;

// Reusable test black box: the Side owns the fixture formula and its genuine
// current-value schedule. It never calls an Instrument or another Side.
[EconomicDefinition("synthetic_value_side_v1")]
internal sealed record SyntheticValueSide : Side
{
    [IdentityField] public string Model { get; }
    [IdentityField] public ReferenceKey Currency { get; }
    [IdentityField] public Quantity UnitQuantity { get; }
    [IdentityField] public ImmutableArray<CurveRequest> Markets { get; }
    public override ImmutableArray<CurveRequest> Dependencies=>Markets;
    private readonly Func<SideValuationContext,ExactMoney> calculate;
    private readonly SyntheticValueSchedule schedule;
    private SyntheticValueSide(Guid id,ReferenceKey currency,ReferenceKey quantity,ImmutableArray<CurveRequest> markets,
        Func<SideValuationContext,ExactMoney> calculate,string model)
        :base(id,new(CalendarBinding.NotApplicable(),CalendarBinding.NotApplicable(),CalendarBinding.NotApplicable(),SideCalendarPolicy.Implementation))
    {Model=model;Markets=markets;Currency=currency;UnitQuantity=new(ExactDecimal.Parse("1"),quantity);this.calculate=calculate;schedule=new(this);}
    public override SideSchedule GenerateSchedule()=>schedule;
    public override SideValuation PV(SideValuationContext context)
    {
        var amount=calculate(context);var row=schedule.Rows.Single();
        var value=new ScheduleRowValue(Id,null,ComponentKind.Holding,null,ExactQuantity.FromQuantity(UnitQuantity),VolumeState.Contractual,null,[],[],[],
            amount,ExactDecimal.Parse("1"),Model,context.Snapshot.ValuationAt,null,amount,null,null,ValueCoverage.HoldingValue,null){Row=row};
        return new SyntheticValueValuation(schedule,context,value);
    }
    internal static ImmutableArray<SideMembership> One(Guid id,ReferenceKey currency,ReferenceKey quantity,ImmutableArray<CurveRequest> markets,
        Func<SideValuationContext,ExactMoney> calculate,string model)=>[new(new SyntheticValueSide(id,currency,quantity,markets,calculate,model),ExactDecimal.Parse("1"))];
    private sealed record SyntheticValueSchedule : SideSchedule
    {
        private readonly SyntheticValueSide side;
        public override ImmutableArray<CurveRequest> Dependencies=>side.Dependencies;
        public override IReadOnlyList<ScheduleRow> Rows{get;}
        internal SyntheticValueSchedule(SyntheticValueSide side):base(side.Id,side.Currency,side.UnitQuantity,side.Model)
        {this.side=side;Rows=[new(new ValueScheduleRow(side.Id,side.Currency,side.UnitQuantity,new(0,ComponentKind.Holding,null,null,null,null,null),side.Model))];}
        public override SideValuation Evaluate(SideValuationContext context)=>side.PV(context);
    }
    private sealed record SyntheticValueValuation(SideSchedule NativeSchedule,SideValuationContext NativeContext,ScheduleRowValue Value)
        :SideValuation(NativeSchedule,NativeContext,Value.RequirePresentValue())
    {
        public override SideScheduleSnapshot InspectSchedule(string manifest,ExactDecimal scale,SignedRatio coefficient,Func<DateOnly,DateTimeOffset> boundary)=>
            SideScheduleSnapshot.FromRows(this,[Value],manifest,scale,coefficient,boundary);
    }
}
internal abstract record SyntheticSidedInstrument : SidedInstrument
{
    protected SyntheticSidedInstrument(Guid id,ImmutableArray<SideMembership> sides):base(id,sides) { }
    internal override bool SupportsSettlement=>false;
    internal override UnitPricingContract DeclareScope(UnitValuationContext context,bool lifecycle)=>Declare(context);
}
