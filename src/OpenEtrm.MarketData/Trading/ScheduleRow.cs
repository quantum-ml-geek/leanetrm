using System.Collections.Immutable;
using OpenEtrm.MarketData.Power;

namespace OpenEtrm.MarketData.Trading;

public readonly record struct RetainedScheduleRowReference([property:System.Text.Json.Serialization.JsonIgnore]ScheduleDefinition Definition,int RootOrdinal,int? CellOrdinal)
{
    public Guid SideId=>Definition.SideId;
    public string Manifest=>Definition.Manifest;
    public ScheduleObligationIdentity Obligation=>Definition.ObligationIdentity(RootOrdinal,CellOrdinal);
}
internal sealed record IntervalRowBlock(PpaSideTerms Terms,IntervalScheduleMonth Month,IntervalSchedulePrice Price,RetainedSideSchedule? Retained=null);

// A row is a small view over shared immutable terms and an interval grid. Native
// schedules retain one block per month rather than one object for every row.
public readonly record struct ScheduleRow
{
    private readonly RetainedProgramRow? program = null;
    public RetainedProgramRow? ProgramReference => program;
    private readonly ValueScheduleRow? value=null;
    internal ValueScheduleRow? Value=>value;
    private readonly DatedScheduleRow? dated;
    private readonly IntervalRowBlock? block;
    private readonly OperatingScheduleRow? operating=null;
    internal OperatingScheduleRow? Operating=>operating;
    private readonly int offset;
    private readonly DeliveryInterval? physicalInterval;
    public bool IsValid=>program is not null||dated is not null||block is not null||operating is not null||value is not null;
    private DatedScheduleRow Dated=>dated??throw new MarketDataException("schedule_row_kind","This row has native interval input references.");
    private IntervalRowBlock Block=>block??throw new MarketDataException("schedule_row_kind","This row has dated contractual payment terms.");
    public SidePaymentKey Key=>program?.Payment??(value is {} native?native.Term.Payment??throw new MarketDataException("schedule_row_kind","A noncash value row has no payment identity."):dated?.Key??operating?.Key??Block.Month.Payment);
    public Guid SideId=>program?.SideId??value?.SideId??Key.SideId;
    public int Ordinal=>program?.Instruction??value?.Term.Ordinal??dated?.Ordinal??operating?.Key.Ordinal??Block.Month.FirstRowOrdinal+offset;
    public DeliveryInterval? Interval=>program?.Interval??physicalInterval??operating?.Period.Interval??block?.Month.Intervals[offset];
    public ScheduleDeliveryWindow DeliveryWindow=>program is {} saved ? saved.Interval is {} interval ? new IntervalScheduleWindow(interval) :
        saved.Output.DeliveryFrom is {} from && saved.Output.DeliveryTo is {} to ? new DatedScheduleWindow(from,to) : new ValueScheduleWindow(null,null) : value is {} native?new ValueScheduleWindow(native.Term.From,native.Term.To):physicalInterval is {} physical?new IntervalScheduleWindow(physical):
        dated?.DeliveryWindow??new IntervalScheduleWindow(operating?.Period.Interval??Block.Month.Intervals[offset]);
    public DateOnly DeliveryFrom=>program?.Output.DeliveryFrom??Dated.DeliveryFrom;
    public DateOnly DeliveryTo=>program?.Output.DeliveryTo??Dated.DeliveryTo;
    public DateTimeOffset PaymentAt=>Key.PaymentAt;
    public DateOnly PaymentDate=>DateOnly.FromDateTime(PaymentAt.UtcDateTime);
    public ReferenceKey Currency=>program?.Currency??value?.Currency??Key.Currency;
    public Quantity UnitQuantity=>program?.UnitQuantity??value?.UnitQuantity??dated?.UnitQuantity??operating?.UnitQuantity??Block.Terms.UnitQuantity;
    public ExactQuantity AllocatedQuantity=>value is {} native?ExactQuantity.FromQuantity(native.UnitQuantity):Dated.AllocatedQuantity;
    public ScheduleQuantityReference QuantityReference=>value is {} native?new ContractualScheduleQuantity(ExactQuantity.FromQuantity(native.UnitQuantity)):dated?.QuantityReference??(operating is {} source?
        new OperatingScheduleQuantity(source.Period.Quantity,source.Period.Interval):new IntervalScheduleQuantity(Block.Terms.Quantity,Block.Month.Intervals[offset]));
    public RetainedScheduleRowReference? RetainedReference=>dated?.RetainedReference??(block?.Retained is {} retained?
        new(retained.Definition,retained.NativeRows[Ordinal].Root,retained.NativeRows[Ordinal].CellOrdinal):null);
    public IntervalSchedulePrice? IntervalPrice=>block?.Retained is {} retained&&retained.NativeRows[Ordinal].FixedPrice is {} price?
        new FixedIntervalSchedulePrice(new RetainedFixedPrice(price)):block?.Price;
    public GeneratedPaymentDate? GeneratedDate=>dated?.GeneratedDate??operating?.GeneratedDate;
    public PaymentRule? PaymentConvention=>value is not null?null:dated is not null?dated.PaymentConvention:operating is not null?operating.Rule:Block.Terms.DateRule;
    public DateTimeOffset? FirstFixingAt=>value is not null?null:Dated.FirstFixingAt;
    public FloatingAveraging? Averaging=>value is not null?null:Dated.Averaging;
    public SwapObservationCalendar? Calendar=>value is not null?null:Dated.Calendar;
    public ImmutableArray<SchedulePriceTerm> Prices=>value is not null?[]:Dated.Prices;
    public ImmutableArray<SchedulePriceApplication> Applications=>value is not null?[]:Dated.Applications;
    public string Implementation=>program is not null?"retained_program_side_execution_v1":value?.Implementation??dated?.Implementation??(operating is not null?OperatingSideTerms.SupportedImplementation:"interval_side_schedule_v2");

    internal ScheduleRow(RetainedProgramRow row)
    {program=row;value=null;dated=null;block=null;offset=0;}

    internal ScheduleRow(ValueScheduleRow row)
    {value=row;dated=null;block=null;offset=0;}

    internal ScheduleRow(OperatingScheduleRow row)
    {dated=null;block=null;offset=0;operating=row;}

    internal ScheduleRow(Guid sideId,DateOnly from,DateOnly to,DateTimeOffset paymentAt,ReferenceKey currency,Quantity unitQuantity,
        DateTimeOffset? firstFixingAt,FloatingAveraging? averaging,SwapObservationCalendar? calendar,ImmutableArray<SchedulePriceTerm> prices,
        string implementation,ImmutableArray<FloatingObservationApplication> applications,string mappingRule,
        GeneratedPaymentDate? generatedDate=null,PaymentRule? paymentConvention=null)
    {
        dated=new(sideId,from,to,paymentAt,currency,unitQuantity,firstFixingAt,averaging,calendar,prices,implementation,applications,mappingRule,generatedDate,paymentConvention);
        block=null;offset=0;
    }
    internal ScheduleRow(ScheduleRow period,Guid sideId,int ordinal,ExactQuantity allocation)
    {dated=new(period.Dated,sideId,ordinal,allocation);block=null;offset=0;}
    private ScheduleRow(DatedScheduleRow row){dated=row;block=null;offset=0;}
    private ScheduleRow(DatedScheduleRow row,DeliveryInterval interval){dated=row;block=null;offset=0;physicalInterval=interval;}
    internal ScheduleRow WithPhysicalInterval(DeliveryInterval interval)=>new(Dated,interval);
    internal ScheduleRow WithRetainedReference(ScheduleDefinition definition,int root)=>new(Dated with{RetainedReference=new(definition,root,null)});
    internal ScheduleRow(IntervalRowBlock block,int offset)
    {
        if(block is null||(uint)offset>=(uint)block.Month.Intervals.Length)throw new MarketDataException("schedule_row","A row must select an exact native interval from its shared schedule block.");
        this.block=block;this.offset=offset;dated=null;
    }
}
