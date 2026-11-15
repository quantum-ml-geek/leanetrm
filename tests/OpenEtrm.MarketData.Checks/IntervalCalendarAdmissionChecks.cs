using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Trading;

internal static class IntervalCalendarAdmissionChecks
{
    internal static void Run()
    {
        var f=new PpaAcceptanceFixture();
        var holiday=f.Month.AddDays(2);
        var calendar=new CalendarDefinition(f.R("synthetic_holiday"),f.Month,f.Month.AddMonths(2),96,
            [new(holiday,false)],CalendarDefinition.Implementation);
        var policy=SideCalendarPolicy.UseOne(calendar,true,false,true);
        PowerPhysicalSide Physical(DeliveryHours hours)=>new(Guid.NewGuid(),f.Terms(f.Profile with{Hours=hours}),f.Asset.Location,policy);
        Reject("side_calendar_conflict",()=>Physical(new(BlockMembership.Peak,new(7,23,false),[])));
        Reject("side_calendar_conflict",()=>Physical(new(BlockMembership.Peak,new(7,23,false),[holiday,holiday.AddDays(1)])));
        var all=Physical(new(BlockMembership.All,null,[holiday]));
        var cells=all.Terms.Schedule.Generate(all.Id,all.Terms.Currency,all.Terms.DateRule).Single().Intervals;
        if(cells.Length!=721||cells.Count(c=>c.OperatingDate==holiday)!=24)
            throw new Exception("November's all-hours grid must retain its fallback hour and include the calendar holiday.");
        var product=new PublishedTouBinding(Guid.NewGuid(),Guid.NewGuid(),1,f.Delivery.Clock,calendar.Key,new(7,23,false),PublishedTouBinding.HolidayConvention);
        var hours=product.Bind(BlockMembership.Peak,f.Delivery.Clock,policy,f.Delivery.From,f.Delivery.To);
        var other=new PublishedTouBinding(product.CatalogId,Guid.NewGuid(),1,f.Delivery.Clock,f.R("other_calendar"),product.Peak,product.HolidayTreatment);
        var original=f.Terms(f.Profile with{Hours=hours});
        var forged=original with{Quantity=f.Profile with{Hours=hours with{Product=other}}};
        Reject("ppa_cadence",()=>new PowerPhysicalSide(Guid.NewGuid(),forged,f.Asset.Location,policy));
        _=new PowerPhysicalSide(Guid.NewGuid(),original,f.Asset.Location,policy);
        Console.WriteLine("PASS interval calendar admission: exact custom closures, all-hours holidays and profile product provenance");
    }
    private static void Reject(string code,Action action)
    {
        try{action();}catch(MarketDataException error)when(error.Code==code){return;}
        throw new Exception("Expected "+code);
    }
}
