using OpenEtrm.Shared.Temporal;
using System.Collections.Concurrent;
using System.Collections.Immutable;
using System.Net;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.FileProviders;
using Npgsql;
using OpenEtrm.Api;
using OpenEtrm.MarketData;

if (!args.Contains("--local-preview")) throw new InvalidOperationException("This host supports only an explicitly selected local synthetic preview.");
var root=Path.GetFullPath(Environment.GetEnvironmentVariable("OPENETRM_PREVIEW_ROOT") ?? throw new InvalidOperationException("Use tools/run_preview.py."));
var runId=Guid.Parse(File.ReadAllText(Path.Combine(root,".openetrm-preview")));
var port=int.Parse(Environment.GetEnvironmentVariable("OPENETRM_PREVIEW_PORT") ?? throw new InvalidOperationException("Explicit preview port is required."));
var webRoot=Path.GetFullPath(Environment.GetEnvironmentVariable("OPENETRM_PREVIEW_WEB") ?? throw new InvalidOperationException("Explicit built web root is required."));
var builder=WebApplication.CreateBuilder(args);
builder.Logging.ClearProviders(); builder.Logging.AddSimpleConsole(o=>o.SingleLine=true); builder.Logging.SetMinimumLevel(LogLevel.Warning);
builder.WebHost.ConfigureKestrel(o=> { o.Listen(IPAddress.Loopback,port); o.Limits.MaxRequestBodySize=32*1024; });
builder.Services.AddDataProtection().UseEphemeralDataProtectionProvider();
builder.Services.AddAntiforgery(o=> { o.HeaderName="X-Preview-CSRF"; o.Cookie.Name="openetrm_preview_csrf"; o.Cookie.HttpOnly=true; o.Cookie.SameSite=SameSiteMode.Strict; o.Cookie.SecurePolicy=CookieSecurePolicy.None; });
builder.Services.ConfigureHttpJsonOptions(o=>o.SerializerOptions.PropertyNamingPolicy=JsonNamingPolicy.CamelCase);
var app=builder.Build();
await using var database=new PreviewDatabase(root);
var sessions=new ConcurrentDictionary<string,PreviewSession>();
var profiles=new[] { new {id="viewer",name="Viewer",description="Read only"},new {id="editor",name="Market Data Editor",description="Read and correct synthetic prices"},new {id="approver",name="Market Data Approver",description="Read and publish schedule definitions"},new {id="admin",name="Access Administrator",description="Manage workspace identities and roles"} };

app.Use(async (context,next)=>
{
    var origin=$"http://127.0.0.1:{port}";
    if (context.Connection.RemoteIpAddress is not {} remote || !IPAddress.IsLoopback(remote) ||
        context.Request.Host.Host!="127.0.0.1" || context.Request.Host.Port!=port ||
        context.Request.Headers.TryGetValue("Origin",out var supplied) && supplied!=origin)
    { context.Response.StatusCode=403; return; }
    context.Response.Headers["Content-Security-Policy"]="default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'";
    context.Response.Headers["X-Content-Type-Options"]="nosniff"; context.Response.Headers["Referrer-Policy"]="no-referrer";
    if (context.Request.Path.StartsWithSegments("/api")) context.Response.Headers.CacheControl="no-store";
    using var deadline=CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted); deadline.CancelAfter(TimeSpan.FromSeconds(15));
    context.RequestAborted=deadline.Token;
    try
    {
        if (context.Request.Method is not ("GET" or "HEAD"))
        {
            if (!context.Request.Headers.TryGetValue("Origin",out var requestOrigin) || requestOrigin!=origin) throw new PreviewDeniedException();
            await context.RequestServices.GetRequiredService<IAntiforgery>().ValidateRequestAsync(context);
        }
        await next(context);
    }
    catch (Exception e) when (!context.Response.HasStarted)
    {
        var (status,code,message)=e switch
        {
            PreviewDeniedException => (403,"access_denied","The selected test identity cannot perform this operation."),
            AntiforgeryValidationException => (400,"request_token","Reload the preview to obtain a valid request token."),
            MarketDataException m when m.Code is "shortcut_conflict" or "tou_conflict" => (409,m.Code,m.Message),
            PostgresException p when p.SqlState is "23505" or "40001" && context.Request.Path.StartsWithSegments("/api/tou-products") => (409,"tou_conflict","This TOU product changed or its code already exists. Reload before editing."),
            MarketDataException m => (422,m.Code,m.Message),
            TemporalException t when t.Code is "date_definition_conflict" or "schedule_conflict" => (409,t.Code,t.Message),
            TemporalException t => (422,t.Code,t.Message),
            PostgresException p when p.SqlState is "23505" or "40001" && context.Request.Path.StartsWithSegments("/api/date-schedules") => (409,"schedule_conflict","This schedule changed or the reference already exists. Reload before editing."),
            PostgresException p when p.SqlState=="P0001" && p.MessageText=="admin_conflict" => (409,"admin_conflict","This account or request changed. Reload administration before editing."),
            PostgresException p when p.SqlState=="P0001" && p.MessageText is "last_administrator" or "self_access_change" or "admin_input" or "admin_limit" => (422,p.MessageText,"The administrative change was rejected. Keep a current administrator and supply explicit account details and roles."),
            PostgresException p when p.SqlState=="23505" && context.Request.Path.StartsWithSegments("/api/admin") => (409,"admin_conflict","That account or request already exists. Reload administration."),
            PostgresException p when p.SqlState=="23505" => (409,"revision_conflict","This observation has already been revised. Inspect its history and explicitly select the intended revision."),
            PostgresException p when p.SqlState=="P0001" && p.MessageText is "knowledge_coverage" or "knowledge_clock" or "knowledge_tracking" or "knowledge_retention" or "knowledge_limit" or "knowledge_timeline" => (422,p.MessageText,"The requested knowledge cutoff cannot be certified. Check retained coverage, clock health and commit tracking."),
            PostgresException p when p.SqlState=="42501" => (403,"access_denied","Database permissions rejected this operation."),
            PostgresException p when p.SqlState is "23514" or "55000" => (422,"definition_rejected","The value or operation violates an explicit database specification."),
            PostgresException when context.Items.ContainsKey("administration_attempted") => (503,"administration_outcome_unknown","The administrative outcome cannot be confirmed. Retain the original request and inspect the audit before retrying."),
            OperationCanceledException when context.Items.ContainsKey("administration_attempted") => (503,"administration_outcome_unknown","The administrative outcome is unknown. Retain the request identity and inspect the audit before retrying the exact command."),
            NpgsqlException when context.Items.ContainsKey("administration_attempted") => (503,"administration_outcome_unknown","The administrative outcome is unknown. Retain the request identity and inspect the audit before retrying the exact command."),
            OperationCanceledException when context.Items.ContainsKey("correction_attempted") => (503,"mutation_outcome_unknown","The correction outcome is unknown. Reload, inspect the input's revisions and explicitly select any saved successor before submitting again."),
            NpgsqlException when context.Items.ContainsKey("correction_attempted") => (503,"mutation_outcome_unknown","The correction outcome is unknown. Reload, inspect the input's revisions and explicitly select any saved successor before submitting again."),
            OperationCanceledException => (503,"request_cancelled","The request was cancelled or exceeded its time limit."),
            BadHttpRequestException or JsonException => (400,"request_format","The request is incomplete or malformed."),
            _ => (500,"preview_error","The preview could not complete the operation.")
        };
        if(e is PostgresException pg)app.Logger.LogWarning("Database operation rejected: {SqlState}",pg.SqlState);
        if (status==500) app.Logger.LogError("Preview operation failed: {ErrorType}",e.GetType().Name);
        context.Response.StatusCode=status;
        await context.Response.WriteAsJsonAsync(new {code,message},CancellationToken.None);
    }
});

