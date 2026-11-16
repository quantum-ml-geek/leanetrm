using OpenEtrm.Api;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;

internal static class CalendarPolicyReplayChecks
{
    internal static void Run()
    {
        var reference=new ReferenceKey(new(Guid.NewGuid(),Guid.NewGuid()),"synthetic_calendar");
        var originalProof=new CalendarPublicationProof(Guid.NewGuid(),7,DateTimeOffset.Parse("2040-01-02T12:00:00Z"));
        var earlierProof=new CalendarPublicationProof(Guid.NewGuid(),3,DateTimeOffset.Parse("2040-01-01T12:00:00Z"));
        CalendarDefinition Calendar(CalendarPublicationProof proof)=>new(reference,new(2040,1,1),new(2042,1,1),0,[],CalendarDefinition.Implementation,proof);
        var original=SideCalendarPolicy.UseOne(Calendar(originalProof),true,false,true);
        var newlyVisible=SideCalendarPolicy.UseOne(Calendar(earlierProof),true,false,true);
        var canonical="{\"contract\":\"synthetic_calendar_replay_v1\",\"CalendarPolicy\":"+DefinitionIdentity.For(original).Canonical+"}";
        var input=SideCalendarPolicies.FromRetained(canonical);
        var pureCalendar=new CalendarDefinition(reference,new(2040,1,1),new(2042,1,1),0,[],CalendarDefinition.Implementation,null);
        var purePolicy=SideCalendarPolicy.UseOne(pureCalendar,true,false,true);
        var pureCanonical="{\"contract\":\"synthetic_calendar_replay_v1\",\"CalendarPolicy\":"+DefinitionIdentity.For(purePolicy).Canonical+"}";
        if(DefinitionIdentity.For(RetainedSideCalendarPolicy.Read(pureCanonical))!=DefinitionIdentity.For(purePolicy))
            throw new Exception("The pure retained definition must preserve nullable synthetic publication evidence exactly.");
        try{SideCalendarPolicies.FromRetained(pureCanonical);throw new Exception("Native calendar hydration must still require its original publication proof.");}
        catch(MarketDataException error)when(error.Code=="side_calendar_policy"){}
        // No current metadata is consulted to reinterpret a verified retained identity.
        var replay=SideCalendarPolicies.Resolve(null!,input);
        if(DefinitionIdentity.For(replay)!=DefinitionIdentity.For(original)||DefinitionIdentity.For(replay)==DefinitionIdentity.For(newlyVisible))
            throw new Exception("Gaining access to an earlier publication must not change a retained Side's selected proof.");
        var changed=input with{Payment=input.Payment with{Calendar=reference with{Code="different_calendar"}}};
        try{SideCalendarPolicies.Resolve(null!,changed);throw new Exception("An authored reference cannot contradict retained calendar evidence.");}
        catch(MarketDataException error)when(error.Code=="side_calendar_conflict"){}
        var wire=System.Text.Json.JsonSerializer.Serialize(input,new System.Text.Json.JsonSerializerOptions(System.Text.Json.JsonSerializerDefaults.Web));
        if(wire.Contains("Retained",StringComparison.OrdinalIgnoreCase)||wire.Contains(originalProof.CatalogId.ToString(),StringComparison.Ordinal))
            throw new Exception("Private retained evidence must not become an author-controlled proof selection.");
        var ppa=new PpaTermsInput(Guid.NewGuid(),reference.Revision.CatalogId,reference.Revision.RevisionId,
            new("synthetic_clock",60,"2040-01-01","2040-02-01"),"usd","mw",false,"ppa_composed_instrument_v1",[],
            [new("energy_delivery",0,"1",new("energy",null!,null!,null,null,null,null){CalendarPolicy=input})]);
        try{SideCalendarPolicies.Retain(ppa,_=>canonical);throw new Exception("Incomplete retained clock evidence must fail with a structured error.");}
        catch(MarketDataException error)when(error.Code=="clock_rule"){}
        var json=new System.Text.Json.JsonSerializerOptions(System.Text.Json.JsonSerializerDefaults.Web);
        var unfinished=new SwapScheduledSideInput("period_total",reference,null,null,"period_average_times_quantity_v1",null,[]);
        var priorSide=new PpaSideInput("fixed",null!,null!,null,null,null,null);
        foreach(var payload in new[]{System.Text.Json.JsonSerializer.Serialize(unfinished,json),System.Text.Json.JsonSerializer.Serialize(priorSide,json)})
            if(payload.Contains("calendarPolicy",StringComparison.Ordinal))
                throw new Exception("Reading an older completed request must not inject a null policy and change its retry hash.");
        Console.WriteLine("PASS calendar replay: original publication proof survives newly visible sources and cannot be overridden by authoring terms");
    }
}
