using System.Text.Json;
using Npgsql;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

internal static class RecForwardCatalog
{
    internal const string Convention="rec_forward_v1";
    internal static async Task<object> Read(NpgsqlConnection c,PreviewDatabase database,PreviewData data,InputFrame frame,string knownAt,bool current,CancellationToken ct)
    {
        var pins=data.ReferenceRevision;
        var products=await PreviewDatabase.Rows(c,"SELECT value::text FROM jsonb_array_elements(security.rec_products($1,$2,$3))",[database.Manifest.CatalogId,pins.CatalogId,pins.RevisionId],ct);
        var rows=await PreviewDatabase.Rows(c,"""
            SELECT row_to_json(r)::text FROM(SELECT a.code,a.product_code,a.vintage_from,a.vintage_to,a.curve_code,a.contract_id
             FROM market_data.rec_valuation_assignments a WHERE(a.catalog_id,a.revision_id)=($1,$2) ORDER BY a.code)r
            """,[data.DefinitionRevision.CatalogId,data.DefinitionRevision.RevisionId],ct);
        var prices=StructuredPowerTradeCatalog.Prices(data,frame);
        var assignments=rows.Select(a=>{
            var price=prices.SingleOrDefault(p=>p.CurveCode==a.Text("curve_code")&&p.ContractId==a.Id("contract_id"));
            if(price is null)throw new MarketDataException("rec_mark","An eligible certificate assignment requires its exact selected dated price contract.");
            return new{code=a.Text("code"),productCode=a.Text("product_code"),vintageFrom=a.Text("vintage_from"),vintageTo=a.Text("vintage_to"),
                price.CurveCode,price.ContractId,price.QuoteCode,price.CurrencyCode,price.QuantityCode,price.DeliveryFrom,price.DeliveryTo,price.Label};
        }).ToArray();
        await using var owner=ScheduleStore.Command(c,"SELECT security.rec_trade_owner($1)",database.Manifest.CatalogId);
        var ownerId=(string)(await owner.ExecuteScalarAsync(ct))!;
        var trades=await PreviewDatabase.HasPermission(c,"ReadTrades",ct);var parties=await PreviewDatabase.HasPermission(c,"ReadTradeParties",ct);
        var result=new{ownerId,snapshotId=frame.Id,contextId=frame.ContextId,knownAt,definitionRevisionId=data.DefinitionRevision.RevisionId,
            referenceCatalogId=pins.CatalogId,referenceRevisionId=pins.RevisionId,products,assignments,
            quotes=StructuredPowerPreview.Catalog(data,false,false).Quotes,priceContracts=prices,paymentImplementation=PaymentRule.Implementation,
            calendarImplementation=SideCalendarPolicy.Implementation,convention=Convention,
            books=trades?await BookScope.Read(c,database.Manifest.CatalogId,ct):[],
            legalEntities=parties?await TradeParties.Catalog(c,database.Manifest.CatalogId,true,ct):[],
            counterparties=parties?await TradeParties.Catalog(c,database.Manifest.CatalogId,false,ct):[],
            canBook=current&&trades&&parties&&await PreviewDatabase.HasPermission(c,"BookTrade",ct)};
        if(parties&&!await PreviewDatabase.HasPermission(c,"ReadTradeParties",ct))throw new PreviewDeniedException();
        return result;
    }
}
