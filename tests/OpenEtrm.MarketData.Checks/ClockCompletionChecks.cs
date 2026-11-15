using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Gas;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Trading;
using OpenEtrm.Shared.Numerics;

internal static class ClockCompletionChecks
{
    internal static int Run()
    {
        var f=new CommodityLookupFixture(31);
        ReferenceKey Key(string code)=>new(f.Quote.Key.Revision,code);
        var power=new QuantitySpecification(Key("mw"),Key("electricity"),Key("rate"),Key("megawatt"),Key("power"));
        var energy=new QuantitySpecification(f.Quote.Quantity,Key("electricity"),Key("delivered"),Key("megawatt_hour"),Key("energy"));
        var from=new DateOnly(2027,1,1);var to=new DateOnly(2027,2,1);
        var policy=SyntheticSideCalendars.Dated(false);
        var original=f.Swap().Floating;
        var captured=PowerClock.Capture(TimeZoneInfo.Utc).CaptureForDelivery(original.DeliveryFrom,original.DeliveryTo);
        foreach(var floating in new[]{false,true})
            Reject("clock_reference",()=>{
                var foreign=new ReferenceKey(new(Guid.NewGuid(),Guid.NewGuid()),"clock");
                var parameters=new ScheduledPowerQuantityParameters(foreign,captured.Rules,captured.Fingerprint,power,energy,
                    TimeOfUse.All(60),60,[new(original.DeliveryFrom,original.DeliveryTo,ExactDecimal.Parse("1"))]);
                var completion=PaymentDatePolicy.Start(original.DeliveryTo);
                if(floating)
                    _=new FloatingSide(Guid.NewGuid(),original.Settlement,original.Quote,original.UnitQuantity,
                        [original.Periods[0] with{DeliveryCompletionAt=completion}],SyntheticSideCalendars.Dated(true),parameters);
                else
                    _=new FixedSide(Guid.NewGuid(),new FlatPrice(new UnitPrice(ExactDecimal.Parse("3"),f.Quote)),f.Quote,original.UnitQuantity,
                        [new(original.DeliveryFrom,original.DeliveryTo,original.PaymentAt,ExactRatio.One,null){DeliveryCompletionAt=completion}],policy,parameters);
            });
        foreach(var (offset,completionText,paymentText) in new[]{(-5,"2027-02-01T05:00:00Z","2027-02-01T00:00:00Z"),(11,"2027-01-31T13:00:00Z","2027-01-31T00:00:00Z")})
        {
            var clock=PowerClock.Capture(TimeZoneInfo.CreateCustomTimeZone("Synthetic/Power"+offset,TimeSpan.FromHours(offset),"Synthetic","Synthetic")).CaptureForDelivery(from,to);
            // Peak stops at 23:00, but completion is the full contractual midnight boundary.
            var parameters=new ScheduledPowerQuantityParameters(Key("clock"),clock.Rules,clock.Fingerprint,power,energy,
                TimeOfUse.DailyBlock(60,7,23),60,[new(from,to,ExactDecimal.Parse("1"))]);
            var completion=DateTimeOffset.Parse(completionText);var payment=DateTimeOffset.Parse(paymentText);
            var period=new FixedSidePeriod(from,to,payment,ExactRatio.One,null){DeliveryCompletionAt=completion};
            FixedSide Cash(FixedSidePeriod p)=>new(Guid.NewGuid(),new FlatPrice(new UnitPrice(ExactDecimal.Parse("3"),f.Quote)),f.Quote,
                new(ExactDecimal.Parse("1"),f.Quote.Quantity),[p],policy,parameters);
            var cash=Cash(period);
            if(cash.PaymentAt!=payment||cash.Periods[0].DeliveryCompletionAt!=completion)throw new Exception("Clock-based payments must preserve their independent UTC date and actual completion instant.");
            Reject("delivery_completion",()=>Cash(period with{DeliveryCompletionAt=null}));
            Reject("delivery_completion",()=>Cash(period with{DeliveryCompletionAt=completion.AddHours(-1)}));
            Reject("delivery_completion",()=>Cash(period with{DeliveryCompletionAt=completion.AddHours(1)}));
            Reject("payment_before_completion",()=>Cash(period with{PaymentAt=payment.AddDays(-1)}));
            if(offset==11)
            {
                var calendar=new CalendarDefinition(Key("business_days"),new(2027,1,1),new(2028,1,1),96,[],CalendarDefinition.Implementation);
                var preceding=new PaymentRule(PaymentFrequency.Monthly,PaymentDateRule.DaysAfterPeriodEnd,0,null,PaymentDayBasis.CalendarDays,null,
                    OpenEtrm.Shared.Temporal.DateRoll.Preceding,new(calendar.Key,calendar.BusinessDays),PaymentRule.Implementation);
                var intervals=new IntervalScheduleParameters(new(Key("clock"),60,from,to),clock,IntervalScheduleCadence.NativeIntervals,
                    new(BlockMembership.Peak,new(7,23,false),[]));
                Reject("payment_before_completion",()=>intervals.Generate(Guid.NewGuid(),f.Quote.Currency,preceding));
            }

        }
        foreach(var (offset,minute,completionText,paymentText) in new[]{(-6,540,"2027-02-01T15:00:00Z","2027-02-01T00:00:00Z"),(-14,1439,"2027-02-02T13:59:00Z","2027-02-02T00:00:00Z")})
        {
            var clock=GasDayClock.Capture(Key("gas_clock"),TimeZoneInfo.CreateCustomTimeZone("Synthetic/Gas"+offset,TimeSpan.FromHours(offset),"Synthetic","Synthetic"),minute);
            var completion=DateTimeOffset.Parse(completionText);var payment=DateTimeOffset.Parse(paymentText);
            var period=new FixedSidePeriod(from,to,payment,ExactRatio.One,null){DeliveryCompletionAt=completion};
            FixedSide Cash(FixedSidePeriod p)=>new(Guid.NewGuid(),new FlatPrice(new UnitPrice(ExactDecimal.Parse("3"),f.Quote)),f.Quote,
                new(ExactDecimal.Parse("1"),f.Quote.Quantity),[p],policy,gasDeliveryClock:clock);
            var cash=Cash(period);
            if(cash.PaymentAt!=payment||!DefinitionIdentity.For(cash).Canonical.Contains("GasDeliveryClock"))throw new Exception("Gas cash must retain its own executable completion contract.");
            Reject("delivery_completion",()=>Cash(period with{DeliveryCompletionAt=null}));
            Reject("delivery_completion",()=>Cash(period with{DeliveryCompletionAt=completion.AddMinutes(-1)}));
            Reject("payment_before_completion",()=>Cash(period with{PaymentAt=payment.AddDays(-1)}));
        }
        Console.WriteLine("PASS clock completion: gas-day and west/east UTC dates, full-term peak boundary, missing and forged completion refusal");
        return 1;
    }
    private static void Reject(string code,Action action)
    {
        try{action();}catch(MarketDataException error)when(error.Code==code){return;}
        throw new Exception("Expected "+code);
    }
}
