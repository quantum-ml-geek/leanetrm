using System.Globalization;
using System.Runtime.CompilerServices;
using System.Text.Json;

namespace OpenEtrm.MarketData.Trading;

// Reconstruction requires an independently admitted retained identity. This
// pure decoder never selects a calendar or refreshes its publication proof.
public static class RetainedSideCalendarPolicy
{
    private static readonly ConditionalWeakTable<BookedSideProgram,SideCalendarPolicy> Policies=new();
    public static SideCalendarPolicy Read(BookedSideProgram program)=>Policies.GetValue(program,
        static saved=>Read(saved.Document.EconomicIdentity));
    public static SideCalendarPolicy Read(string economicIdentity)
    {
        try
        {
            using var document=JsonDocument.Parse(economicIdentity);var saved=document.RootElement.GetProperty("CalendarPolicy");
            static DateOnly Date(JsonElement row,string field)=>DateOnly.ParseExact(row.GetProperty(field).GetString()!,"yyyy-MM-dd",CultureInfo.InvariantCulture);
            CalendarBinding ReadBinding(string purpose)
            {
                var binding=saved.GetProperty(purpose);
                if(!binding.GetProperty("Applicable").GetBoolean())return CalendarBinding.NotApplicable();
                var definition=binding.GetProperty("Calendar");var key=definition.GetProperty("Key");
                if(key.GetArrayLength()!=3||key[0].GetString()!="reference"||key[1].GetArrayLength()!=3||key[1][0].GetString()!="reference_revision")throw Invalid();
                var proof=binding.GetProperty("Publication");
                var calendar=new CalendarDefinition(new(new(key[1][1].GetGuid(),key[1][2].GetGuid()),key[2].GetString()!),
                    Date(definition,"From"),Date(definition,"To"),definition.GetProperty("WeekendMask").GetInt32(),
                    [..definition.GetProperty("Exceptions").EnumerateArray().Select(day=>new CalendarException(Date(day,"Date"),day.GetProperty("Open").GetBoolean()))],
                    definition.GetProperty("contract").GetString()!,proof.ValueKind==JsonValueKind.Null?null:new(proof.GetProperty("CatalogId").GetGuid(),proof.GetProperty("EventOrder").GetInt32(),proof.GetProperty("KnownFrom").GetDateTimeOffset()));
                return CalendarBinding.Owned(calendar);
            }
            var policy=new SideCalendarPolicy(ReadBinding("Delivery"),ReadBinding("Observation"),ReadBinding("Payment"),saved.GetProperty("contract").GetString()!);
            if(DefinitionIdentity.For(policy).Canonical!=saved.GetRawText())throw Invalid();
            return policy;
        }
        catch(Exception error)when(error is JsonException or KeyNotFoundException or InvalidOperationException or FormatException or IndexOutOfRangeException or ArgumentException)
        {throw Invalid();}
    }
    private static MarketDataException Invalid()=>new("side_calendar_policy","The retained program has no complete, consistent captured calendar policy and publication evidence.");
}
