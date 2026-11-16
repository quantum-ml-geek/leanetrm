using System.Collections.Immutable;
using System.Text.Json;

namespace OpenEtrm.Api;

// HTTP and SSE share these projections; transport never changes financial terms.
internal static class AsyncReadProjections
{
    internal static object Curve(PriceRead read,PinnedContext pin,BuildRequest body,object? workspace=null)
    {
        if(pin.Context is null&&!body.IncludeSources&&!body.IncludeWorkspace)return read.Result;
        var json=JsonSerializer.SerializeToNode(read.Result,AsyncReadContract.Json)!.AsObject();
        if(pin.Context is {} view)json["context"]=JsonSerializer.SerializeToNode(view,AsyncReadContract.Json);
        if(body.IncludeSources)
        {
            json["observations"]=JsonSerializer.SerializeToNode(read.Observations);
            json["observationScope"]="selected_frame";
            json["inputSelection"]=JsonSerializer.SerializeToNode(read.InputSelection,AsyncReadContract.Json);
        }
        if(body.IncludeWorkspace)json["workspace"]=JsonSerializer.SerializeToNode(workspace??throw new InvalidOperationException("The requested workspace projection is missing."),AsyncReadContract.Json);
        return json;
    }
    internal static object History(ImmutableArray<HistorySample> points,PinnedContext pin,HistoryRequest body,string policy)
    {
        var chart=HistoryChart.Of(points);
        var read=new Dictionary<string,object?>{["mode"]="exact_visible_close_history_with_selected_instant_v1",["revisionPolicy"]=policy,["knowledgeCutoff"]=pin.Context?.KnownAt,
            ["knowledgeBasis"]=pin.Context is null?"current_knowledge":"selected_context",["points"]=points,
            ["chart"]=chart.Conflict is {} conflict?new{conflict=new{at=conflict.At,message=conflict.Message}}:new{points=chart.Points}};
        if(body.Overlays is {} requests)
        {
            if(chart.Conflict is null)read["overlays"]=OpenEtrm.Shared.Analytics.Overlays.Compute(chart.OverlayInput(),requests);
            else OpenEtrm.Shared.Analytics.Overlays.Compute([],requests);
        }
        return read;
    }
}
