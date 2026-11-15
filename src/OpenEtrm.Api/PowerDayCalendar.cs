using System.Globalization;
using System.Text;
using System.Text.Json;
using OpenEtrm.MarketData;

namespace OpenEtrm.Api;

public sealed record PowerDayCalendarRequest(Guid ReferenceCatalogId,Guid ReferenceRevisionId,DateOnly From,DateOnly Through,string[] ClockCodes);
public static class PowerDayCalendar
{
    // Operator-only preparation. Collector credentials cannot write or replace these rows.
    public static string Render(PowerDayCalendarRequest request)
    {
        if(request.ReferenceCatalogId==Guid.Empty||request.ReferenceRevisionId==Guid.Empty||request.Through<request.From||request.Through.DayNumber-request.From.DayNumber>1461||request.ClockCodes is null||request.ClockCodes.Length is <1 or >2||request.ClockCodes.Distinct(StringComparer.Ordinal).Count()!=request.ClockCodes.Length||request.ClockCodes.Any(string.IsNullOrWhiteSpace))
            throw new MarketDataException("collection_calendar","Supply exact references, distinct market clocks and an explicit window of at most four years.");
        var sql=new StringBuilder("BEGIN;\n");
        foreach(var code in request.ClockCodes)
            for(var day=request.From;day<=request.Through;day=day.AddDays(1))
                sql.Append(CultureInfo.InvariantCulture,$"SELECT power_data.publish_operating_day('{request.ReferenceCatalogId}','{request.ReferenceRevisionId}','{code.Replace("'","''",StringComparison.Ordinal)}','{day:yyyy-MM-dd}');\n");
        return sql.Append("COMMIT;\n").ToString();
    }
    public static void Run(string input,string output)
    {
        var request=JsonSerializer.Deserialize<PowerDayCalendarRequest>(File.ReadAllText(input),new JsonSerializerOptions(JsonSerializerDefaults.Web))??throw new InvalidOperationException("Calendar request required.");
        using var file=new FileStream(output,FileMode.CreateNew,FileAccess.Write);
        using var writer=new StreamWriter(file);writer.Write(Render(request));
    }
}
