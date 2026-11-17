using System.Collections.Immutable;
using System.Text.Json.Serialization;
using OpenEtrm.MarketData;

namespace OpenEtrm.Api;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredPowerTradeReadRequest([property:JsonRequired]Guid SnapshotId,[property:JsonRequired]Guid TradeId,
    FuturesReadRequest? Context=null,Guid? BindingId=null,int? Revision=null)
{
    internal bool Selected=>Context is not null||BindingId is not null||Revision is not null;
    internal TradePositionSelection Selection()
    {
        if(Context is null||Context.SnapshotId!=SnapshotId||SnapshotId==Guid.Empty||Context.Convention!=TradingBlotter.Convention||BindingId is null||Revision is null)
            throw new MarketDataException("position_request","Retain the exact matching snapshot, context and operating trade/binding/revision.");
        return TradePositionSelection.From(new(Context,TradeId,BindingId.Value,Revision.Value,OperatingPositions.Type));
    }
    internal void RequireCurrentValuation()
    {
        if(Selected)throw new MarketDataException("position_request","This valuation operation accepts only its explicit current snapshot and trade; retained selected reads use Get.");
    }
}
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredPowerTradeDirectoryRequest([property:JsonRequired]Guid SnapshotId,
    [property:JsonRequired]ImmutableArray<Guid> BookIds,[property:JsonRequired]int Offset,[property:JsonRequired]int Limit);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StructuredPowerTradeStatusRequest([property:JsonRequired]Guid OperationId);
