using System.Globalization;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

internal static class CalendarDefinitions
{
    internal static CalendarDefinition From(PreviewData data,ReferenceKey reference)
    {
        if(data.CapturedCalendars.TryGetValue(reference,out var captured))return captured;
        if(!data.CalendarDaysRead)throw new MarketDataException("calendar_definition","Load exact calendar exceptions before generating schedules.");
        if(reference.Revision!=data.ReferenceRevision)
            throw new MarketDataException("calendar_reference","The requested exact calendar has not been resolved in this authorized reference snapshot.");
        var rows=data.References["calendars"].Where(row=>row.Text("code")==reference.Code).ToArray();
        if(rows.Length!=1)throw new MarketDataException("calendar_reference","The exact calendar is missing or ambiguous in this authorized snapshot.");
        var row=rows[0];
        return new(reference,DateWorkspace.Date(row.Text("coverage_from")),DateWorkspace.Date(row.Text("coverage_to")),
            int.Parse(row.Text("weekend_mask"),CultureInfo.InvariantCulture),
            [..data.References["calendar_days"].Where(day=>day.Text("calendar_code")==reference.Code)
                .Select(day=>new CalendarException(DateWorkspace.Date(day.Text("business_date")),day.GetProperty("is_business_day").GetBoolean()))],
            CalendarDefinition.Implementation);
    }
}
