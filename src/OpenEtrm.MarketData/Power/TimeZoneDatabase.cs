using System.Text.RegularExpressions;

namespace OpenEtrm.MarketData.Power;

// The installed zoneinfo data that .NET's Unix TimeZoneInfo reads, as seen by a clock rule.
public sealed record TimeZoneSource(Func<string> Version,Func<string,bool> HasZoneFile);

// Identifies the tzdb release that .NET reads ($TZDIR or the system zoneinfo
// directory). An unknown or non-standard release is an error, never a guess.
public static class TimeZoneDatabase
{
    public static TimeZoneSource Installed()
    {
        if(!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
            throw new MarketDataException("clock_tzdb","The installed time-zone database release cannot be verified on this platform.");
        var directory=Directory(Environment.GetEnvironmentVariable("TZDIR"));
        return new(()=>Version(directory),zone=>File.Exists(Path.Combine(directory,zone)));
    }
    // .NET treats a set-but-empty TZDIR as a directory, so it is rejected rather than reinterpreted.
    public static string Directory(string? tzdir) => tzdir switch
    {
        null=>"/usr/share/zoneinfo",
        ""=>throw new MarketDataException("clock_tzdb","TZDIR is set but empty; set a zoneinfo directory or unset it."),
        _=>tzdir
    };
    public static string Version(string directory)
    {
        var marker=Path.Combine(directory,"+VERSION");
        if(File.Exists(marker))return Release(File.ReadAllText(marker).Trim());
        var data=Path.Combine(directory,"tzdata.zi");
        var first=File.Exists(data)?File.ReadLines(data).FirstOrDefault():null;
        if(first is not null && first.StartsWith("# version ",StringComparison.Ordinal))return Release(first["# version ".Length..].Trim());
        throw new MarketDataException("clock_tzdb","The installed time-zone database release cannot be determined.");
    }
    private static string Release(string value) => Regex.IsMatch(value,@"\A[0-9]{4}[a-z]\z",RegexOptions.CultureInvariant)?value:
        throw new MarketDataException("clock_tzdb","The installed time-zone database release is not a standard tzdb release.");
}
