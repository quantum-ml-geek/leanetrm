namespace OpenEtrm.Shared.Temporal;

public sealed class TemporalException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}
public sealed class DateSet : IEquatable<DateSet>
{
    private readonly int[] days;
    private readonly int hash;
    public DateOnly From { get; }
    public DateOnly To { get; }
    public int Count => days.Length;
    public DateOnly this[int index] => DateOnly.FromDayNumber(days[index]);
    public IEnumerable<DateOnly> Dates => days.Select(DateOnly.FromDayNumber);

    private DateSet(DateOnly from, DateOnly to, int[] sortedUniqueDays)
    {
        From = from; To = to; days = sortedUniqueDays;
        var h = new HashCode(); h.Add(from); h.Add(to);
        foreach (var day in days) h.Add(day);
        hash = h.ToHashCode();
    }
    public static DateSet Create(DateOnly from, DateOnly to, IEnumerable<DateOnly> dates)
    {
        ArgumentNullException.ThrowIfNull(dates);
        if (from >= to) throw new TemporalException("date_coverage", "Supply a nonempty half-open date coverage.");
        var days = dates.Select(d => d.DayNumber).Distinct().Order().ToArray();
        if (days.Length != 0 && (days[0] < from.DayNumber || days[^1] >= to.DayNumber))
            throw new TemporalException("date_coverage", "A member is outside the supplied date coverage.");
        return new(from, to, days);
    }
    internal int Search(DateOnly day)
    {
        if (day < From || day >= To) throw new TemporalException("date_coverage", "The requested day is outside known coverage.");
        return Array.BinarySearch(days, day.DayNumber);
    }
    public bool Contains(DateOnly day) => Search(day) >= 0;
    public DateSet Union(DateSet other) => Combine(other, SetOperation.Union);
    public DateSet Intersect(DateSet other) => Combine(other, SetOperation.Intersect);
    public DateSet Except(DateSet other) => Combine(other, SetOperation.Except);
    private enum SetOperation { Union, Intersect, Except }
    private DateSet Combine(DateSet other, SetOperation operation)
    {
        ArgumentNullException.ThrowIfNull(other);
        if (From != other.From || To != other.To)
            throw new TemporalException("date_coverage", "Set composition requires identical known coverage.");
        if (Equals(other)) return operation == SetOperation.Except ? new(From, To, []) : this;
        var result = new List<int>(operation switch {
            SetOperation.Union => checked(Count + other.Count), SetOperation.Intersect => Math.Min(Count, other.Count), _ => Count });
        var i = 0; var j = 0;
        while (i < Count && j < other.Count)
        {
            if (days[i] == other.days[j])
            { if (operation != SetOperation.Except) result.Add(days[i]); i++; j++; }
            else if (days[i] < other.days[j])
            { if (operation != SetOperation.Intersect) result.Add(days[i]); i++; }
            else
            { if (operation == SetOperation.Union) result.Add(other.days[j]); j++; }
        }
        if (operation != SetOperation.Intersect) while (i < Count) result.Add(days[i++]);
        if (operation == SetOperation.Union) while (j < other.Count) result.Add(other.days[j++]);
        return new(From, To, result.ToArray());
    }
    public bool Equals(DateSet? other) => ReferenceEquals(this, other) || other is not null &&
        From == other.From && To == other.To && days.AsSpan().SequenceEqual(other.days);
    public override bool Equals(object? obj) => obj is DateSet other && Equals(other);
    public override int GetHashCode() => hash;
}
