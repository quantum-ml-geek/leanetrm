using System.Collections.Immutable;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power;

namespace OpenEtrm.Api;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PowerCatalogRequest(Guid SnapshotId);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PowerPreviewRequest(Guid SnapshotId,string Curve,Guid ContractId,string Product,int ProductVersion,string Block,
    int Minutes,string HourLabels,string Megawatts,string PriceType,string Timing,
    string NonHolidays,string Holidays,string NumericalPolicy);

// Unsaved, explicitly synthetic product bindings read from versioned reference rows.
// This is not a publication API or a replacement for the curve's contractual profile.
public static class PowerPreview
{
    // A published TOU product version with its resolved clock rule.
    public sealed record Product(string Code,string Name,int Version,ClockRule Clock,int Start,int End,bool Saturday);
    // Products whose clock is outside this workspace's reference data are listed as unavailable, never dropped silently.
    public sealed record ProductSet(ImmutableArray<Product> Available,ImmutableArray<TouProductVersion> Unavailable);
    public static ProductSet Products(IEnumerable<TouProductVersion> published,IReadOnlyCollection<ClockChoice> clocks)
    {
        var resolved=published.Select(v=>(Version:v,Clock:clocks.SingleOrDefault(c=>c.Reference==v.Clock))).ToArray();
        return new([..resolved.Where(r=>r.Clock is not null).Select(r=>new Product(r.Version.Code,r.Version.Name,r.Version.Version,r.Clock!.Rule,
            r.Version.PeakStartHour,r.Version.PeakEndHour,r.Version.PeakSaturday))],[..resolved.Where(r=>r.Clock is null).Select(r=>r.Version)]);
    }
    // Engine capabilities, not reference data: the supported mask blocks, grids and labels.
    private static readonly (string Code,string Name)[] Blocks=[("all","All hours"),("peak","On-peak"),("off","Off-peak")];
    private static readonly int[] Intervals=[60,30,15,5];
    private static readonly (string Code,string Name)[] HourLabels=[("HE","Hour ending · HE"),("HB","Hour beginning · HB")];
    // Suggested index classification labels; any explicit label up to 40 characters is accepted.
    private static readonly string[] PriceTypes=["Test","Official"],Timings=["End of day","Intraday"];
    private static TimeOfUse Mask(Product p,string block,int minutes) => block switch
    {
        "all"=>TimeOfUse.All(minutes),
        "peak"=>TimeOfUse.WeekdayBlock(minutes,p.Start,p.End,p.Saturday),
        "off"=>TimeOfUse.WeekdayBlock(minutes,p.Start,p.End,p.Saturday).Complement(),
        _=>throw new MarketDataException("tou_grid","Choose all hours, on-peak or off-peak.")
    };
    private static bool SingleIndex(PreviewData data,JsonElement curve)
    {
        var target=data.References["settlement_targets"].Single(t=>t.Text("code")==curve.Text("settlement_target_code"));
        return target.Text("kind")=="index" && target.OptionalText("index_b_code") is null && target.OptionalText("index_a_code") is not null;
    }
    // The single explicitly bound settlement index of a power curve and its calendar.
    private static (JsonElement Index,JsonElement Calendar) SettlementIndex(PreviewData data,JsonElement curve)
    {
        if(!SingleIndex(data,curve))
            throw new MarketDataException("power_index","The preview supports a single explicitly bound index, not futures settlement or index differences.");
        var target=data.References["settlement_targets"].Single(t=>t.Text("code")==curve.Text("settlement_target_code"));
        var indexCode=target.Text("index_a_code");
        var index=data.References["price_index_definitions"].Single(i=>i.Text("code")==indexCode);
        return (index,data.References["calendars"].Single(c=>c.Text("code")==index.Text("calendar_code")));
    }
    // Closed dates inside [from,to) from the index calendar; the calendar must cover the whole period.
    private static DateOnly[] Holidays(PreviewData data,JsonElement calendar,DateOnly from,DateOnly to)
    {
        var code=calendar.Text("code");
        if(DateWorkspace.Date(calendar.Text("coverage_from"))>from || DateWorkspace.Date(calendar.Text("coverage_to"))<to)
            throw new MarketDataException("power_calendar",$"Calendar {code} does not cover the whole delivery period.");
        return data.References["calendar_days"].Where(d=>d.Text("calendar_code")==code && d.Text("is_business_day")=="false")
            .Select(d=>DateWorkspace.Date(d.Text("business_date"))).Where(d=>d>=from && d<to).Order().ToArray();
    }
    private static bool PerMwhOutright(PreviewData data,JsonElement c)
    {
        var quote=data.References["quote_specifications"].Single(q=>q.Text("code")==c.Text("quote_code"));
        var quantity=data.References["quantity_specifications"].Single(q=>q.Text("code")==quote.Text("quantity_code"));
        // The hour engine settles energy in MWh; the quote must be an outright price per MWh of the curve's own commodity.
        return quantity.Text("commodity_code")==c.Text("commodity_code") && quantity.Text("unit_code")=="megawatt_hour" && quote.Text("kind")=="outright";
    }
    public static object Catalog(PreviewData data,InputFrame frame,ProductSet set)
    {
        var products=set.Available;
        return new
        {
            products=products.Select(p=>new {p.Code,p.Name,p.Version,clock=p.Clock.Code}),
            unavailableProducts=set.Unavailable.Select(v=>new {v.Code,v.Name,v.Version,reason="Its market clock is outside this workspace's reference data."}),
            blocks=Blocks.Select(b=>new {code=b.Code,name=b.Name}),intervals=Intervals,
            hourLabels=HourLabels.Select(h=>new {code=h.Code,name=h.Name}),
            classifications=new {priceTypes=PriceTypes,timings=Timings},
            presets=products.SelectMany(p=>Blocks.SelectMany(block=>Intervals.Select(minutes=>
            {
                var mask=Mask(p,block.Code,minutes);
                return new {product=p.Code,block=block.Code,minutes,mask.NonHolidays,mask.Holidays,
                    columns=Enumerable.Range(0,mask.Columns).Select(i=>new {
                        he=$"HE{i*minutes/60+1:D2}"+(minutes==60?"":$" +{i*minutes%60:D2}m"),
                        hb=$"HB{i*minutes/60:D2}"+(minutes==60?"":$" +{i*minutes%60:D2}m")}).ToArray()};
            }))),
            // Only curves the calculation supports are offered; one unsupported curve never hides the rest.
            curves=data.Definitions["curves"].Where(c=>PerMwhOutright(data,c) && SingleIndex(data,c)).Select(c=>new {code=c.Text("code"),
                holidayCalendar=SettlementIndex(data,c).Calendar.Text("code"),
                contracts=data.Contracts.Where(k=>frame.CurveContracts.TryGetValue(c.Text("code"),out var members)&&members.Contains(k.Key.Id)).Select(k=>new {
                    id=k.Key.Id,from=k.DeliveryFrom.ToString("yyyy-MM-dd",CultureInfo.InvariantCulture),to=k.DeliveryTo.ToString("yyyy-MM-dd",CultureInfo.InvariantCulture)}).ToArray()}),
            weekdays=new[]{"Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"},
            numericalPolicy=PowerSettlementPolicy.Preview.Implementation
        };
    }
    public static object Calculate(PreviewData data,InputFrame frame,PowerPreviewRequest body,ProductSet set)
    {
        if(string.IsNullOrWhiteSpace(body.Megawatts) || !HourLabels.Any(h=>h.Code==body.HourLabels) ||
            body.NumericalPolicy!=PowerSettlementPolicy.Preview.Implementation ||
            new[]{body.PriceType,body.Timing}.Any(s=>string.IsNullOrWhiteSpace(s)||s.Length>40||s.Any(char.IsControl)))
            throw new MarketDataException("power_input","Supply hour labels, classifications and the explicit numerical policy.");
        if(set.Unavailable.Any(v=>v.Code==body.Product))
            throw new MarketDataException("clock_reference","This TOU product's market clock is outside this workspace's reference data.");
        var product=set.Available.SingleOrDefault(p=>p.Code==body.Product)??throw new MarketDataException("power_input","Choose a power product example.");
        // The check is pinned to the product version its hour grid was built from; a newer publication is never substituted.
        if(product.Version!=body.ProductVersion)
            throw new MarketDataException("tou_conflict",$"TOU product {product.Code} is now version {product.Version}; reload the product before checking hours.");
        // Require a known preset choice even when its grids have been edited.
        _=Mask(product,body.Block,body.Minutes);
        var mask=new TimeOfUse(body.Minutes,body.NonHolidays,body.Holidays);
        var curve=data.Definitions["curves"].SingleOrDefault(c=>c.Text("code")==body.Curve);
        if(curve.ValueKind==System.Text.Json.JsonValueKind.Undefined)throw new MarketDataException("missing_curve","Choose an available curve.");
        var quote=data.References["quote_specifications"].Single(q=>q.Text("code")==curve.Text("quote_code"));
        var quantity=data.References["quantity_specifications"].Single(q=>q.Text("code")==quote.Text("quantity_code"));
        if(!PerMwhOutright(data,curve) || quote.Number("multiplier")!=ExactDecimal.Parse("1"))
            throw new MarketDataException("power_units","This example requires an outright price per MWh with multiplier one.");
        var built=data.Build(frame,body.Curve);
        var value=built.Values.SingleOrDefault(v=>v.Request.Contract.Id==body.ContractId)??throw new MarketDataException("power_contract","Choose a contract in the selected curve and market view.");
        var contract=data.Contracts.Single(k=>k.Key.Id==body.ContractId);
        var (indexDefinition,calendar)=SettlementIndex(data,curve);
        var holidays=Holidays(data,calendar,contract.DeliveryFrom,contract.DeliveryTo);
        var clock=PowerClock.FromRule(product.Clock,TimeZoneDatabase.Installed());
        var periods=PowerHours.Compile(contract.DeliveryFrom,contract.DeliveryTo,clock,mask,holidays,body.Minutes);
        var currency=data.References["currencies"].Single(c=>c.Text("code")==quote.Text("currency_code"));
        var powerUnit=data.References["units"].Single(u=>u.Text("code")=="megawatt" && u.Text("dimension_code")=="power");
        if(currency.Text("display_minor_units")!="2")
            throw new MarketDataException("settlement_policy","The preview's explicit cash rounding supports two minor units.");
        var references=new ReferenceRevision(quote.Id("catalog_id"),quote.Id("revision_id"));
        var indexCode=indexDefinition.Text("code");
        if(indexDefinition.Text("commodity_code")!=curve.Text("commodity_code") ||
            indexDefinition.Text("currency_code")!=quote.Text("currency_code") ||
            indexDefinition.Text("quote_unit_code")!=quantity.Text("unit_code") ||
            indexDefinition.Number("quote_multiplier")!=ExactDecimal.Parse("1"))
            throw new MarketDataException("power_index","Index commodity, currency and unit must match the selected power quote exactly.");
        var index=new PowerIndex(new(references,indexCode),new(references,quote.Text("currency_code")),new(references,"megawatt_hour"),body.PriceType,body.Timing);
        // All-in values have no invented LMP decomposition. Component-aware
        // settlement is independently checked in the domain tests.
        var fixings=periods.Select(p=>new PowerFixing(p.Start,p.End,index,value.Value,null)).ToArray();
        var byStart=fixings.ToDictionary(f=>f.Start);
        var summary=PowerSettlement.Calculate(periods,fixings,index,ExactDecimal.Parse(body.Megawatts),PowerSettlementPolicy.Preview);
        return new {summary,currency=currency.Text("display_code"),mark=value.Value.ToString(),at=frame.At,
            from=contract.DeliveryFrom.ToString("yyyy-MM-dd",CultureInfo.InvariantCulture),to=contract.DeliveryTo.ToString("yyyy-MM-dd",CultureInfo.InvariantCulture),
            synthetic=true,saved=false,clock=new {clock.Id,clock.Fingerprint,rules=clock.Rules},
            pins=new {definitions=data.Definitions["revisions"][0],quote,quantity,curve,powerUnit,indexDefinition},
            holidays,holidayCalendar=calendar.Text("code"),clockRule=product.Clock,mask,megawatts=body.Megawatts,product=product.Name,productVersion=product.Version,
            days=periods.GroupBy(p=>p.OperatingDate).Select(g=>new {date=g.Key.ToString("yyyy-MM-dd",CultureInfo.InvariantCulture),
                intervals=g.Count(),hours=PowerSettlement.Calculate(g.ToArray(),g.Select(p=>byStart[p.Start]).ToArray(),index,ExactDecimal.Parse(body.Megawatts),PowerSettlementPolicy.Preview).Hours}).ToArray(),
            rows=periods.Select(p=>new {label=PowerHours.Label(p,body.HourLabels=="HE"),p.Start,p.End,p.OffsetMinutes,p.Occurrence,p.Holiday,price=value.Value.ToString()}).ToArray()};
    }
}
