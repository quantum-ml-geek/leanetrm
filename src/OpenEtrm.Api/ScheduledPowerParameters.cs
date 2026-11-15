using System.Text.Json;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

internal static class ScheduledPowerParameters
{
    // The enclosing program and its economic identity have already been verified.
    internal static ScheduledPowerQuantityParameters? FromRetained(string identity)
    {
        try
        {
            using var document=JsonDocument.Parse(identity);
            var saved=document.RootElement.GetProperty("PowerQuantity");
            if(saved.ValueKind==JsonValueKind.Null)return null;
            ReferenceKey Reference(JsonElement value)
            {
                if(value.GetArrayLength()!=3||value[0].GetString()!="reference"||value[1].GetArrayLength()!=3||value[1][0].GetString()!="reference_revision")throw Invalid();
                return new(new(value[1][1].GetGuid(),value[1][2].GetGuid()),value[2].GetString()!);
            }
            QuantitySpecification Quantity(JsonElement value)
            {
                if(value.GetArrayLength()!=6||value[0].GetString()!="quantity_specification_v1")throw Invalid();
                return new(Reference(value[1]),Reference(value[2]),Reference(value[3]),Reference(value[4]),Reference(value[5]));
            }
            var parameters=new ScheduledPowerQuantityParameters(Reference(saved.GetProperty("Clock")),saved.Text("ClockRules"),saved.Text("ClockFingerprint"),
                Quantity(saved.GetProperty("Power")),Quantity(saved.GetProperty("Energy")),
                new(saved.GetProperty("MaskMinutes").GetInt32(),saved.Text("WeeklyMask"),saved.Text("HolidayMask")),saved.GetProperty("IntervalMinutes").GetInt32(),
                [..saved.GetProperty("Periods").EnumerateArray().Select(p=>new ScheduledPowerQuantityPeriod(DateWorkspace.Date(p.Text("From")),DateWorkspace.Date(p.Text("To")),ExactDecimal.Parse(p.Text("Rate"))))]);
            if(DefinitionIdentity.For(parameters).Canonical!=saved.GetRawText())throw Invalid();
            return parameters;
        }
        catch(Exception error)when(error is JsonException or KeyNotFoundException or InvalidOperationException or FormatException or IndexOutOfRangeException)
        {throw Invalid();}
    }
    private static MarketDataException Invalid()=>new("scheduled_quantity","The retained Side has no consistent captured power generation parameters.");
}
