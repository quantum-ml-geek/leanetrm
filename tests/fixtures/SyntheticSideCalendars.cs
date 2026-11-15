using System.Collections.Immutable;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;
using OpenEtrm.Shared.Temporal;

// Explicit synthetic inputs for arithmetic and lifecycle fixtures. Calendar-rule
// checks author their own masks and exceptions with independent expected dates.
internal static class SyntheticSideCalendars
{
    private static readonly ReferenceRevision Revision=new(Guid.Parse("2e6f3c90-54e8-4c00-8356-1e2a7d950001"),Guid.Parse("2e6f3c90-54e8-4c00-8356-1e2a7d950002"));
    internal static CalendarDefinition AllDates { get; }=new(new(Revision,"synthetic_all_dates"),new(2000,1,1),new(2100,1,1),0,[],CalendarDefinition.Implementation);
    internal static CalendarDefinition HundredYearTerm { get; }=new(new(Revision,"synthetic_century_term"),new(2040,12,1),new(2141,2,1),0,[],CalendarDefinition.Implementation);
    private static CalendarDefinition ExplicitDays(ReferenceKey key,DateSet days)=>new(key,days.From,days.To,127,
        [..days.Dates.Select(date=>new CalendarException(date,true))],CalendarDefinition.Implementation);
    internal static SideCalendarPolicy Dated(bool observations,PaymentRule? payment=null,SwapObservationCalendar? observation=null)=>new(
        CalendarBinding.Owned(AllDates),observations?CalendarBinding.Owned(observation is null?AllDates:ExplicitDays(observation.Key,observation.BusinessDays)):CalendarBinding.NotApplicable(),
        CalendarBinding.Owned(payment?.Calendar is {} calendar?ExplicitDays(calendar.Key,calendar.BusinessDays):AllDates),SideCalendarPolicy.Implementation);
    internal static SideCalendarPolicy FixedPeriods(ImmutableArray<FixedSidePeriod> periods)=>Dated(false,periods.IsDefaultOrEmpty?null:periods[0]?.PaymentSchedule);
    internal static SideCalendarPolicy FloatingPeriods(ImmutableArray<FloatingSidePeriod> periods)=>Dated(true,periods.IsDefaultOrEmpty?null:periods[0]?.PaymentSchedule,periods.IsDefaultOrEmpty?null:periods[0]?.Calendar);
    internal static SideCalendarPolicy Physical()=>SideCalendarPolicy.UseOne(AllDates,true,false,false);
    private static CalendarDefinition IntervalCalendar(PpaSideTerms terms)=>terms.Schedule.Hours is {} hours&&!hours.Holidays.IsEmpty
        ?new(new(Revision,"synthetic_interval_closures"),AllDates.From,AllDates.To,0,
            [..hours.Holidays.Select(day=>new CalendarException(day,false))],CalendarDefinition.Implementation):AllDates;
    internal static SideCalendarPolicy Interval(PpaSideTerms terms,bool observations)=>new(
        terms.Quantity is SlotQuantity?CalendarBinding.NotApplicable():CalendarBinding.Owned(IntervalCalendar(terms)),
        observations?CalendarBinding.Owned(AllDates):CalendarBinding.NotApplicable(),
        CalendarBinding.Owned(terms.DateRule.Calendar is {} calendar?ExplicitDays(calendar.Key,calendar.BusinessDays):AllDates),SideCalendarPolicy.Implementation);
}
