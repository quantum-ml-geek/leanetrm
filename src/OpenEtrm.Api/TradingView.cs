using System.Globalization;
using Npgsql;

namespace OpenEtrm.Api;

// The dated cutoff a trading read binds and the frame it reads at. Trading facts are always read
// as of a context: current knowledge captured for this read over a working frame, which may be
// edited, or a historical view's retained context, which may not. Page views use PinnedContext.
public sealed record TradingView
{
    // Views are made by Capture or Retained; the checks alone rebuild a page's own view directly.
    internal TradingView(InputFrame? frame,ScheduleContext context,bool working)
    {
        Frame=frame??throw PinnedContext.Missing();Context=PinnedContext.Exact(context);Working=working;
    }
    public InputFrame Frame {get;}
    public ScheduleContext Context {get;}
    // The context was captured from current knowledge for this read over a working frame.
    public bool Working {get;}
    // Working data as of current knowledge, captured now at the working frame's date.
    public static async Task<TradingView> Capture(NpgsqlConnection connection,KnowledgeStore store,InputFrame? frame,CancellationToken ct)
    {
        if(frame is not {ContextId:null})throw PinnedContext.Missing();
        var on=frame.At.UtcDateTime.ToString("yyyy-MM-dd",CultureInfo.InvariantCulture);
        return new(frame,(await store.Capture(connection,new(on,null,"current"),ct)).Context,true);
    }
    // A historical view: its retained context, read at one of its own frames.
    public static TradingView Retained(InputFrame? frame,ScheduleContext context)=>
        frame is not null && frame.ContextId==context.ContextId?new(frame,context,false):throw PinnedContext.Missing();
    public Task Bind(NpgsqlConnection connection,Guid catalog,CancellationToken ct)=>PinnedContext.BindExact(connection,catalog,Context,ct);
}
