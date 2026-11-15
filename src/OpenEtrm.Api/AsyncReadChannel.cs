using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Channels;
using Npgsql;
using OpenEtrm.MarketData;
using OpenEtrm.Shared.Temporal;

namespace OpenEtrm.Api;

internal sealed record AsyncReadError(string Code,string Message);
internal sealed record AsyncReadCompletion(AsyncReadRequest Request,AsyncReadPlan Plan,string State,JsonElement? Result,AsyncReadError? Error,
    Func<NpgsqlConnection,CancellationToken,Task>? Recheck=null);

// Ephemeral reads for the workbench. This channel retains request hashes,
// never durable outcomes, and owns every worker until cancellation and completion.
internal sealed class AsyncReadChannel:IAsyncDisposable
{
    internal const string Protocol="async_reads_v1";
    internal const int MaximumActive=2,MaximumRequests=128,MaximumRequestBytes=32*1024,MaximumResultBytes=16*1024*1024;
    internal static readonly TimeSpan Lifetime=TimeSpan.FromMinutes(5),ReadLimit=TimeSpan.FromSeconds(60);
    readonly object gate=new();
    readonly CancellationTokenSource lifetime;
    readonly CancellationToken stopping;
    readonly Channel<AsyncReadCompletion> responses=Channel.CreateBounded<AsyncReadCompletion>(new BoundedChannelOptions(MaximumActive){SingleReader=true,FullMode=BoundedChannelFullMode.Wait});
    readonly Dictionary<Guid,Pending> requests=[];
    bool connected,closed;
    Task? disposal;
    int active;
    internal Guid Id{get;}
    internal bool Closed=>closed||stopping.IsCancellationRequested;
    internal CancellationToken Stopping=>stopping;
    internal AsyncReadChannel(Guid id,CancellationToken applicationStopping)
    {
        Id=id;lifetime=CreateLifetime(applicationStopping);stopping=lifetime.Token;
    }
    sealed class Pending(string hash,CancellationTokenSource cancellation)
    {
        internal string Hash=>hash;
        internal CancellationTokenSource Cancellation=>cancellation;
        internal Task Work=Task.CompletedTask;
    }
    static CancellationTokenSource CreateLifetime(CancellationToken stopping)
    {
        var result=CancellationTokenSource.CreateLinkedTokenSource(stopping);result.CancelAfter(Lifetime);return result;
    }
    internal void Connect()
    {
        lock(gate){RequireOpen();if(connected)throw Refusal(409,"async_channel_connected","This response channel already has a listener.");connected=true;}
    }
    internal static void Validate(AsyncReadRequest request)
    {
        if(request.ChannelId==Guid.Empty||request.RequestId==Guid.Empty)throw AsyncReadContract.Invalid();
        _=AsyncReadContract.Decode(request);
        if(JsonSerializer.SerializeToUtf8Bytes(request,JsonSerializerOptions.Web).Length>MaximumRequestBytes)
            throw Refusal(413,"async_request_size","The read request exceeds the request limit.");
    }
    internal void Submit(AsyncReadRequest request,AsyncReadPlan plan)
    {
        Validate(request);
        if(request.ChannelId!=Id||request.Operation!=plan.Input.Operation)throw Refusal(422,"async_request","The request and selected input frame must match.");
        var decoded=AsyncReadContract.Decode(request);
        var hash=Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(new
        {request.ChannelId,request.RequestId,request.Operation,Body=decoded.Body},AsyncReadContract.Json)));
        lock(gate)
        {
            RequireOpen();
            if(!connected)throw Refusal(409,"async_channel_not_ready","Connect the response stream before submitting reads.");
            if(requests.TryGetValue(request.RequestId,out var prior))
            {
                if(prior.Hash!=hash)throw Refusal(409,"async_request_conflict","This request identity already names different inputs.");
                return;
            }
            if(requests.Count>=MaximumRequests)throw Refusal(429,"async_channel_limit","Open a fresh response channel after this channel's requests complete.");
            if(active>=MaximumActive)throw Refusal(429,"async_busy","This response channel already has two active reads.");
            var cancellation=CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);cancellation.CancelAfter(ReadLimit);
            var pending=new Pending(hash,cancellation);requests.Add(request.RequestId,pending);active++;
            // Task.Run also keeps synchronous graph evaluation off the HTTP submission path.
            pending.Work=Task.Run(()=>Evaluate(request,plan,pending));
        }
    }
    async Task Evaluate(AsyncReadRequest request,AsyncReadPlan plan,Pending pending)
    {
        AsyncReadCompletion completion;
        try
        {
            using var visibility=new AsyncReadVisibility();
            var outcome=await plan.Execute(pending.Cancellation.Token);pending.Cancellation.Token.ThrowIfCancellationRequested();
            var bytes=JsonSerializer.SerializeToUtf8Bytes(outcome.Value,AsyncReadContract.Json);
            if(bytes.Length>MaximumResultBytes)throw Refusal(422,"async_result_size","The read result exceeds the response limit.");
            using var json=JsonDocument.Parse(bytes);
            var evidence=visibility.Seal();var recheck=outcome.Recheck;
            completion=new(request,plan,"completed",json.RootElement.Clone(),null,async(connection,ct)=>
            {
                await recheck(connection,ct);await evidence.Require(connection,ct);
            });
        }
        catch(OperationCanceledException){completion=new(request,plan,"cancelled",null,new("request_cancelled","The read was cancelled or exceeded its time limit."));}
        catch(Exception e){completion=new(request,plan,"failed",null,Error(e));}
        lock(gate)
        {
            active--;
            if(!Closed&&!responses.Writer.TryWrite(completion))Close();
        }
    }
    internal void Cancel(Guid requestId)
    {
        lock(gate)
        {
            RequireOpen();
            if(!requests.TryGetValue(requestId,out var pending))throw Refusal(404,"async_request_missing","This response channel has no such request.");
            pending.Cancellation.Cancel();
        }
    }
    internal async Task<AsyncReadCompletion> Read(CancellationToken ct)=>await responses.Reader.ReadAsync(ct);
    internal ChannelReader<AsyncReadCompletion> Responses=>responses.Reader;
    internal void Close()
    {
        lock(gate){if(closed)return;closed=true;lifetime.Cancel();responses.Writer.TryComplete();}
    }
    public ValueTask DisposeAsync()
    {
        lock(gate)
        {
            // Stream shutdown and explicit replacement can retire the same channel
            // concurrently. Every caller must await the same worker drain.
            if(disposal is null){Close();disposal=Drain([..requests.Values]);}
            return new(disposal);
        }
    }
    async Task Drain(Pending[] pending)
    {
        await Task.WhenAll(pending.Select(request=>request.Work));
        foreach(var request in pending)request.Cancellation.Dispose();
        lifetime.Dispose();
    }
    void RequireOpen(){if(Closed)throw Refusal(410,"async_channel_unavailable","This response channel ended. Open a new channel and explicitly request the read again.");}
    internal static AsyncReadException Refusal(int status,string code,string message)=>new(status,code,message);
    internal static AsyncReadError Error(Exception e)
    {
        AsyncReadError error=e switch
        {
            AsyncReadException a=>new(a.Code,a.Message),
            MarketDataException m=>new(m.Code,m.Message),
            TemporalException t=>new(t.Code,t.Message),
            PreviewDeniedException or PreviewSessionEnded=>new("access_denied","Current authorization no longer permits this read."),
            PostgresException p when p.SqlState=="42501"=>new("access_denied","Current authorization no longer permits this read."),
            _=>new("async_read_failed","The read could not be completed.")
        };
        return error.Code.Length<=128&&error.Message.Length<=1000?error:new("async_read_failed","The read could not be completed.");
    }
}
