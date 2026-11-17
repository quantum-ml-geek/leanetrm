using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

internal sealed record PointTraderMarkPoint(Guid CatalogId,Guid DefinitionRevisionId,Guid SeriesId,string Source,DateTimeOffset ObservedAt);

internal static class PointTraderMarkIdentity
{
    private static readonly UTF8Encoding Utf8=new(false,true);
    internal static string Event(PointTraderMarkPoint point)=>Identity("manual_point_event_v1",Fields(point));
    internal static string Revision(PointTraderMarkPoint point,string sourceEventId,Guid? previous)
    {
        if(string.IsNullOrEmpty(sourceEventId)||previous==Guid.Empty)throw Invalid();
        return Identity("manual_point_revision_v1",[..Fields(point),sourceEventId,previous?.ToString("D")??""]);
    }
    private static string[] Fields(PointTraderMarkPoint point)
    {
        if(point is null||point.CatalogId==Guid.Empty||point.DefinitionRevisionId==Guid.Empty||point.SeriesId==Guid.Empty||
            string.IsNullOrWhiteSpace(point.Source)||!TradingInstant.IsSupported(point.ObservedAt))throw Invalid();
        return [point.CatalogId.ToString("D"),point.DefinitionRevisionId.ToString("D"),point.SeriesId.ToString("D"),point.Source,
            "trader_mark",point.ObservedAt.ToString("yyyy-MM-dd'T'HH:mm:ss.ffffff'Z'",CultureInfo.InvariantCulture)];
    }
    private static string Identity(string domain,string[] fields)
    {
        try
        {
            var text=new StringBuilder();
            foreach(var field in new[]{domain}.Concat(fields))
            {
                if(field.Contains('\0'))throw Invalid();
                text.Append(Utf8.GetByteCount(field).ToString(CultureInfo.InvariantCulture)).Append(':').Append(field);
            }
            return domain+":"+Convert.ToHexStringLower(SHA256.HashData(Utf8.GetBytes(text.ToString())));
        }
        catch(EncoderFallbackException error)
        {throw new MarketDataException("point_trader_mark_input","Retain valid exact UTF-8 point and source-event identities.",error);}
    }
    private static MarketDataException Invalid()=>new("point_trader_mark_input","Retain an exact point, source event and explicit predecessor at a supported UTC microsecond instant.");
}
