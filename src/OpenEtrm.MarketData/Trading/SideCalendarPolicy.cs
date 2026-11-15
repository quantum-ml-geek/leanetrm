namespace OpenEtrm.MarketData.Trading;

public enum CalendarPurpose { Delivery=1,Observation,Payment }

[EconomicDefinition("side_calendar_binding_v1")]
public sealed record CalendarBinding
{
    [IdentityField] public bool Applicable { get; }
    [IdentityField] public CalendarDefinition? Calendar { get; }
    [IdentityField] public string? DefinitionDigest=>Calendar?.Digest;
    [IdentityField] public CalendarPublicationProof? Publication=>Calendar?.Publication;
    private CalendarBinding(bool applicable,CalendarDefinition? calendar){Applicable=applicable;Calendar=calendar;}
    public static CalendarBinding Owned(CalendarDefinition calendar)=>new(true,calendar??
        throw new MarketDataException("side_calendar_policy","An applicable schedule requires its exact calendar."));
    public static CalendarBinding NotApplicable()=>new(false,null);
}

[EconomicDefinition(Implementation)]
public sealed record SideCalendarPolicy
{
    public const string Implementation="side_calendar_policy_v1";
    [IdentityField] public CalendarBinding Delivery { get; }
    [IdentityField] public CalendarBinding Observation { get; }
    [IdentityField] public CalendarBinding Payment { get; }
    [IdentityField] public string? PaymentTiming=>Payment.Applicable?PaymentDatePolicy.Implementation:null;
    public SideCalendarPolicy(CalendarBinding delivery,CalendarBinding observation,CalendarBinding payment,string implementation)
    {
        if(delivery is null||observation is null||payment is null||implementation!=Implementation)
            throw new MarketDataException("side_calendar_policy","Explicitly bind every applicable schedule purpose and mark the others not applicable.");
        foreach(var group in new[]{delivery,observation,payment}.Select(binding=>binding.Calendar).OfType<CalendarDefinition>().GroupBy(calendar=>calendar.Key))
            foreach(var calendar in group.Skip(1))group.First().RequireSameDefinition(calendar);
        Delivery=delivery;Observation=observation;Payment=payment;
    }
    // An explicit authoring action expands to concrete references; no alias is retained.
    public static SideCalendarPolicy UseOne(CalendarDefinition calendar,bool delivery,bool observation,bool payment)=>
        new(delivery?CalendarBinding.Owned(calendar):CalendarBinding.NotApplicable(),
            observation?CalendarBinding.Owned(calendar):CalendarBinding.NotApplicable(),
            payment?CalendarBinding.Owned(calendar):CalendarBinding.NotApplicable(),Implementation);
    public void RequirePurposes(bool delivery,bool observation,bool payment)
    {
        if(Delivery.Applicable!=delivery||Observation.Applicable!=observation||Payment.Applicable!=payment)
            throw new MarketDataException("side_calendar_applicability","The calendar purposes do not match this Side's owned schedules.");
    }
    public CalendarDefinition For(CalendarPurpose purpose)=>(purpose switch
    {
        CalendarPurpose.Delivery=>Delivery,CalendarPurpose.Observation=>Observation,CalendarPurpose.Payment=>Payment,
        _=>throw new MarketDataException("side_calendar_policy","Select an explicit supported calendar purpose.")
    }).Calendar??throw new MarketDataException("side_calendar_applicability","The selected schedule purpose is not applicable to this Side.");
    public void RequireCalendar(CalendarPurpose purpose,CalendarDefinition calendar)
    {
        var binding=For(purpose);
        if(calendar is null||binding.Key!=calendar.Key)
            throw new MarketDataException("side_calendar_conflict","Every period of this schedule purpose must use the Side's exact calendar binding.");
        binding.RequireSameDefinition(calendar);
    }
    internal void RequireCalendar(CalendarPurpose purpose,ReferenceKey key,OpenEtrm.Shared.Temporal.DateSet days)
    {
        var binding=For(purpose);
        if(binding.Key!=key)throw new MarketDataException("side_calendar_conflict","Every period of this purpose must use the Side's exact calendar binding.");
        if(days is null||binding.From!=days.From||binding.To!=days.To||!binding.BusinessDays.Dates.SequenceEqual(days.Dates))
            throw new MarketDataException("calendar_definition_mismatch","Schedule rules must consume the exact captured calendar definition.");
    }
    internal void RequirePayment(DateOnly from,DateOnly to,DateTimeOffset at,PaymentRule? rule)
    {
        var calendar=For(CalendarPurpose.Payment);
        var date=PaymentDatePolicy.Date(at);
        calendar.RequireCoverage(date,date.AddDays(1));
        if(rule is null)return;
        if(rule.Calendar is {} selected)RequireCalendar(CalendarPurpose.Payment,selected.Key,selected.BusinessDays);
        var anchor=rule.Generate(from,to).Unadjusted;
        calendar.RequireCoverage(anchor,anchor.AddDays(1));
    }
    internal void RequireObservation(DateOnly from,DateOnly to,SwapObservationCalendar? selected)
    {
        For(CalendarPurpose.Observation).RequireCoverage(from,to);
        if(selected is not null)RequireCalendar(CalendarPurpose.Observation,selected.Key,selected.BusinessDays);
    }
    internal void RequireInterval(PpaSideTerms terms,bool observations)
    {
        var ownedDelivery=terms.Quantity is not SlotQuantity;
        RequirePurposes(ownedDelivery,observations,true);
        if(terms.Quantity is ProfileQuantity profile&&(terms.Schedule.Cadence!=IntervalScheduleCadence.NativeIntervals||
            terms.Schedule.Hours is not {} profileHours||profileHours.Membership!=profile.Hours.Membership||
            profileHours.Peak!=profile.Hours.Peak||profileHours.Product!=profile.Hours.Product||
            !profileHours.Holidays.SequenceEqual(profile.Hours.Holidays)))
            throw new MarketDataException("ppa_cadence","The generated schedule must retain its quantity rule's exact delivery cadence, mask and product provenance.");
        if(ownedDelivery)For(CalendarPurpose.Delivery).RequireCoverage(terms.Delivery.From,terms.Delivery.To);
        if(ownedDelivery&&terms.Schedule.Hours is {Product:{} product} hours)
            product.Require(hours,terms.Delivery.Clock,this,terms.Delivery.From,terms.Delivery.To);
        if(ownedDelivery&&terms.Schedule.Hours is {} selected&&
            !selected.Holidays.SequenceEqual(For(CalendarPurpose.Delivery).Closures(terms.Delivery.From,terms.Delivery.To)))
            throw new MarketDataException("side_calendar_conflict","Delivery hours must retain the exact closures of their Side calendar.");
        if(observations)RequireObservation(terms.Delivery.From,terms.Delivery.To,null);
        for(var month=terms.Delivery.From;month<terms.Delivery.To;month=month.AddMonths(1))
            RequirePayment(month,month.AddMonths(1),FixedSide.PaymentBoundary(terms.DateRule,month,month.AddMonths(1)),terms.DateRule);
    }
}
