using System.Collections.Immutable;
using Npgsql;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

internal sealed class RecScheduleSource(PreviewDatabase database):IBookedScheduleSource
{
    public ImmutableArray<string> InstrumentTypes=>[RecPositions.Type];
    public async Task<BookedSchedulePosition> Open(NpgsqlConnection connection,TradingView view,TradePositionSelection selected,CancellationToken ct)
    {
        async Task<RecPosition> Position(CancellationToken token)=>(await RecPositions.Read(connection,database.Manifest,[],[],token,selected)).Single();
        var position=await Position(ct);var retained=new RetainedScheduleStore(database);
        async Task<ImmutableArray<BookedScheduleSide>> Directory(CancellationToken token)=>BookedScheduleSources.Headers(
            await retained.Directory(connection,position.Binding,view.CalculationFrame.ContextId,view.CalculationFrame.At,token),[]);
        var headers=await Directory(ct);
        async Task<SideScheduleSnapshot> Evaluate(int slot,string? window,CancellationToken token)
        {
            var frame=view.CalculationFrame;var data=await MarketInputSelection.Resolve(database,connection,frame,
                new(position.Definition,position.Reference.CatalogId,position.Reference.RevisionId),[],false,token);
            SideScheduleSnapshot? result=null;
            try
            {
                await new RecForwardStore(database).EvaluatePrograms(connection,data.Data,data.Frame,position,token,(index,input)=>
                {
                    if(index==slot)result=SideScheduleSnapshot.FromProgram(headers.Single(h=>h.Slot==slot).SideId,frame.Id,input,BookedScheduleSources.Utc);
                },slot);
                return result??throw BookedScheduleSources.Missing();
            }
            catch(MarketDataException error)when(error.Code is "rec_delivery_lifecycle" or "operating_delivery_lifecycle" or "side_payment_due")
            {
                var program=(await retained.LoadPrograms(connection,position.Binding,frame.ContextId,frame.At,token)).Single(p=>p.Slot==slot);
                return SideScheduleSnapshot.Plan(program.SideId,frame.Id,frame.ContextId!.Value,$"side_{slot}",program.Program,
                    BookedScheduleSources.Utc,frame.At,SchedulePreview.ParseAt(view.Context.KnownAt),error.Code);
            }
        }
        async Task Recheck(CancellationToken token)
        {
            if((await Position(token)).Binding!=position.Binding)throw TradePositionSelection.Unavailable();
            BookedScheduleSources.RequireSame(headers,await Directory(token));
        }
        return new(selected,position.Binding,headers,Evaluate,Recheck);
    }
}
