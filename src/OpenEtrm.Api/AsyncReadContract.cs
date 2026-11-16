using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Serialization;
using Npgsql;
using OpenEtrm.MarketData;

namespace OpenEtrm.Api;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record AsyncReadRequest(Guid ChannelId,Guid RequestId,string Operation,JsonElement Body);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record AsyncReadCancel(Guid ChannelId,Guid RequestId);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record AsyncReadOpenRequest([property:JsonRequired]Guid ClientId);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
internal sealed record AsyncReadEmpty;
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
internal sealed record AsyncReadJob(Guid Id);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
internal sealed record AsyncReadArchive(string Method,int Limit,string? Before,Guid? Id);
internal sealed record ReadInput(string Operation,object Body,Guid? SnapshotId,ImmutableArray<string> Permissions,FuturesReadRequest? Context=null);
internal sealed record ReadPlan(ReadInput Input,Func<CancellationToken,Task<ReadOutcome>> Execute);
internal sealed record ReadOutcome(object Value,Func<NpgsqlConnection,CancellationToken,Task> Recheck);
internal sealed class AsyncReadException(int status,string code,string message):Exception(message)
{
    internal int Status=>status;
    internal string Code=>code;
}

// Only named existing reads cross this transport. Body decoding stays typed;
// URLs, commands, retained-job submission and cancellation are not operations.
internal static class AsyncReadContract
{
    internal static readonly JsonSerializerOptions Json=new(JsonSerializerDefaults.Web)
    {AllowDuplicateProperties=false,Converters={new ExactDecimalJsonConverter()}};
    internal static ReadInput Decode(AsyncReadRequest request)
    {
        if(request.Body.ValueKind!=JsonValueKind.Object)throw Invalid();
        T Body<T>()=>request.Body.Deserialize<T>(Json)??throw Invalid();
        ReadInput Market(object body,Guid snapshot)=>snapshot!=Guid.Empty?
            new(request.Operation,body,snapshot,["ReadMarketData"]):throw Invalid();
        ReadInput Trading(object body,FuturesReadRequest? context,bool risk=false)=>context is {SnapshotId:var snapshot}&&snapshot!=Guid.Empty?
            new(request.Operation,body,snapshot,risk?["ReadTrades","ReadMarketData","RunScenario"]:["ReadTrades","ReadMarketData"],context):throw Invalid();
        switch(request.Operation)
        {
            case "curve.evaluate.v1":var evaluate=Body<BuildRequest>();return Market(evaluate,evaluate.SnapshotId);
            case "curve.history.v1":var history=Body<HistoryRequest>();return Market(history,history.SnapshotId);
            case "curve.shapes.v1":var shapes=Body<CurveShapesRequest>();return Market(shapes,shapes.SnapshotId);
            case "trading.directory.v1":case "trading.freshness.v1":var directory=Body<FuturesReadRequest>();return Trading(directory,directory);
            case "trading.positions.v1":var positions=Body<TradingPositionsRequest>();return Trading(positions,positions.Context);
            case "trading.position.v1":var position=Body<TradePositionReadRequest>();return Trading(position,position.Context);
            case "trading.workspace.v1":var workspace=Body<TradingWorkspaceRequest>();return Trading(workspace,workspace.Context);
            case "trading.blotter.v1":var blotter=Body<FuturesBlotterRequest>();return Trading(blotter,blotter.Context);
            case "futures.editor.v1":var future=Body<FuturesEditorRequest>();return Trading(future,future.Context);
            case "swaps.editor.v1":var swap=Body<SwapEditorRequest>();return Trading(swap,swap.Context);
            case "options.strategy.analyze.v1":var strategy=Body<OptionStrategyAnalyzeRequest>();return Trading(strategy,strategy.Context);
            case "portfolio.risk.scope.v1":var scope=Body<RiskScopeRequest>();return Trading(scope,scope.Context,true);
            case "portfolio.risk.catalog.v1":case "portfolio.risk.statistical.setup.v1":var catalog=Body<PortfolioRiskCatalogRequest>();return Trading(catalog,catalog.Context,true);
            case "portfolio.risk.calculate.v1":var risk=Body<PortfolioRiskRequest>();return Trading(risk,risk.Context,true);
            case "portfolio.risk.history.v1":var riskHistory=Body<PortfolioHistoryRequest>();return Trading(riskHistory,riskHistory.Scope?.Context,true);
            case "portfolio.risk.parametric.calculate.v1":case "portfolio.risk.parametric.summary.v1":var parametric=Body<PortfolioParametricRequest>();return Trading(parametric,parametric.History?.Scope?.Context,true);
            case "portfolio.risk.historical.calculate.v1":case "portfolio.risk.historical.summary.v1":var historical=Body<PortfolioHistoricalRequest>();return Trading(historical,historical.History?.Scope?.Context,true);
            case "portfolio.risk.historical.sample.v1":var sample=Body<PortfolioHistoricalSampleRequest>();return Trading(sample,sample.Request?.History?.Scope?.Context,true);
            case "portfolio.risk.monte_carlo.calculate.v1":var monteCarlo=Body<PortfolioMonteCarloRequest>();return Trading(monteCarlo,monteCarlo.History?.Scope?.Context,true);
            case "portfolio.risk.jobs.list.v1":return new(request.Operation,Body<AsyncReadEmpty>(),null,["RunScenario"]);
            case "portfolio.risk.jobs.read.v1":var job=Body<AsyncReadJob>();return job.Id!=Guid.Empty?new(request.Operation,job,null,["RunScenario"]):throw Invalid();
            case "portfolio.risk.archive.v1":
                var archive=Body<AsyncReadArchive>();
                if(archive.Method is not("statistical" or "parametric" or "historical" or "monte_carlo")||archive.Limit is <1 or >100||
                    (archive.Before is null)!=(archive.Id is null)||archive.Id==Guid.Empty)throw Invalid();
                if(archive.Before is not null)_=SchedulePreview.ParseAt(archive.Before);
                return new(request.Operation,archive,null,["RunScenario"]);
            default:throw new AsyncReadException(422,"async_operation","This operation is not an admitted asynchronous read.");
        }
    }
    internal static AsyncReadException Invalid()=>new(422,"async_request","Supply the complete typed read request and its exact selected context.");
}
