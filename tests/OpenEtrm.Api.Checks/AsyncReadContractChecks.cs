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
        // Operations no page requests are not kept on the allowlist; their ordinary routes remain.
        foreach(var unrequested in new[]{"trading.position.v1","portfolio.risk.statistical.setup.v1","portfolio.risk.parametric.calculate.v1",
            "portfolio.risk.parametric.summary.v1","portfolio.risk.historical.calculate.v1","portfolio.risk.historical.summary.v1",
            "portfolio.risk.historical.sample.v1","portfolio.risk.monte_carlo.calculate.v1"})
        {
            try{AsyncReadContract.Decode(Request(unrequested,new{context=new{snapshotId=snapshot,convention=TradingBlotter.Convention,knowledgeMode="current"}}));}
            catch(AsyncReadException e)when(e.Code=="async_operation"){continue;}
            throw new Exception($"{unrequested} has no page consumer and must not be an admitted asynchronous read.");
        }
        TypedInputs(snapshot,channel);
        Console.WriteLine("PASS async read contracts: typed allowlist, exact context, typed route inputs, authorized status reads and mutation refusal");
    }
    // An ordinary route supplies its already-typed body; it must be classified exactly as the same body decoded from the channel.
    static void TypedInputs(Guid snapshot,Guid channel)
    {
        var context=new{snapshotId=snapshot,convention=TradingBlotter.Convention,knowledgeMode="current"};
        var scope=new{scope=new{context}};
        foreach(var(operation,body)in new(string,object)[]{
            ("curve.evaluate.v1",new{snapshotId=snapshot,curve="synthetic"}),("curve.history.v1",new{snapshotId=snapshot,curve="synthetic"}),
            ("curve.shapes.v1",new{snapshotId=snapshot,curves=new[]{"synthetic"}}),
            ("trading.directory.v1",context),("trading.freshness.v1",context),("trading.positions.v1",new{context,bookIds=Array.Empty<Guid>(),portfolioIds=Array.Empty<Guid>(),offset=0,limit=64}),
            ("trading.workspace.v1",new{context}),("trading.blotter.v1",new{context}),("futures.editor.v1",new{context,tradeId=Guid.NewGuid()}),
            ("swaps.editor.v1",new{context,tradeId=Guid.NewGuid()}),("options.strategy.analyze.v1",OptionStrategyRequestChecks.Request()),
            ("portfolio.risk.scope.v1",new{context}),("portfolio.risk.catalog.v1",new{context}),
            ("portfolio.risk.calculate.v1",new{context}),("portfolio.risk.history.v1",scope),
            ("portfolio.risk.jobs.list.v1",new{}),("portfolio.risk.jobs.read.v1",new{id=Guid.NewGuid()}),
            ("portfolio.risk.archive.v1",new{method="statistical",limit=25})})
        {
            var decoded=AsyncReadContract.Decode(new(channel,Guid.NewGuid(),operation,JsonSerializer.SerializeToElement(body,AsyncReadContract.Json)));var typed=AsyncReadContract.Input(operation,decoded.Body);
            if(typed.Operation!=operation||typed.SnapshotId!=decoded.SnapshotId||!typed.Permissions.SequenceEqual(decoded.Permissions)||
                typed.Context!=decoded.Context||!ReferenceEquals(typed.Body,decoded.Body))
                throw new Exception($"A typed {operation} body must be classified as the same body decoded from the channel.");
        }
        foreach(var(operation,body,code)in new(string,object,string)[]{
            ("curve.evaluate.v1",new HistoryRequest(snapshot,"synthetic"),"async_request"),
            ("curve.evaluate.v1",new BuildRequest(Guid.Empty,"synthetic"),"async_request"),
            ("portfolio.risk.jobs.read.v1",new AsyncReadJob(Guid.Empty),"async_request"),
            ("portfolio.risk.archive.v1",new AsyncReadArchive("other",25,null,null),"async_request"),
            ("trades.book.v1",new FuturesReadRequest(snapshot,TradingBlotter.Convention,"current"),"async_operation")})
        {
            try{AsyncReadContract.Input(operation,body);}
            catch(AsyncReadException e)when(e.Code==code){continue;}
            throw new Exception($"A typed {operation} input of the wrong shape or without its exact selection must be refused {code}.");
        }
    }
}