app.MapGet("/api/health",()=>new {mode="local-synthetic-preview",runId});
app.MapGet("/api/bootstrap",async (HttpContext context,IAntiforgery antiforgery)=>
{
    foreach(var item in sessions.Where(x=>DateTimeOffset.UtcNow-x.Value.Created>TimeSpan.FromMinutes(30)).ToArray()) sessions.TryRemove(item.Key,out _);
    PreviewSession session;
    if (context.Request.Cookies.TryGetValue("openetrm_preview",out var cookie)&&sessions.TryGetValue(cookie,out var existing)) session=existing;
    else
    {
        if (sessions.Count>=64) throw new PreviewDeniedException();
        var id=Convert.ToHexString(RandomNumberGenerator.GetBytes(32)); session=new PreviewSession(database.Manifest);
        sessions[id]=session;
        context.Response.Cookies.Append("openetrm_preview",id,new CookieOptions {HttpOnly=true,SameSite=SameSiteMode.Strict,Secure=false,MaxAge=TimeSpan.FromMinutes(30),Path="/"});
    }
    await session.Gate.WaitAsync(context.RequestAborted);
    try { return new {mode="local-synthetic-preview",runId,notice="Disposable synthetic workspace. Test identities are simulations, not production sign-in.",profiles,
        profile=session.Profile,customProfiles=session.CustomProfiles.Select(p=>new{id=p.Key,name=p.Value}).ToArray(),csrfToken=antiforgery.GetAndStoreTokens(context).RequestToken,frames=session.Frames.Values.Where(f=>f.ContextId==session.MarketContext?.ContextId).OrderBy(f=>f.At).ToArray(),
        tenantId=database.Manifest.TenantId,workspaceId=database.Manifest.WorkspaceId}; }
    finally { session.Gate.Release(); }
});
PreviewSession Session(HttpContext context)
{
    if (!context.Request.Cookies.TryGetValue("openetrm_preview",out var id)||!sessions.TryGetValue(id,out var session)||DateTimeOffset.UtcNow-session.Created>TimeSpan.FromMinutes(30)) throw new PreviewDeniedException();
    return session;
}
async Task<IResult> Locked(HttpContext context,Func<PreviewSession,Task<IResult>> work)
{
    var session=Session(context); await session.Gate.WaitAsync(context.RequestAborted);
    try {return await work(session);} finally {session.Gate.Release();}
}
string Profile(PreviewSession session)=>session.Profile ?? throw new PreviewDeniedException();
InputFrame Frame(PreviewSession session,Guid id)=>session.Frames.TryGetValue(id,out var frame) && frame.ContextId==session.MarketContext?.ContextId?frame:throw new MarketDataException("snapshot_missing","Select a saved input snapshot from this preview session.");
app.MapPost("/api/profile",(HttpContext c,ProfileRequest body)=>Locked(c,session=>
{
    if (!profiles.Any(p=>p.id==body.Profile) && !session.CustomProfiles.ContainsKey(body.Profile)) throw new PreviewDeniedException();
    session.Profile=body.Profile; session.MarketContext=null; return Task.FromResult(Results.Ok(new {profile=session.Profile}));
}));
PreviewSequenceCoverage ScheduleSource(string? code) => (database.Manifest.Schedules ?? []).SingleOrDefault(s=>s.Curve==code)
    ?? throw new MarketDataException("sequence_source","Choose an explicitly configured contract schedule.");
