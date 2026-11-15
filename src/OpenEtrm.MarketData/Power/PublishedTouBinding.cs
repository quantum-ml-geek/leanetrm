using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.MarketData.Power;

[EconomicDefinition("published_tou_binding_v1")]
public sealed record PublishedTouBinding
{
    public const string HolidayConvention="weekly_mask_explicit_closures_v1";
    [IdentityField]public Guid CatalogId { get; }
    [IdentityField]public Guid ProductId { get; }
    [IdentityField]public int Version { get; }
    [IdentityField]public ReferenceKey Clock { get; }
    [IdentityField]public ReferenceKey Calendar { get; }
    [IdentityField]public TouPeak Peak { get; }
    [IdentityField]public string HolidayTreatment { get; }
    public PublishedTouBinding(Guid catalogId,Guid productId,int version,ReferenceKey clock,ReferenceKey calendar,TouPeak peak,string holidayTreatment)
    {
        if(catalogId==Guid.Empty||productId==Guid.Empty||version<=0||peak is null||holidayTreatment!=HolidayConvention)throw Invalid();
        Money.RequireKey(clock);Money.RequireKey(calendar);
        _=TimeOfUse.WeekdayBlock(60,peak.StartHour,peak.EndHour,peak.Saturday);
        CatalogId=catalogId;ProductId=productId;Version=version;Clock=clock;Calendar=calendar;Peak=peak;HolidayTreatment=holidayTreatment;
    }
    public void RequireGrid(ReferenceKey clock,ReferenceKey calendar)
    {
        if(clock!=Clock||calendar!=Calendar)throw Invalid();
    }
    public DeliveryHours Bind(BlockMembership membership,ReferenceKey clock,SideCalendarPolicy policy,DateOnly from,DateOnly to)
    {
        if(!Enum.IsDefined(membership))throw Invalid();
        RequireGrid(clock,policy.For(CalendarPurpose.Delivery).Key);
        return new(membership,membership==BlockMembership.All?null:Peak,policy.For(CalendarPurpose.Delivery).Closures(from,to)){Product=this};
    }
    public void Require(DeliveryHours hours,ReferenceKey clock,SideCalendarPolicy policy,DateOnly from,DateOnly to)
    {
        var bound=Bind(hours.Membership,clock,policy,from,to);
        if(hours.Product!=this||hours.Peak!=bound.Peak||!hours.Holidays.SequenceEqual(bound.Holidays))throw Invalid();
    }
    private static MarketDataException Invalid()=>new("tou_product_override","A published TOU fixes its exact clock, calendar, weekly hours and holiday convention; select another version or an explicit custom schedule to change them.");
}
