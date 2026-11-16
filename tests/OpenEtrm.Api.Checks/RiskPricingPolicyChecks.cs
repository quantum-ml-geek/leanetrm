using System.Text.Json;
using System.Text.Json.Nodes;
using OpenEtrm.Api;
using OpenEtrm.MarketData;

internal static class RiskPricingPolicyChecks
{
    internal static void Run()
    {
        var policy=PortfolioRiskPreview.AccountingPricingPolicy;
        var request=new JsonObject{
            ["context"]=JsonSerializer.SerializeToNode(new FuturesReadRequest(Guid.NewGuid(),TradingBlotter.Convention,"retained",Guid.NewGuid()),RiskJobs.Json),
            ["bookIds"]=new JsonArray(Guid.NewGuid()),["portfolioIds"]=new JsonArray(),
            ["pricingPolicy"]=JsonSerializer.SerializeToNode(policy,RiskJobs.Json)};
        var accepted=request.Deserialize<PortfolioRiskCatalogRequest>(RiskJobs.Json)??throw new Exception("Missing catalog policy request.");
        var recorded=JsonSerializer.SerializeToNode(accepted,RiskJobs.Json)!;
        if(!JsonNode.DeepEquals(recorded["pricingPolicy"],request["pricingPolicy"]))
            throw new Exception("An ordinary Risk catalog request must retain the explicitly selected complete pricing policy.");
        var legacy=accepted with{PricingPolicy=null};
        if(JsonSerializer.SerializeToNode(legacy,RiskJobs.Json)!.AsObject().ContainsKey("pricingPolicy"))
            throw new Exception("Legacy history and economic scope shapes must not gain an unstated pricing policy.");
        var native=RiskPricingPolicies.NativeGas;
        var choices=RiskPricingPolicies.Choices(true,true);
        if(choices.Length!=2||choices[0].WholeBooksOnly||!choices[1].WholeBooksOnly||choices[0].PricingPolicy.GasOwned is not null||
            !RiskPricingPolicies.Same(choices[1].PricingPolicy with{GasOwned=null},policy)||
            RiskPricingPolicies.Choices(false,true).Length!=1||RiskPricingPolicies.Choices(true,false).Length!=1)
            throw new Exception("Ordinary Risk must offer the existing base and only its authorized whole-book independent-gas variant.");
        foreach(var choice in choices)PortfolioValuation.ValidatePolicy(choice.PricingPolicy);
        if(!RiskPricingPolicies.Same(RiskPricingPolicies.Resolve(null,false,null),policy)||
            !RiskPricingPolicies.Same(RiskPricingPolicies.Resolve(policy,false,[Guid.NewGuid()]),policy)||
            !RiskPricingPolicies.Same(RiskPricingPolicies.Resolve(native,true,null),native))
            throw new Exception("Policy omission preserves base compatibility; native ownership requires its explicit complete selection.");
        Reject("gas_owned_scope",()=>RiskPricingPolicies.Resolve(native,true,[Guid.NewGuid()]));
        Reject("risk_pricing_policy",()=>RiskPricingPolicies.Resolve(native with{BumpTicks=2},true,null));
        try{RiskPricingPolicies.Resolve(native,false,null);throw new Exception("Missing current gas authority was accepted.");}
        catch(PreviewDeniedException){}
        RiskPricingPolicies.RequireScopePolicy(accepted,policy);
        Reject("risk_pricing_policy",()=>RiskPricingPolicies.RequireScopePolicy(accepted,native));
        static JsonNode Result(PortfolioValuationPolicy selected)=>new JsonObject{["inputs"]=new JsonObject{["pricingPolicy"]=JsonSerializer.SerializeToNode(selected,RiskJobs.Json)}};
        if(RiskPricingPolicies.StatedId(Result(policy))!=choices[0].Id||RiskPricingPolicies.StatedId(Result(native))!=choices[1].Id||
            RiskPricingPolicies.StatedId(Result(native with{BumpTicks=2})) is not null||
            PortfolioRiskPreview.UnderStatedPricingPolicy(Result(native))||!PortfolioRiskPreview.UnderStatedPricingPolicy(Result(native),native)||
            PortfolioRiskPreview.UnderStatedPricingPolicy(Result(policy),native))
            throw new Exception("Current-report comparisons must preserve base behavior and match an explicitly selected complete policy exactly.");
        Console.WriteLine("PASS Risk catalog policy: exact explicit pricing selection survives its typed request.");
        Console.WriteLine("PASS Risk pricing choices: current authority and whole-book scope gate native ownership, with policy-aware retained comparison and no implicit selection.");
    }

    private static void Reject(string code,Action action)
    {try{action();}catch(MarketDataException error)when(error.Code==code){return;}throw new Exception("Expected "+code);}
}
