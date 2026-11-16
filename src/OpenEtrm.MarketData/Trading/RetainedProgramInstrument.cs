using System.Collections.Immutable;
using OpenEtrm.Shared.Numerics;
using OpenEtrm.MarketData.Risk;

namespace OpenEtrm.MarketData.Trading;

// Commodity definitions retain their own identity fields and membership rules.
public interface IRetainedProgramMember
{
    Guid SideId { get; }
    BookedSideProgram Program { get; }
    string ProgramDigest { get; }
    ExactDecimal ValuationCoefficient { get; }
    ExactRatio? ValuationRatio { get; }
}

// Shared contractual PV mechanics for independently valued retained programs.
// Source admission, units and physical policies stay with the concrete model.
internal interface IRetainedProgramComposition;
public abstract record RetainedProgramInstrument<TMember> : SidedInstrument,IRetainedProgramComposition where TMember : IRetainedProgramMember
{
    public abstract ImmutableArray<TMember> Members { get; }
    // Members already encode these exact immutable economics in the published
    // identity contract. This derived view must not add a second identity field.
    public new ImmutableArray<SideMembership> Sides=>base.Sides;
    public override bool SupportsQuantityScaling => true;
    internal override bool RequiresNativeProgramMarket => true;
    public override string RetainedScheduleIdentity => "retained_side_programs_v1/" + string.Join('/', Members.Select(m => m.ProgramDigest));

    protected RetainedProgramInstrument(Guid id) : base(id) { }
    protected abstract ScheduleMarketSources Sources(CurveBuild basis);
    private protected virtual RetainedProgramSources ProgramSources=>new RetainedProgramSources.Admitted(Sources);
    protected override ImmutableArray<SideMembership> ComposeSides()
    {
        var owned=new Dictionary<Guid,RetainedProgramSide>();var sources=ProgramSources;
        return [..Members.Select(member=>
        {
            if(!owned.TryGetValue(member.SideId,out var side))
            {
                side=sources is RetainedProgramSources.Operating?RetainedProgramSide.ForOperating(member.SideId,member.Program,UnitQuantity,Currency):
                    new RetainedProgramSide(member.SideId,member.Program,UnitQuantity,Currency,sources);
                owned.Add(member.SideId,side);
            }
            else if(side.ProgramDigest!=member.ProgramDigest)
                throw new MarketDataException("side_identity","One exact Side identity cannot own different retained programs.");
            return new SideMembership(side,member.ValuationCoefficient,member.ValuationRatio);
        })];
    }
    internal override bool SupportsSettlement=>false;
    internal override UnitPricingContract DeclareScope(UnitValuationContext context,bool lifecycle)=>Declare(context);
    public override InstrumentValuation PV(SideValuationContext context)
    {
        if(context is null)throw new MarketDataException("side_context","Supply the exact retained Side valuation context.");
        if(context.BindingState is PhysicalCashState)
            throw new MarketDataException(PhysicalLifecycle.ContextRefusal,"A held physical lifecycle requires its unit valuation path; raw contractual Side PV cannot replace paid-state valuation.");
        ValidateValuationState(context.BindingState);
        PhysicalLifecycle.RequireUnstarted(Members.Select(member=>member.Program),context.Snapshot.ValuationAt);
        return base.PV(context);
    }

    public override ExactMoney Value(UnitValuationContext context)
    {
        if(context.Measure!=ValuationMeasure.PresentValue)
            throw new MarketDataException("valuation_measure","This retained instrument implements contractual present value only.");
        return PV(context.SideContext(context.DiscountProvider)).PresentValue;
    }

    // One unscaled evaluation per member, in member order, from the shared base and scenario markets.
    protected ImmutableArray<BookedSideEvaluation> EvaluateMembers(UnitValuationContext context)
    {
        if (context.Measure != ValuationMeasure.PresentValue)
            throw new MarketDataException("valuation_measure", "This retained instrument implements contractual present value only.");
        var inputs=context.SideContext(context.DiscountProvider);
        return [..Sides.Select(member=>((RetainedProgramSideValuation)inputs.Evaluate(member.Side)).Execution)];
    }
    protected static ExactMoney Signed(TMember member, ExactMoney value) =>
        (member.ValuationRatio is {} ratio ? value.Scale(ratio) : value).Scale(member.ValuationCoefficient);

    // The started-delivery lifecycle has one supported consumer; other commodities name the missing policy.
    public override void ValidateValuationState(IBindingValuationState? state)
    {
        if (state is PhysicalCashState)
            throw new MarketDataException("physical_lifecycle_unsupported", "This retained instrument has no started-delivery lifecycle policy.");
        if(state is not null)
            throw new MarketDataException("settlement_scope","This instrument does not support the supplied binding valuation state.");
    }
}
