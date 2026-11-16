using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Nodes;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Calculation;

namespace OpenEtrm.Api;

internal sealed record RiskPricingPolicyChoice(string Id,string Label,PortfolioValuationPolicy PricingPolicy,bool WholeBooksOnly);
internal sealed record RiskPricingSetup(ImmutableArray<RiskPricingPolicyChoice> PricingPolicies,string SelectedPricingPolicyId);

// These are executable choices for ordinary Risk setup. Calculation requests
// retain their full policy; an identity never replaces that financial contract.
internal static class RiskPricingPolicies
{
    internal static PortfolioValuationPolicy Base=>PortfolioRiskPreview.AccountingPricingPolicy;
    internal static PortfolioValuationPolicy NativeGas=>Base with{GasOwned=new(GasOwnedValuationPolicy.Version,
        GasOwnedValuationPolicy.WholeBooks,GasOwnedValuationPolicy.CurrencyDefault,RateDiscountTiming.Version)};

    internal static ImmutableArray<RiskPricingPolicyChoice> Choices(bool canReadGas,bool wholeBooks)
    {
        var result=ImmutableArray.CreateBuilder<RiskPricingPolicyChoice>();
        result.Add(new("base","Contractual positions",Base,false));
        if(canReadGas&&wholeBooks)result.Add(new("native-gas-v1","Contractual positions and independent gas holdings",NativeGas,true));
        return result.ToImmutable();
    }

    internal static bool Same(PortfolioValuationPolicy left,PortfolioValuationPolicy right)=>
        JsonNode.DeepEquals(JsonSerializer.SerializeToNode(left,RiskJobs.Json),JsonSerializer.SerializeToNode(right,RiskJobs.Json));

    internal static PortfolioValuationPolicy Resolve(PortfolioValuationPolicy? selected,bool canReadGas,ImmutableArray<Guid>? trades)
    {
        if(selected is null||Same(selected,Base))return Base;
        if(!Same(selected,NativeGas))
            throw new MarketDataException("risk_pricing_policy","Select one exact pricing policy offered by ordinary Risk setup.");
        if(trades is not null)
            throw new MarketDataException("gas_owned_scope","Independent gas ownership requires the complete book scope. Select contractual pricing for individual trades.");
        if(!canReadGas)throw new PreviewDeniedException();
        return NativeGas;
    }

    internal static string? StatedId(JsonNode? report)
    {
        if(report is not JsonObject value||value["inputs"] is not JsonObject inputs||inputs["pricingPolicy"] is not {} policy)return null;
        foreach(var choice in Choices(true,true))
            if(JsonNode.DeepEquals(policy,JsonSerializer.SerializeToNode(choice.PricingPolicy,RiskJobs.Json)))return choice.Id;
        return null;
    }

    internal static void RequireScopePolicy(PortfolioRiskCatalogRequest scope,PortfolioValuationPolicy policy)
    {
        if(scope is not null&&scope.PricingPolicy is {} selected&&!Same(selected,policy))
            throw new MarketDataException("risk_pricing_policy","The scope and calculation must identify the same complete pricing policy.");
    }
}