Task<IResult> ScheduleOperation(HttpContext c,Func<PreviewSession,PreviewData,IResult> work) => Locked(c,async session=>
    await database.WithIdentity(Profile(session),"ReadMarketData",async (connection,ct)=>work(session,await MarketData(session,connection,ct)),c.RequestAborted));
var touStore=new TouProductStore(database.Manifest.CatalogId,database.Manifest.ReferenceCatalogId,database.Manifest.ReferenceRevisionId);
// TOU products are current definitions; a historical view never substitutes them.
Task<IResult> PowerOperation(HttpContext c,string permission,Func<PreviewSession,NpgsqlConnection,CancellationToken,Task<IResult>> work)=>Locked(c,session=>
{
    if(session.MarketContext is not null)
        throw new MarketDataException("power_historical","TOU products and power hours require current inputs; historical TOU publication is not implemented.");
    return database.WithIdentity(Profile(session),permission,(connection,ct)=>work(session,connection,ct),c.RequestAborted);
});
async Task<PowerPreview.ProductSet> PublishedProducts(NpgsqlConnection connection,CancellationToken ct)=>
    PowerPreview.Products(TouProductStore.Published(await touStore.Read(connection,ct)),await touStore.Clocks(connection,ct));
app.MapPost("/api/power/catalog",(HttpContext c,PowerCatalogRequest body)=>PowerOperation(c,"ReadMarketData",async(session,connection,ct)=>
    Results.Ok(PowerPreview.Catalog(await database.Read(connection,ct),Frame(session,body.SnapshotId),await PublishedProducts(connection,ct)))));
app.MapPost("/api/power/preview",(HttpContext c,PowerPreviewRequest body)=>PowerOperation(c,"ReadMarketData",async(session,connection,ct)=>
    Results.Ok(PowerPreview.Calculate(await database.Read(connection,ct),Frame(session,body.SnapshotId),body,await PublishedProducts(connection,ct)))));
app.MapGet("/api/tou-products",(Func<HttpContext,Task<IResult>>)(c=>PowerOperation(c,"ReadMarketData",async(session,connection,ct)=>
{
    var canEdit=await HasPermission(connection,"WriteMarketDefinitions",ct);var canPublish=await HasPermission(connection,"SealMarketDefinitions",ct);
    // Row security returns drafts to authors only; readers receive published versions.
    return Results.Ok(new {versions=await touStore.Read(connection,ct),clocks=await touStore.Clocks(connection,ct),canEdit,canPublish});
})));
app.MapPost("/api/tou-products/save",(HttpContext c,TouProductSaveRequest body)=>PowerOperation(c,"WriteMarketDefinitions",async(session,connection,ct)=>
    Results.Ok(await touStore.Save(connection,body,ct))));
app.MapPost("/api/tou-products/publish",(HttpContext c,TouProductPublishRequest body)=>PowerOperation(c,"SealMarketDefinitions",async(session,connection,ct)=>
    Results.Ok(await touStore.Publish(connection,body,ct))));
app.MapGet("/api/schedules",(Func<HttpContext,Task<IResult>>)(c=>ScheduleOperation(c,(session,data)=>
{
    var sources=(database.Manifest.Schedules??[]).Select(source=>
    {
        var sequence=SchedulePreview.Compile(data,source);
        return new {source.Curve,name=data.Definitions["curves"].Single(c=>c.Text("code")==source.Curve).Text("name"),source.From,source.To,source.ExampleAt,
            entries=sequence.Entries.Select(e=>new {contractId=e.Contract.Key.Id,e.Ordinal,
                label=data.References["futures_series"].Single(s=>s.Text("code")==e.Contract.FuturesSeries!.Value.Code).Text("series_label"),
                e.EligibleFrom,rollAt=e.Contract.Expiry,beforeExpiryAt=e.Contract.Expiry.AddTicks(-1),e.Contract.DeliveryFrom,e.Contract.DeliveryTo,e.LastTradingDate}).ToArray()};
    }).ToArray();
    return Results.Ok(new {sources,shortcuts=session.Shortcuts.For(Profile(session)).Select(SchedulePreview.Describe).ToArray(),
        dateSchedules=session.Dates.For(Profile(session)).ToArray(),draftCurves=session.Dates.Curves(Profile(session)).ToArray(),
        curveTemplates=data.Definitions["curves"].Select(c=>new {code=c.Text("code")}).ToArray(),dateRoles=SchedulePreview.DateRoleChoices});
})));
app.MapPost("/api/schedules/preview",(HttpContext c,SchedulePreviewRequest body)=>ScheduleOperation(c,(session,data)=>
    Results.Ok(SchedulePreview.Result(SchedulePreview.Create(SchedulePreview.Compile(data,ScheduleSource(body.Curve)),body),SchedulePreview.ParseAt(body.At)))));
