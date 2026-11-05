using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json.Serialization;
using System.Text.Json;
using Npgsql;

namespace OpenEtrm.Api;

// A conservative equality token, never a read authorization. Its input head is sampled before a valuation starts;
// a publication during that valuation therefore forces a new read at the next validation rather than being missed.
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record BlotterChangesRequest([property:JsonRequired] FuturesReadRequest Context,[property:JsonRequired] string Version);

internal static class BlotterFreshness
{
    // Notifications are hints. The durable authorized head is checked before waiting
    // and after every wake/timeout; neither a DB connection nor a session gate waits.
    internal static async Task<string> Wait(CalculationChanges changes,string expected,Func<Task<string>> read,CancellationToken ct)
    {
        if(expected is null||expected.Length!=64||expected.Any(c=>!char.IsAsciiHexDigitLower(c)))
            throw new OpenEtrm.MarketData.MarketDataException("blotter_version","Supply the exact server version being displayed.");
        var subscription=changes.Subscribe();var started=Stopwatch.GetTimestamp();
        try
        {
            while(true)
            {
                var version=await read();var remaining=TimeSpan.FromSeconds(8)-Stopwatch.GetElapsedTime(started);
                if(version!=expected||remaining<=TimeSpan.Zero)return version;
                using var wake=CancellationTokenSource.CreateLinkedTokenSource(ct);wake.CancelAfter(remaining);
                try{await subscription.Reader.ReadAsync(wake.Token);}
                catch(OperationCanceledException)when(!ct.IsCancellationRequested){}
                while(subscription.Reader.TryRead(out _)){}
            }
        }
        finally{changes.Remove(subscription.Id);}
    }
    // A server restart/release cannot validate values made by another running implementation.
    static readonly Guid instance=Guid.NewGuid();
    internal static async Task<string> Read(NpgsqlConnection connection,PreviewManifest manifest,FuturesReadRequest request,
        TradingReadSelection selection,CancellationToken ct)
    {
        await using var command=ScheduleStore.Command(connection,"SELECT security.blotter_head($1)",manifest.CatalogId);
        var head=(string)(await command.ExecuteScalarAsync(ct)??throw new PreviewDeniedException());
        var inputs=JsonSerializer.SerializeToUtf8Bytes(new{instance,head,manifest,request,selection.Profile,selection.Frame,selection.SelectedContext,selection.Live});
        return Convert.ToHexStringLower(SHA256.HashData(inputs));
    }
}
