using OpenEtrm.Shared.Temporal;

namespace OpenEtrm.MarketData.Trading;

public enum PaymentFrequency { Monthly=1 }
public enum PaymentDateRule { DaysAfterPeriodEnd=1, DayOfFollowingMonth }
public enum PaymentDayBasis { CalendarDays=1, BusinessDays }
public sealed record PaymentCalendar(ReferenceKey Key,DateSet BusinessDays);
public sealed record GeneratedPaymentDate(DateOnly PeriodFrom,DateOnly PeriodTo,DateOnly Unadjusted,DateOnly Date);

public sealed record PaymentRule
{
    public const int MaximumCalendarDays=36600;
    public const string Implementation="monthly_payment_date_rules_v1";
    public PaymentFrequency Frequency { get; }
    public PaymentDateRule Rule { get; }
    public int? Days { get; }
    public int? DayOfMonth { get; }
    public PaymentDayBasis? DayBasis { get; }
    public ShortMonth? ShortMonthPolicy { get; }
    public DateRoll Adjustment { get; }
    public PaymentCalendar? Calendar { get; }

    public PaymentRule(PaymentFrequency frequency,PaymentDateRule rule,int? days,int? dayOfMonth,
        PaymentDayBasis? dayBasis,ShortMonth? shortMonthPolicy,DateRoll adjustment,PaymentCalendar? calendar,string implementation)
    {
        var lag=rule==PaymentDateRule.DaysAfterPeriodEnd;
        if(frequency!=PaymentFrequency.Monthly||!Enum.IsDefined(rule)||!Enum.IsDefined(adjustment)||implementation!=Implementation||
            (lag?(days is null or <0 or >366||dayOfMonth is not null||dayBasis is null||!Enum.IsDefined(dayBasis.Value)||shortMonthPolicy is not null):
                (days is not null||dayBasis is not null||dayOfMonth is null or <1 or >31||shortMonthPolicy is not(ShortMonth.Reject or ShortMonth.Clamp)))||
            (dayBasis==PaymentDayBasis.BusinessDays||adjustment!=DateRoll.Unadjusted)!=(calendar is not null))
            throw new MarketDataException("payment_rule","Choose explicit monthly frequency, one payment rule, its applicable parameters and a covered calendar only when consumed.");
        if(calendar is not null){Money.RequireKey(calendar.Key);if(calendar.BusinessDays is null||calendar.BusinessDays.To.DayNumber-calendar.BusinessDays.From.DayNumber>MaximumCalendarDays)throw new MarketDataException("payment_calendar","A covered exact payment calendar is required.");}
        Frequency=frequency;Rule=rule;Days=days;DayOfMonth=dayOfMonth;DayBasis=dayBasis;
        ShortMonthPolicy=shortMonthPolicy;Adjustment=adjustment;Calendar=calendar;
    }

    public GeneratedPaymentDate Generate(DateOnly from,DateOnly to)
    {
        if(from.Year is <1901 or >2198||from.Day!=1||from.AddMonths(1)!=to)
            throw new MarketDataException("payment_period","The monthly payment rule requires one complete supported calendar month.");
        try
        {
            var last=to.AddDays(-1);
            DateOnly unadjusted;
            if(Rule==PaymentDateRule.DaysAfterPeriodEnd)
                unadjusted=DayBasis==PaymentDayBasis.CalendarDays?last.AddDays(Days!.Value):
                    Days==0?last:DateRolling.Advance(last,Calendar!.BusinessDays,Days!.Value);
            else
            {
                var month=new DateOnly(last.Year,last.Month,1).AddMonths(1);
                var length=DateTime.DaysInMonth(month.Year,month.Month);
                if(DayOfMonth>length&&ShortMonthPolicy==ShortMonth.Reject)
                    throw new MarketDataException("short_month","The selected payment day does not exist in the following month. Choose its short-month rule explicitly.");
                unadjusted=new(month.Year,month.Month,Math.Min(DayOfMonth!.Value,length));
            }
            var adjusted=Calendar is null?unadjusted:DateRolling.Adjust(unadjusted,Calendar.BusinessDays,Adjustment);
            if(adjusted.Year is <1901 or >2199)throw new MarketDataException("payment_period","The generated payment exceeds supported date coverage.");
            return new(from,to,unadjusted,adjusted);
        }
        catch(TemporalException e){throw new MarketDataException("payment_calendar",e.Message);}
    }
}