app.MapPost("/api/schedules/keep",(HttpContext c,SchedulePreviewRequest body)=>ScheduleOperation(c,(session,data)=>
{
    var shortcut=SchedulePreview.Create(SchedulePreview.Compile(data,ScheduleSource(body.Curve)),body);
    if(session.Dates.For(Profile(session)).Any(s=>s.Definition.Symbol==shortcut.Symbol))
        throw new TemporalException("date_definition_conflict","A date schedule already uses this shortcut.");
    _=shortcut.Resolve(SchedulePreview.ParseAt(body.At));
    return Results.Ok(SchedulePreview.Describe(session.Shortcuts.Keep(Profile(session),shortcut)));
}));
app.MapPost("/api/schedules/resolve",(HttpContext c,ShortcutResolveRequest body)=>ScheduleOperation(c,(session,data)=>
{
    var shortcut=session.Shortcuts.Find(Profile(session),body.Symbol);
    var source=ScheduleSource(shortcut.Sequence.Key.Code);
    if(shortcut.Sequence.Key.Revision!=new DefinitionRevision(database.Manifest.CatalogId,database.Manifest.RevisionId) ||
       shortcut.Sequence.References!=new ReferenceRevision(database.Manifest.ReferenceCatalogId,database.Manifest.ReferenceRevisionId) ||
       source.From!=shortcut.Sequence.From || source.To!=shortcut.Sequence.To)
        throw new MarketDataException("sequence_definition","The retained shortcut pins differ from this preview's exact source bundle.");
    return Results.Ok(SchedulePreview.Result(shortcut,SchedulePreview.ParseAt(body.At)));
}));
DateReceipt ResolveDate(PreviewSession session,PreviewData data,string? expression,string? at,CalendarDraft? calendar)
{
    var instant=at is null? (DateTimeOffset?)null:SchedulePreview.ParseAt(at);
    return session.Dates.Resolve(Profile(session),expression,instant,symbol=>
    {
        var shortcut=session.Shortcuts.Find(Profile(session),symbol);
        var source=ScheduleSource(shortcut.Sequence.Key.Code);
        var current=SchedulePreview.Compile(data,source);
        if(current.Key!=shortcut.Sequence.Key || current.References!=shortcut.Sequence.References ||
            current.From!=shortcut.Sequence.From || current.To!=shortcut.Sequence.To)
            throw new MarketDataException("sequence_definition","The shortcut no longer matches the selected exact source bundle.");
        var resolved=shortcut.Resolve(instant!.Value);
        return new(symbol,resolved.Date,symbol,null,null,null,resolved);
    },calendar);
}
app.MapPost("/api/schedules/dates/preview",(HttpContext c,MonthlyDraft body)=>ScheduleOperation(c,(session,data)=>Results.Ok(DateWorkspace.Compile(body))));
app.MapPost("/api/schedules/dates/keep",(HttpContext c,MonthlyDraft body)=>ScheduleOperation(c,(session,data)=>
{
    var compiled=DateWorkspace.Compile(body);
    if(session.Shortcuts.For(Profile(session)).Any(s=>s.Symbol==body.Symbol))
        throw new TemporalException("date_definition_conflict","A contract shortcut already uses this name.");
    return Results.Ok(session.Dates.Keep(Profile(session),compiled));
}));
app.MapPost("/api/schedules/expression",(HttpContext c,DateExpressionRequest body)=>ScheduleOperation(c,(session,data)=>
    Results.Ok(ResolveDate(session,data,body.Expression,body.At,body.RollingCalendar))));
CurveDatesSaved CompileCurve(PreviewSession session,PreviewData data,CurveDatesRequest body)
{
    if(body.Code is null || !System.Text.RegularExpressions.Regex.IsMatch(body.Code,@"\A[a-z][a-z0-9_]{0,31}\z") ||
        string.IsNullOrWhiteSpace(body.Name) || body.Name.Length>80 || body.Contracts is null || body.Contracts.Length is <1 or >120 ||
        body.Contracts.Any(c=>c is null) ||
        body.Contracts.Select(c=>c.Label).Distinct().Count()!=body.Contracts.Length)
        throw new TemporalException("contract_dates","Name the draft curve and supply 1–120 uniquely named contracts.");
    if(data.Definitions["curves"].Any(c=>c.Text("code")==body.Code))
        throw new TemporalException("date_definition_conflict","Choose a new curve code; a retained definition already uses this code.");
    var templates=data.Definitions["curves"].Where(c=>c.Text("code")==body.TemplateCurve).ToArray();
    if(templates.Length!=1)throw new MarketDataException("missing_curve","Select an exact curve specification to reuse.");
    var at=SchedulePreview.ParseAt(body.At);
    var contracts=body.Contracts.Select(d=>DateWorkspace.Contract(d,e=>ResolveDate(session,data,e,body.At,body.RollingCalendar))).ToImmutableArray();
    // A curve's configured contract order must remain deterministic and unambiguous.
    for(var i=1;i<contracts.Length;i++)
        if(contracts[i].DeliveryFrom<contracts[i-1].DeliveryTo || contracts[i].Expiry<=contracts[i-1].Expiry)
            throw new TemporalException("contract_dates","Contracts must have ordered, nonoverlapping delivery periods and increasing expiries.");
    return new(body.Code,body.Name,body.TemplateCurve!,templates[0].Clone(),
        new DefinitionRevision(database.Manifest.CatalogId,database.Manifest.RevisionId),
        new ReferenceRevision(database.Manifest.ReferenceCatalogId,database.Manifest.ReferenceRevisionId),
        at.ToString("O",System.Globalization.CultureInfo.InvariantCulture),body.RollingCalendar,contracts);
}
app.MapPost("/api/schedules/contracts/preview",(HttpContext c,CurveDatesRequest body)=>ScheduleOperation(c,(session,data)=>Results.Ok(CompileCurve(session,data,body))));
app.MapPost("/api/schedules/contracts/keep",(HttpContext c,CurveDatesRequest body)=>ScheduleOperation(c,(session,data)=>
    Results.Ok(session.Dates.KeepCurve(Profile(session),CompileCurve(session,data,body)))));
