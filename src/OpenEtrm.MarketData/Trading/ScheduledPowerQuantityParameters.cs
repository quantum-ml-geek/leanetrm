using System.Collections.Immutable;
using OpenEtrm.MarketData.Power;
using OpenEtrm.Shared.Numerics;

namespace OpenEtrm.MarketData.Trading;

[EconomicDefinition("scheduled_power_quantity_period_v1")]
public sealed record ScheduledPowerQuantityPeriod([property:IdentityField]DateOnly From,
    [property:IdentityField]DateOnly To,[property:IdentityField]ExactDecimal Rate);

// Whole-Side generation terms. The Side's delivery binding is the sole calendar
// owner; the stored clock payload prevents replay from consulting installed rules.
[EconomicDefinition("scheduled_power_quantity_parameters_v1")]
public sealed class ScheduledPowerQuantityParameters
{
    [IdentityField]public ReferenceKey Clock { get; }
    [IdentityField]public string ClockRules { get; }
    [IdentityField]public string ClockFingerprint { get; }
    [IdentityField]public QuantitySpecification Power { get; }
    [IdentityField]public QuantitySpecification Energy { get; }
    [IdentityField]public int MaskMinutes { get; }
    [IdentityField]public string WeeklyMask { get; }
    [IdentityField]public string HolidayMask { get; }
    [IdentityField]public int IntervalMinutes { get; }
    [IdentityField]public ImmutableArray<ScheduledPowerQuantityPeriod> Periods { get; }
    private readonly PowerClock clock;
    private readonly TimeOfUse mask;

    public ScheduledPowerQuantityParameters(ReferenceKey clockReference,string clockRules,string clockFingerprint,
        QuantitySpecification power,QuantitySpecification energy,TimeOfUse mask,int intervalMinutes,
        ImmutableArray<ScheduledPowerQuantityPeriod> periods)
    {
        Money.RequireKey(clockReference);
        if(periods.IsDefaultOrEmpty||periods.Any(p=>p is null)||mask is null||!QuantityDefinitions.Coherent(power)||!QuantityDefinitions.Coherent(energy)||intervalMinutes is not(5 or 15 or 30 or 60)||mask.Minutes%intervalMinutes!=0)throw Invalid();
        if(clockReference.Revision!=power.Key.Revision||clockReference.Revision!=energy.Key.Revision)
            throw new MarketDataException("clock_reference","The power clock and quantity specifications must retain the same exact reference revision.");
        SwapQuantitySchedule.ValidateAuthoring([..periods.Select(p=>new QuantityPeriod(p.From,p.To))],
            [..periods.Select(p=>p.Rate)],SwapQuantityBasis.SelectedIntervalPower,null);
        clock=PowerClock.Restore(clockRules,clockFingerprint);
        Clock=clockReference;ClockRules=clockRules;ClockFingerprint=clockFingerprint;
        Power=power;Energy=energy;MaskMinutes=mask.Minutes;WeeklyMask=mask.NonHolidays;HolidayMask=mask.Holidays;
        IntervalMinutes=intervalMinutes;Periods=periods;this.mask=mask;
    }
    public DateTimeOffset CompletionAt(DateOnly to)=>clock.StartOfDay(to).ToUniversalTime();
    public ImmutableArray<PowerQuantitySchedule> Generate(SideCalendarPolicy policy)
    {
        var calendar=policy.For(CalendarPurpose.Delivery);
        return [..Periods.Select(p=>
        {
            calendar.RequireCoverage(p.From,p.To);
            return PowerQuantitySchedule.Compile(new(p.Rate,Power.Key),PowerQuantityBasis.FlatPower,Power,Energy,
                p.From,p.To,clock,mask,[..calendar.Closures(p.From,p.To)],IntervalMinutes,null);
        })];
    }
    internal SwapQuantitySchedule Quantities(SideCalendarPolicy policy)=>SwapQuantitySchedule.Resolve(
        [..Periods.Select(p=>new QuantityPeriod(p.From,p.To))],[..Periods.Select(p=>p.Rate)],
        SwapQuantityBasis.SelectedIntervalPower,null,Energy.Key,Generate(policy));
    public void RequireAllocations(SideCalendarPolicy policy,ReferenceKey quantity,ImmutableArray<QuantityPeriod> periods,ImmutableArray<ExactRatio> allocations)
    {
        if(quantity!=Energy.Key||!periods.SequenceEqual(Periods.Select(p=>new QuantityPeriod(p.From,p.To)))||
            !allocations.SequenceEqual(Quantities(policy).Shares))throw Invalid();
    }
    private static MarketDataException Invalid()=>new("scheduled_quantity","Power Side periods and allocations must agree with their exact captured generation parameters.");
}
