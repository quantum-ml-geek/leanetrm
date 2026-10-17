namespace OpenEtrm.Shared.Temporal;

public sealed class UtcGrid : IEquatable<UtcGrid>
{
    private readonly long[] boundaries;
    private readonly int hash;
    public int Count => boundaries.Length - 1;
    private UtcGrid(long[] boundaries)
    {
        this.boundaries = boundaries;
        var h = new HashCode(); foreach (var boundary in boundaries) h.Add(boundary);
        hash = h.ToHashCode();
    }
    public static UtcGrid Uniform(DateTimeOffset from, DateTimeOffset to, TimeSpan step, int maximumIntervals)
    {
        RequireUtc(from); RequireUtc(to);
        if (from >= to || step.Ticks <= 0 || (to.Ticks - from.Ticks) % step.Ticks != 0)
            throw new TemporalException("grid_alignment", "Supply positive, exactly aligned UTC interval bounds and step.");
        var count = (to.Ticks - from.Ticks) / step.Ticks;
        if (maximumIntervals <= 0 || count > maximumIntervals || count >= int.MaxValue)
            throw new TemporalException("grid_size", "The grid exceeds its explicit interval limit.");
        var boundaries = new long[(int)count + 1];
        for (var i = 0; i < boundaries.Length; i++) boundaries[i] = from.Ticks + i * step.Ticks;
        return new(boundaries);
    }
    public static UtcGrid Create(ReadOnlySpan<DateTimeOffset> boundaries)
    {
        if (boundaries.Length < 2) throw new TemporalException("grid_boundaries", "At least two strictly increasing UTC boundaries are required.");
        var ticks = new long[boundaries.Length];
        for (var i = 0; i < boundaries.Length; i++)
        {
            RequireUtc(boundaries[i]); ticks[i] = boundaries[i].Ticks;
            if (i > 0 && ticks[i] <= ticks[i - 1])
                throw new TemporalException("grid_boundaries", "Grid boundaries must strictly increase.");
        }
        return new(ticks);
    }
    private static void RequireUtc(DateTimeOffset instant)
    {
        if (instant.Offset != TimeSpan.Zero) throw new TemporalException("grid_utc", "Grid boundaries must be explicit UTC instants.");
    }
    internal void RequireSlot(int slot)
    {
        if ((uint)slot >= (uint)Count) throw new TemporalException("grid_slot", "The interval slot is outside this exact grid.");
    }
    public DateTimeOffset Start(int slot) { RequireSlot(slot); return new(boundaries[slot], TimeSpan.Zero); }
    public DateTimeOffset End(int slot) { RequireSlot(slot); return new(boundaries[slot + 1], TimeSpan.Zero); }
    public long DurationTicks(int slot) { RequireSlot(slot); return boundaries[slot + 1] - boundaries[slot]; }
    public UtcSelection Select(ReadOnlySpan<int> slots) => new(this, slots);
    public bool Equals(UtcGrid? other) => ReferenceEquals(this, other) || other is not null && boundaries.AsSpan().SequenceEqual(other.boundaries);
    public override bool Equals(object? obj) => obj is UtcGrid other && Equals(other);
    public override int GetHashCode() => hash;
}
public sealed class UtcSelection : IEquatable<UtcSelection>
{
    private readonly ulong[] words;
    private readonly int hash;
    public UtcGrid Grid { get; }
    public int Count { get; }
    public long DurationTicks { get; }
    internal UtcSelection(UtcGrid grid, ReadOnlySpan<int> slots)
    {
        Grid = grid; words = new ulong[(int)(((long)grid.Count + 63) / 64)];
        foreach (var slot in slots)
        {
            grid.RequireSlot(slot);
            var bit = 1UL << (slot & 63);
            if ((words[slot >> 6] & bit) != 0) continue;
            words[slot >> 6] |= bit; Count++; DurationTicks = checked(DurationTicks + grid.DurationTicks(slot));
        }
        var h = new HashCode(); h.Add(grid);
        foreach (var word in words) h.Add(word);
        hash = h.ToHashCode();
    }
    public bool Contains(int slot)
    { Grid.RequireSlot(slot); return (words[slot >> 6] & (1UL << (slot & 63))) != 0; }
    public bool Equals(UtcSelection? other) => ReferenceEquals(this, other) || other is not null &&
        Grid.Equals(other.Grid) && words.AsSpan().SequenceEqual(other.words);
    public override bool Equals(object? obj) => obj is UtcSelection other && Equals(other);
    public override int GetHashCode() => hash;
}