var scheduleStore=new ScheduleStore(database.Manifest.CatalogId,database.Manifest.ReferenceCatalogId,database.Manifest.ReferenceRevisionId);
var knowledgeStore=new KnowledgeStore(database.Manifest.CatalogId);
Task<IResult> DateOperation(HttpContext c,string permission,Func<PreviewSession,NpgsqlConnection,CancellationToken,Task<IResult>> work)=>Locked(c,session=>
    database.WithIdentity(Profile(session),permission,async(connection,ct)=>
    {
        if(session.MarketContext is {} selected)await MarketContextStore.Bind(connection,database.Manifest.CatalogId,selected,ct);
        return await work(session,connection,ct);
    },c.RequestAborted));
async Task<bool> HasPermission(NpgsqlConnection connection,string permission,CancellationToken ct)
{
    await using var command=ScheduleStore.Command(connection,"SELECT security.has_permission($1)",permission);
    return Equals(await command.ExecuteScalarAsync(ct),true);
}
app.MapGet("/api/date-schedules",(Func<HttpContext,Task<IResult>>)(c=>DateOperation(c,"ReadMarketData",async(session,connection,ct)=>
{
    var knownThrough=session.MarketContext?.KnownThrough??await scheduleStore.Capture(connection,ct);
    var canEdit=session.MarketContext is null && await HasPermission(connection,"WriteMarketDefinitions",ct);
    var canPublish=session.MarketContext is null && await HasPermission(connection,"SealMarketDefinitions",ct);
    // Row security returns drafts to authors only; readers receive published versions.
    var versions=session.MarketContext is {} selected?await scheduleStore.ReadAt(connection,selected,ct):await scheduleStore.Read(connection,ct);
    return Results.Ok(new {knownThrough,versions,canEdit,canPublish,choices=DateWorkspace.Choices,
        contractDefinitions=session.ContractDefinitions.Where(p=>p.Key.Owner==Profile(session)).Select(p=>p.Value).ToArray(),
        calendars=(await scheduleStore.Calendars(connection,ct)).Select(c=>new {c.Reference,c.CoverageFrom,c.CoverageTo,c.WeekendDays,
            closedDates=c.Days.Where(d=>!d.Open).Select(d=>d.Date),openDates=c.Days.Where(d=>d.Open).Select(d=>d.Date)})});
})));
app.MapPost("/api/date-schedules/preview",(HttpContext c,DateSchedulePreviewRequest body)=>DateOperation(c,"ReadMarketData",async(session,connection,ct)=>
    Results.Ok(DateWorkspace.Compile(body.Definition??throw new TemporalException("schedule_definition","Supply an explicit schedule definition."),
        await scheduleStore.Calendar(connection,body.Calendar,ct)))));
app.MapPost("/api/date-schedules/save",(HttpContext c,ScheduleSaveRequest body)=>DateOperation(c,"WriteMarketDefinitions",async(session,connection,ct)=>
    Results.Ok(await scheduleStore.Save(connection,body,ct))));
app.MapPost("/api/date-schedules/publish",(HttpContext c,SchedulePublishRequest body)=>DateOperation(c,"SealMarketDefinitions",async(session,connection,ct)=>
    Results.Ok(await scheduleStore.Publish(connection,body,ct))));
app.MapPost("/api/date-schedules/context",(HttpContext c,ContextCaptureRequest body)=>DateOperation(c,"ReadMarketData",async(session,connection,ct)=>
    Results.Ok(await knowledgeStore.Capture(connection,body,ct))));
