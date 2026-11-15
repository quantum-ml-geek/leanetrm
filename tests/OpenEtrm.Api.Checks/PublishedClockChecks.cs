using System.Text.Json;
using OpenEtrm.Api;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power;

internal static class PublishedClockChecks
{
    internal static void Run()
    {
        var source=PowerClock.Capture(TimeZoneInfo.FindSystemTimeZoneById("Australia/Sydney")).CaptureForDelivery(new(2027,1,1),new(2027,2,1));
        var payload=source.Rules.Replace("Australia/Sydney","Synthetic/Unavailable",StringComparison.Ordinal);
        var digest=Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(payload)));
        var rule=new ClockRule("synthetic_clock","iana",null,"Synthetic/Unavailable","synthetic_release");
        JsonElement Row(string from="2027-01-01",string to="2027-02-01",string? hash=null)=>JsonSerializer.SerializeToElement(new{
            clock_code="synthetic_clock",coverage_from=from,coverage_to=to,payload,definition_digest="\\x"+(hash??digest),tzdb_version="synthetic_release"});
        void Reject(string code,Action action){try{action();}catch(MarketDataException e)when(e.Code==code){return;}throw new Exception("Expected "+code);}
        Reject("clock_reference",()=>PublishedClocks.Resolve([],rule));
        var restored=PublishedClocks.Resolve([Row()],rule);
        foreach(var invalid in new[]{payload.Replace("\"Minutes\":660","\"Minutes\":660e0",StringComparison.Ordinal),
            payload.Replace("T13:00:00"," 13:00:00",StringComparison.Ordinal),
            payload.Replace("T13:00:00","T13:00:00.0000001",StringComparison.Ordinal),
            payload.Replace("\"Minutes\":660","\"Minutes\":660,\"Minutes\":660",StringComparison.Ordinal),
            payload.Replace("\"Implementation\":","\"Implementation\":\"captured_power_grid_clock_v1\",\"Implementation\":",StringComparison.Ordinal)})
        {
            if(invalid==payload)throw new Exception("The malformed clock fixture did not change its wire token.");
            var hash=Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(invalid)));
            Reject("clock_rule",()=>PowerClock.Restore(invalid,hash));
        }
        if(restored.StartOfDay(new(2027,2,1)).ToUniversalTime()!=DateTimeOffset.Parse("2027-01-31T13:00:00Z"))throw new Exception("Published replay must preserve its captured offset without an installed source.");
        Reject("clock_rule",()=>PublishedClocks.Resolve([Row(hash:new string('0',64))],rule));
        Reject("clock_reference",()=>PublishedClocks.Resolve([Row(),Row()],rule));
        Reject("clock_reference",()=>PublishedClocks.Resolve([Row()],rule with{TzdbVersion="changed"}));
        Reject("clock_reference",()=>PublishedClocks.Resolve([Row(to:"2027-01-31")],rule));
        var spaced=System.Text.Json.Nodes.JsonNode.Parse(Row().GetRawText())!;
        var publishedBytes=payload+" ";
        spaced["payload"]=publishedBytes;
        spaced["definition_digest"]="\\x"+Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(publishedBytes)));
        var exact=PublishedClocks.Resolve([JsonSerializer.SerializeToElement(spaced)],rule);
        if(exact.Rules!=publishedBytes||exact.StartOfDay(new(2027,2,1)).ToUniversalTime()!=DateTimeOffset.Parse("2027-01-31T13:00:00Z"))
            throw new Exception("Replay must preserve the exact published bytes and their independently specified clock boundary.");
        var request=new ClockCaptureRequest(Guid.NewGuid(),Guid.NewGuid(),new(2027,1,1),new(2027,2,1),[new("synthetic_fixed","fixed_offset",39600,null,null)]);
        var sql=ClockCapturePublication.Render(request);
        if(!sql.Contains("2026-12-31T13:00:00+00:00")||!sql.Contains("2027-01-31T13:00:00+00:00")||!sql.Contains("SELECT ref_data.publish_clock_capture"))
            throw new Exception("Publication must retain the independently specified UTC bounds and exact source reference.");
        Reject("clock_capture",()=>ClockCapturePublication.Render(request with{Clocks=[request.Clocks[0],request.Clocks[0]]}));
        Console.WriteLine("PASS published clock replay: unavailable source, exact UTC boundaries, tampered payload/release and coverage refusal");
    }
}
