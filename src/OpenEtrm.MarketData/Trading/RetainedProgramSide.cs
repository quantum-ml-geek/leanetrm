using System.Collections.Immutable;
using OpenEtrm.Shared.Numerics;

namespace OpenEtrm.MarketData.Trading;

// Admitted source values and connected physical geometry, never an Instrument
// or a resolver for another Side. Each Side executes only its own saved program.
internal sealed record RetainedProgramContext(ScheduleMarketSources Sources, CurveBuild Scenario)
{
    internal PhysicalLifecycleGeometry? Geometry { get; init; }
    internal PhysicalCashState? Cash { get; init; }
    internal ImmutableArray<SignedRatio> HeldFactors { get; init; } = [];
}
public sealed partial class SideValuationContext
{
    internal RetainedProgramContext? RetainedPrograms { get; private set; }
    internal SideValuationContext WithRetainedPrograms(RetainedProgramContext inputs)
    {var copy=(SideValuationContext)MemberwiseClone();copy.RetainedPrograms=inputs;return copy;}
}

[EconomicDefinition("retained_program_side_v1")]
public sealed record RetainedProgramSide : Side
{
    public BookedSideProgram Program { get; }
    [IdentityField] public string ProgramDigest { get; }
    [IdentityField] public ReferenceKey Currency { get; }
    [IdentityField] public Quantity UnitQuantity { get; }
    internal int Slot { get; }
    public override ImmutableArray<CurveRequest> Dependencies => [..Program.Document.Instructions.SelectMany(i => i.Bindings)
        .Where(b => b.Market is not null).Select(b => b.Market!.Value).Distinct()];
    // Structure-only construction uses the same definition as valued retained
    // Instruments. Authority and executable source inputs stay with the caller.
    public static RetainedProgramSide Define(Guid sideId,int slot,BookedSideProgram program,Quantity normalizedUnit,ReferenceKey currency)
    {
        if(program is null)throw new MarketDataException("retained_side_composition","Retain an exact admitted Side program.");
        return new(sideId,slot,program,normalizedUnit,currency);
    }
    private RetainedProgramSide(Guid id, int slot, BookedSideProgram program, Quantity unit, ReferenceKey currency)
        : base(id, RetainedSideCalendarPolicy.Read(program))
    {
        if(slot < 0 || unit is null || unit.Amount != ExactDecimal.Parse("1"))
            throw new MarketDataException("retained_side_composition", "A retained Side requires its exact normalized unit and ordered membership slot.");
        Program = program; ProgramDigest = BookedSideProgram.Digest(program.Write());
        Slot = slot; UnitQuantity = unit; Currency = currency;
    }
    private static readonly System.Runtime.CompilerServices.ConditionalWeakTable<RetainedProgramSide,RetainedProgramSchedule> Schedules = new();
    public override RetainedProgramSchedule GenerateSchedule() => Schedules.GetValue(this, static side => new(side));
    public override RetainedProgramValuation PV(SideValuationContext context) => GenerateSchedule().Evaluate(context);
}