async Task<(ImmutableArray<ScheduleVersion> Versions,ScheduleContext Context)> ScheduleView(NpgsqlConnection connection,ScheduleContext? context,CancellationToken ct)
{
    if(context is null)throw new TemporalException("schedule_context","Choose an explicit temporal context.");
    if(context.KnownAt is not null || context.ContextId is not null)
    {
        var resolved=await knowledgeStore.Resolve(connection,context,ct);
        return(await scheduleStore.ReadAt(connection,resolved,ct),resolved);
    }
    // Explicit logical-prefix replay is retained for old API clients; this is
    // a different authoring form from a certified wall-clock request.
    _=PublishedSchedules.ContextDate(context);var head=await scheduleStore.Capture(connection,ct);
    if(context.KnownThrough>head)throw new TemporalException("schedule_context","This publication view has not been captured in this catalog.");
    return(await scheduleStore.Read(connection,ct),context);
}
app.MapPost("/api/date-schedules/resolve",(HttpContext c,PublishedDateRequest body)=>DateOperation(c,"ReadMarketData",async(session,connection,ct)=>
{
    var view=await ScheduleView(connection,body.Context,ct);
    return Results.Ok(PublishedSchedules.Resolve(view.Versions,body.Expression,view.Context));
}));
async Task<BoundContractDefinition> BindContracts(NpgsqlConnection connection,PublishedContractRequest body,CancellationToken ct)
{
    if(body.Code is null || !System.Text.RegularExpressions.Regex.IsMatch(body.Code,@"\A[a-z][a-z0-9_]{0,31}\z") ||
        string.IsNullOrWhiteSpace(body.Name) || body.Name.Length>80 || body.Contracts is null || body.Contracts.Length is <1 or >120 ||
        body.Contracts.Any(c=>c is null) || body.Contracts.Select(c=>c.Label).Distinct().Count()!=body.Contracts.Length)
        throw new TemporalException("contract_dates","Name the definition and supply uniquely named contracts.");
    var view=await ScheduleView(connection,body.Context,ct);
    var contracts=body.Contracts.Select(d=>DateWorkspace.Contract(new(d.Label,d.Start,d.End,d.LastTrading,d.CutoffUtc),e=>PublishedSchedules.Resolve(view.Versions,e,view.Context))).ToImmutableArray();
    for(var n=1;n<contracts.Length;n++)if(contracts[n].DeliveryFrom<contracts[n-1].DeliveryTo || contracts[n].Expiry<=contracts[n-1].Expiry)
        throw new TemporalException("contract_dates","Contract periods must be ordered without overlap and have increasing last-trading instants.");
    return new(body.Code,body.Name,view.Context,contracts.Select(c=>new DatedContractDefinition(c.Label,c.DeliveryFrom,c.DeliveryTo,c.Expiry,c.DeliveryStart,c.DeliveryEnd,c.LastTrading,c.CutoffUtc)).ToImmutableArray());
}
app.MapPost("/api/date-schedules/contracts/preview",(HttpContext c,PublishedContractRequest body)=>DateOperation(c,"ReadMarketData",async(session,connection,ct)=>
    Results.Ok(await BindContracts(connection,body,ct))));
