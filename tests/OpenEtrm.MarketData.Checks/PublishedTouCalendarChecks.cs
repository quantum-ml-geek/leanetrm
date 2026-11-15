using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Trading;

internal static class PublishedTouCalendarChecks
{
    internal static int Run()
    {
        var revision=new ReferenceRevision(Guid.NewGuid(),Guid.NewGuid());
        ReferenceKey Key(string code)=>new(revision,code);
        var calendar=new CalendarDefinition(Key("holiday_calendar"),new(2027,1,1),new(2028,1,1),48,
            [new(new(2027,1,1),false),new(new(2027,1,2),true)],CalendarDefinition.Implementation);
        var policy=SideCalendarPolicy.UseOne(calendar,true,false,true);
        var product=new PublishedTouBinding(Guid.NewGuid(),Guid.NewGuid(),1,Key("clock"),calendar.Key,new(7,23,false),PublishedTouBinding.HolidayConvention);
        var hours=product.Bind(BlockMembership.Peak,Key("clock"),policy,new(2027,1,1),new(2027,2,1));
        if(hours.Product!=product||hours.Holidays.Length!=1||hours.Holidays[0]!=new DateOnly(2027,1,1))throw new Exception("Published product provenance and explicit closures must be retained.");
        Reject(()=>product.Bind(BlockMembership.Peak,Key("different_clock"),policy,new(2027,1,1),new(2027,2,1)));
        var other=SideCalendarPolicy.UseOne(new(Key("another_calendar"),calendar.From,calendar.To,calendar.WeekendMask,calendar.Exceptions,CalendarDefinition.Implementation),true,false,true);
        Reject(()=>product.Bind(BlockMembership.Peak,Key("clock"),other,new(2027,1,1),new(2027,2,1)));
        Reject(()=>product.Require(hours with{Peak=new(6,22,true)},Key("clock"),policy,new(2027,1,1),new(2027,2,1)));
        Console.WriteLine("PASS published TOU: exact product, clock, calendar, hours and closures cannot be overridden");
        return 4;
    }
    private static void Reject(Action action)
    {
        try{action();}catch(MarketDataException error)when(error.Code=="tou_product_override"){return;}
        throw new Exception("Expected published product override refusal.");
    }
}