public sealed record RetainedProgramSchedule : SideSchedule
{
    public RetainedProgramSide Side { get; }
    public BookedSideProgram Program => Side.Program;
    public override ImmutableArray<CurveRequest> Dependencies => Side.Dependencies;
    private readonly Lazy<IReadOnlyList<ScheduleRow>> rows;
    public override IReadOnlyList<ScheduleRow> Rows => rows.Value;
    internal RetainedProgramSchedule(RetainedProgramSide side)
        : base(side.Id, side.Currency, side.UnitQuantity, "retained_program_side_execution_v1")
    {
        Side = side;
        // Exact output addresses are views of the stored program, not a newly
        // generated schedule. A grid contribution retains every native cell.
        rows = new(() => [..Program.Document.Instructions.Where(i => i.Output.Operation == "output_guard").SelectMany(i =>
            Enumerable.Range(0, i.Output.Grid is {} grid ? Program.Document.Grids[grid].CellCount : 1)
                .Select(cell => new ScheduleRow(new RetainedProgramRow(SideId, Program, i.Output.Ordinal, cell, UnitQuantity, Currency))))]);
    }
    public override RetainedProgramValuation Evaluate(SideValuationContext context)
    {
        if(context?.RetainedPrograms is not {} inputs)
            throw new MarketDataException("native_program_context", "A retained Side requires its exact admitted base/scenario source values.");
        var execution = inputs.Sources.Evaluate(Program, SideId, inputs.Scenario, context.Discounting, context.UnitEvaluation.Cancellation);
        PhysicalLifecycleValue? lifecycle = null;
        if(inputs.Cash is {} state)
        {
            if(inputs.Geometry is null || Side.Slot >= inputs.HeldFactors.Length)
                throw new MarketDataException(PhysicalLifecycle.ContextRefusal, "The Side requires its exact connected gas-day geometry and held cash normalization.");
            lifecycle = PhysicalLifecycle.EvaluateSide(Program, execution, Program.Document.Family == "gas", Side.Slot,
                inputs.HeldFactors[Side.Slot], inputs.Geometry, state, context.Snapshot, Currency);
        }
        return new(this, context, execution, lifecycle);
    }
}
public sealed record RetainedProgramValuation : SideValuation
{
    public BookedSideEvaluation Execution { get; }
    public PhysicalLifecycleValue? Lifecycle { get; }
    internal RetainedProgramValuation(RetainedProgramSchedule schedule, SideValuationContext context,
        BookedSideEvaluation execution, PhysicalLifecycleValue? lifecycle)
        : base(schedule, context, lifecycle?.Total ?? execution.PresentValue)
    { Execution = execution; Lifecycle = lifecycle; }
    public override SideScheduleSnapshot InspectSchedule(string manifest, ExactDecimal scale, SignedRatio coefficient, Func<DateOnly, DateTimeOffset> boundary)
    {
        var program = ((RetainedProgramSchedule)Schedule).Program;
        if(manifest != program.Document.ScheduleManifest || !Context.IsBaseScenario)
            throw new MarketDataException("side_schedule_inspection", "Inspect the exact base-scenario retained Side program.");
        if(Lifecycle is null) return SideScheduleSnapshot.FromProgramValue(this, Execution, program, manifest, scale, coefficient, boundary);
        var factor = new SignedRatio(scale.ScaledValue, ExactDecimal.WorkingScale) * coefficient;
        var rows = PhysicalLifecycle.Scale(Lifecycle, factor).Rows;
        return SideScheduleSnapshot.FromLifecycle(SideId, Snapshot.Id, new(SideId.ToString(), Execution, program, scale, coefficient, []),
            rows, ImmutableDictionary<int, ExactMoney>.Empty, boundary);
    }
}

// Native program address, retained for schedules and inspection without
// reconstructing dated terms or recompiling an already certified program.
public sealed record RetainedProgramRow(Guid SideId, BookedSideProgram Program, int Instruction, int Cell, Quantity UnitQuantity, ReferenceKey Currency)
{
    internal ScheduleDefinitionRow Output => Program.Document.Instructions[Instruction].Output;
    internal DeliveryInterval? Interval => Output.Grid is {} grid ? Program.Document.Grids[grid].Interval(Cell) : Output.Interval;
    internal SidePaymentKey Payment => Output.ValueAt is {} at && Output.PaymentOrdinal is {} occurrence
        ? new(SideId, occurrence, at, Currency){Timing=Output.Parameters["lifecycle"]==OperatingContractScheduleSource.DeliveryLifecycle?ValueTimingKind.Instant:ValueTimingKind.UtcPaymentDay}
        : throw new MarketDataException("schedule_row_kind", "This retained output has no payment/value-time identity.");
}