app.MapPost("/api/date-schedules/contracts/save",(HttpContext c,PublishedContractRequest body)=>DateOperation(c,"ReadMarketData",async(session,connection,ct)=>
{
    var result=await BindContracts(connection,body,ct);var key=(Profile(session),result.Code);
    if(session.ContractDefinitions.TryGetValue(key,out var old) && JsonSerializer.Serialize(old)!=JsonSerializer.Serialize(result))
        throw new TemporalException("date_definition_conflict","This candidate name has different terms. Choose a new code.");
    if(!session.ContractDefinitions.ContainsKey(key) && session.ContractDefinitions.Keys.Count(k=>k.Owner==Profile(session))>=16)
        throw new TemporalException("preview_limit","At most 16 candidate definitions can be kept per persona.");
    session.ContractDefinitions[key]=result;return Results.Ok(result);
}));
async Task<PreviewData> MarketData(PreviewSession session,NpgsqlConnection connection,CancellationToken ct)
{
    if(session.MarketContext is {} selected)await MarketContextStore.Bind(connection,database.Manifest.CatalogId,selected,ct);
    return await database.Read(connection,ct);
}
app.MapPost("/api/market/context",(HttpContext c,MarketContextRequest body)=>Locked(c,async session=>
{
    if(body.Selection!="latest_correction")throw new MarketDataException("selection_policy","Choose the explicit latest-known correction policy.");
    var snapshot=await database.WithIdentity(Profile(session),"ReadMarketData",async(connection,ct)=>
    {
        var captured=await knowledgeStore.Capture(connection,new(body.EffectiveOn,body.KnownAt,body.Mode),ct);
        await MarketContextStore.Bind(connection,database.Manifest.CatalogId,captured.Context,ct);
        var data=await database.Read(connection,ct);
        var end=DateWorkspace.Date(captured.Context.EffectiveOn).AddDays(1).ToDateTime(TimeOnly.MinValue,DateTimeKind.Utc);
        var selected=session.InitialFrames.Select(id=>session.Frames[id]).Where(f=>f.At.UtcDateTime<end).ToArray();
        var frames=selected.Select(f=>session.Frames.Values.FirstOrDefault(existing=>existing.ContextId==captured.Context.ContextId&&existing.At==f.At)
            ??MarketContextStore.Select(f,data,captured.Context)).ToArray();
        if(session.Frames.Count+frames.Count(f=>!session.Frames.ContainsKey(f.Id))>128)throw new MarketDataException("preview_limit","This preview has reached its retained input limit.");
        return (captured,frames);
    },c.RequestAborted);
    foreach(var frame in snapshot.frames)session.Frames.TryAdd(frame.Id,frame);
    session.MarketContext=snapshot.captured.Context;
    return Results.Ok(snapshot.captured);
}));
app.MapPost("/api/market/current",(Func<HttpContext,Task<IResult>>)(c=>Locked(c,async session=>
{
    await database.WithIdentity(Profile(session),"ReadMarketData",(_,_)=>Task.FromResult(true),c.RequestAborted);
    session.MarketContext=null;return Results.Ok(new {mode="explicit_input_pins"});
})));
app.MapGet("/api/workspace",(Func<HttpContext,Task<IResult>>)(c=>Locked(c,async session=>
{
    var data=await database.WithIdentity(Profile(session),"ReadMarketData",(connection,ct)=>MarketData(session,connection,ct),c.RequestAborted);
    return Results.Ok(new {context=session.MarketContext,profile=session.Profile,example=database.Manifest.Example,definitions=data.Definitions,references=data.References,observations=data.Observations,
        frames=session.Frames.Values.Where(f=>f.ContextId==session.MarketContext?.ContextId).OrderBy(f=>f.At).ToArray(),initialFrameIds=session.MarketContext is null?session.InitialFrames:session.Frames.Values.Where(f=>f.ContextId==session.MarketContext.ContextId).Select(f=>f.Id).ToArray()});
})));
app.MapPost("/api/evaluate",(HttpContext c,BuildRequest body)=>Locked(c,async session=>
{
    var frame=Frame(session,body.SnapshotId);
    if(session.MarketContext is {} selected && DateOnly.FromDateTime(frame.At.UtcDateTime)!=DateWorkspace.Date(selected.EffectiveOn))
        throw new MarketDataException("market_date","Choose inputs for the selected context date. No earlier market date is substituted.");
    var result=await database.WithIdentity(Profile(session),"ReadMarketData",async (connection,ct)=>(await MarketData(session,connection,ct)).Result(frame,body.Curve),c.RequestAborted);
    if(session.MarketContext is {} view)
    {
        var json=System.Text.Json.Nodes.JsonNode.Parse(JsonSerializer.Serialize(result,new JsonSerializerOptions{PropertyNamingPolicy=JsonNamingPolicy.CamelCase}))!.AsObject();
        json["context"]=JsonSerializer.SerializeToNode(view,new JsonSerializerOptions{PropertyNamingPolicy=JsonNamingPolicy.CamelCase});return Results.Ok(json);
    }
    return Results.Ok(result);
}));
app.MapPost("/api/history",(HttpContext c,HistoryRequest body)=>Locked(c,async session=>
{
    var current=Frame(session,body.SnapshotId);
    var result=await database.WithIdentity(Profile(session),"ReadMarketData",async (connection,ct)=>
    {
        var data=await MarketData(session,connection,ct);
        var frames=(session.MarketContext is null?session.InitialFrames.Select(id=>Frame(session,id)):session.Frames.Values.Where(f=>f.ContextId==session.MarketContext.ContextId)).Select(f=>f.At==current.At?current:f).OrderBy(f=>f.At).ToArray();
        return frames.Select(f=>
        {
            try {
                var value=data.HistoryValue(f,body.Curve,body.ContractId,body.SeriesId);
                return new HistorySample(f.At,value.Value,f.Id,value.Inputs,null);
            }
            catch(MarketDataException error) when(error.Code is "missing_observation" or "source_expired")
            { return new HistorySample(f.At,null,f.Id,[],error.Code); }
        }).ToArray();
    },c.RequestAborted);
    return Results.Ok(new {mode="rebuilt_from_explicit_seed_pins_with_selected_frame",points=result});
}));
app.MapPost("/api/corrections",(HttpContext c,CorrectionRequest body)=>Locked(c,async session=>
{
    if(session.MarketContext is not null)throw new MarketDataException("historical_read_only","Return to current input editing before changing observations.");
    var frame=Frame(session,body.SnapshotId);
    if (!frame.ObservationIds.Contains(body.ObservationId)) throw new MarketDataException("snapshot_input","Only an explicitly selected observation can be corrected here.");
    if (session.Frames.Count>=128) throw new MarketDataException("preview_limit","Restart the disposable preview to create more saved selections.");
    if (string.IsNullOrWhiteSpace(body.Value)) throw new MarketDataException("missing_value","Enter an exact decimal value.");
    c.Items["correction_attempted"]=true;
    var id=await database.WithIdentity(Profile(session),"ImportObservations",(connection,ct)=>database.Correct(connection,body.ObservationId,body.Value,ct),c.RequestAborted);
    var updated=frame with {Id=Guid.NewGuid(),Name="Edited inputs",ObservationIds=frame.ObservationIds.Replace(body.ObservationId,id)};
    session.Frames.Add(updated.Id,updated);
    return Results.Ok(new {frame=updated,observationId=id});
}));
app.MapPost("/api/select-observation",(HttpContext c,SelectionRequest body)=>Locked(c,async session=>
{
    if(session.MarketContext is not null)throw new MarketDataException("historical_read_only","Return to current input editing before changing selected revisions.");
    var frame=Frame(session,body.SnapshotId);
    var updated=await database.WithIdentity(Profile(session),"ReadMarketData",async (connection,ct)=>
    {
        var data=await database.Read(connection,ct); var chosen=data.Observation(body.ObservationId);
        var previous=frame.ObservationIds.Where(id=>
        {
            var o=data.Observation(id);
            return o.Id("series_id")==chosen.Id("series_id")&&o.Text("source_event_id")==chosen.Text("source_event_id")&&o.Text("source_code")==chosen.Text("source_code")&&o.Text("role")==chosen.Text("role")&&o.Instant("observed_at")==chosen.Instant("observed_at");
        }).ToArray();
        if (previous.Length!=1) throw new MarketDataException("selection_mismatch","Select a revision of the same exact source fact and time.");
        return frame with {Id=Guid.NewGuid(),Name="Explicit revision selection",ObservationIds=frame.ObservationIds.Replace(previous[0],body.ObservationId)};
    },c.RequestAborted);
    if (session.Frames.Count>=128) throw new MarketDataException("preview_limit","Restart the disposable preview to create more saved selections.");
    session.Frames.Add(updated.Id,updated); return Results.Ok(new {frame=updated});
}));
app.MapGet("/api/access",(Func<HttpContext,Task<IResult>>)(c=>Locked(c,session=>
    database.WithIdentity(Profile(session),null,async(connection,ct)=>
    {
        await using var command=ScheduleStore.Command(connection,"SELECT security.current_permissions()");
        return Results.Ok(new {permissions=(string[])(await command.ExecuteScalarAsync(ct))!});
    },c.RequestAborted))));
