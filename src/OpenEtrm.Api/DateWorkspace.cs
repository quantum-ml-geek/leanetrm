using System.Collections.Immutable;
using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using OpenEtrm.Shared.Temporal;

namespace OpenEtrm.Api;

public sealed record CalendarDraft(string? Name,string? From,string? To,ImmutableList<int>? WeekendDays,ImmutableList<string>? ClosedDates);
public sealed record MonthlyDraft(string? Name,string? Symbol,string? FirstMonth,string? LastMonth,string? Anchor,
    int? Day,string? ShortMonth,string? Adjustment,CalendarDraft? Calendar);
public sealed record MonthlySaved(MonthlyDraft Definition,ImmutableList<MonthlyOccurrence> Dates,[property: System.Text.Json.Serialization.JsonIgnore] DateSet BusinessDays);
public sealed record DateExpressionRequest(string? Expression,string? At,CalendarDraft? RollingCalendar);
public sealed record DateReceipt(string Expression,DateOnly Date,string Symbol,int? Index,int? BusinessDays,
    CalendarDraft? Calendar,object Source);
public sealed record ContractDatesDraft(string? Label,string? DeliveryStart,string? DeliveryEnd,string? LastTrading,string? CutoffUtc);
public sealed record ContractDates(string Label,DateOnly DeliveryFrom,DateOnly DeliveryTo,DateTimeOffset Expiry,
    DateReceipt DeliveryStart,DateReceipt DeliveryEnd,DateReceipt LastTrading,string CutoffUtc);
public sealed record CurveDatesRequest(string? Code,string? Name,string? TemplateCurve,string? At,
    CalendarDraft? RollingCalendar,ContractDatesDraft[]? Contracts);
public sealed record CurveDatesSaved(string Code,string Name,string TemplateCurve,object Template,object DefinitionPin,
    object ReferencePin,string At,CalendarDraft? RollingCalendar,ImmutableArray<ContractDates> Contracts);

