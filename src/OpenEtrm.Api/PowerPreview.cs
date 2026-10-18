using System.Globalization;
using System.Text.Json.Serialization;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power;

namespace OpenEtrm.Api;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PowerCatalogRequest(Guid SnapshotId);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PowerAmountInput(string Value,ReferenceKey Specification);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PowerDisplayInput(int Quantity,int Price,int Money);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PowerPreviewRequest(Guid SnapshotId,string Curve,Guid ContractId,string Product,string Block,
    int Minutes,string HourLabels,PowerAmountInput Quantity,string QuantityBasis,string? Allocation,string PriceType,string Timing,string[] HolidayDates,
    string NonHolidays,string Holidays,string NumericalPolicy,PowerDisplayInput Display);

// Unsaved, explicitly synthetic product bindings. This is not a publication API
// or a replacement for the selected curve's existing contractual profile.
public static class PowerPreview
{
    private sealed record Product(string Code,string Name,string Zone,int Start,int End,bool Saturday,bool Fixed);
    private static readonly Product[] Products=[
        new("pjm","PJM · Eastern prevailing","America/New_York",7,23,false,false),
        new("ercot","ERCOT · Central prevailing","America/Chicago",6,22,false,false),
        new("caiso","CAISO / WECC · Pacific prevailing","America/Los_Angeles",6,22,true,false),
        new("miso","MISO settlement / FTR · fixed EST","fixed_est",6,22,false,true)];
    private static PowerClock Clock(Product p)=>PowerClock.Capture(p.Fixed?
        TimeZoneInfo.CreateCustomTimeZone("fixed_est",TimeSpan.FromHours(-5),"Fixed EST","Fixed EST"):
        TimeZoneInfo.FindSystemTimeZoneById(p.Zone));
    private static TimeOfUse Mask(Product p,string block,int minutes) => block switch
    {
        "all"=>TimeOfUse.All(minutes),
        "peak"=>TimeOfUse.WeekdayBlock(minutes,p.Start,p.End,p.Saturday),
        "off"=>TimeOfUse.WeekdayBlock(minutes,p.Start,p.End,p.Saturday).Complement(),
        _=>throw new MarketDataException("tou_grid","Choose all hours, on-peak or off-peak.")
    };
    public static object Catalog(PreviewData data,InputFrame frame) => new
    {
        products=Products.Select(p=>new {p.Code,p.Name}),
        presets=Products.SelectMany(p=>new[]{"all","peak","off"}.SelectMany(block=>new[]{5,15,30,60}.Select(minutes=>
        {
            var mask=Mask(p,block,minutes);
            return new {product=p.Code,block,minutes,mask.NonHolidays,mask.Holidays,
                columns=Enumerable.Range(0,mask.Columns).Select(i=>new {
                    he=$"HE{i*minutes/60+1:D2}"+(minutes==60?"":$" +{i*minutes%60:D2}m"),
                    hb=$"HB{i*minutes/60:D2}"+(minutes==60?"":$" +{i*minutes%60:D2}m")}).ToArray()};
        }))),
        curves=data.Definitions["curves"].Where(c=>
        {
            var quote=data.References["quote_specifications"].Single(q=>q.Text("code")==c.Text("quote_code"));
            var quantity=data.References["quantity_specifications"].Single(q=>q.Text("code")==quote.Text("quantity_code"));
            return c.Text("commodity_code")=="test_power" && quantity.Text("commodity_code")=="test_power" && quantity.Text("unit_code")=="megawatt_hour" && quote.Text("kind")=="outright";
        }).Select(c=>new {code=c.Text("code"),contracts=data.Contracts.Where(k=>
            frame.CurveContracts.TryGetValue(c.Text("code"),out var members)&&members.Contains(k.Key.Id)).Select(k=>new {
                id=k.Key.Id,from=k.DeliveryFrom.ToString("yyyy-MM-dd",CultureInfo.InvariantCulture),to=k.DeliveryTo.ToString("yyyy-MM-dd",CultureInfo.InvariantCulture)}).ToArray()}),
        weekdays=new[]{"Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"},
        quantityChoices=data.References["quantity_specifications"].Where(q=>q.Text("commodity_code")=="test_power" && q.Text("unit_code") is "megawatt" or "megawatt_hour")
            .Select(q=>new{basis=q.Text("unit_code")=="megawatt"?"flat_power":"total_energy",
                label=(q.Text("unit_code")=="megawatt"?"Flat MW over selected hours":"Total MWh for the delivery period")+" · "+q.Text("basis_code").Replace('_',' '),
                specification=new ReferenceKey(data.ReferenceRevision,q.Text("code"))}),
        display=new PowerDisplayInput(3,4,2),
        numericalPolicy=PowerSettlementPolicy.Preview.Implementation
    };
    public static object Calculate(PreviewData data,InputFrame frame,PowerPreviewRequest body)
    {
        if(body.Quantity is null || string.IsNullOrWhiteSpace(body.Quantity.Value) || body.Display is null || body.HolidayDates is null || body.HolidayDates.Length>366 || body.HourLabels is not ("HE" or "HB") ||
            body.NumericalPolicy!=PowerSettlementPolicy.Preview.Implementation ||
            new[]{body.PriceType,body.Timing}.Any(s=>string.IsNullOrWhiteSpace(s)||s.Length>40||s.Any(char.IsControl)))
            throw new MarketDataException("power_input","Supply hour labels, classifications, holiday dates and the explicit numerical policy.");
        var product=Products.SingleOrDefault(p=>p.Code==body.Product)??throw new MarketDataException("power_input","Choose a power product example.");
        // Require a known preset choice even when its grids have been edited.
        _=Mask(product,body.Block,body.Minutes);
        var mask=new TimeOfUse(body.Minutes,body.NonHolidays,body.Holidays);
        var holidays=body.HolidayDates.Select(s=>DateOnly.TryParseExact(s,"yyyy-MM-dd",CultureInfo.InvariantCulture,DateTimeStyles.None,out var date)?date:
            throw new MarketDataException("power_holidays","Use YYYY-MM-DD holiday dates.")).ToArray();
        var curve=data.Definitions["curves"].SingleOrDefault(c=>c.Text("code")==body.Curve);
        if(curve.ValueKind==System.Text.Json.JsonValueKind.Undefined)throw new MarketDataException("missing_curve","Choose an available curve.");
        var quote=data.References["quote_specifications"].Single(q=>q.Text("code")==curve.Text("quote_code"));
        var quantity=data.References["quantity_specifications"].Single(q=>q.Text("code")==quote.Text("quantity_code"));
        if(curve.Text("commodity_code")!="test_power" || quantity.Text("commodity_code")!="test_power" || quantity.Text("unit_code")!="megawatt_hour" || quote.Text("kind")!="outright" || quote.Number("multiplier")!=ExactDecimal.Parse("1"))
            throw new MarketDataException("power_units","This example requires an outright price per MWh with multiplier one.");
        var built=data.Build(frame,body.Curve);
        var value=built.Values.SingleOrDefault(v=>v.Request.Contract.Id==body.ContractId)??throw new MarketDataException("power_contract","Choose a contract in the selected curve and market view.");
        var contract=data.Contracts.Single(k=>k.Key.Id==body.ContractId);
        var clock=Clock(product);
        var basis=body.QuantityBasis switch{"flat_power"=>PowerQuantityBasis.FlatPower,"total_energy"=>PowerQuantityBasis.TotalEnergy,_=>throw new MarketDataException("power_quantity","Choose total MWh or flat MW explicitly.")};
        var allocation=body.Allocation switch{null=>(PowerAllocation?)null,"flat_rate"=>PowerAllocation.FlatRate,_=>throw new MarketDataException("power_quantity","Choose an explicit supported total-energy allocation.")};
        var source=data.References["quantity_specifications"].SingleOrDefault(q=>new ReferenceKey(data.ReferenceRevision,q.Text("code"))==body.Quantity.Specification);
        if(source.ValueKind==System.Text.Json.JsonValueKind.Undefined)throw new MarketDataException("power_quantity","Select an exact quantity specification from this market's reference revision.");
        QuantitySpecification Definition(System.Text.Json.JsonElement q)=>new(new(data.ReferenceRevision,q.Text("code")),new(data.ReferenceRevision,q.Text("commodity_code")),
            new(data.ReferenceRevision,q.Text("basis_code")),new(data.ReferenceRevision,q.Text("unit_code")),new(data.ReferenceRevision,q.Text("dimension_code")));
        var schedule=PowerQuantitySchedule.Compile(new(ExactDecimal.Parse(body.Quantity.Value),body.Quantity.Specification),basis,Definition(source),Definition(quantity),
            contract.DeliveryFrom,contract.DeliveryTo,clock,mask,holidays,body.Minutes,allocation);
        var periods=schedule.Intervals.Select(p=>p.Interval).ToArray();
        var quantityFormat=new AmountFormat(body.Display.Quantity,CashTieRule.ToEven,true,false);
        var priceFormat=new AmountFormat(body.Display.Price,CashTieRule.ToEven,true,false);
        var moneyFormat=new AmountFormat(body.Display.Money,CashTieRule.ToEven,true,false);
        var currency=data.References["currencies"].Single(c=>c.Text("code")==quote.Text("currency_code"));
        var powerUnit=data.References["units"].Single(u=>u.Text("code")=="megawatt" && u.Text("dimension_code")=="power");
        if(currency.Text("display_minor_units")!="2")
            throw new MarketDataException("settlement_policy","The preview's explicit cash rounding supports two minor units.");
        var references=new ReferenceRevision(quote.Id("catalog_id"),quote.Id("revision_id"));
        var target=data.References["settlement_targets"].Single(t=>t.Text("code")==curve.Text("settlement_target_code"));
        string? indexCode;
        if(target.Text("kind")=="index" && target.OptionalText("index_b_code") is null)indexCode=target.OptionalText("index_a_code");
        else if(target.Text("kind")=="future_series" && contract.FuturesSeries is {} seriesKey)
        {
            var series=data.References["futures_series"].Single(s=>s.Text("code")==seriesKey.Code);
            indexCode=data.References.GetValueOrDefault("futures_product_terms",[]).SingleOrDefault(i=>i.Text("product_code")==series.Text("product_code")) is var link && link.ValueKind!=System.Text.Json.JsonValueKind.Undefined?link.Text("index_code"):null;
        }
        else indexCode=null;
        if(indexCode is null)throw new MarketDataException("power_index","The preview requires one explicitly bound settlement index.");
        var indexDefinition=data.References["price_index_definitions"].Single(i=>i.Text("code")==indexCode);
        if(indexDefinition.Text("commodity_code")!=curve.Text("commodity_code") ||
            indexDefinition.Text("currency_code")!=quote.Text("currency_code") ||
            indexDefinition.Text("quote_unit_code")!=quantity.Text("unit_code") ||
            indexDefinition.Number("quote_multiplier")!=ExactDecimal.Parse("1"))
            throw new MarketDataException("power_index","Index commodity, currency and unit must match the selected power quote exactly.");
        var index=new PowerIndex(new(references,indexCode),new(references,quote.Text("currency_code")),new(references,"megawatt_hour"),new(references,quantity.Text("code")),body.PriceType,body.Timing);
        // All-in values have no invented LMP decomposition. Component-aware
        // settlement is independently checked in the domain tests.
        var fixings=periods.Select(p=>new PowerFixing(p.Start,p.End,index,value.Price.Value,null)).ToArray();
        var settled=PowerSettlement.Calculate(schedule,fixings,index,PowerSettlementPolicy.Preview);
        var currencyLabel=new AmountLabel(index.Currency,currency.Text("display_code"));
        var energyLabel=new AmountLabel(schedule.EnergyDefinition.Key,"MWh");
        var priceText=value.Price.ToString(priceFormat,currencyLabel,energyLabel);
        return new {summary=settled.Summary,currency=currency.Text("display_code"),mark=value.Price.Value.ToString(),at=frame.At,
            amounts=new{input=schedule.Input,energy=settled.Energy,cash=settled.Cash,
                energyText=settled.Energy.ToString(quantityFormat,energyLabel),cashText=settled.Cash.ToString(moneyFormat,currencyLabel),
                priceText},
            from=contract.DeliveryFrom.ToString("yyyy-MM-dd",CultureInfo.InvariantCulture),to=contract.DeliveryTo.ToString("yyyy-MM-dd",CultureInfo.InvariantCulture),
            synthetic=true,saved=false,clock=new {clock.Id,clock.Fingerprint,rules=clock.Rules},
            pins=new {definitions=data.Definitions["revisions"][0],quote,quantity,source,curve,powerUnit,indexDefinition},
            holidays,mask,quantityBasis=body.QuantityBasis,body.Allocation,body.Display,quantityImplementation=PowerQuantitySchedule.Implementation,product=product.Name,
            days=periods.GroupBy(p=>p.OperatingDate).Select(g=>new {date=g.Key.ToString("yyyy-MM-dd",CultureInfo.InvariantCulture),
                intervals=g.Count(),hours=new AmountFormat(18,CashTieRule.ToEven,false,true).FormatFraction(g.Sum(p=>(p.End-p.Start).Ticks),TimeSpan.TicksPerHour)}).ToArray(),
            rows=schedule.Intervals.Select(p=>new {label=PowerHours.Label(p.Interval,body.HourLabels=="HE"),p.Interval.Start,p.Interval.End,p.Interval.OffsetMinutes,p.Interval.Occurrence,p.Interval.Holiday,
                energy=p.Energy,energyText=p.Energy.ToString(quantityFormat,energyLabel),price=value.Price.Value.ToString(),priceText}).ToArray()};
    }
}
