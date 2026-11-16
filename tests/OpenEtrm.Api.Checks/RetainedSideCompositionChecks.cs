using System.Collections.Immutable;
using OpenEtrm.Api;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;
using OpenEtrm.Shared.Temporal;

internal static class RetainedSideCompositionChecks
{
    internal static void Run()
    {
        var f=StructuredPowerChecks.Fixture();var one=ExactDecimal.Parse("1");var day=new DateOnly(2040,2,1);
        var at=new DateTimeOffset(day.ToDateTime(TimeOnly.MinValue,DateTimeKind.Utc));
        var interval=new DeliveryInterval(at,at.AddHours(1),day,0,0,1);var quote=f.Data.QuoteRows("energy_price").Single();
        var unit=new Quantity(one,new(f.Data.ReferenceRevision,"right"));
        var payment=new PaymentRule(PaymentFrequency.Monthly,PaymentDateRule.DaysAfterPeriodEnd,18,null,PaymentDayBasis.CalendarDays,null,DateRoll.Unadjusted,null,PaymentRule.Implementation);
        var calendars=new SideCalendarPolicy(CalendarBinding.NotApplicable(),CalendarBinding.NotApplicable(),CalendarBinding.NotApplicable(),SideCalendarPolicy.Implementation);
        OperatingSideTerms Terms(CurveRequest? curve)=>new(unit,quote,payment,ComponentKind.Payment,
            [new(interval,day,day.AddMonths(1),new(null,new(ExactDecimal.Parse("5"),quote.Quantity)),curve)],OperatingSideTerms.SupportedImplementation,calendars);
        var missing=new CurveRequest(new(f.Data.DefinitionRevision,"synthetic_missing_source"),new(f.Data.DefinitionRevision,Guid.NewGuid()));
        Side[] sides=[new FixedSide(Guid.NewGuid(),Terms(null),new FlatPrice(new(ExactDecimal.Parse("100"),quote))),new FloatingSide(Guid.NewGuid(),Terms(missing))];
        var programs=sides.Select((side,slot)=>{
            var program=BookedSideProgram.Compile(ScheduleDefinitionCompiler.Generate(side));
            return new RetainedSideProgram(slot,side.Id,Guid.NewGuid(),program.Identity,program);
        }).ToImmutableArray();
        ImmutableArray<InstrumentSideLabels> labels=[new(0,"Receipt","Contractual receipt","Company receives",[new("Terms",[new("Price","100")])]),
            new(1,"Consideration","Contractual consideration","Company pays",[new("Terms",[new("Price source","Exact retained market contract")])])];
        ImmutableArray<RetainedInstrumentSidePresentation.Membership> memberships=[new(0,ExactDecimal.Parse("1")),new(1,ExactDecimal.Parse("-1"),new(7,9))];
        var binding=Guid.NewGuid();var group=RetainedInstrumentSidePresentation.Compose(binding,unit.Specification,quote.Currency,programs,memberships,labels,"Retained contract composition");
        if(group.InstrumentId!=binding||group.BindingId!=binding||group.Sides.Length!=2||
            !group.Sides.Select(side=>side.SideId).SequenceEqual(programs.Select(program=>program.SideId))||
            group.Sides[1].RoleLabel!="Contractual consideration")
            throw new Exception("An unpriced retained view must expose every exact native program Side and binding without evaluating its missing market source.");
        var native=group.Sides[1].OverviewSections.Single(section=>section.Label=="Native membership");
        if(native.Values.Single(value=>value.Label=="Coefficient").Value!="-1"||native.Values.Single(value=>value.Label=="Quantity ratio").Value!="7 / 9")
            throw new Exception("A retained membership must preserve its exact signed coefficient and rational quantity ratio without manufacturing positive unit membership.");
        var reused=programs.SetItem(1,programs[0] with{Slot=1});
        var repeated=RetainedInstrumentSidePresentation.Compose(binding,unit.Specification,quote.Currency,reused,memberships,labels,"Reused cash definition");
        if(repeated.Sides.Length!=2||repeated.Sides[0].SideId!=repeated.Sides[1].SideId||repeated.Sides[0].Slot==repeated.Sides[1].Slot)
            throw new Exception("One reusable Side identity can occur more than once with independent ordered membership roles and signs.");
        foreach(var malformed in new[]{programs.RemoveAt(0),programs.SetItem(1,programs[1] with{Slot=0}),
            programs.SetItem(1,programs[1] with{Identity=programs[0].Identity})})
        {
            try{RetainedInstrumentSidePresentation.Compose(binding,unit.Specification,quote.Currency,malformed,memberships,labels,"Retained");}
            catch(MarketDataException error)when(error.Code=="instrument_side_presentation"){continue;}
            throw new Exception("Missing, reordered or falsely attested retained program memberships cannot acquire a complete composition summary.");
        }
    }
}