// All accesses hold the session gate and current ReadMarketData authority fence.
// These are private immutable drafts, not durable or published reference revisions.
public sealed class DateWorkspace
{
    private readonly Dictionary<(string Owner,string Symbol),MonthlySaved> schedules=[];
    private readonly Dictionary<(string Owner,string Code),CurveDatesSaved> curves=[];
    public IEnumerable<MonthlySaved> For(string owner)=>schedules.Where(p=>p.Key.Owner==owner).Select(p=>p.Value);
    public IEnumerable<CurveDatesSaved> Curves(string owner)=>curves.Where(p=>p.Key.Owner==owner).Select(p=>p.Value);
    public MonthlySaved Find(string owner,string symbol)=>schedules.TryGetValue((owner,symbol),out var found)?found:
        throw Error("date_reference_missing","Choose a date schedule kept in this persona's preview session.");
    public static DateOnly Date(string? value)
    {
        if(!DateOnly.TryParseExact(value,"yyyy-MM-dd",CultureInfo.InvariantCulture,DateTimeStyles.None,out var date))
            throw Error("calendar_definition","Supply an exact date in year-month-day form.");
        return date;
    }
    public static DateSet Calendar(CalendarDraft? draft)
    {
        if(draft is null || string.IsNullOrWhiteSpace(draft.Name) || draft.Name.Length>80 || draft.WeekendDays is null || draft.ClosedDates is null ||
            draft.WeekendDays.Count>7 || draft.WeekendDays.Any(d=>d<0||d>6) || draft.WeekendDays.Distinct().Count()!=draft.WeekendDays.Count || draft.ClosedDates.Count>3660)
            throw Error("calendar_definition","Name the calendar and explicitly supply weekend days, closures and known coverage.");
        var from=Date(draft.From);var to=Date(draft.To);var count=to.DayNumber-from.DayNumber;
        if(count<1||count>3660)throw Error("calendar_definition","Calendar coverage must be nonempty and at most 3660 days.");
        var closed=DateSet.Create(from,to,draft.ClosedDates.Select(Date));
        return DateSet.Create(from,to,Enumerable.Range(0,count).Select(from.AddDays)
            .Where(d=>!draft.WeekendDays.Contains((int)d.DayOfWeek)&&!closed.Contains(d)));
    }
    public static MonthlySaved Compile(MonthlyDraft request)
    {
        if(string.IsNullOrWhiteSpace(request.Name)||request.Name.Length>80 || request.Symbol is null ||
            !Regex.IsMatch(request.Symbol,@"\Aoe\.[a-z][a-z0-9_]{0,31}\z",RegexOptions.CultureInvariant))
            throw Error("monthly_definition","Name the schedule and give it a lowercase oe.shortcut.");
        DateOnly Month(string? text)=>text?.Length==7?Date(text+"-01"):throw Error("monthly_definition","Choose explicit first and last months.");
        var anchor=request.Anchor switch{"day"=>MonthlyAnchor.DayOfMonth,"month_end"=>MonthlyAnchor.MonthEnd,_=>throw Error("monthly_definition","Choose a monthly anchor.")};
        var shortMonth=request.ShortMonth switch{"reject"=>ShortMonth.Reject,"clamp"=>ShortMonth.Clamp,"not_applicable"=>ShortMonth.NotApplicable,_=>throw Error("monthly_definition","Choose a short-month policy.")};
        var adjustment=request.Adjustment switch{"unadjusted"=>DateRoll.Unadjusted,"following"=>DateRoll.Following,"preceding"=>DateRoll.Preceding,
            "modified_following"=>DateRoll.ModifiedFollowing,"modified_preceding"=>DateRoll.ModifiedPreceding,_=>throw Error("roll_convention","Choose a business-day adjustment.")};
        var calendar=Calendar(request.Calendar);
        return new(request,MonthlyDates.Generate(Month(request.FirstMonth),Month(request.LastMonth),anchor,request.Day,shortMonth,adjustment,calendar).ToImmutableList(),calendar);
    }
    public MonthlySaved Keep(string owner,MonthlySaved value)
    {
        var key=(owner,value.Definition.Symbol!);
        if(schedules.TryGetValue(key,out var old))
        {
            if(JsonSerializer.Serialize(old.Definition)!=JsonSerializer.Serialize(value.Definition))throw Error("date_definition_conflict","This shortcut has different terms. Choose a new name.");
            return old;
        }
        if(For(owner).Count()>=32)throw Error("preview_limit","This persona already has 32 date schedules.");
        var shared=For(owner).FirstOrDefault(s=>s.Dates.SequenceEqual(value.Dates));
        var kept=shared is null?value:value with{Dates=shared.Dates};schedules.Add(key,kept);return kept;
    }
    public DateReceipt Resolve(string owner,string? expression,DateTimeOffset? at,Func<string,DateReceipt>? resolveContract,CalendarDraft? rollingCalendar=null)
    {
        var reference=DateReference.Parse(expression);
        DateOnly date;object source;CalendarDraft? calendar;
        if(schedules.TryGetValue((owner,reference.Symbol),out var schedule))
        {
            if(reference.Index is not int index || index>=schedule.Dates.Count)throw Error("date_index","Select a zero-based occurrence within the schedule.");
            date=schedule.Dates[index].Date;source=schedule.Definition;calendar=schedule.Definition.Calendar;
            if(reference.BusinessDays is int count)date=DateRolling.Advance(date,schedule.BusinessDays,count);
        }
        else
        {
            if(reference.Index is not null)throw Error("date_reference_missing","No such date schedule is kept in this persona's session.");
            if(at is null || resolveContract is null)throw Error("date_reference_missing","Choose a kept date reference and an explicit context.");
            var resolved=resolveContract(reference.Symbol);date=resolved.Date;source=resolved.Source;calendar=rollingCalendar;
            if(reference.BusinessDays is int count)date=DateRolling.Advance(date,Calendar(calendar),count);
            else if(calendar is not null)_=Calendar(calendar);
        }
        return new(expression!,date,reference.Symbol,reference.Index,reference.BusinessDays,calendar,source);
    }
    public static ContractDates Contract(ContractDatesDraft draft,Func<string,DateReceipt> resolve)
    {
        if(string.IsNullOrWhiteSpace(draft.Label)||draft.Label.Length>80 ||
            !TimeOnly.TryParseExact(draft.CutoffUtc,"HH:mm",CultureInfo.InvariantCulture,DateTimeStyles.None,out var cutoff))
            throw Error("contract_dates","Name the contract and select an explicit UTC last-trading time (hours and minutes).");
        var start=resolve(draft.DeliveryStart!);var end=resolve(draft.DeliveryEnd!);var last=resolve(draft.LastTrading!);
        if(start.Date>=end.Date || last.Date>=end.Date)throw Error("contract_dates","Delivery end must follow start and last trading.");
        return new(draft.Label,start.Date,end.Date,new DateTimeOffset(last.Date.ToDateTime(cutoff,DateTimeKind.Utc)),start,end,last,draft.CutoffUtc!);
    }
    public CurveDatesSaved KeepCurve(string owner,CurveDatesSaved value)
    {
        var key=(owner,value.Code);
        if(curves.TryGetValue(key,out var old))
        {
            if(JsonSerializer.Serialize(old)!=JsonSerializer.Serialize(value))throw Error("date_definition_conflict","This draft curve already has different terms. Choose a new code.");
            return old;
        }
        if(Curves(owner).Count()>=16)throw Error("preview_limit","This persona already has 16 draft curves.");
        curves.Add(key,value);return value;
    }
    private static TemporalException Error(string code,string message)=>new(code,message);
}
