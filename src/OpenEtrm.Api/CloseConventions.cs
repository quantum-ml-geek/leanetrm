using System.Text.Json;
using Npgsql;
using OpenEtrm.MarketData.Power;

namespace OpenEtrm.Api;

// A recorded close's convention, as the exact session version the close names states it. Its clock is the clock of the
// calendar that version pins, and is absent when that calendar cannot be read at the reading context.
internal sealed record CloseConvention(string Session,int SessionVersion,string Name,string Calendar,ClockRule? Clock);

internal static class CloseConventions
{
    // The exact session version a close names is immutable configuration and gives the name and the calendar; the
    // calendar's clock rule is reference data, read under the connection's bound context.
    internal static async Task<CloseConvention> Read(NpgsqlConnection connection,Guid catalog,FrameClose close,CancellationToken ct)
    {
        var rows=await PreviewDatabase.Rows(connection,"SELECT row_to_json(t)::text FROM(SELECT s.name,v.calendar_code,CASE WHEN r.code IS NOT NULL THEN to_jsonb(r) END clock "+
            "FROM market_data.close_session_versions v JOIN market_data.close_sessions s USING(catalog_id,code) "+
            "LEFT JOIN ref_data.calendars c ON(c.catalog_id,c.revision_id,c.code)=(v.reference_catalog_id,v.reference_revision_id,v.calendar_code) "+
            "LEFT JOIN ref_data.clock_rules r ON(r.catalog_id,r.revision_id,r.code)=(c.catalog_id,c.revision_id,c.clock_code) "+
            "WHERE(v.catalog_id,v.code,v.version)=($1,$2,$3))t",[catalog,close.Session,close.SessionVersion],ct);
        if(rows.Length!=1)throw new PreviewDeniedException();
        var clock=rows[0].GetProperty("clock");
        return new(close.Session,close.SessionVersion,rows[0].Text("name"),rows[0].Text("calendar_code"),clock.ValueKind==JsonValueKind.Null?null:ReferenceClockJson.Read(clock));
    }
}
