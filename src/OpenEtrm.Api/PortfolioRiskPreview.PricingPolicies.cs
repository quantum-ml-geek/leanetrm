using System.Collections.Immutable;
using Npgsql;
using OpenEtrm.MarketData;

namespace OpenEtrm.Api;

public sealed partial class PortfolioRiskPreview
{
    public async Task<object> Setup(NpgsqlConnection connection,InputFrame frame,PortfolioRiskCatalogRequest body,CancellationToken ct)
    {
        if(frame.ContextId is null||body.BookIds.IsDefault||body.PortfolioIds.IsDefault)
            throw new MarketDataException("risk_context","Select the certified Risk context and explicit book scope.");
        var books=BookScope.Select(await BookScope.Read(connection,database.Manifest.CatalogId,ct),body.BookIds,body.PortfolioIds)
            .Select(book=>book.Id("id")).Order().ToImmutableArray();
        if(books.IsEmpty)throw new MarketDataException("risk_position","Select visible books before preparing Risk.");
        if(body.TradeIds is not null)await RiskTradeScope.Resolve(connection,database.Manifest.CatalogId,books,body.TradeIds,ct);
        var canReadGas=body.TradeIds is null&&await FuturesOptionPhysicalPermissionAdmission.TryCapture(connection,database,ct);
        var selected=RiskPricingPolicies.Resolve(body.PricingPolicy,canReadGas,body.TradeIds);
        var choices=RiskPricingPolicies.Choices(canReadGas,body.TradeIds is null);
        return new RiskPricingSetup(choices,choices.Single(choice=>RiskPricingPolicies.Same(choice.PricingPolicy,selected)).Id);
    }

    private async Task<PortfolioValuationPolicy> SelectedPricingPolicy(NpgsqlConnection connection,PortfolioRiskCatalogRequest body,CancellationToken ct)
    {
        var selected=RiskPricingPolicies.Resolve(body.PricingPolicy,true,body.TradeIds);
        if(selected.GasOwned is not null)await FuturesOptionPhysicalPermissionAdmission.Capture(connection,database,ct);
        return selected;
    }
}
