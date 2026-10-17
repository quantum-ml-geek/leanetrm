using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power;

static class PowerHoursChecks
{
    public static void Run()
    {
        var count = 0;
        void Equal<T>(T actual, T expected) { if (!Equals(actual,expected)) throw new Exception($"Expected {expected}; got {actual}"); count++; }
        void Reject(string code, Action action) { try { action(); } catch (MarketDataException e) when(e.Code==code) { count++; return; } throw new Exception($"Expected {code}"); }
        var ny = PowerClock.Capture(TimeZoneInfo.FindSystemTimeZoneById("America/New_York"));
        var fixedEst = PowerClock.Capture(TimeZoneInfo.CreateCustomTimeZone("fixed_est",TimeSpan.FromHours(-5),"Fixed EST","Fixed EST"));
        var all = TimeOfUse.All(60);
        var fall = PowerHours.Compile(new(2026,11,1),new(2026,11,2),ny,all,[],60);
        Equal(fall.Length,25);
        Equal(fall.Count(h=>h.HourEnding==2),2);
        Equal(fall.Where(h=>h.HourEnding==2).Select(h=>h.Occurrence).ToArray().SequenceEqual([1,2]),true);
        Equal(fall.Select(h=>h.Start).Distinct().Count(),25);
        Equal(PowerHours.Compile(new(2027,3,14),new(2027,3,15),ny,all,[],60).Length,23);
        Equal(PowerHours.Compile(new(2026,11,1),new(2026,11,2),fixedEst,all,[],60).Length,24);
        var peak = TimeOfUse.WeekdayBlock(60,7,23,false);
        var off = peak.Complement();
        DateOnly[] holidays=[new(2026,11,26)];
        var whole=PowerHours.Compile(new(2026,11,1),new(2026,12,1),ny,all,holidays,60);
        var p=PowerHours.Compile(new(2026,11,1),new(2026,12,1),ny,peak,holidays,60);
        var o=PowerHours.Compile(new(2026,11,1),new(2026,12,1),ny,off,holidays,60);
        Equal(p.Length,320);Equal(o.Length,401);
        Equal(p.Select(h=>h.Start).Intersect(o.Select(h=>h.Start)).Any(),false);
        Equal(p.Length+o.Length,whole.Length);
        Equal(p.Any(h=>h.OperatingDate==holidays[0]),false);
        var five=PowerHours.Compile(new(2026,11,1),new(2026,11,2),ny,TimeOfUse.All(5),[],5);
        Equal(five.Length,300);
        var revision=new ReferenceRevision(Guid.NewGuid(),Guid.NewGuid());
        var index=new PowerIndex(new(revision,"synthetic_test_v1"),new(revision,"test_currency"),new(revision,"megawatt_hour"),"Test","Intraday");
        var rows=five.Select(h=>new PowerFixing(h.Start,h.End,index,ExactDecimal.Parse("30"),new(ExactDecimal.Parse("28"),ExactDecimal.Parse("3"),ExactDecimal.Parse("-1")))).ToArray();
        var result=PowerSettlement.Calculate(five,rows,index,ExactDecimal.Parse("10"),PowerSettlementPolicy.Preview);
        Equal(result.Hours,"25");Equal(result.Energy,"250");Equal(result.AveragePrice,"30");Equal(result.Amount,"7500");
        Equal(PowerSettlement.Hourly(five,rows,index,PowerSettlementPolicy.Preview).Count,25);
        Equal(PowerSettlement.Hourly(five,rows,index,PowerSettlementPolicy.Preview).Values.All(v=>v=="30"),true);
        // Independent weighted-mean oracle, including a non-terminating 1/3.
        var hour=five.Take(12).ToArray();
        var uneven=hour.Select((h,i)=>new PowerFixing(h.Start,h.End,index,ExactDecimal.Parse(i<4?"1":"0"),null)).ToArray();
        Equal(PowerSettlement.Calculate(hour,uneven,index,ExactDecimal.Parse("1"),PowerSettlementPolicy.Preview).AveragePrice,"0.333333333333333333");
        Equal(PowerSettlement.Calculate(hour,uneven,index,ExactDecimal.Parse("1"),PowerSettlementPolicy.Preview).Amount,"0.33");
        Reject("settlement_coverage",()=>PowerSettlement.Calculate(five,rows[..^1],index,ExactDecimal.Parse("10"),PowerSettlementPolicy.Preview));
        Reject("settlement_coverage",()=>PowerSettlement.Calculate(five,rows.Append(rows[0]).ToArray(),index,ExactDecimal.Parse("10"),PowerSettlementPolicy.Preview));
        Reject("settlement_index",()=>PowerSettlement.Calculate(five,rows.Select(r=>r with {Index=index with {PriceType="Official"}}).ToArray(),index,ExactDecimal.Parse("10"),PowerSettlementPolicy.Preview));
        Reject("lmp_components",()=>PowerSettlement.Calculate(five,rows.Select(r=>r with {Total=ExactDecimal.Parse("31")}).ToArray(),index,ExactDecimal.Parse("10"),PowerSettlementPolicy.Preview));
        Reject("tou_resolution",()=>new TimeOfUse(7,new string('0',7),new string('0',7)));
        Reject("power_period",()=>PowerHours.Compile(new(2026,12,1),new(2026,11,1),ny,all,[],60));
        Equal(PowerSettlement.Calculate(fall,fall.Select(h=>new PowerFixing(h.Start,h.End,index,ExactDecimal.Parse("-2"),null)).ToArray(),index,ExactDecimal.Parse("10"),PowerSettlementPolicy.Preview).Amount,"-500");
        Reject("missing_reference",()=>PowerSettlement.Calculate(five,rows,index with {Definition=new(default,"missing")},ExactDecimal.Parse("10"),PowerSettlementPolicy.Preview));
        Reject("settlement_index",()=>PowerSettlement.Calculate(five,rows,index with {EnergyUnit=new(revision,"kilowatt_hour")},ExactDecimal.Parse("10"),PowerSettlementPolicy.Preview));
        var negative=PowerSettlement.Calculate(five,rows,index,ExactDecimal.Parse("-10"),PowerSettlementPolicy.Preview);
        Equal(negative.Amount,"-7500");Equal(negative.Energy,"-250");
        foreach(var (zone,expected) in new[]{("America/Chicago",721),("America/Los_Angeles",721)})
            Equal(PowerHours.Compile(new(2026,11,1),new(2026,12,1),PowerClock.Capture(TimeZoneInfo.FindSystemTimeZoneById(zone)),all,[],60).Length,expected);
        var west=TimeOfUse.WeekdayBlock(60,6,22,true);
        Equal(PowerHours.Compile(new(2026,11,1),new(2026,12,1),PowerClock.Capture(TimeZoneInfo.FindSystemTimeZoneById("America/Los_Angeles")),west,holidays,60).Length,384);
        Equal(PowerHours.Compile(new(2026,1,1),new(2026,4,1),ny,all,[],60).Length,2159);
        Console.WriteLine($"PASS {count} power-hour, TOU, DST and synthetic settlement checks");
    }
}
