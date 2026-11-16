using System.Collections.Immutable;
using OpenEtrm.Shared.Numerics;
using OpenEtrm.MarketData.Risk;

namespace OpenEtrm.MarketData.Trading;

public interface IRetainedProgramMember
{
    Guid SideId { get; }
    BookedSideProgram Program { get; }
    string ProgramDigest { get; }
    ExactDecimal ValuationCoefficient { get; }
    ExactRatio? ValuationRatio { get; }
}

// Published Members remain the canonical contract. Sides are a checked,
// deterministic execution view of those same programs, in membership order.
internal interface IRetainedSideComposition
{
    void RequireRetainedSides();
}

public abstract record RetainedProgramInstrument<TMember> : SidedInstrument, IRetainedSideComposition where TMember : IRetainedProgramMember
{
    public abstract ImmutableArray<TMember> Members { get; }
    internal override bool SupportsSettlement => false;
    internal override bool RequiresNativeProgramMarket => true;
    public override string RetainedScheduleIdentity => "retained_side_programs_v1/" + string.Join('/', Members.Select(m => m.ProgramDigest));

    protected RetainedProgramInstrument(Guid id, ImmutableArray<TMember> members, Quantity unit, ReferenceKey currency)
        : base(id, CreateSides(members, unit, currency)) { }
    private static ImmutableArray<SideMembership> CreateSides(ImmutableArray<TMember> members, Quantity unit, ReferenceKey currency)
    {
        if(members.IsDefaultOrEmpty || members.Any(m => m is null || m.Program is null))
            throw new MarketDataException("retained_side_composition", "Retain the complete ordered program memberships.");
        return [..members.Select((m, slot) => new SideMembership(
            RetainedProgramSide.Define(m.SideId, slot, m.Program, unit, currency), m.ValuationCoefficient, m.ValuationRatio))];
    }
    private static readonly System.Runtime.CompilerServices.ConditionalWeakTable<RetainedProgramInstrument<TMember>,object> Proofs = new();
    public void RequireRetainedSides() => _ = Proofs.GetValue(this, static instrument =>
    {instrument.ValidateRetainedSides();return new object();});
    private void ValidateRetainedSides()
    {
        if(Sides.IsDefault || Sides.Length != Members.Length) throw Composition();
        for(var slot = 0; slot < Members.Length; slot++)
        {
            var member = Members[slot]; var actual = Sides[slot];
            if(actual?.Side is not RetainedProgramSide side || side.Slot != slot || side.Id != member.SideId ||
                actual.Coefficient != member.ValuationCoefficient || actual.QuantityRatio != member.ValuationRatio ||
                side.ProgramDigest != member.ProgramDigest || side.Currency != Currency || side.UnitQuantity != UnitQuantity ||
                !ReferenceEquals(side.Program, member.Program) && !side.Program.Write().AsSpan().SequenceEqual(member.Program.Write()) ||
                DefinitionIdentity.For(side.CalendarPolicy) != DefinitionIdentity.For(RetainedSideCalendarPolicy.Read(member.Program)))
                throw Composition();
        }
    }
    private static MarketDataException Composition() => new("retained_side_composition", "Every retained Side must preserve its exact ordered native program, coefficient, ratio, unit and captured calendar policy.");
    protected UnitPricingContract RetainedDeclaration(UnitPricingContract declaration)
    {RequireRetainedSides();return declaration;}
    protected abstract ScheduleMarketSources Sources(CurveBuild basis);
    private protected virtual RetainedProgramContext PrepareSides(UnitValuationContext context, CurveBuild basis, CurveBuild scenario) => new(Sources(basis), scenario);
    protected InstrumentValuation EvaluateSides(UnitValuationContext context)
    {
        RequireRetainedSides();
        if(context.Measure != ValuationMeasure.PresentValue)
            throw new MarketDataException("valuation_measure", "This retained instrument implements contractual present value only.");
        var (basis, scenario) = context.RetainedProgramMarkets(Declare(context).Dependencies);
        return PV(context.SideContextRetained(PrepareSides(context, basis, scenario)));
    }
    public override InstrumentValuation PV(SideValuationContext context)
    {
        RequireRetainedSides();
        return base.PV(context);
    }
    public override ExactMoney Value(UnitValuationContext context) => EvaluateSides(context).PresentValue;
    internal override UnitPricingContract DeclareScope(UnitValuationContext context, bool lifecycle)
    {
        RequireRetainedSides();
        return Declare(context);
    }
    public override void ValidateValuationState(IBindingValuationState? state)
    {
        if(state is PhysicalCashState)
            throw new MarketDataException("physical_lifecycle_unsupported", "This retained instrument has no started-delivery lifecycle policy.");
        if(state is not null)
            throw new MarketDataException("settlement_scope", "This retained instrument does not accept an unrelated settlement state.");
    }
}
