using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Nodes;
using Npgsql;
using OpenEtrm.Api;
using OpenEtrm.MarketData;

// Market and reference reads run without an HTTP request or workspace session. Given the
// pinned context a page used, a direct caller receives exactly the page's read, and each read
// binds exactly its pin: a retained context for the request, or nothing for working data.
internal static class MarketReadChecks
{
    static readonly JsonSerializerOptions Json=new(JsonSerializerDefaults.Web){Converters={new ExactDecimalJsonConverter()}};

    public static async Task Run(string fixturePath)
    {
        await using var database=new PreviewDatabase(Path.GetFullPath(Environment.GetEnvironmentVariable("OPENETRM_PREVIEW_ROOT")
            ??throw new InvalidOperationException("Run through tools/run_preview.py.")));
        var reads=new MarketReads(database);
        using var fixture=JsonDocument.Parse(File.ReadAllText(fixturePath));
        var profile=fixture.RootElement.GetProperty("profile").GetString()!;
        var views=fixture.RootElement.GetProperty("views").EnumerateArray().Select(v=>new View(v)).ToArray();
        var (working,historical)=(views.Single(v=>v.Context is null),views.Single(v=>v.Context is not null));
        Task<T> Read<T>(Func<NpgsqlConnection,CancellationToken,Task<T>> read)=>database.WithIdentity(profile,"ReadMarketData",read,CancellationToken.None);
        // A request binds a market context at most once, so a second bind shows whether the read bound one.
        Task<T> Direct<T>(View view,string name,Func<NpgsqlConnection,CancellationToken,Task<T>> read)=>Read(async(c,ct)=>
        {
            var value=await read(c,ct);
            await Execute(c,"SAVEPOINT bind_probe",ct);
            var bound=false;
            try{await MarketContextStore.Bind(c,database.Manifest.CatalogId,historical.Context!,ct);}
            catch(PostgresException e) when(e.SqlState=="42501"&&e.MessageText.Contains("exactly once",StringComparison.Ordinal))
            {bound=true;await Execute(c,"ROLLBACK TO SAVEPOINT bind_probe",ct);}
            if(bound!=(view.Context is not null))throw new Exception($"{view.Name} {name} did not bind exactly its pin.");
            return value;
        });
        foreach(var view in views)
        {
            var catalog=await Direct(view,"catalog",(c,ct)=>reads.Workspace(c,view.Pin(),true,ct));
            var full=await Direct(view,"workspace",(c,ct)=>reads.Workspace(c,view.Pin(),false,ct));
            foreach(var (read,page) in new[]{(catalog,view.Page("catalog")),(full,view.Page("workspace"))})
                Same($"{view.Name} workspace data matches its page",new{definitions=read.Data.Definitions,references=read.Data.References,observations=read.Data.Observations,unitCatalog=read.Units,curveNames=read.CurveNames},
                    page,"definitions","references","observations","unitCatalog","curveNames");
            Same($"{view.Name} curve names match their page",await Direct(view,"curve names",(c,ct)=>reads.CurveNames(c,view.Pin(),ct)),view.Page("curveNames"));
            Same($"{view.Name} reference page matches its page",await Direct(view,"reference page",(c,ct)=>reads.References(c,view.Pin(),"currencies",0,"",ct)),view.Page("references"),
                "table","rows","references","offset","pageSize","maximumOffset","hasMore","search","referenceRevision","definitionRevisionId");
            foreach(var curve in view.Page("evaluations").AsObject())
                Same($"{view.Name} {curve.Key} prices match their page",(await Direct(view,"prices",(c,ct)=>reads.Evaluate(c,view.Pin(view.Selected),curve.Key,ct))).Result,
                    Without(curve.Value!.AsObject(),"context"));
            var history=view.Page("history");
            Same($"{view.Name} history matches its page",await Direct(view,"history",(c,ct)=>reads.History(c,view.Pin(view.Selected),view.Initial,history["curve"]!.GetValue<string>(),history["contractId"]!.GetValue<Guid>(),null,ct)),
                history["response"]!["points"]);
            Console.WriteLine($"PASS {view.Name} reads bind exactly their pin");
        }
        var effective=DateWorkspace.Date(historical.Context!.EffectiveOn);
        bool Later(WorkspaceRead read)=>read.Data.Observations.Any(o=>DateOnly.FromDateTime(o.Instant("observed_at").UtcDateTime)>effective);
        if(!Later(await Read((c,ct)=>reads.Workspace(c,working.Pin(),false,ct)))||Later(await Read((c,ct)=>reads.Workspace(c,historical.Pin(),false,ct))))
            throw new Exception("A direct retained read must hide observations after its effective date that working data shows.");
        Console.WriteLine("PASS a direct retained read hides observations after its effective date");
        await Rejects("snapshot_missing","a frame-consuming read refuses a pin without a frame",()=>Read((c,ct)=>reads.Evaluate(c,working.Pin(),"local_power",ct)));
        await Rejects("snapshot_missing","a retained pin refuses a working frame",()=>Task.FromResult(PinnedContext.Retained(historical.Context!,working.Selected)));
        await Rejects("snapshot_missing","a working pin refuses a retained frame",()=>Task.FromResult(PinnedContext.Current(historical.Selected)));
        await Rejects("snapshot_missing","history refuses a frame outside its pinned context",()=>Read((c,ct)=>reads.History(c,historical.Pin(historical.Selected),[..historical.Initial,working.Selected],"local_power",null,null,ct)));
        var earlier=historical.Frames.Where(f=>DateOnly.FromDateTime(f.At.UtcDateTime)!=effective).MinBy(f=>f.At)
            ??throw new Exception("The historical fixture needs a frame before its effective date.");
        await Rejects("market_date","a retained pin prices only its effective market date",()=>Read((c,ct)=>reads.Evaluate(c,historical.Pin(earlier),"local_power",ct)));
    }

