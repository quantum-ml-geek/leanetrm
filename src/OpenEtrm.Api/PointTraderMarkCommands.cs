using System.Text.Json;
using System.Text.RegularExpressions;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

internal static class PointTraderMarkCommands
{
    internal const string Policy="manual_final_direct_point_trader_mark_v1";
    internal static readonly JsonSerializerOptions Json=new(JsonSerializerDefaults.Web){AllowDuplicateProperties=false};
    internal static JsonElement Normalize(Guid catalog,JsonElement command)
    {
        try
        {
            var body=command.Deserialize<PointTraderMarkCommand>(Json)??throw Invalid();
            var target=body.Target??throw Invalid();
            if(catalog==Guid.Empty||body.Policy!=Policy||target.DefinitionRevisionId==Guid.Empty||target.ReferenceCatalogId==Guid.Empty||
                target.ReferenceRevisionId==Guid.Empty||target.ContractId==Guid.Empty||target.SeriesId==Guid.Empty||
                target.ExpectedPreviousObservationId==Guid.Empty)throw Invalid();
            foreach(var code in new[]{target.CurveCode,target.Source,target.Quote})
                if(code is null||!Regex.IsMatch(code,"\\A[a-z][a-z0-9_.-]{0,63}\\z",RegexOptions.CultureInvariant))throw Invalid();
            var at=TradingInstant.Parse(target.ObservedAt,"point_trader_mark_input");
            var point=new PointTraderMarkPoint(catalog,target.DefinitionRevisionId,target.SeriesId,target.Source,at);
            if(target.ExpectedPreviousObservationId is null&&target.SourceEventId!=PointTraderMarkIdentity.Event(point)||
                target.SourceRevisionToken!=PointTraderMarkIdentity.Revision(point,target.SourceEventId,target.ExpectedPreviousObservationId))throw Invalid();
            if(body.OriginalInputs is {} original&&(original.SnapshotId==Guid.Empty||original.Fingerprint is null||
                !Regex.IsMatch(original.Fingerprint,"\\A[0-9a-f]{64}\\z",RegexOptions.CultureInvariant)))throw Invalid();
            if(body.Value is null)throw Invalid();
            return JsonSerializer.SerializeToElement(body with
            {
                Target=target with{ObservedAt=at.ToString("yyyy-MM-dd'T'HH:mm:ss.ffffff'Z'",System.Globalization.CultureInfo.InvariantCulture)},
                Value=ExactDecimal.Parse(body.Value).ToString(),
                Evidence=GasOperationText.Evidence(body.Evidence,"point_trader_mark_input")
            },Json);
        }
        catch(MarketDataException error)when(error.Code!="point_trader_mark_input"){throw Invalid();}
        catch(Exception error)when(error is JsonException or InvalidOperationException or ArgumentException or FormatException or OverflowException)
        {throw Invalid();}
    }
    private static MarketDataException Invalid()=>new("point_trader_mark_input",
        "Supply the complete selected point, explicit predecessor, exact signed value, publication policy and evidence.");
}
