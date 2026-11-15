using System.Text.Json;
using OpenEtrm.Api;

internal static class AsyncReadContractChecks
{
    internal static void Run()
    {
        var snapshot=Guid.NewGuid();var channel=Guid.NewGuid();
        var client=Guid.NewGuid();
        if(JsonSerializer.Deserialize<AsyncReadOpenRequest>(JsonSerializer.Serialize(new{clientId=client}),AsyncReadContract.Json)?.ClientId!=client)
            throw new Exception("Channel opening must retain the exact page client identity.");
        try{JsonSerializer.Deserialize<AsyncReadOpenRequest>("{}",AsyncReadContract.Json);throw new Exception("A channel must not silently choose a client identity shared by other pages.");}
        catch(JsonException){}
        AsyncReadRequest Request(string operation,object body)=>new(channel,Guid.NewGuid(),operation,JsonSerializer.SerializeToElement(body,JsonSerializerOptions.Web));
        var curve=AsyncReadContract.Decode(Request("curve.evaluate.v1",new BuildRequest(snapshot,"synthetic",true,true,new(CurveDisplay.Version,CurveDisplay.Live))));
        if(curve.SnapshotId!=snapshot||curve.Body is not BuildRequest{IncludeWorkspace:true})throw new Exception("The ordinary curve workspace projection must retain its exact explicit request over SSE.");
        var directory=AsyncReadContract.Decode(Request("trading.directory.v1",new FuturesReadRequest(snapshot,TradingBlotter.Convention,"current")));
        if(directory.SnapshotId!=snapshot||!directory.Permissions.Contains("ReadTrades"))throw new Exception("Directory reads must retain their direct context and trading authorization.");
        var jobs=AsyncReadContract.Decode(Request("portfolio.risk.jobs.list.v1",new {}));
        if(jobs.SnapshotId is not null||!jobs.Permissions.Contains("RunScenario"))throw new Exception("Retained job status must not invent a market snapshot or lose its risk permission.");
        foreach(var forbidden in new[]{"portfolio.risk.jobs.submit.v1","portfolio.risk.jobs.cancel.v1","trades.book.v1","/api/evaluate"})
        {
            try{AsyncReadContract.Decode(Request(forbidden,new {}));}
            catch(AsyncReadException e)when(e.Code=="async_operation"){continue;}
            throw new Exception("The async read allowlist must never accept writes or arbitrary routes.");
        }
        Console.WriteLine("PASS async read contracts: typed allowlist, exact context, authorized status reads and mutation refusal");
    }
}
