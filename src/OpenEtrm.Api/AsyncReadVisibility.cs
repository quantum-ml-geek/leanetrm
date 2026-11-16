using System.Collections.Immutable;
using Npgsql;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

internal sealed record AsyncReadBookScope(Guid Catalog,ImmutableArray<Guid> Ids);
internal sealed record AsyncReadCalendar(ReferenceKey Reference,CalendarPublicationProof Publication);
internal sealed record AsyncReadInstrument(Guid Catalog,Guid Id,Guid? Context,DateTimeOffset? AsOf,int Members);
internal sealed record AsyncReadVisibilityProof(ImmutableArray<PreviewManifest> Bundles,ImmutableArray<PreviewManifest> References,
    ImmutableArray<(Guid Catalog,Guid Revision)> Versions,ImmutableArray<Guid> Catalogs,ImmutableArray<AsyncReadBookScope> Books,
    ImmutableArray<AsyncReadCalendar> Calendars,ImmutableArray<AsyncReadInstrument> Instruments)
{
    internal async Task Require(NpgsqlConnection connection,CancellationToken ct)
    {
        foreach(var scope in Books)
        {
            var rows=await PreviewDatabase.Rows(connection,"SELECT json_build_object('id',id)::text FROM trading.books WHERE catalog_id=$1 AND id=ANY($2::uuid[])",[scope.Catalog,scope.Ids.ToArray()],ct);
            if(!scope.Ids.ToHashSet().SetEquals(rows.Select(row=>row.Id("id"))))throw new PreviewDeniedException();
        }
        foreach(var manifest in Bundles)await MarketBundle.Require(connection,manifest,ct);
        foreach(var manifest in References)await MarketBundle.RequireReferenceVisibility(connection,manifest,ct);
        foreach(var(catalog,revision)in Versions)
        {
            await using var check=ScheduleStore.Command(connection,"SELECT security.reference_access($1,'ReadMarketData') AND security.reference_version_visible($1,$2)",catalog,revision);
            if(!Equals(await check.ExecuteScalarAsync(ct),true))throw new PreviewDeniedException();
        }
        if(!Catalogs.IsEmpty)
        {
            await using var check=ScheduleStore.Command(connection,"SELECT bool_and(security.reference_access(catalog,'ReadMarketData')) FROM unnest($1::uuid[]) catalog",Catalogs.ToArray());
            if(!Equals(await check.ExecuteScalarAsync(ct),true))throw new PreviewDeniedException();
        }
        foreach(var calendar in Calendars)await SideCalendarPolicies.RequirePublication(connection,calendar.Reference,calendar.Publication,ct);
        foreach(var instrument in Instruments)await new RetainedScheduleStore(instrument.Catalog).RequireProgramAuthority(connection,
            instrument.Id,instrument.Context,instrument.AsOf,instrument.Members,ct);
    }
}

// Exact coordinates touched by one asynchronous read are inputs to fresh
// publication checks, never cached authorization decisions. Nested scopes restore
// their parent; parallel worker execution contexts never share this collector.
internal sealed class AsyncReadVisibility:IDisposable
{
    internal const int MaximumCoordinates=512,MaximumBooks=4096,MaximumInstruments=4096;
    static readonly AsyncLocal<AsyncReadVisibility?> current=new();
    readonly AsyncReadVisibility? prior;
    readonly object gate=new();
    readonly Dictionary<(Guid Catalog,Guid Revision,Guid References,Guid ReferenceRevision),PreviewManifest> bundles=[];
    readonly Dictionary<(Guid Catalog,Guid Revision),PreviewManifest> references=[];
    readonly HashSet<Guid> referenceCatalogs=[];
    readonly HashSet<(Guid Catalog,Guid Revision)> referenceVersions=[];
    readonly Dictionary<Guid,HashSet<Guid>> books=[];
    readonly HashSet<AsyncReadCalendar> calendars=[];
    readonly HashSet<AsyncReadInstrument> instruments=[];
    internal AsyncReadVisibility(){prior=current.Value;current.Value=this;}
    internal static void Bundle(PreviewManifest manifest)=>current.Value?.Capture(manifest,true);
    internal static void Reference(PreviewManifest manifest)=>current.Value?.Capture(manifest,false);
    internal static void Books(Guid catalog,IEnumerable<Guid> ids)
    {
        if(current.Value is not {} scope)return;
        lock(scope.gate)
        {
            if(!scope.books.TryGetValue(catalog,out var selected))scope.books[catalog]=selected=[];
            selected.UnionWith(ids);scope.RequireLimit();
        }
    }
    internal static void ReferenceCatalog(Guid catalog)
    {
        if(current.Value is not {} scope)return;
        lock(scope.gate){scope.referenceCatalogs.Add(catalog);scope.RequireLimit();}
    }
    internal static void ReferenceVersion(Guid catalog,Guid revision)
    {
        if(current.Value is not {} scope)return;
        lock(scope.gate){scope.referenceVersions.Add((catalog,revision));scope.RequireLimit();}
    }
    internal static void Calendar(ReferenceKey reference,CalendarPublicationProof publication)
    {
        if(current.Value is not {} scope)return;
        lock(scope.gate){scope.calendars.Add(new(reference,publication));scope.RequireLimit();}
    }
    internal static void Instrument(Guid catalog,Guid id,Guid? context,DateTimeOffset? asOf,int members)
    {
        if(current.Value is not {} scope)return;
        lock(scope.gate){scope.instruments.Add(new(catalog,id,context,asOf,members));scope.RequireLimit();}
    }
    void RequireLimit()
    {
        if(bundles.Count+references.Count+referenceCatalogs.Count+referenceVersions.Count+calendars.Count>MaximumCoordinates||books.Sum(p=>p.Value.Count)>MaximumBooks||instruments.Count>MaximumInstruments)
            throw new AsyncReadException(422,"async_visibility_limit","The read exceeds the bounded publication evidence limit.");
    }
    void Capture(PreviewManifest manifest,bool bundle)
    {
        lock(gate)
        {
            if(bundle)bundles.TryAdd((manifest.CatalogId,manifest.RevisionId,manifest.ReferenceCatalogId,manifest.ReferenceRevisionId),manifest);
            else references.TryAdd((manifest.ReferenceCatalogId,manifest.ReferenceRevisionId),manifest);
            RequireLimit();
        }
    }
    internal AsyncReadVisibilityProof Seal()
    {
        lock(gate)
        {
            ImmutableArray<PreviewManifest> exactBundles=[..bundles.Values];
            var covered=exactBundles.Select(m=>(m.ReferenceCatalogId,m.ReferenceRevisionId)).ToHashSet();
            ImmutableArray<PreviewManifest> exactReferences=[..references.Where(p=>!covered.Contains(p.Key)).Select(p=>p.Value)];
            covered.UnionWith(exactReferences.Select(m=>(m.ReferenceCatalogId,m.ReferenceRevisionId)));
            ImmutableArray<(Guid Catalog,Guid Revision)> versions=[..referenceVersions.Where(v=>!covered.Contains(v))];
            var checkedCatalogs=covered.Select(v=>v.Item1).Concat(versions.Select(v=>v.Catalog)).ToHashSet();
            return new(exactBundles,exactReferences,versions,[..referenceCatalogs.Where(c=>!checkedCatalogs.Contains(c))],
                [..books.Select(p=>new AsyncReadBookScope(p.Key,[..p.Value]))],[..calendars],[..instruments]);
        }
    }
    public void Dispose()=>current.Value=prior;
}