// The principal kinds security.principals accepts; each maps to one login kind.
(string Code,string Name)[] IdentityKinds=[("human","Human"),("service","Service"),("agent","Agent")];
app.MapGet("/api/admin",(Func<HttpContext,Task<IResult>>)(c=>Locked(c,session=>
    database.WithIdentity(Profile(session),"ManageAccess",async(connection,ct)=>
    {
        await using var command=ScheduleStore.Command(connection,"SELECT security.administration_directory()::text");
        var directory=JsonSerializer.Deserialize<Dictionary<string,JsonElement>>((string)(await command.ExecuteScalarAsync(ct))!)!;
        directory["kinds"]=JsonSerializer.SerializeToElement(IdentityKinds.Select(k=>new {code=k.Code,name=k.Name}));
        return Results.Ok(directory);
    },c.RequestAborted))));
async Task<IResult> AdminMutation(HttpContext c,object body,string action)=>await Locked(c,async session=>
{
    c.Items["administration_attempted"]=true;
    var result=await database.WithIdentity(Profile(session),"ManageAccess",async(connection,ct)=>
    {
        var request=System.Text.Json.Nodes.JsonNode.Parse(JsonSerializer.Serialize(body,new JsonSerializerOptions{PropertyNamingPolicy=JsonNamingPolicy.CamelCase}))!.AsObject();request["action"]=action;
        await using var command=ScheduleStore.Command(connection,"SELECT security.apply_administration($1::jsonb)::text",request.ToJsonString());
        return JsonSerializer.Deserialize<JsonElement>((string)(await command.ExecuteScalarAsync(ct))!);
    },c.RequestAborted,administration:true);
    if(result.GetProperty("kind").GetString()=="human")session.CustomProfiles[result.GetProperty("login").GetString()!]=result.GetProperty("name").GetString()!;
    return Results.Ok(result);
});
app.MapPost("/api/admin/create",(HttpContext c,AdminCreate body)=>AdminMutation(c,body,"create"));
app.MapPost("/api/admin/update",(HttpContext c,AdminUpdate body)=>AdminMutation(c,body,"update"));
var files=new PhysicalFileProvider(webRoot);
app.UseDefaultFiles(new DefaultFilesOptions {FileProvider=files});
app.UseStaticFiles(new StaticFileOptions {FileProvider=files});
app.Lifetime.ApplicationStarted.Register(()=>Console.WriteLine($"PREVIEW_READY http://127.0.0.1:{port}"));
await app.RunAsync();

[System.Text.Json.Serialization.JsonUnmappedMemberHandling(System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow)]
public sealed record AdminCreate(Guid OperationId,string? Login,string? Name,string? Kind,string[]? Roles);
[System.Text.Json.Serialization.JsonUnmappedMemberHandling(System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow)]
public sealed record AdminUpdate(Guid OperationId,Guid Id,int ExpectedVersion,string? Name,bool? Enabled,string[]? Roles);
public sealed record ProfileRequest(string Profile);
public sealed record BuildRequest(Guid SnapshotId,string Curve);
public sealed record HistoryRequest(Guid SnapshotId,string Curve,Guid? ContractId=null,Guid? SeriesId=null);
public sealed record HistorySample(DateTimeOffset At,string? Value,Guid SnapshotId,Guid[] ObservationIds,string? UnavailableReason);
public sealed record CorrectionRequest(Guid SnapshotId,Guid ObservationId,string Value);
public sealed record SelectionRequest(Guid SnapshotId,Guid ObservationId);
public sealed class PreviewSession
{
    public DateTimeOffset Created {get;}=DateTimeOffset.UtcNow;
    public SemaphoreSlim Gate {get;}=new(1,1);
    public string? Profile {get;set;}
    public ScheduleContext? MarketContext {get;set;}
    public Dictionary<string,string> CustomProfiles {get;}=[];
    public Dictionary<Guid,InputFrame> Frames {get;}=[];
    public PreviewShortcutLibrary Shortcuts {get;}=new();
    public DateWorkspace Dates {get;}=new();
    public Dictionary<(string Owner,string Code),BoundContractDefinition> ContractDefinitions {get;}=[];
    public Guid[] InitialFrames {get;}
    public PreviewSession(PreviewManifest manifest)
    {
        foreach(var f in manifest.Frames) {
            if(f.CurveContracts is null)throw new MarketDataException("missing_curve_view","Every seed frame requires explicit curve contract selections.");
            var frame=new InputFrame(Guid.NewGuid(),"Initial synthetic inputs",f.At,f.ObservationIds.ToImmutableArray(),
                f.CurveContracts.ToImmutableDictionary(p=>p.Key,p=>p.Value.ToImmutableArray()));Frames.Add(frame.Id,frame);
        }
        InitialFrames=Frames.Keys.ToArray();
    }
}
