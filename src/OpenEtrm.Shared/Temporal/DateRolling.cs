using System.Collections.Immutable;
namespace OpenEtrm.Shared.Temporal;

public enum DateRoll { Following = 1, Preceding, ModifiedFollowing, Unadjusted, ModifiedPreceding }
public static class DateRolling
{
    public static DateOnly Adjust(DateOnly day, DateSet businessDays, DateRoll convention)
    {
        ArgumentNullException.ThrowIfNull(businessDays);
        Validate(convention);
        var index = businessDays.Search(day);
        if (index >= 0 || convention == DateRoll.Unadjusted) return day;
        index = ~index;
        DateOnly At(int n) => n >= 0 && n < businessDays.Count ? businessDays[n] :
            throw new TemporalException("no_business_day", "No required business-day candidate exists in known coverage.");
        if (convention is DateRoll.Preceding or DateRoll.ModifiedPreceding)
        {
            var preceding = At(index - 1);
            return convention == DateRoll.ModifiedPreceding && (preceding.Year != day.Year || preceding.Month != day.Month)
                ? At(index) : preceding;
        }
        var following = At(index);
        return convention == DateRoll.ModifiedFollowing && (following.Year != day.Year || following.Month != day.Month)
            ? At(index - 1) : following;
    }
    // Strict movement: a closed base is not adjusted before counting open days.
    public static DateOnly Advance(DateOnly day, DateSet businessDays, int count)
    {
        ArgumentNullException.ThrowIfNull(businessDays);
        if (count == 0 || count < -10000 || count > 10000)
            throw new TemporalException("business_offset", "Choose a nonzero business-day offset between -10000 and 10000.");
        var index = businessDays.Search(day);
        var target = index >= 0 ? (long)index + count : (long)~index + count - (count > 0 ? 1 : 0);
        if (target < 0 || target >= businessDays.Count)
            throw new TemporalException("no_business_day", "The requested movement exceeds known business-day coverage.");
        return businessDays[(int)target];
    }
    public static ImmutableArray<DateOnly> AdjustOccurrences(ReadOnlySpan<DateOnly> dates, DateSet businessDays, DateRoll convention)
    {
        ArgumentNullException.ThrowIfNull(businessDays);
        Validate(convention);
        var result = ImmutableArray.CreateBuilder<DateOnly>(dates.Length);
        foreach (var day in dates) result.Add(Adjust(day, businessDays, convention));
        return result.MoveToImmutable();
    }
    private static void Validate(DateRoll convention)
    {
        if (!Enum.IsDefined(convention)) throw new TemporalException("roll_convention", "Select a supported roll convention explicitly.");
    }
}
