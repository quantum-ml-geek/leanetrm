using System.Collections.Immutable;
using System.Text.Json;
using OpenEtrm.MarketData;

namespace OpenEtrm.Api;

public sealed record StructuredPowerPins(Guid DefinitionCatalogId,Guid DefinitionRevisionId,Guid ReferenceCatalogId,Guid ReferenceRevisionId);
public sealed record StructuredPowerChoice(string Code,string Label);
public sealed record StructuredPowerKindChoice(string Code,string Label,ImmutableArray<int> IntervalMinutes);
public sealed record StructuredPowerQuantityChoice(string Code,string Label,string CommodityCode,string UnitCode,string DimensionCode);
public sealed record StructuredPowerQuoteChoice(string Code,string Label,string QuantityCode,string CurrencyCode,string Multiplier);
public sealed record StructuredPowerCatalogResult(StructuredPowerPins Pins,ImmutableArray<StructuredPowerChoice> Locations,
    ImmutableArray<StructuredPowerChoice> Clocks,ImmutableArray<StructuredPowerKindChoice> Kinds,
    ImmutableArray<StructuredPowerQuantityChoice> PowerQuantities,ImmutableArray<StructuredPowerQuantityChoice> EnergyQuantities,
    ImmutableArray<StructuredPowerQuantityChoice> FuelQuantities,ImmutableArray<StructuredPowerQuantityChoice> RightQuantities,
    ImmutableArray<StructuredPowerChoice> Currencies,ImmutableArray<StructuredPowerQuoteChoice> Quotes,string PaymentImplementation,bool CanSave,bool CanPreview);

public static partial class StructuredPowerPreview
{
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
            Choices("currencies"),[..data.Quotes.Where(x=>x.Kind==QuoteKind.Outright).Select(x=>new StructuredPowerQuoteChoice(x.Key.Code,$"{x.Key.Code} · {x.Currency.Code} per {x.Quantity.Code} × {x.Multiplier}",x.Quantity.Code,x.Currency.Code,x.Multiplier.ToString()))],OpenEtrm.MarketData.Trading.PaymentRule.Implementation,canSave,canPreview);
    }
}
