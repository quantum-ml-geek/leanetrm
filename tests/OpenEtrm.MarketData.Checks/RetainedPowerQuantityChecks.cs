using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Trading;
using OpenEtrm.Shared.Numerics;

internal static class RetainedPowerQuantityChecks
{
    internal static int Run()
    {
        var revision=new ReferenceRevision(Guid.NewGuid(),Guid.NewGuid());
        ReferenceKey Key(string code)=>new(revision,code);
        var power=new QuantitySpecification(Key("mw"),Key("electricity"),Key("rate"),Key("megawatt"),Key("power"));
        var energy=new QuantitySpecification(Key("mwh"),Key("electricity"),Key("delivered"),Key("megawatt_hour"),Key("energy"));
        var calendar=new CalendarDefinition(Key("synthetic_calendar"),new(2026,1,1),new(2028,1,1),48,[],CalendarDefinition.Implementation);
        var policy=SideCalendarPolicy.UseOne(calendar,true,false,true);
        var clock=PowerClock.Capture(TimeZoneInfo.FindSystemTimeZoneById("America/New_York")).CaptureForDelivery(new(2026,1,1),new(2028,1,1));
        var parameters=new ScheduledPowerQuantityParameters(Key("contract_clock"),clock.Rules,clock.Fingerprint,power,energy,
            TimeOfUse.All(60),60,[new(new(2027,3,1),new(2027,4,1),ExactDecimal.Parse("2")),new(new(2027,4,1),new(2027,5,1),ExactDecimal.Parse("2"))]);
        var generated=parameters.Generate(policy);
        if(generated[0].Total.ToQuantity().Amount!=ExactDecimal.Parse("1486")||generated[1].Total.ToQuantity().Amount!=ExactDecimal.Parse("1440"))
            throw new Exception("Captured DST rules must yield independently specified March and April energy.");
        parameters.RequireAllocations(policy,energy.Key,[new(new(2027,3,1),new(2027,4,1)),new(new(2027,4,1),new(2027,5,1))],
            [new(743,1463),new(720,1463)]);
        Reject("scheduled_quantity",()=>parameters.RequireAllocations(policy,energy.Key,[new(new(2027,3,1),new(2027,4,1)),new(new(2027,4,1),new(2027,5,1))],[new(1,2),new(1,2)]));
        Reject("clock_rule",()=>new ScheduledPowerQuantityParameters(Key("contract_clock"),clock.Rules,new string('0',64),power,energy,TimeOfUse.All(60),60,parameters.Periods));
        var identity=DefinitionIdentity.For(parameters).Canonical;
        if(!identity.Contains("ClockRules")||!identity.Contains("ClockFingerprint")||!identity.Contains("1486")&& !identity.Contains("Rate"))
            throw new Exception("Quantity identity must retain generation inputs, not just allocations.");
        var januaryCalendar=new CalendarDefinition(Key("january"),new(2026,1,1),new(2028,1,1),48,[new(new(2027,1,1),false),new(new(2027,1,2),true)],CalendarDefinition.Implementation);
        var januaryPolicy=SideCalendarPolicy.UseOne(januaryCalendar,true,false,true);
        ScheduledPowerQuantityParameters January(TimeOfUse mask)=>new(Key("contract_clock"),clock.Rules,clock.Fingerprint,power,energy,mask,60,[new(new(2027,1,1),new(2027,2,1),ExactDecimal.Parse("1"))]);
        var five=January(TimeOfUse.WeekdayBlock(60,7,23,false)).Generate(januaryPolicy)[0];
        var six=January(TimeOfUse.WeekdayBlock(60,7,23,true)).Generate(januaryPolicy)[0];
        var off=January(TimeOfUse.WeekdayBlock(60,7,23,true).Complement()).Generate(januaryPolicy)[0];
        if(five.Hours!="320"||six.Hours!="400"||six.Total.Add(off.Total).ToQuantity().Amount!=ExactDecimal.Parse("744"))
            throw new Exception("Peak weekly masks ignore generic weekends; reopening preserves excluded weekdays, off-peak completes the all-hours grid.");
        var sydney=PowerClock.Capture(TimeZoneInfo.FindSystemTimeZoneById("Australia/Sydney")).CaptureForDelivery(new(2027,1,1),new(2027,2,1));
        var restored=PowerClock.Restore(sydney.Rules,sydney.Fingerprint);
        var boundary=DateTimeOffset.Parse("2026-12-31T13:00:00Z");
        var local=restored.LocalAt(boundary);
        if(local.DateTime!=new DateTime(2027,1,1)||local.Offset!=TimeSpan.FromHours(11))throw new Exception("Sydney year-boundary clock conversion must retain the original local date and hour.");
        var intervalParameters=new IntervalScheduleParameters(new(Key("sydney"),60,new(2027,1,1),new(2027,2,1)),sydney,IntervalScheduleCadence.NativeIntervals,new(BlockMembership.All,null,[]));
        if(!DefinitionIdentity.For(intervalParameters).Canonical.Contains("ClockRules"))throw new Exception("Interval Side identity must retain the captured clock cells.");
        var firstHour=PowerHours.Compile(new(2027,1,1),new(2027,1,2),restored,TimeOfUse.DailyBlock(60,0,1),[],60);
        if(firstHour.Length!=1||firstHour[0].Start!=boundary||firstHour[0].OperatingDate!=new DateOnly(2027,1,1)||firstHour[0].HourBeginning!=0)
            throw new Exception("Captured clock replay must preserve midnight TOU membership across UTC and operating years.");
        var independentRules=sydney.Rules.Replace("Australia/Sydney","Synthetic/UnavailableZone",StringComparison.Ordinal);
        var independentDigest=Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(independentRules)));
        var unavailable=PowerClock.Restore(independentRules,independentDigest);
        if(unavailable.LocalAt(boundary)!=local||unavailable.LocalAt(boundary).Offset!=local.Offset)throw new Exception("Replay must not need an installed timezone name.");
        var malformed=System.Text.Json.Nodes.JsonNode.Parse(sydney.Rules)!;
        var malformedRuns=new System.Text.Json.Nodes.JsonArray();malformedRuns.Add((System.Text.Json.Nodes.JsonNode?)null);
        malformed["Runs"]=malformedRuns;
        var malformedRules=malformed.ToJsonString();
        var malformedDigest=Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(malformedRules)));
        Reject("clock_rule",()=>PowerClock.Restore(malformedRules,malformedDigest));
        Reject("clock_rule",()=>restored.LocalAt(boundary.AddTicks(-1)));
        if(restored.StartOfDay(new(2027,2,1)).ToUniversalTime()!=DateTimeOffset.Parse("2027-01-31T13:00:00Z"))throw new Exception("The exact exclusive endpoint must remain available.");
        var halfHour=PowerClock.Capture(TimeZoneInfo.FindSystemTimeZoneById("Australia/Lord_Howe")).CaptureForDelivery(new(2027,4,4),new(2027,4,5));
        var halfRestored=PowerClock.Restore(halfHour.Rules,halfHour.Fingerprint);
        var halfCells=PowerHours.Compile(new(2027,4,4),new(2027,4,5),halfRestored,TimeOfUse.All(15),[],15);
        if(halfCells.Length!=98||halfCells.Count(i=>i.Occurrence==2)!=2)throw new Exception("A half-hour fallback requires 98 quarter-hours and two repeated cells.");
        Reject("power_clock",()=>PowerHours.Compile(new(2027,4,4),new(2027,4,5),halfRestored,TimeOfUse.All(60),[],60));
        var shortStart=TimeZoneInfo.TransitionTime.CreateFixedDateRule(new DateTime(1,1,1,2,1,0),3,1);
        var shortEnd=TimeZoneInfo.TransitionTime.CreateFixedDateRule(new DateTime(1,1,1,2,3,0),3,1);
        var shortRule=TimeZoneInfo.AdjustmentRule.CreateAdjustmentRule(new(2027,1,1),new(2027,12,31),TimeSpan.FromMinutes(1),shortStart,shortEnd);
        var shortClock=PowerClock.Capture(TimeZoneInfo.CreateCustomTimeZone("Synthetic/ShortTransitions",TimeSpan.Zero,"Synthetic","Synthetic","Synthetic daylight",[shortRule]));
        Reject("clock_rule",()=>shortClock.CaptureForDelivery(new(2027,3,1),new(2027,3,2)));
        var fall=PowerHours.Compile(new(2026,11,1),new(2026,11,2),clock,TimeOfUse.All(60),[],60);
        var spring=PowerHours.Compile(new(2027,3,14),new(2027,3,15),clock,TimeOfUse.All(60),[],60);
        if(fall.Length!=25||fall.Count(i=>i.Occurrence==2)!=1||spring.Length!=23)throw new Exception("Captured replay must preserve 23/25-hour geometry and repeated labels.");
        Console.WriteLine("PASS retained power quantities: exact inputs, DST energy, allocation refusal and five/six-day partition");
        return 4;
    }
    private static void Reject(string code,Action action)
    {
        try{action();}catch(MarketDataException error)when(error.Code==code){return;}
        throw new Exception("Expected "+code);
    }
}
