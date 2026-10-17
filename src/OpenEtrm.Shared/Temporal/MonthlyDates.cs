using System.Collections.Immutable;

namespace OpenEtrm.Shared.Temporal;

public enum MonthlyAnchor { DayOfMonth=1, MonthEnd }
public enum ShortMonth { Reject=1, Clamp, NotApplicable }
public sealed record MonthlyOccurrence(DateOnly Month, DateOnly Unadjusted, DateOnly Date);

public static class MonthlyDates
{
    // Inclusive month bounds, each on day 1. This generates anchors, not accrual stubs.
    public static ImmutableArray<MonthlyOccurrence> Generate(DateOnly firstMonth, DateOnly lastMonth,
        MonthlyAnchor anchor, int? day, ShortMonth shortMonth, DateRoll adjustment, DateSet calendar)
    {
        ArgumentNullException.ThrowIfNull(calendar);
        var count=(lastMonth.Year-firstMonth.Year)*12+lastMonth.Month-firstMonth.Month+1;
        if (firstMonth.Day!=1 || lastMonth.Day!=1 || count<1 || count>120 ||
            !Enum.IsDefined(anchor) || !Enum.IsDefined(shortMonth) || !Enum.IsDefined(adjustment) ||
            (anchor==MonthlyAnchor.MonthEnd ? day is not null || shortMonth!=ShortMonth.NotApplicable :
                day is null or <1 or >31 || shortMonth==ShortMonth.NotApplicable))
            throw new TemporalException("monthly_definition", "Select explicit month bounds, anchor, short-month policy and adjustment. Maximum 120 months.");
        var result=ImmutableArray.CreateBuilder<MonthlyOccurrence>(count);
        for(var i=0;i<count;i++)
        {
            var month=firstMonth.AddMonths(i);
            var days=DateTime.DaysInMonth(month.Year,month.Month);
            if(anchor==MonthlyAnchor.DayOfMonth && day>days && shortMonth==ShortMonth.Reject)
                throw new TemporalException("short_month", "The requested day does not exist in one of the selected months.");
            var unadjusted=new DateOnly(month.Year,month.Month,anchor==MonthlyAnchor.MonthEnd?days:Math.Min(day!.Value,days));
            result.Add(new(month,unadjusted,DateRolling.Adjust(unadjusted,calendar,adjustment)));
        }
        return result.MoveToImmutable();
    }
}
