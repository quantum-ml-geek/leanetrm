namespace OpenEtrm.MarketData.Power;

// Two immutable Monday-first grids. Dates and clocks belong to the product binding.
public sealed record TimeOfUse
{
    public int Minutes { get; }
    public string NonHolidays { get; }
    public string Holidays { get; }
    public int Columns => 1440 / Minutes;

    public TimeOfUse(int minutes, string nonHolidays, string holidays)
    {
        if (minutes is not (5 or 15 or 30 or 60))
            throw new MarketDataException("tou_resolution", "Use 5, 15, 30 or 60 minute cells.");
        if (nonHolidays is null || holidays is null || nonHolidays.Length != 7*1440/minutes ||
            holidays.Length != nonHolidays.Length || nonHolidays.Concat(holidays).Any(c=>c is not ('0' or '1')))
            throw new MarketDataException("tou_grid", "Supply both complete weekday grids using 0 and 1 cells.");
        Minutes=minutes; NonHolidays=nonHolidays; Holidays=holidays;
    }

    public bool Contains(DateTime localStart, bool holiday)
    {
        var weekday=((int)localStart.DayOfWeek+6)%7;
        var column=(localStart.Hour*60+localStart.Minute)/Minutes;
        return (holiday?Holidays:NonHolidays)[weekday*Columns+column]=='1';
    }
    public TimeOfUse Complement() => new(Minutes,Flip(NonHolidays),Flip(Holidays));
    private static string Flip(string cells)=>new(cells.Select(c=>c=='1'?'0':'1').ToArray());
    public static TimeOfUse All(int minutes) => new(minutes,new string('1',7*1440/Valid(minutes)),new string('1',7*1440/Valid(minutes)));
    private static int Valid(int minutes) => minutes is 5 or 15 or 30 or 60 ? minutes : throw new MarketDataException("tou_resolution","Unsupported grid resolution.");
    public static TimeOfUse WeekdayBlock(int minutes,int startHour,int endHour,bool saturday)
    {
        Valid(minutes);
        if(startHour<0 || endHour>24 || startHour>=endHour)
            throw new MarketDataException("tou_grid","Block hours must be ordered within a day.");
        var columns=1440/minutes;
        var cells=new string(Enumerable.Range(0,7*columns).Select(i=>i/columns<(saturday?6:5) &&
            i%columns*minutes>=startHour*60 && i%columns*minutes<endHour*60?'1':'0').ToArray());
        return new(minutes,cells,new string('0',cells.Length));
    }
}
