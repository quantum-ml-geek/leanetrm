using System.Collections.Immutable;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using Npgsql;
using OpenEtrm.MarketData;

namespace OpenEtrm.Api;

internal sealed record RecPosition(JsonElement Head,JsonElement Book,JsonElement Product)
{
    internal Guid Trade=>Head.Id("trade_id");
    internal Guid Binding=>Head.Id("instrument_id");
    internal Guid Definition=>Head.Id("definition_revision_id");
    internal string From=>Head.Text("delivery_from");
    internal string To=>Head.Text("delivery_to");
    internal string Curve=>Product.Text("curve_code");
    internal string MarketLabel=>$"{Product.Text("name")} · vintage {Head.Text("vintage_from")} to {Head.Text("vintage_to")}";
    internal ReferenceRevision Reference=>new(Product.Id("reference_catalog_id"),Product.Id("reference_revision_id"));
    internal ReferenceKey Quantity=>new(Reference,Product.Text("quantity_code"));
    internal ReferenceKey Currency=>new(Reference,Product.Text("currency_code"));
    internal ExactDecimal TotalQuantity=>ExactDecimal.Parse(Head.Text("quantity"));
    internal RecForwardBookRequest Terms()=>Head.GetProperty("request").Deserialize<RecForwardBookRequest>(new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
    internal TradePositionFact Fact()=>new(Trade,Binding,int.Parse(Head.Text("revision"),CultureInfo.InvariantCulture),TradingReference.Trade(Head),Book.Id("id"),Book.Text("name"),
        RecPositions.Type,MarketLabel,From,To,TotalQuantity.ToString(),Product.Text("unit"));
    internal JsonObject Holding()=>JsonSerializer.SerializeToNode(new{
        booking=new{tradeDate=Head.Text("trade_date"),legalEntityId=Head.Id("legal_entity_id"),legalEntityRevision=int.Parse(Head.Text("legal_entity_revision"),CultureInfo.InvariantCulture),
            legalEntity=Head.Text("legal_entity"),counterpartyId=Head.Id("counterparty_id"),counterpartyRevision=int.Parse(Head.Text("counterparty_revision"),CultureInfo.InvariantCulture),counterparty=Head.Text("counterparty")},
        traderId=Head.Id("booker_id"),trader=Head.Text("booker_name"),traderCode=Head.Text("booker_login"),memo=(string?)null,
        tradeId=Trade,bindingId=Binding,instrumentId=Binding,revision=Head.Text("revision"),tradeReference=TradingReference.Trade(Head),instrumentReference=TradingReference.Instrument(Head),
        bookId=Book.Id("id"),book=Book.Text("name"),portfolioId=Book.Id("portfolio_id"),portfolio=Book.Text("portfolio"),
        instrumentType=RecPositions.Type,contractIdentityKind="rec_forward",contractId=Binding,definitionRevisionId=Definition,
        curve=Curve,projectionCurves=Product.GetProperty("projection_curves").EnumerateArray().Select(x=>x.GetString()).ToArray(),marketKey=Curve,marketLabel=MarketLabel,
        commodity=new{code=Product.Text("commodity_code"),name=Product.Text("commodity_name")},certificateProduct=Product.Text("code"),vintageFrom=Head.Text("vintage_from"),vintageTo=Head.Text("vintage_to"),
        deliveryFrom=From,deliveryTo=To,lots=(string?)null,quantity=TotalQuantity.ToString(),unit=Product.Text("unit"),quantitySpecification=Quantity,
        currency=Product.Text("currency"),currencyReference=Currency,quoteMultiplier="1",direction=Head.Text("physical_direction")=="1"?"receive":"deliver",
        executedAt=Head.Text("executed_at"),bookingFacts=new{implementation=Head.Text("booking_implementation"),labelCapturedAt=Head.Text("label_captured_at")},
        executionPrice=(string?)null,fixedPrice=(string?)null,mark=(string?)null,markMinusPrice=(string?)null,executionPnl=(string?)null,
        settlement="unprocessed",measure=RecPositions.Measure,measureLabel="Certificate contractual PV",quantityPolicy="linear_certificate_count_v1",presentValue=(string?)null,unavailableReason=(string?)null
    },TradingBlotter.Json)!.AsObject();
}

internal static class RecPositions
{
    internal const string Type="rec_forward",Measure="rec_contractual_present_value";
    private static MarketDataException Missing()=>new("position_facts","Every certificate position needs exact product/vintage, party, booking and retained source metadata.");
    internal static async Task<ImmutableArray<RecPosition>> Read(NpgsqlConnection connection,PreviewManifest manifest,
        ImmutableArray<Guid> bookIds,ImmutableArray<Guid> portfolioIds,CancellationToken ct,TradePositionSelection? position=null,Guid? trade=null,ImmutableHashSet<Guid>? trades=null)
    {
        var books=await BookScope.Read(connection,manifest.CatalogId,ct);var selectedTrade=position?.TradeId??trade;
        if(selectedTrade is {} required&&trades is not null&&!trades.Contains(required))throw TradePositionSelection.Unavailable();
        var scope=selectedTrade is {} one?ImmutableHashSet.Create(one):trades;
        var inventory=await PreviewDatabase.Rows(connection,"SELECT value::text FROM jsonb_array_elements(security.rec_forward_position_scope($1,$2::uuid[],$3::uuid[],$4::uuid[]))",
            [manifest.CatalogId,bookIds.ToArray(),portfolioIds.ToArray(),(object?)scope?.ToArray()??DBNull.Value],ct);
        var selected=BookScope.Select(books,bookIds,portfolioIds).ToImmutableDictionary(b=>b.Id("id"));
        if(selected.IsEmpty)return [];
        var rows=await PreviewDatabase.Rows(connection,"SELECT value::text FROM jsonb_array_elements(security.read_rec_forward_positions($1,$2::uuid[],$3::uuid[],$4::uuid[]))",
            [manifest.CatalogId,bookIds.ToArray(),portfolioIds.ToArray(),(object?)scope?.ToArray()??DBNull.Value],ct);
        var heads=rows.Select(r=>r.GetProperty("head")).ToImmutableArray();PositionInventory.Require(inventory,heads,Missing);
        if(position is not null)position.Require(heads);
        var result=rows.Select(row=>new RecPosition(row.GetProperty("head"),selected[row.GetProperty("head").Id("book_id")],row.GetProperty("product"))).ToImmutableArray();
        foreach(var item in result)AsyncReadVisibility.Bundle(manifest with{RevisionId=item.Definition,ReferenceCatalogId=item.Reference.CatalogId,ReferenceRevisionId=item.Reference.RevisionId});
        return result;
    }
}
