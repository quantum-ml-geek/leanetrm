using System.Text.Json;
using System.Collections.Immutable;
using OpenEtrm.Api;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;
using OpenEtrm.MarketData.Gas;

internal static class InstrumentSidePresentationChecks
{
    internal static void Run()
    {
        var reference=new ReferenceRevision(Guid.Parse("ef000000-0000-4000-8000-000000000001"),Guid.Parse("ef000000-0000-4000-8000-000000000002"));
        var currency=new ReferenceKey(reference,"usd");
        var at=DateTimeOffset.Parse("2032-03-14T08:00:00.123456Z");
        var instrument=new TimedCashPayment(currency,at);var binding=Guid.Parse("ef000000-0000-4000-8000-000000000003");
        InstrumentSideLabels labels=new(0,"Independent fee payment","Ordinary cash payment","Company pays",[
            new("Cash terms",[new("Currency",currency.Code),new("Due",at.ToString("O"),"instant"),new("Evidence","2032-03-14T08:00:00Z")])]);
        var group=InstrumentSidePresentation.Describe(instrument,binding,"Independent fee cash",[labels]);
        if(group.InstrumentId!=instrument.Id||group.BindingId!=binding||group.Sides.Length!=1||group.Sides[0].Slot!=0||
            group.Sides[0].SideId!=instrument.CashPaymentSide.Id||group.Sides[0].RoleLabel!="Ordinary cash payment"||group.Sides[0].DirectionLabel!="Company pays")
            throw new Exception("Side presentation must project actual memberships and exact native binding without deriving company direction or paid state.");
        var draft=InstrumentSidePresentation.Describe(instrument,null,"Unbooked cash instrument",[labels]);
        var json=JsonSerializer.SerializeToElement(draft,new JsonSerializerOptions(JsonSerializerDefaults.Web));
        if(json.GetProperty("bindingId").ValueKind!=JsonValueKind.Null||json.GetProperty("sides")[0].GetProperty("overviewSections")[0].GetProperty("values")[1].GetProperty("kind").GetString()!="instant"||
            json.GetProperty("sides")[0].GetProperty("overviewSections")[0].GetProperty("values")[2].TryGetProperty("kind",out _))
            throw new Exception("Unbooked composition must explicitly omit ownership while only marked timestamps acquire formatting semantics.");
        Reject(()=>InstrumentSidePresentation.Describe(instrument,binding,"Cash",[]));
        Reject(()=>InstrumentSidePresentation.Describe(instrument,binding,"Cash",[labels with{Slot=1}]));
        Reject(()=>InstrumentSidePresentation.Describe(instrument,binding,"Cash",[labels,labels]));
        Reject(()=>InstrumentSidePresentation.Describe(instrument,binding,"Cash",[labels with{RoleLabel=""}]));
        Reject(()=>InstrumentSidePresentation.Describe(instrument,Guid.Empty,"Cash",[labels]));
        var failures=new List<Exception>();
        foreach(var check in new Action[]{FieldGroups,UnpricedDefinition,ServiceDescriptions,ServiceSideCompositionChecks.Run,RetainedSideCompositionChecks.Run,SideEntryAndReadChecks.Run})try{check();}catch(Exception error){failures.Add(error);}
        if(failures.Count>0)throw new AggregateException("Required Side description contracts failed.",failures);
        Console.WriteLine("PASS instrument Side presentation: exact membership, ownership and typed terms");
    }
    static void FieldGroups()
    {
        var original=GasTransportFinancialTicket.Description;
        var group=new TicketFieldGroup("terms","Explicit terms","agreement",[..original.TradeFields.Select(field=>field.Id)]);
        var description=original with{FieldGroups=[group]};TicketDescriptions.Validate(description);
        foreach(var invalid in new[]{description with{FieldGroups=[group with{Fields=group.Fields.RemoveAt(0)}]},
            description with{FieldGroups=[group with{Fields=group.Fields.Add(group.Fields[0])}]},description with{FieldGroups=[group with{Kind="inferred_side"}]},
            description with{FieldGroups=[group with{Fields=group.Fields.Add("invented_field")}]}})
        {
            try{TicketDescriptions.Validate(invalid);}catch(MarketDataException error)when(error.Code=="ticket_description"){continue;}
            throw new Exception("Backend field groups must reject missing, repeated, unknown or inferred terms before describing an editable ticket.");
        }
        var reference=new ReferenceRevision(Guid.NewGuid(),Guid.NewGuid());var cash=new TimedCashPayment(new(reference,"usd"),DateTimeOffset.Parse("2032-03-14T08:00:00Z"));
        var mapped=InstrumentSidePresentation.Describe(cash,null,"Cash",[new(0,"Cash payment","Independent cash","Company pays",[new("Terms",[new("Currency","USD")])])],"terms");
        if(mapped.FieldGroupId!="terms")throw new Exception("Genuine instrument groups must retain their explicit declared field-card mapping.");
        InstrumentSidePresentation.RequireMappings(description,[mapped]);
        Reject(()=>InstrumentSidePresentation.RequireMappings(description,[mapped with{FieldGroupId="another_profile"}]));
    }
    static void UnpricedDefinition()
    {
        var reference=new ReferenceRevision(Guid.NewGuid(),Guid.NewGuid());var id=Guid.NewGuid();
        var terms=new GasTransportDirectRightsTerms(GasTransportDirectRightsPolicy.Version,new(reference,"whole_package"),new(reference,"usd"));
        var state=new GasTransportDirectRightsState(Guid.NewGuid(),Guid.NewGuid(),Guid.NewGuid(),"synthetic_remaining_rights");
        var through=DateTimeOffset.Parse("2032-03-15T00:00:00Z");
        var side=GasTransportDirectRightsInstrument.DefineSide(id,terms,state,through,GasTransportDirectRightsPolicy.ExpiryAtThrough,null);
        var group=InstrumentSidePresentation.Define(id,[new(side,ExactDecimal.Parse("1"))],null,"Unpriced rights",[
            new(0,"Remaining rights","Commercial entitlement","Explicit signed whole-package value",[new("Rights",[new("Package basis",terms.PackageQuantity.Code),new("Through",through.ToString("O"),"instant")])])]);
        if(group.InstrumentId!=id||group.BindingId is not null||group.Sides.Single().SideId!=side.Id)
            throw new Exception("An unpriced draft must expose its genuine rights Side definition without a fabricated owner, observation or zero valuation.");
    }
    static void ServiceDescriptions()
    {
        TicketDraft Draft(string profile)=>new(GasParkLoanTicket.Product,1,new Dictionary<string,string>{{"profile",profile}}.ToImmutableDictionary(),[]);
        var descriptions=new[]{GasParkLoanTicket.Description,GasParkLoanTicket.Describe(Draft(GasParkAndLoanTerms.Version)),
            GasParkLoanTicket.Describe(Draft(GasParkLoanBalanceFeeTerms.Version)),GasParkCustodyTicket.Describe(Draft(GasParkCustodyTerms.Version)),GasTransportFinancialTicket.Description};
        foreach(var description in descriptions)
        {
            if(description.FieldGroups is not {} groups||!description.SideGroupsRequired||
                !groups.SelectMany(group=>group.Fields).Order().SequenceEqual(description.TradeFields.Select(field=>field.Id).Order())||
                groups.SingleOrDefault(group=>group.Id=="fee") is not{Label:"Independent fee terms",Kind:"independent_instrument_terms"}||
                !groups.Where(group=>group.Kind=="agreement").SelectMany(group=>group.Fields).Contains("book"))
                throw new Exception("Service entry must describe a complete explicit Agreement/Side/independent-fee field layout without preselecting values or inventing cash ownership.");
            TicketDescriptions.Validate(description);
        }
        var custody=descriptions[3];
        if(custody.FieldGroups!.Value.Any(group=>group.Id=="custody"&&group.Kind!="agreement"))
            throw new Exception("Custody performance terms cannot be labeled as a fabricated financial gas Side.");
    }
    static void Reject(Action action)
    {
        try{action();}catch(MarketDataException error)when(error.Code=="instrument_side_presentation"){return;}
        throw new Exception("An incomplete or conflicting Side presentation must refuse.");
    }
}
