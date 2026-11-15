using System.Runtime.Serialization;
using System.Text.RegularExpressions;

namespace OpenEtrm.Shared.Temporal;

public static class RetainedTimeZone
{
    public const int MaximumRulesLength=65_536;

    public static TimeZoneInfo Restore(string rules,string? expectedId=null)
    {
        if(string.IsNullOrWhiteSpace(rules)||rules.Length>MaximumRulesLength)
            throw new SerializationException("Supply bounded retained time-zone rules.");
        var delimiter=rules.IndexOf(';');
        var id=expectedId??(delimiter is >0 and <=256?rules[..delimiter]:null);
        if(id is not null&&id.Length<=256&&Regex.IsMatch(id,@"\A[A-Za-z0-9_+\-]+(/[A-Za-z0-9_+\-]+)*\z",RegexOptions.CultureInvariant))
        {
            TimeZoneInfo? installed=null;
            try{installed=TimeZoneInfo.FindSystemTimeZoneById(id);}
            catch(Exception error)when(error is TimeZoneNotFoundException or InvalidTimeZoneException){}
            // BCL serialization omits internal IANA transition flags. A successful
            // round trip of its text can still change southern DST or historical
            // base-offset behavior. Use the source only after exact payload proof;
            // a changed installed release cannot substitute for captured terms.
            if(installed is not null)return Exact(installed,rules,expectedId);
        }
        try
        {
            var restored=Exact(TimeZoneInfo.FromSerializedString(rules),rules,expectedId);
            if(restored.GetAdjustmentRules().Any(rule=>rule.BaseUtcOffsetDelta!=TimeSpan.Zero||
                rule.DateStart.Month!=1||rule.DateStart.Day!=1||rule.DateEnd.Month!=12||rule.DateEnd.Day!=31||
                rule.DateStart.TimeOfDay!=TimeSpan.Zero||rule.DateEnd.TimeOfDay!=TimeSpan.Zero))
                throw new SerializationException("The exact retained transition source is unavailable.");
            return restored;
        }
        catch(Exception error)when(error is ArgumentException or InvalidTimeZoneException)
        {throw new SerializationException("The exact retained time-zone rules are unavailable.",error);}
    }

    private static TimeZoneInfo Exact(TimeZoneInfo zone,string rules,string? expectedId)
    {
        if(expectedId is not null&&!StringComparer.Ordinal.Equals(zone.Id,expectedId)||
            !StringComparer.Ordinal.Equals(zone.ToSerializedString(),rules))
            throw new SerializationException("The restored time zone differs from its retained rules or identity.");
        return zone;
    }
}
