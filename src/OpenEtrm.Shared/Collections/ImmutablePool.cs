namespace OpenEtrm.Shared.Collections;

// Scoped to one owner/lifetime. Values and their equality/hash must be immutable.
// This is in-memory storage reuse, not a persistent ID or authorization decision.
public sealed class ImmutablePool<T> where T : class, IEquatable<T>
{
    private readonly Dictionary<T, T> values = [];
    private readonly object gate = new();
    public int Capacity { get; }
    public ImmutablePool(int capacity)
    {
        if (capacity <= 0) throw new ArgumentOutOfRangeException(nameof(capacity));
        Capacity = capacity;
    }
    public int Count { get { lock (gate) return values.Count; } }
    public T Intern(T candidate)
    {
        ArgumentNullException.ThrowIfNull(candidate);
        lock (gate)
        {
            if (values.TryGetValue(candidate, out var existing)) return existing;
            if (values.Count == Capacity) throw new InvalidOperationException("Immutable pool capacity reached.");
            values.Add(candidate, candidate);
            return candidate;
        }
    }
}
