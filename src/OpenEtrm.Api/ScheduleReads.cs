using System.Collections.Immutable;
using Npgsql;
using OpenEtrm.MarketData;

namespace OpenEtrm.Api;

public sealed record ScheduleLibrary(int KnownThrough,ImmutableArray<ScheduleVersion> Versions,bool CanEdit,bool CanPublish,ImmutableArray<LibraryCalendar> Calendars);
// A reference calendar's exact version, coverage and weekend days, with the dates its day rows close or open.
public sealed record LibraryCalendar(CalendarReference Reference,DateOnly CoverageFrom,DateOnly CoverageTo,ImmutableArray<string> WeekendDays,
    ImmutableArray<DateOnly> ClosedDates,ImmutableArray<DateOnly> OpenDates)
{
    public static LibraryCalendar From(ReferenceCalendar calendar)=>new(calendar.Reference,calendar.CoverageFrom,calendar.CoverageTo,[..calendar.WeekendDays],
        [..calendar.Days.Where(d=>!d.Open).Select(d=>d.Date)],[..calendar.Days.Where(d=>d.Open).Select(d=>d.Date)]);
}
public sealed record TouProductLibrary(ImmutableArray<TouProductVersion> Versions,ImmutableArray<ClockChoice> Clocks,bool CanEdit,bool CanPublish);

// Schedule reads callable without an HTTP request or workspace session, on the same terms as
// MarketReads. Date schedules and their calendars follow the pin; TOU products and power hours
// are current definitions, which a historical pin refuses rather than substitutes.
public sealed class ScheduleReads(PreviewDatabase database)
{
    readonly ScheduleStore schedules=new(database.Manifest.CatalogId,database.Manifest.ReferenceCatalogId,database.Manifest.ReferenceRevisionId);
    readonly TouProductStore products=new(database.Manifest.CatalogId,database.Manifest.ReferenceCatalogId,database.Manifest.ReferenceRevisionId);

    // Row security returns drafts to authors only; readers receive published versions. A historical view is read-only.
    public async Task<ScheduleLibrary> Library(NpgsqlConnection connection,PinnedContext pin,CancellationToken ct)
    {
        await pin.Bind(connection,database.Manifest.CatalogId,ct);
        // Working data reads the publication head under the capture lock, which publication also
        // takes, so the versions read next are exactly those published through it.
        var (knownThrough,versions)=pin.Context is {} context
            ?(context.KnownThrough!.Value,await schedules.ReadAt(connection,context,ct))
            :(await schedules.Capture(connection,ct),await schedules.Read(connection,ct));
        var working=pin.Context is null;
        return new(knownThrough,versions,
            working&&await PreviewDatabase.HasPermission(connection,"WriteMarketDefinitions",ct),
            working&&await PreviewDatabase.HasPermission(connection,"SealMarketDefinitions",ct),
            [..(await schedules.Calendars(connection,ct)).Select(LibraryCalendar.From)]);
    }

    // Row security returns drafts to authors only; readers receive published versions.
    public async Task<TouProductLibrary> TouProducts(NpgsqlConnection connection,PinnedContext pin,CancellationToken ct)
    {
        RequireCurrent(pin);
        var canEdit=await PreviewDatabase.HasPermission(connection,"WriteMarketDefinitions",ct);
        var canPublish=await PreviewDatabase.HasPermission(connection,"SealMarketDefinitions",ct);
        return new(await products.Read(connection,ct),await products.Clocks(connection,ct),canEdit,canPublish);
    }

    // Each TOU product's latest published version, resolved to its market clock.
    public async Task<PowerPreview.ProductSet> PublishedProducts(NpgsqlConnection connection,PinnedContext pin,CancellationToken ct)
    {
        RequireCurrent(pin);
        return PowerPreview.Products(TouProductStore.Published(await products.Read(connection,ct)),await products.Clocks(connection,ct));
    }

    // The power hours offered in the pinned frame: published products, their masks and the frame's single-index contracts.
    public async Task<object> PowerCatalog(NpgsqlConnection connection,PinnedContext pin,CancellationToken ct)
    {
        var frame=RequireCurrent(pin).RequireFrame();
        return PowerPreview.Catalog(await database.Read(connection,ct,observationIds:[]),frame,await PublishedProducts(connection,pin,ct));
    }

    // Current definitions are read with no market context bound: row security hides TOU products
    // under any bound context. A historical pin is refused rather than given current definitions.
    public static PinnedContext RequireCurrent(PinnedContext pin)=>pin.Context is null?pin:
        throw new MarketDataException("power_historical","TOU products and power hours require current inputs; historical TOU publication is not implemented.");
}
