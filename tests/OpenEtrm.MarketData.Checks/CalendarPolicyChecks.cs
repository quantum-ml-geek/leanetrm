using System.Collections.Immutable;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;
using OpenEtrm.Shared.Temporal;

internal static class CalendarPolicyChecks
{
    public static int Run()
    {
        var passed=0;
        void Check(string name,Action test){test();passed++;Console.WriteLine("PASS calendar policy: "+name);}
        void Require(bool value){if(!value)throw new Exception("Calendar policy assertion failed.");}
        void Reject(string code,Action test){try{test();}catch(MarketDataException e)when(e.Code==code){return;}throw new Exception("Expected "+code);}
        var reference=new ReferenceRevision(Guid.Parse("72336d7e-5cf1-41ec-a993-8c6250d5ec8e"),Guid.Parse("1bc3aeca-aee6-4879-9793-0826fed8e0d0"));
        DateOnly D(string text)=>DateOnly.ParseExact(text,"yyyy-MM-dd");
        CalendarDefinition Calendar(string code,int weekends,ImmutableArray<CalendarException> exceptions)=>
            new(new(reference,code),D("2023-12-01"),D("2025-01-10"),weekends,exceptions,CalendarDefinition.Implementation);
        var standard=Calendar("synthetic_standard",96,[new(D("2024-01-01"),false),new(D("2024-01-02"),false),new(D("2024-01-06"),true)]);
        Check("nonstandard weekends and exceptional opening are explicit",()=>{
            var fridaySaturday=Calendar("synthetic_weekend",48,[new(D("2024-01-05"),true)]);
            Require(fridaySaturday.BusinessDays.Contains(D("2024-01-05")));
            Require(!fridaySaturday.BusinessDays.Contains(D("2024-01-06")));
            Require(fridaySaturday.BusinessDays.Contains(D("2024-01-07")));
            Require(standard.BusinessDays.Contains(D("2024-01-06")));
        });
        Check("rolls honor year boundaries and consecutive holidays",()=>{
            Require(standard.Adjust(D("2023-12-31"),DateRoll.Following)==D("2024-01-03"));
            Require(standard.Adjust(D("2023-12-31"),DateRoll.ModifiedFollowing)==D("2023-12-29"));
            Require(standard.Adjust(D("2024-01-01"),DateRoll.Preceding)==D("2023-12-29"));
            Require(standard.Adjust(D("2024-01-01"),DateRoll.ModifiedPreceding)==D("2024-01-03"));
            Require(standard.Adjust(D("2024-01-01"),DateRoll.Unadjusted)==D("2024-01-01"));
            Require(standard.Advance(D("2023-12-29"),2)==D("2024-01-04"));
            Require(standard.Advance(D("2024-01-03"),-1)==D("2023-12-29"));
            Require(standard.Advance(D("2024-02-28"),1)==D("2024-02-29"));
        });
        Check("unadjusted rules and offsets still require covered anchors",()=>{
            Reject("calendar_coverage",()=>standard.Adjust(D("2025-01-10"),DateRoll.Unadjusted));
            Reject("calendar_coverage",()=>standard.Advance(D("2025-01-09"),1));
            Reject("calendar_coverage",()=>standard.Advance(D("2023-12-01"),-1));
        });
        Check("calendar definition cannot hide duplicate exceptions or invalid masks",()=>{
            Reject("calendar_definition",()=>Calendar("synthetic_bad",128,[]));
            Reject("calendar_definition",()=>Calendar("synthetic_bad",96,[new(D("2024-01-01"),true),new(D("2024-01-01"),false)]));
            Reject("calendar_definition",()=>Calendar("synthetic_bad",96,default));
        });
        Check("same-key altered payloads are different pinned definitions",()=>{
            var tampered=Calendar("synthetic_standard",96,[]);
            Require(standard.Digest!=tampered.Digest);
            Reject("calendar_definition_mismatch",()=>standard.RequireSameDefinition(tampered));
            var reordered=Calendar("synthetic_standard",96,[new(D("2024-01-06"),true),new(D("2024-01-02"),false),new(D("2024-01-01"),false)]);
            standard.RequireSameDefinition(reordered);
            Require(standard.Digest==reordered.Digest);
        });
        Check("one Side permits different purposes but no missing applicable binding",()=>{
            var payment=Calendar("synthetic_payment",48,[]);
            var policy=new SideCalendarPolicy(CalendarBinding.Owned(standard),CalendarBinding.NotApplicable(),CalendarBinding.Owned(payment),SideCalendarPolicy.Implementation);
            policy.RequirePurposes(true,false,true);
            Require(policy.For(CalendarPurpose.Payment)==payment);
            Reject("side_calendar_applicability",()=>policy.RequirePurposes(true,true,true));
            Reject("side_calendar_policy",()=>new SideCalendarPolicy(null!,CalendarBinding.NotApplicable(),CalendarBinding.Owned(payment),SideCalendarPolicy.Implementation));
        });
        Check("shared selection expands to concrete independent purpose bindings",()=>{
            var policy=SideCalendarPolicy.UseOne(standard,true,true,true);
            Require(policy.Delivery.Calendar==standard&&policy.Observation.Calendar==standard&&policy.Payment.Calendar==standard);
            Require(DefinitionIdentity.For(policy).Canonical.Contains(standard.Key.Code,StringComparison.Ordinal));
        });
        Check("every period must use the same exact binding and captured definition",()=>{
            var policy=SideCalendarPolicy.UseOne(standard,false,true,true);
            policy.RequireCalendar(CalendarPurpose.Observation,standard);
            Reject("side_calendar_conflict",()=>policy.RequireCalendar(CalendarPurpose.Observation,Calendar("synthetic_other",96,[])));
            Reject("calendar_definition_mismatch",()=>policy.RequireCalendar(CalendarPurpose.Payment,Calendar("synthetic_standard",96,[])));
        });
        Check("one exact reference cannot carry conflicting definitions across purposes",()=>{
            Reject("calendar_definition_mismatch",()=>new SideCalendarPolicy(CalendarBinding.Owned(standard),CalendarBinding.NotApplicable(),
                CalendarBinding.Owned(Calendar("synthetic_standard",48,[])),SideCalendarPolicy.Implementation));
        });
        Check("authored observations use an exact calendar independently of the quote revision",()=>{
            var quote=new IndexFixingChecks.FixingFixture(monthly:true).Quote;
            var selected=new SwapObservationCalendar(standard.Key,standard.BusinessDays);
            var plan=FloatingObservationPlan.Generate(D("2024-01-01"),D("2024-01-08"),FloatingAveraging.ObservationArithmetic,quote,selected,[]);
            Require(plan.Observations.Select(o=>o.From).SequenceEqual(new[]{D("2024-01-03"),D("2024-01-04"),D("2024-01-05"),D("2024-01-06")}));
        });
        Check("interval payments use their captured calendar independently of the delivery clock revision",()=>{
            var fixture=new PpaAcceptanceFixture();
            var calendar=new CalendarDefinition(new(reference,"synthetic_payment"),D("2031-10-01"),D("2032-01-01"),0,
                [new(D("2031-12-10"),false)],CalendarDefinition.Implementation);
            var payment=new PaymentRule(PaymentFrequency.Monthly,PaymentDateRule.DayOfFollowingMonth,null,10,null,ShortMonth.Reject,
                DateRoll.Following,new(calendar.Key,calendar.BusinessDays),PaymentRule.Implementation);
            var terms=fixture.Terms(fixture.Profile) with{DateRule=payment};
            var selected=new SideCalendarPolicy(SyntheticSideCalendars.Interval(terms,false).Delivery,CalendarBinding.NotApplicable(),CalendarBinding.Owned(calendar),SideCalendarPolicy.Implementation);
            var side=new FixedSide(Guid.NewGuid(),terms,new FlatPrice(new UnitPrice(ExactDecimal.Parse("3"),fixture.EnergyPrice)),selected);
            var schedule=terms.Schedule.Generate(side.Id,terms.Currency,payment);
            Require(schedule.All(m=>PaymentDatePolicy.Date(m.Payment.PaymentAt)==D("2031-12-11")));
        });
        Check("fixed Side construction requires covered delivery and payment bindings even for unadjusted cash",()=>{
            var fixture=new IndexFixingChecks.FixingFixture(monthly:true);
            var side=fixture.Floating();
            var broad=new CalendarDefinition(new(reference,"synthetic_all_dates"),new(2040,1,1),new(2043,1,1),0,[],CalendarDefinition.Implementation);
            var policy=SideCalendarPolicy.UseOne(broad,true,false,true);
            if(!DefinitionIdentity.For(policy).Canonical.Contains("\"PaymentTiming\":\"utc_payment_day_v1\"",StringComparison.Ordinal))
                throw new Exception("Payment-day behavior must be an explicit retained identity term.");
            FixedSide Make(SideCalendarPolicy selected)=>new(Guid.NewGuid(),new FlatPrice(new UnitPrice(ExactDecimal.Parse("3"),side.Quote)),
                side.Quote,side.UnitQuantity,[new(side.DeliveryFrom,side.DeliveryTo,side.PaymentAt,OpenEtrm.Shared.Numerics.ExactRatio.One,null)],selected);
            Reject("side_calendar_policy",()=>Make(null!));
            Reject("side_calendar_applicability",()=>Make(SideCalendarPolicy.UseOne(broad,true,true,true)));
            Reject("calendar_coverage",()=>Make(SideCalendarPolicy.UseOne(standard,true,false,true)));
            var fixedSide=Make(policy);
            Require(DefinitionIdentity.For(fixedSide).Canonical.Contains(broad.Digest,StringComparison.Ordinal));
            var different=SideCalendarPolicy.UseOne(new CalendarDefinition(new(reference,"synthetic_other_dates"),broad.From,broad.To,48,[],CalendarDefinition.Implementation),true,false,true);
            Require(DefinitionIdentity.For(fixedSide)!=DefinitionIdentity.For(Make(different)));
        });
        return passed;
    }
}
