using System.Text.Json;
using System.Globalization;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

internal static class PointTraderMarkReceipts
{
    internal static void Require(Guid catalog,Guid operation,JsonElement canonical,JsonElement outcome)
    {
        try
        {
            var body=PointTraderMarkCommands.Normalize(catalog,canonical);
            var target=body.GetProperty("target");
            if(operation==Guid.Empty||outcome.Id("operationId")!=operation||outcome.Id("observationId")==Guid.Empty||
                outcome.Text("value")!=body.Text("value"))throw Invalid();
            foreach(var field in new[]{"definitionRevisionId","referenceCatalogId","referenceRevisionId","contractId","seriesId"})
                if(outcome.Id(field)!=target.Id(field))throw Invalid();
            foreach(var field in new[]{"source","quote","sourceEventId"})
                if(outcome.Text(field)!=target.Text(field))throw Invalid();
            if(TradingInstant.Parse(outcome.Text("observedAt"),"point_trader_mark_source")!=
                TradingInstant.Parse(target.Text("observedAt"),"point_trader_mark_source"))throw Invalid();
            var changed=outcome.GetProperty("changed").GetBoolean();
            var previous=target.OptionalId("expectedPreviousObservationId");
            var revision=outcome.Text("sourceRevisionId");
            var actualPrevious=outcome.OptionalId("previousObservationId");
            var sameRevision=revision==target.Text("sourceRevisionToken")&&actualPrevious==previous;
            var acceptedPredecessor=!changed&&previous is {} id&&outcome.Id("observationId")==id;
            if(string.IsNullOrEmpty(revision)||actualPrevious==Guid.Empty||!sameRevision&&!acceptedPredecessor||
                !outcome.GetProperty("knowledgeEventOrder").TryGetInt64(out var order)||order is <1 or >9007199254740991||
                !ulong.TryParse(outcome.Text("publicationXid"),NumberStyles.None,CultureInfo.InvariantCulture,out var xid)||xid==0)
                throw Invalid();
        }
        catch(MarketDataException error)when(error.Code!="point_trader_mark_source"){throw Invalid();}
        catch(Exception error)when(error is KeyNotFoundException or InvalidOperationException or FormatException or ArgumentException or OverflowException)
        {throw Invalid();}
    }
    private static MarketDataException Invalid()=>new("point_trader_mark_source","The publication receipt does not identify the exact accepted point, value and native publication.");
}
