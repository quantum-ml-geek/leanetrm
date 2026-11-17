using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Routing;
using OpenEtrm.MarketData;

namespace OpenEtrm.Api;

internal static class PointTraderMarkEndpoints
{
    internal static void Map(RouteGroupBuilder api,PreviewDatabase database,
        Func<HttpContext,Func<PreviewSession,Task<IResult>>,Task<IResult>> locked,Func<PreviewSession,string> profile)
    {
        var store=new PointTraderMarkStore(database);
        api.MapPost("/market-values/setup",(HttpContext c,PointTraderMarkSetupRequest request)=>locked(c,async session=>
        {
            var original=request.Context?.SnapshotId is {} id?session.Frames.GetValueOrDefault(id):null;
            var result=await database.WithIdentity(profile(session),null,(connection,ct)=>store.Setup(connection,request,original,ct),c.RequestAborted);
            return Results.Ok(result);
        }));
        Task<IResult> Write(HttpContext c,PointTraderMarkWriteRequest request,bool preview)=>locked(c,async session=>
        {
            if(session.MarketContext is not null)throw new MarketDataException("historical_read_only","Return to current working data to publish market values.");
            if(!preview)c.Items["point_trader_mark_attempted"]=true;
            var result=await database.WithIdentity(profile(session),null,(connection,ct)=>store.Execute(connection,request,preview,ct),c.RequestAborted);
            // Business publication has committed. Optional view metadata cannot
            // undo that success or install a precommit/previous-context frame.
            if(!preview)PointTraderMarkStore.Offer(result,session);
            return Results.Ok(result);
        });
        api.MapPost("/market-values/preview",(HttpContext c,PointTraderMarkWriteRequest request)=>Write(c,request,true));
        api.MapPost("/market-values/record",(HttpContext c,PointTraderMarkWriteRequest request)=>Write(c,request,false));
        api.MapPost("/market-values/status",(HttpContext c,PointTraderMarkStatusRequest request)=>locked(c,async session=>
        {
            var result=await database.WithIdentity(profile(session),null,(connection,ct)=>store.Status(connection,request,ct),c.RequestAborted);
            PointTraderMarkStore.Offer(result,session);return Results.Ok(result);
        }));
        api.MapPost("/market-values/inputs",(HttpContext c,PointTraderMarkInputsRequest request)=>locked(c,async session=>
        {
            if(session.MarketContext is not null)throw new MarketDataException("point_trader_mark_inputs_unavailable","Return to current working data to use edited market inputs.");
            if(!session.Frames.TryGetValue(request.OriginalSnapshotId,out var original))
                throw new MarketDataException("point_trader_mark_inputs_unavailable","The original exact input selection is no longer in this session.");
            var edited=await database.WithIdentity(profile(session),null,(connection,ct)=>store.Inputs(connection,request,original,ct),c.RequestAborted);
            // Only the successful committed read may install the edited frame.
            // An existing identity may never be overwritten with other inputs.
            if(session.Frames.TryGetValue(edited.Id,out var existing))
            {
                if(PointTraderMarkInputSelection.Fingerprint(existing)!=PointTraderMarkInputSelection.Fingerprint(edited))
                    throw new MarketDataException("point_trader_mark_inputs_unavailable","This edited selection identity already has different inputs.");
            }
            else
            {
                if(session.Frames.Count>=PreviewSession.MaximumFrames)
                    throw new MarketDataException("point_trader_mark_inputs_unavailable","The session input catalog is full. The market value remains published.");
                session.Frames.Add(edited.Id,edited);
            }
            return Results.Ok(new{request.OperationId,request.OwnerId,request.SelectionId,request.OriginalSnapshotId,request.Fingerprint,
                frame=new NavigationFrame(edited.Id,edited.Name,edited.At,edited.BusinessDate)});
        }));
    }
}