    sealed class View(JsonElement view)
    {
        public string Name {get;}=view.GetProperty("name").GetString()!;
        public ScheduleContext? Context {get;}=view.GetProperty("context").ValueKind==JsonValueKind.Object?view.GetProperty("context").Deserialize<ScheduleContext>(Json):null;
        public ImmutableArray<InputFrame> Frames {get;}=view.GetProperty("frames").Deserialize<ImmutableArray<InputFrame>>(Json);
        public InputFrame Selected=>Frames.Single(f=>f.Id==view.GetProperty("frameId").GetGuid());
        // The page's initial frames are the frames its history rebuilds.
        public ImmutableArray<InputFrame> Initial=>[..view.GetProperty("initialFrameIds").EnumerateArray().Select(id=>Frames.Single(f=>f.Id==id.GetGuid()))];
        public PinnedContext Pin(InputFrame? frame=null)=>Context is null?PinnedContext.Current(frame):PinnedContext.Retained(Context,frame);
        public JsonNode Page(string name)=>JsonNode.Parse(view.GetProperty(name).GetRawText())!;
    }

    static async Task Execute(NpgsqlConnection connection,string sql,CancellationToken ct){await using var command=new NpgsqlCommand(sql,connection);await command.ExecuteNonQueryAsync(ct);}

    static JsonObject Without(JsonObject page,string field){var copy=page.DeepClone().AsObject();copy.Remove(field);return copy;}

    static void Same(string name,object? read,JsonNode? page,params string[] fields)
    {
        var actual=JsonSerializer.SerializeToNode(read,Json);
        if(fields.Length>0)
        {
            actual=new JsonObject(fields.Select(f=>KeyValuePair.Create(f,actual![f]?.DeepClone())));
            page=new JsonObject(fields.Select(f=>KeyValuePair.Create(f,page![f]?.DeepClone())));
        }
        if(!JsonNode.DeepEquals(actual,page))throw new Exception($"{name}: the direct read differs from the page.");
        Console.WriteLine("PASS "+name);
    }

    static async Task Rejects<T>(string code,string name,Func<Task<T>> read)
    {
        try{await read();}
        catch(MarketDataException e) when(e.Code==code){Console.WriteLine("PASS "+name);return;}
        throw new Exception($"{name}: expected {code}.");
    }
}
