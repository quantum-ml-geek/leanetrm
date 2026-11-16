using System.Text.Json.Nodes;
using OpenEtrm.Api;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Risk;
using OpenEtrm.MarketData.Trading;

// What a volatility-surface fit may select for its option sensitivities, and what admission pins of it: the stated
// selection, and the calendar clock one day is counted on. A recorded close states its convention's clock; a working
// snapshot has none, so its request names one.
internal static class OptionSensitivityRequestChecks
{
    private static readonly PnlBumpSelection Bump=new(1,2,"0.000001","0.15","0.1");
    private static readonly ClockRule Utc=new("UTC","fixed_offset",0,null,null);
    private static ClockRule NewYork=>new("New York","iana",null,"America/New_York",TimeZoneDatabase.Installed().Version());
    private static OptionSensitivityRequest Request(ClockRule? clock=null)=>new(FuturesOptionSensitivities.Policy,Bump,"0.01",clock);

    internal static void Run()
    {
        var at=DateTimeOffset.Parse("2026-10-31T21:00:00Z");
        var convention=new CloseConvention("new_york_every_day",2,"New York every day","new_york_all_days",NewYork);

        foreach(var invalid in new[]{Request(Utc) with{Policy="option_sensitivities_unknown_v1"},Request(Utc) with{VolatilityBump="0.02"},
            Request(Utc) with{Bump=Bump with{PriceSteps=3}},Request(Utc) with{Bump=Bump with{Ticks=0}},Request(Utc) with{Bump=Bump with{DeltaRelativeTolerance="2"}},
            Request(Utc) with{Bump=null!},Request(),Request(new("Sydney","iana",null,"Australia/Sydney",TimeZoneDatabase.Installed().Version()))})
            Reject(()=>OptionSurfaceAnalytics.Pin(invalid,null));
        Reject(()=>OptionSurfaceAnalytics.Pin(Request(Utc),convention));
        Console.WriteLine("PASS a fit states one supported sensitivity selection, and names a clock only at a working snapshot");

        var working=OptionSurfaceAnalytics.Plan(OptionSurfaceAnalytics.Pin(Request(Utc),null),at);
        if(working.Selection!=new OptionSensitivitySelection(new(1,2),new(ExactDecimal.Parse("0.000001"),ExactDecimal.Parse("0.15")),
            new(ExactDecimal.Parse("0.000001"),ExactDecimal.Parse("0.1")),ExactDecimal.Parse("0.01")))throw new Exception("The pinned selection is not the stated one.");
        if(working.Day?.At!=at.AddHours(24)||working.Stated is not {ClockSource:"request",ClockZone:"UTC",PriceSteps:2,Ticks:1}||working.Stated.DayTo!=at.AddHours(24)||
            working.Stated.Policy!=FuturesOptionSensitivities.Policy)throw new Exception($"A working snapshot counts its day on the named clock: {working.Stated}.");
        Console.WriteLine("PASS a working snapshot counts one day on the clock its request names");

        // 17:00 in New York on the Saturday before its clocks go back: the same local time on Sunday is 25 hours later.
        var close=OptionSurfaceAnalytics.Plan(OptionSurfaceAnalytics.Pin(Request(),convention),at);
        if(close.Day?.At!=at.AddHours(25)||close.Stated is not {ClockSource:"close_convention",ClockZone:"America/New_York"})
            throw new Exception($"A recorded close counts its day on its convention's clock: {close.Stated}.");
        Console.WriteLine("PASS a recorded close counts one day on its convention's calendar clock");

        var unread=OptionSurfaceAnalytics.Plan(OptionSurfaceAnalytics.Pin(Request(),convention with{Clock=null}),at);
        if(unread.Day is not null||unread.Stated is not {ClockSource:null,ClockZone:null,DayTo:null})throw new Exception("A convention whose clock cannot be read selects no day.");
        Console.WriteLine("PASS a close whose calendar clock cannot be read selects no day");

        // A pinned clock this host cannot count a day on selects no day; the fit still runs and its theta is missing.
        var foreign=OptionSurfaceAnalytics.Pin(Request(),convention);
        foreign["clock"]!["rule"]!["tzdbVersion"]="synthetic_other_release";
        var uncounted=OptionSurfaceAnalytics.Plan(foreign,at);
        if(uncounted.Day is not null||uncounted.Stated is not {ClockSource:"close_convention",DayTo:null}||uncounted.Selection!=working.Selection)
            throw new Exception($"A clock the host cannot count on selects no day: {uncounted.Stated}.");
        Console.WriteLine("PASS a pinned clock this host cannot count a day on selects no day");

        var pinned=OptionSurfaceAnalytics.Pin(Request(Utc),null);
        if(pinned.ToJsonString()!=OptionSurfaceAnalytics.Pin(Request(Utc),null).ToJsonString()||JsonNode.Parse(pinned.ToJsonString())!["policy"]!.GetValue<string>()!=FuturesOptionSensitivities.Policy)
            throw new Exception("A pinned selection is one canonical object.");
        Console.WriteLine("PASS a pinned selection is canonical");
    }

    private static void Reject(Action action)
    {
        try{action();}catch(MarketDataException e)when(e.Code=="option_sensitivity_policy"){return;}
        throw new Exception("Expected option_sensitivity_policy.");
    }
}
