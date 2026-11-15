using System.Collections.Immutable;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace OpenEtrm.MarketData.Power;

public sealed partial class PowerClock
{
    private const string GridClockVersion="captured_power_grid_clock_v1";
    private static readonly TimeSpan NativeCell=TimeSpan.FromMinutes(5);
    [JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
    private sealed record OffsetRun(DateTimeOffset From,int Minutes);
    [JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
    private sealed record GridClock(string Implementation,string Id,DateTimeOffset From,DateTimeOffset To,ImmutableArray<OffsetRun> Runs);
    private readonly GridClock? captured;
    private readonly Dictionary<(DateOnly,DateOnly),PowerClock> captures=new();
    private PowerClock(GridClock captured,string? publishedRules=null)
    {
        this.captured=captured;
        Rules=publishedRules??JsonSerializer.Serialize(captured);
        Fingerprint=Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(Rules)));
    }
    // Captures the complete finest supported native grid, then compresses equal
    // offsets. No timezone rule projection is deserialized or inferred on replay.
    public PowerClock CaptureForDelivery(DateOnly from,DateOnly to)
    {
        if(from>=to||from.Year<2000||to>new DateOnly(2100,1,1))throw CapturedError();
        if(captured is not null)
        {
            _=StartOfDay(from);_=StartOfDay(to);return this;
        }
        lock(captures)
        {
            if(captures.TryGetValue((from,to),out var prior))return prior;
            RequireNativeTransitions(from,to);
            var start=StartOfDay(from).ToUniversalTime();var end=StartOfDay(to).ToUniversalTime();
            if((end-start).Ticks%NativeCell.Ticks!=0)throw CapturedError();
            var runs=ImmutableArray.CreateBuilder<OffsetRun>();int? previous=null;
            for(var at=start;at<end;at+=NativeCell)
            {
                if(!PowerHours.IsCell(this,at,NativeCell))throw CapturedError();
                var offset=checked((int)LocalAt(at).Offset.TotalMinutes);
                if(previous!=offset){runs.Add(new(at,offset));previous=offset;}
            }
            // The exclusive endpoint is retained for period-boundary inversion.
            var final=checked((int)LocalAt(end).Offset.TotalMinutes);
            if(previous!=final)runs.Add(new(end,final));
            var result=new PowerClock(new GridClock(GridClockVersion,Id,start,end,runs.ToImmutable()));
            if(result.StartOfDay(from).ToUniversalTime()!=start||result.StartOfDay(to).ToUniversalTime()!=end)throw CapturedError();
            captures.Add((from,to),result);return result;
        }
    }
    private void RequireNativeTransitions(DateOnly from,DateOnly to)
    {
        // Sampling equal offsets at both ends cannot detect two changes inside a
        // cell. Require the source's transition grammar to fit the native grid
        // before sampling it. BCL IANA end rules may name the final millisecond
        // before the transition instead of the following cell boundary.
        static bool Aligned(DateTime value,bool inclusiveEnd=false)=>value.TimeOfDay.Ticks%NativeCell.Ticks==0||
            inclusiveEnd&&(value.TimeOfDay.Ticks+TimeSpan.TicksPerMillisecond)%NativeCell.Ticks==0;
        foreach(var rule in Zone!.GetAdjustmentRules().Where(r=>DateOnly.FromDateTime(r.DateEnd)>=from.AddDays(-1)&&
            DateOnly.FromDateTime(r.DateStart)<=to.AddDays(1)))
            if(rule.DaylightDelta.Ticks%NativeCell.Ticks!=0||rule.BaseUtcOffsetDelta.Ticks%NativeCell.Ticks!=0||
                !Aligned(rule.DateStart)||!Aligned(rule.DateEnd,true)||
                rule.DaylightDelta!=TimeSpan.Zero&&(!Aligned(rule.DaylightTransitionStart.TimeOfDay)||!Aligned(rule.DaylightTransitionEnd.TimeOfDay,true)))
                throw CapturedError();
    }
    public static PowerClock Restore(string rules,string fingerprint)
    {
        if(string.IsNullOrEmpty(rules)||rules.Length>65536||
            Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(rules)))!=fingerprint)throw CapturedError();
        try
        {
            using var document=JsonDocument.Parse(rules);
            static bool DistinctProperties(JsonElement element)=>element.ValueKind switch
            {
                JsonValueKind.Object=>element.EnumerateObject().Select(p=>p.Name).Distinct(StringComparer.Ordinal).Count()==element.EnumerateObject().Count()&&
                    element.EnumerateObject().All(p=>DistinctProperties(p.Value)),
                JsonValueKind.Array=>element.EnumerateArray().All(DistinctProperties),
                _=>true
            };
            if(!DistinctProperties(document.RootElement))throw CapturedError();
            var value=document.Deserialize<GridClock>();
            if(value is null||value.Implementation!=GridClockVersion||string.IsNullOrWhiteSpace(value.Id)||value.Id.Length>256||
                value.From.Offset!=TimeSpan.Zero||value.To.Offset!=TimeSpan.Zero||value.From.Ticks%TimeSpan.TicksPerMinute!=0||
                value.To.Ticks%TimeSpan.TicksPerMinute!=0||value.From>=value.To||value.To-value.From>TimeSpan.FromDays(36600)||
                value.Runs.IsDefaultOrEmpty||value.Runs.Length>4096||value.Runs[0] is null||value.Runs[0].From!=value.From||value.Runs.Where((r,n)=>r is null||
                    r.From.Offset!=TimeSpan.Zero||r.From<value.From||r.From>value.To||(r.From-value.From).Ticks%NativeCell.Ticks!=0||
                    r.Minutes is <-840 or >840||n>0&&(value.Runs[n-1].From>=r.From||value.Runs[n-1].Minutes==r.Minutes)).Any())throw CapturedError();
            // Preserve the exact authorized publication bytes, including harmless JSON whitespace.
            return new PowerClock(value,rules);
        }
        catch(Exception error)when(error is JsonException or ArgumentException or OverflowException)
        {throw CapturedError();}
    }
    public DateTimeOffset LocalAt(DateTimeOffset instant)
    {
        if(captured is not {} grid)return TimeZoneInfo.ConvertTime(instant,Zone!);
        if(instant<grid.From||instant>grid.To)throw CapturedError();
        var low=0;var high=grid.Runs.Length;
        while(low+1<high){var middle=(low+high)/2;if(grid.Runs[middle].From<=instant)low=middle;else high=middle;}
        return instant.ToOffset(TimeSpan.FromMinutes(grid.Runs[low].Minutes));
    }
    private ImmutableArray<DateTimeOffset> LocalCandidates(DateTime local)
    {
        var grid=captured??throw CapturedError();
        return [..grid.Runs.Select(r=>r.Minutes).Distinct().Select(offset=>new DateTimeOffset(local,TimeSpan.FromMinutes(offset)))
            .Where(at=>at>=grid.From&&at<=grid.To&&LocalAt(at).DateTime==local).OrderBy(at=>at)];
    }
    internal bool ConstantOffset(DateTimeOffset from,DateTimeOffset to)=>captured is {} grid
        ? !grid.Runs.Any(r=>r.From>from&&r.From<to)
        : LocalAt(from).Offset==LocalAt(to.AddTicks(-1)).Offset;
    public int Occurrence(DateTimeOffset instant)
    {
        var local=LocalAt(instant);
        if(captured is not null)
        {
            var candidates=LocalCandidates(local.DateTime);
            for(var n=0;n<candidates.Length;n++)if(candidates[n]==instant)return n+1;
            throw CapturedError();
        }
        return Zone!.IsAmbiguousTime(local.DateTime)&&local.Offset!=Zone.GetAmbiguousTimeOffsets(local.DateTime).Max()?2:1;
    }
    private static MarketDataException CapturedError()=>new("clock_rule","Supply intact captured clock cells covering the contractual interval and unambiguous local boundaries.");
}
