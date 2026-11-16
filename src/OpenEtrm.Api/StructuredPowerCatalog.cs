using System.Collections.Immutable;
using System.Text.Json;
using OpenEtrm.MarketData;

namespace OpenEtrm.Api;

public sealed record StructuredPowerPins(Guid DefinitionCatalogId,Guid DefinitionRevisionId,Guid ReferenceCatalogId,Guid ReferenceRevisionId);
public sealed record StructuredPowerChoice(string Code,string Label);
public sealed record StructuredPowerKindChoice(string Code,string Label,ImmutableArray<int> IntervalMinutes);
public sealed record StructuredPowerQuantityChoice(string Code,string Label,string CommodityCode,string UnitCode,string DimensionCode);
public sealed record StructuredPowerQuoteChoice(string Code,string Label,string QuantityCode,string CurrencyCode,string Multiplier);
public sealed record StructuredPowerSideChoice(string Kind,string Code,string Label,string QuantityKind)
{
    public ImmutableArray<string> AllowedKinds=>Code=="horizon_right"?["payment"]:["payment","delivery"];
}
public sealed record StructuredPowerCatalogResult(StructuredPowerPins Pins,ImmutableArray<StructuredPowerChoice> Locations,
    ImmutableArray<StructuredPowerChoice> Clocks,ImmutableArray<StructuredPowerKindChoice> Kinds,
    ImmutableArray<StructuredPowerQuantityChoice> PowerQuantities,ImmutableArray<StructuredPowerQuantityChoice> EnergyQuantities,
    ImmutableArray<StructuredPowerQuantityChoice> FuelQuantities,ImmutableArray<StructuredPowerQuantityChoice> RightQuantities,
    ImmutableArray<StructuredPowerChoice> Currencies,ImmutableArray<StructuredPowerQuoteChoice> Quotes,string PaymentImplementation,bool CanSave,bool CanPreview)
{
    public ImmutableArray<StructuredPowerPriceContract> PriceContracts { get; init; }=[];
    public ImmutableArray<string> OperatingBookingClockCodes { get; init; }=[];
    public string CompositionImplementation=>StructuredPowerPreview.CompositionImplementation;
    public ImmutableArray<StructuredPowerSideChoice> SideChoices=>StructuredPowerPreview.SideChoices;
    public int MaximumSides=>StructuredPowerPreview.MaximumOperatingSides;
}

public static partial class StructuredPowerPreview
{
    internal static readonly ImmutableArray<StructuredPowerSideChoice> SideChoices=[
        new("thermal","energy_output","Generated output energy","energy"),new("thermal","guaranteed_fuel","Contract guaranteed fuel","fuel"),new("thermal","consumption_fuel","Modeled fuel consumption","fuel"),
        new("battery","discharging_energy","Grid discharging energy","energy"),new("battery","charging_energy","Grid charging energy","energy"),new("battery","grid_throughput","Grid charging plus discharging energy","energy"),
        new("solar","energy_output","Entitled physical production","energy"),new("solar","payment_energy","Contract payment energy","energy"),
        new("thermal","horizon_right","Complete right once; first operating month billing","right"),new("battery","horizon_right","Complete right once; first operating month billing","right"),new("solar","horizon_right","Complete right once; first operating month billing","right")];
    private static string SourcePort(string source)=>source switch
    {"energy_output" or "discharging_energy"=>"energy","charging_energy"=>"charge","grid_throughput"=>"variable","payment_energy"=>"payment",_=>source};
    public static StructuredPowerCatalogResult Catalog(PreviewData data,bool canSave,bool canPreview)
    {
        static string Label(JsonElement row)=>Text(row,"name")??Text(row,"symbol")??row.Text("code");
        static string? Text(JsonElement row,string field)=>row.TryGetProperty(field,out var value)&&value.ValueKind==JsonValueKind.String?value.GetString():null;
        ImmutableArray<StructuredPowerChoice> Choices(string table)=>data.References.TryGetValue(table,out var rows)?
            [..rows.Select(row=>new StructuredPowerChoice(row.Text("code"),Label(row)))]:[];
        var quantities=data.References["quantity_specifications"].Select(row=>new StructuredPowerQuantityChoice(row.Text("code"),Label(row),row.Text("commodity_code"),row.Text("unit_code"),row.Text("dimension_code"))).ToArray();
        return new(new(data.DefinitionRevision.CatalogId,data.DefinitionRevision.RevisionId,data.ReferenceRevision.CatalogId,data.ReferenceRevision.RevisionId),
            Choices("locations"),Choices("clock_rules"),[new("battery","Battery storage",[5,15,30,60]),new("thermal","Thermal tolling",[15,60]),new("solar","Solar output right",[15,60])],
            [..quantities.Where(x=>x.UnitCode=="megawatt"&&x.DimensionCode=="power")],[..quantities.Where(x=>x.UnitCode=="megawatt_hour"&&x.DimensionCode=="energy")],
            [..quantities.Where(x=>x.DimensionCode=="energy")],[..quantities.Where(x=>x.UnitCode=="resource_right"&&CompleteRightDimension(data,x.DimensionCode))],
            Choices("currencies"),[..data.Quotes.Where(x=>x.Kind==QuoteKind.Outright).Select(x=>new StructuredPowerQuoteChoice(x.Key.Code,$"{x.Key.Code} · {x.Currency.Code} per {x.Quantity.Code} × {x.Multiplier}",x.Quantity.Code,x.Currency.Code,x.Multiplier.ToString()))],OpenEtrm.MarketData.Trading.PaymentRule.Implementation,canSave,canPreview)
        {OperatingBookingClockCodes=[..data.References["clock_rules"].Where(r=>r.Text("kind")=="fixed_offset"&&r.Number("fixed_offset_seconds")==default).Select(r=>r.Text("code"))]};
    }
}
