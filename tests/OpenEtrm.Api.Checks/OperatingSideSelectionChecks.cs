using System.Collections.Immutable;
using OpenEtrm.Api;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Trading;
using OpenEtrm.Shared.Temporal;

internal static class OperatingSideSelectionChecks
{
    internal static void Run()
    {
        var f=StructuredPowerChecks.Fixture();var one=ExactDecimal.Parse("1");
        var at=DateTimeOffset.Parse("2040-01-31T00:00:00Z");var day=new DateOnly(2040,2,1);
        var interval=new DeliveryInterval(at.AddDays(1),at.AddDays(1).AddHours(1),day,0,0,1);
        var quote=f.Data.QuoteRows("energy_price").Single();var unit=new Quantity(one,new(f.Data.ReferenceRevision,"right"));
        var payment=new PaymentRule(PaymentFrequency.Monthly,PaymentDateRule.DaysAfterPeriodEnd,18,null,PaymentDayBasis.CalendarDays,null,DateRoll.Unadjusted,null,PaymentRule.Implementation);
        var calendar=new SideCalendarPolicy(CalendarBinding.NotApplicable(),CalendarBinding.NotApplicable(),CalendarBinding.NotApplicable(),SideCalendarPolicy.Implementation);
        OperatingSideTerms Terms(CurveRequest? projection)=>new(unit,quote,payment,ComponentKind.Payment,
            [new(interval,day,day.AddMonths(1),new(null,new(ExactDecimal.Parse("5"),quote.Quantity)),projection)],OperatingSideTerms.SupportedImplementation,calendar);
        var fixedSide=new FixedSide(Guid.NewGuid(),Terms(null),new FlatPrice(new(ExactDecimal.Parse("100"),quote)));
        // This unrelated side deliberately has no admitted market source.
        var missing=new CurveRequest(new(f.Data.DefinitionRevision,"unavailable_source"),new(f.Data.DefinitionRevision,Guid.NewGuid()));
        var floatingSide=new FloatingSide(Guid.NewGuid(),Terms(missing));
        RetainedSideProgram Retain(Side side,int slot)
        {
            var program=BookedSideProgram.Compile(ScheduleDefinitionCompiler.Generate(side));
            return new(slot,side.Id,Guid.NewGuid(),program.Identity,program);
        }
        ImmutableArray<RetainedSideProgram> retained=[Retain(fixedSide,0),Retain(floatingSide,1)];
        var selected=StructuredPowerBookingStore.SelectPrograms(retained,0);
        var dependencies=selected.SelectMany(p=>p.Program.Document.Instructions).SelectMany(i=>i.Bindings)
            .Where(b=>b.Kind=="contract_price").Select(b=>b.Market!.Value).Distinct().ToImmutableArray();
        var frame=new InputFrame(Guid.NewGuid(),"Synthetic selected-side inspection",at,DateOnly.FromDateTime(at.UtcDateTime),[],ImmutableDictionary<string,ImmutableArray<Guid>>.Empty);
        var snapshot=f.Data.Snapshot(frame).WithKnowledge(Guid.NewGuid(),at);var market=f.Data.Model.Build(snapshot,dependencies);
        var value=ScheduleMarketSources.ForOperating(market).Evaluate(selected.Single().Program,fixedSide.Id,market,
            new ExplicitDiscounting(one,DiscountFactorSource.Undiscounted));
        if(value.PresentValue.ToExactString()!="500")throw new Exception("The selected fixed operating Side must value independently of unrelated missing market inputs.");
        try{StructuredPowerBookingStore.SelectPrograms(retained,99);throw new Exception("An absent operating Side slot must not return an empty successful valuation.");}
        catch(MarketDataException error)when(error.Code=="side_schedule_inspection"){}
        if(StructuredPowerBookingStore.SelectPrograms(retained,null).Length!=2)throw new Exception("Whole-instrument valuation must retain every selected membership.");
        Console.WriteLine("PASS operating Side selection: fixed gross value needs no unrelated market source; absent slots refuse");
    }
}
