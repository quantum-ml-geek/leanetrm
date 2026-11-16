using System.Collections.Immutable;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Risk;
using OpenEtrm.Shared.Numerics;

namespace OpenEtrm.MarketData.Trading;

// A native value row can be a holding or a payment. A current value has no
// invented delivery interval, payment date or discount operation.
public sealed record ValueSideTerm(int Ordinal,ComponentKind Kind,DateTimeOffset? From,DateTimeOffset? To,
    DateTimeOffset? ValueAt,SidePaymentKey? Payment,CurveRequest? Market);
internal sealed record ValueScheduleRow(Guid SideId,ReferenceKey Currency,Quantity UnitQuantity,ValueSideTerm Term,string Implementation);

internal sealed record UnitSideEvaluation(DateTimeOffset CalculationAt,bool IsLifecycleProjection,ValuationMeasure Measure,CancellationToken Cancellation);
public sealed partial class SideValuationContext
{
    private UnitSideEvaluation? unitEvaluation;
    internal UnitSideEvaluation UnitEvaluation=>unitEvaluation??throw new MarketDataException("side_context","This Side requires an explicit unit calculation clock, measure and held state.");
    internal SideValuationContext WithUnitEvaluation(DateTimeOffset at,bool lifecycle,ValuationMeasure measure,CancellationToken cancellation)
    {
        var copy=(SideValuationContext)MemberwiseClone();copy.unitEvaluation=new(at,lifecycle,measure,cancellation);return copy;
    }
}

// Cash, gas claims and marked rights have genuine scalar value schedules. Their
// concrete Sides own the calculation; this base only retains rows and delegates.
public abstract record ValueSide:Side
{
    public ReferenceKey Currency {get;}
    public Quantity UnitQuantity {get;}
    public string Implementation {get;}
    public ImmutableArray<ValueSideTerm> ValueTerms {get;}
    private readonly ValueSideSchedule schedule;
    protected ValueSide(Guid id,ReferenceKey currency,Quantity unit,string implementation,ImmutableArray<ValueSideTerm> terms)
        :base(id,new(CalendarBinding.NotApplicable(),CalendarBinding.NotApplicable(),CalendarBinding.NotApplicable(),SideCalendarPolicy.Implementation))
    {
        Money.RequireKey(currency);
        if(unit is null||unit.Amount!=ExactDecimal.Parse("1")||string.IsNullOrWhiteSpace(implementation)||terms.IsDefaultOrEmpty||
            terms.Any(t=>t is null||t.Ordinal<0||!Enum.IsDefined(t.Kind)||(t.From is null)!=(t.To is null)||
                t.From is {} from&&(!TradingInstant.IsSupported(from)||t.To<=from)||t.To is {} to&&!TradingInstant.IsSupported(to)||
                t.ValueAt is {} at&&!TradingInstant.IsSupported(at)||t.Kind==ComponentKind.Payment&&(t.Payment is null||t.ValueAt!=t.Payment.Value.PaymentAt)||
                t.Kind!=ComponentKind.Payment&&t.Payment is not null)||terms.Select(t=>t.Ordinal).Distinct().Count()!=terms.Length)
            throw new MarketDataException("side_definition","Retain complete exact native value rows, with payment identity only for actual cash.");
        Currency=currency;UnitQuantity=unit;Implementation=implementation;ValueTerms=terms;schedule=new(this);
    }
    public override ImmutableArray<CurveRequest> Dependencies=>[..ValueTerms.Select(t=>t.Market).OfType<CurveRequest>().Distinct()];
    public override ValueSideSchedule GenerateSchedule()=>schedule;
    public override ValueSideValuation PV(SideValuationContext context)
    {
        if(context is null)throw new MarketDataException("side_context","Supply the Side's exact valuation inputs.");
        var scope=context.UnitEvaluation;scope.Cancellation.ThrowIfCancellationRequested();
        if(scope.Measure!=ValuationMeasure.PresentValue)throw new MarketDataException("valuation_measure","This native value Side implements present value only.");
        var rows=Evaluate(context,schedule.Rows);
        if(rows.IsDefault||rows.Length!=ValueTerms.Length||rows.Where((row,n)=>row.SideId!=Id||row.Row.Ordinal!=ValueTerms[n].Ordinal||row.Amount.Currency!=Currency||row.PresentValue?.Currency!=Currency).Any())
            throw new MarketDataException("side_context","Every native value row must retain this exact Side, currency and evaluated contribution.");
        return new(schedule,context,rows);
    }
    protected abstract ImmutableArray<ScheduleRowValue> Evaluate(SideValuationContext context,IReadOnlyList<ScheduleRow> rows);
    protected ScheduleRowValue Value(ScheduleRow row,ExactMoney amount,ExactMoney pv,DateTimeOffset at,
        ExactUnitPrice? price=null,SidePaymentFactor? discount=null,CashPaymentBalance? cash=null)=>
        new(Id,null,row.Value!.Term.Kind,null,ExactQuantity.FromQuantity(UnitQuantity),VolumeState.Contractual,null,[],[],
            price is null?[]:[new(ExactQuantity.FromQuantity(UnitQuantity),price,row.Value.Term.Market is null?RowPriceState.Fixed:RowPriceState.Projected,
                row.Value.Term.Market?.Curve,null,ExactDecimal.Parse("1"),null)],amount,ExactDecimal.Parse("1"),Implementation,at,discount,pv,
            null,null,row.Value.Term.Kind==ComponentKind.Payment?ValueCoverage.UnpaidCashPresentValue:ValueCoverage.HoldingValue,null){Row=row,CashBalance=cash};
}

public sealed record ValueSideSchedule:SideSchedule
{
    public ValueSide Side {get;}
    public override IReadOnlyList<ScheduleRow> Rows {get;}
    public override ImmutableArray<CurveRequest> Dependencies=>Side.Dependencies;
    internal ValueSideSchedule(ValueSide side):base(side.Id,side.Currency,side.UnitQuantity,side.Implementation)
    {Side=side;Rows=[..side.ValueTerms.Select(term=>new ScheduleRow(new ValueScheduleRow(side.Id,side.Currency,side.UnitQuantity,term,side.Implementation)))];}
    public override SideValuation Evaluate(SideValuationContext context)=>Side.PV(context);
}
public sealed record ValueSideValuation:SideValuation
{
    public ImmutableArray<ScheduleRowValue> Rows {get;}
    internal ValueSideValuation(ValueSideSchedule schedule,SideValuationContext context,ImmutableArray<ScheduleRowValue> rows)
        :base(schedule,context,rows.Select(row=>row.RequirePresentValue()).Aggregate((a,b)=>a.Add(b))){Rows=rows;}
    public override SideScheduleSnapshot InspectSchedule(string manifest,ExactDecimal scale,SignedRatio coefficient,Func<DateOnly,DateTimeOffset> boundary)=>
        SideScheduleSnapshot.FromRows(this,Rows,manifest,scale,coefficient,boundary);
}
