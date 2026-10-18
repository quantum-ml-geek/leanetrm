using OpenEtrm.Api;
using OpenEtrm.Shared.Temporal;

internal static class DateWorkspaceChecks
{
    public static void Run()
    {
        var passed=0;
        void Check(string name,Action work){work();passed++;Console.WriteLine($"PASS {name}");}
        void Reject(string code,Action work){try{work();}catch(TemporalException e)when(e.Code==code){return;}throw new Exception($"Expected {code}");}
        var calendar=new CalendarDraft("Synthetic weekdays","2020-12-01","2021-06-01",[0,6],["2021-01-01"]);
        var request=new MonthlyDraft("Delivery months","oe.ng","2021-01","2021-04","day",1,"reject","unadjusted",calendar);
        var workspace=new DateWorkspace();
        var saved=DateWorkspace.Compile(request);
        Check("calendar rules are explicit, bounded and closures cannot escape coverage",()=>{
            Reject("calendar_definition",()=>DateWorkspace.Calendar(calendar with{WeekendDays=null}));
            Reject("date_coverage",()=>DateWorkspace.Calendar(calendar with{ClosedDates=["2022-01-01"]}));
            Reject("calendar_definition",()=>DateWorkspace.Calendar(calendar with{From="2020-12-1"}));
        });
        Check("saved schedules preserve individual occurrences and share equal date payloads",()=>{
            var a=workspace.Keep("viewer",saved);
            var b=workspace.Keep("viewer",DateWorkspace.Compile(request with{Name="Other label",Symbol="oe.other"}));
            if(!ReferenceEquals(a.Dates,b.Dates))throw new Exception("Equal dates not shared");
            Reject("date_reference_missing",()=>workspace.Find("editor","oe.ng"));
            Reject("date_definition_conflict",()=>workspace.Keep("viewer",DateWorkspace.Compile(request with{Adjustment="following"})));
        });
        Check("contract fields consume the same expressions and pinned calendar",()=>{
            DateReceipt Resolve(string s)=>workspace.Resolve("viewer",s,null,null);
            var contract=DateWorkspace.Contract(new("January","oe.ng[0]","oe.ng[1]","oe.ng[0] - 3bd","15:30"),Resolve);
            if(contract.DeliveryFrom!=new DateOnly(2021,1,1)||contract.DeliveryTo!=new DateOnly(2021,2,1)||contract.Expiry!=new DateTimeOffset(2020,12,29,15,30,0,TimeSpan.Zero))throw new Exception("Wrong contract dates");
            if(System.Text.Json.JsonSerializer.Serialize(contract.LastTrading.Calendar)!=System.Text.Json.JsonSerializer.Serialize(calendar) || contract.DeliveryStart.Expression!="oe.ng[0]")throw new Exception("Receipt lost");
            Reject("date_index",()=>Resolve("oe.ng[4]"));Reject("date_index",()=>Resolve("oe.ng"));
            Reject("contract_dates",()=>DateWorkspace.Contract(new("Bad","oe.ng[1]","oe.ng[0]","oe.ng[0]","15:30"),Resolve));
            Reject("contract_dates",()=>DateWorkspace.Contract(new("Bad","oe.ng[0]","oe.ng[1]","oe.ng[0]",null),Resolve));
        });
        Check("reference calendars decode ISO weekend bits, closures and explicit openings",()=>{
            var reference=new CalendarReference(Guid.Empty,Guid.Empty,"synthetic_business");
            ReferenceCalendar Make(int mask,params (DateOnly,bool)[] days)=>new(reference,new(2021,1,1),new(2021,2,1),mask,[..days]);
            // 96 = bits 5 and 6 = Saturday and Sunday when bit 0 is Monday.
            var weekdays=DateWorkspace.Calendar(Make(96,(new(2021,1,1),false),(new(2021,1,9),true)));
            if(weekdays.Contains(new(2021,1,1))||weekdays.Contains(new(2021,1,2))||weekdays.Contains(new(2021,1,3)))throw new Exception("Closure or weekend open");
            if(!weekdays.Contains(new(2021,1,4))||!weekdays.Contains(new(2021,1,8))||!weekdays.Contains(new(2021,1,9)))throw new Exception("Weekday or explicit opening closed");
            var fridays=DateWorkspace.Calendar(Make(16));
            if(fridays.Contains(new(2021,1,1))||!fridays.Contains(new(2021,1,2)))throw new Exception("Bit 4 is Friday");
            if(DateWorkspace.Calendar(Make(0)).Count!=31)throw new Exception("Empty mask closes days");
            Reject("calendar_definition",()=>DateWorkspace.Calendar(Make(128)));
            Reject("calendar_definition",()=>DateWorkspace.Calendar(Make(-1)));
            Reject("date_coverage",()=>DateWorkspace.Calendar(Make(96,(new(2021,2,1),false))));
        });
        Check("a referenced calendar replaces, and never mixes with, an inline calendar",()=>{
            var reference=new ReferenceCalendar(new(Guid.Empty,Guid.Empty,"synthetic_business"),new(2020,12,1),new(2021,6,1),96,[(new DateOnly(2021,1,1),false)]);
            var bound=DateWorkspace.Compile(request with{Calendar=null},reference);
            if(!bound.Dates.Select(d=>d.Date).SequenceEqual(saved.Dates.Select(d=>d.Date)))throw new Exception("Reference calendar changed equal dates");
            Reject("calendar_binding",()=>DateWorkspace.Compile(request,reference));
            Reject("calendar_definition",()=>DateWorkspace.Compile(request with{Calendar=null}));
        });
        Console.WriteLine($"{passed} date workspace checks passed.");
    }
}
