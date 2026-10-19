using Npgsql;
using OpenEtrm.MarketData;
using OpenEtrm.Shared.Temporal;

namespace OpenEtrm.Api;

// The exact knowledge view and input frame a page read runs under, resolved by its caller
// before the read starts: a retained context, or current working data, which binds nothing.
// A read binds only what the pin names; it never captures, widens or substitutes a context.
public sealed record PinnedContext
{
    private PinnedContext(ScheduleContext? context,InputFrame? frame)
    {
        // A retained context names its id and every coordinate; none is ever filled in later.
        if(context is {ContextId:null} or {EffectiveOn:null} or {KnownAt:null} or {KnownThrough:null})
            throw new TemporalException("temporal_context","Pin an exact retained context.");
        Context=context;
        Frame=frame is null?null:Require(frame);
    }
    // The selected retained context, or null for current working data.
    public ScheduleContext? Context {get;}
    public InputFrame? Frame {get;}
    public static PinnedContext Current(InputFrame? frame=null)=>new(null,frame);
    public static PinnedContext Retained(ScheduleContext context,InputFrame? frame=null)=>new(context,frame);
    public InputFrame RequireFrame()=>Frame??throw Missing();
    // A frame belongs to exactly one knowledge view; working frames carry no context.
    public InputFrame Require(InputFrame? frame)=>frame is not null && frame.ContextId==Context?.ContextId?frame:throw Missing();
    // Binds the stored context only when its coordinates are exactly the pin's, so a read never mixes two views.
    public async Task Bind(NpgsqlConnection connection,Guid catalog,CancellationToken ct)
    {
        if(Context is null)return;
        await new KnowledgeStore(catalog).Retained(connection,Context,ct);
        await MarketContextStore.Bind(connection,catalog,Context,ct);
    }
    static MarketDataException Missing()=>new("snapshot_missing","Select a saved input snapshot from this preview session.");
}
