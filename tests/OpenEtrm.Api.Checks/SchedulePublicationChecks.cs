using OpenEtrm.Api;
using OpenEtrm.Shared.Temporal;

internal static class SchedulePublicationChecks
{
    public static void Run()
    {
        void Eq<T>(T a,T b){if(!Equals(a,b))throw new Exception($"Expected {b}, got {a}");}
        void Reject(string code,Action work){try{work();}catch(TemporalException e)when(e.Code==code){return;}throw new Exception($"Expected {code}");}
        var definition=new MonthlyDraft("Monthly dates","oe.ng","2021-01","2021-04","day",1,"reject","unadjusted",new("Weekdays","2020-12-01","2021-06-01",[0,6],[]));
        var version=new ScheduleVersion(Guid.NewGuid(),1,1,"published",definition,"context_month",new(2020,12,1),new(2021,5,1),1,DateTimeOffset.UtcNow);
        var context=new ScheduleContext("2021-01-15",1);
        Eq(PublishedSchedules.Resolve([version],"oe.ng[0]",context).Date,new DateOnly(2021,1,1));
        Eq(PublishedSchedules.Resolve([version],"oe.ng[0]",context with{EffectiveOn="2021-02-15"}).Date,new DateOnly(2021,2,1));
        Eq(PublishedSchedules.Resolve([version],"oe.ng[1]",context).Date,new DateOnly(2021,2,1));
        Eq(PublishedSchedules.Resolve([version],"2021-02-20",context).Date,new DateOnly(2021,2,20));
        Reject("schedule_unpublished",()=>PublishedSchedules.Resolve([version with{State="draft"}],"oe.ng[0]",context));
        Reject("schedule_unpublished",()=>PublishedSchedules.Resolve([version],"oe.ng[0]",context with{KnownThrough=0}));
        var revised=version with{Version=2,PublicationOrder=2,Definition=definition with{Name="Renamed monthly dates",Day=2}};
        Eq(PublishedSchedules.Catalog([version,revised],context).Single().Name,"Monthly dates");
        Eq(PublishedSchedules.Catalog([version,revised],context with{KnownThrough=2}).Single().Version,2);
        Eq(PublishedSchedules.Catalog([revised],context).Length,0);
        Eq(PublishedSchedules.Catalog([version],context with{EffectiveOn="2021-05-01"}).Length,0);
        Eq(PublishedSchedules.Resolve([version,revised],"oe.ng[0]",context).Date,new DateOnly(2021,1,1));
        Eq(PublishedSchedules.Resolve([version,revised],"oe.ng[0]",context with{KnownThrough=2}).Date,new DateOnly(2021,1,2));
        Reject("date_index",()=>PublishedSchedules.Resolve([version],"oe.ng[0]",context with{EffectiveOn="2020-12-15"}));
        Reject("schedule_context",()=>PublishedSchedules.Resolve([version],"oe.ng[0]",new(null,1)));
        Eq(PublishedSchedules.Resolve([version],"oe.ng",context).Date,new DateOnly(2021,1,1));
        Reject("schedule_engine",()=>PublishedSchedules.Resolve([version with{EngineVersion="unsupported"}],"oe.ng",context));
        Console.WriteLine("16 published schedule resolution checks passed.");
    }
}
