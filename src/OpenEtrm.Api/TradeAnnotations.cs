using System.Collections.Immutable;
using System.Text.Json;
using Npgsql;
using OpenEtrm.MarketData;

namespace OpenEtrm.Api;

internal static class TradeAnnotations
{
    internal sealed record TraderChoice(Guid Id,int Revision,string Code,string Name);
    public static async Task<ImmutableArray<TraderChoice>> Catalog(NpgsqlConnection connection,Guid catalog,CancellationToken ct)
    {
        var rows=await PreviewDatabase.Rows(connection,"""
        SELECT row_to_json(t)::text FROM(SELECT DISTINCT ON(id) id,revision,code,name
          FROM trading.traders WHERE catalog_id=$1 ORDER BY id,revision DESC)t ORDER BY t.code
        """,[catalog],ct);
        return rows.Select(r=>new TraderChoice(r.Id("id"),int.Parse(r.Text("revision"),System.Globalization.CultureInfo.InvariantCulture),r.Text("code"),r.Text("name"))).ToImmutableArray();
    }
    public static void ValidateShape(Guid? trader,int? revision,string? memo)
    {
        if((trader is null)!=(revision is null)||memo?.Length>4000||memo?.Contains('\0')==true)
            throw new MarketDataException("trade_annotation","Select an exact trader version or leave attribution unassigned; memo is limited to 4000 characters.");
    }
    public static async Task Validate(NpgsqlConnection connection,Guid catalog,Guid? trader,int? revision,string? memo,DateTimeOffset executed,CancellationToken ct)
    {
        ValidateShape(trader,revision,memo);
        if(trader is null)return;
        var rows=await PreviewDatabase.Rows(connection,"SELECT row_to_json(t)::text FROM trading.traders t WHERE catalog_id=$1 AND id=$2 AND revision=$3 AND effective_at<=$4",[catalog,trader.Value,revision!.Value,executed],ct);
        if(rows.Length!=1)throw new MarketDataException("trade_annotation","The selected trader version is unavailable at the trade's execution date and knowledge view.");
    }
    public static bool Same(JsonElement row,Guid? trader,int? revision,string? memo)=>
        row.OptionalId("trader_id")==trader&&row.OptionalText("trader_revision")==revision?.ToString(System.Globalization.CultureInfo.InvariantCulture)&&row.OptionalText("memo")==memo;
}
