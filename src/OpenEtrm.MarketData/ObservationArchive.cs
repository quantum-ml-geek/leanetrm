using System.Collections.Immutable;

namespace OpenEtrm.MarketData;

// Raw, exactly pinned histories. This does not certify knowledge timestamps,
// select source priority, interpolate, roll, impute or choose latest corrections.
public sealed class ObservationArchive
{
    private static readonly DateTimeOffset End = new(9999, 12, 31, 0, 0, 0, TimeSpan.Zero);
    private readonly ImmutableDictionary<ObservationKey, MarketObservation> observations;
    public ObservationArchive(IEnumerable<MarketObservation> observations)
    {
        var builder = ImmutableDictionary.CreateBuilder<ObservationKey, MarketObservation>();
        foreach (var observation in observations)
        {
            if (observation.Key.Id == Guid.Empty || observation.Key.CatalogId != observation.Series.Revision.CatalogId ||
                observation.Series.Id == Guid.Empty || observation.Series.Revision.CatalogId == Guid.Empty || observation.Series.Revision.RevisionId == Guid.Empty ||
                observation.Source.Revision.CatalogId == Guid.Empty || observation.Source.Revision.RevisionId == Guid.Empty || string.IsNullOrWhiteSpace(observation.Source.Code) ||
                !Enum.IsDefined(observation.Role) || !Enum.IsDefined(observation.State) ||
                observation.ObservedAt.Offset != TimeSpan.Zero || observation.ObservedAt >= End || !builder.TryAdd(observation.Key, observation))
                throw new MarketDataException("archive_identity", "Archive requires distinct scoped observation IDs and UTC observation instants.");
        }
        this.observations = builder.ToImmutable();
    }
    public ImmutableArray<MarketObservation> ReadPinnedHistory(SeriesKey series, DateTimeOffset from,
        DateTimeOffset to, ImmutableHashSet<ObservationKey> knowledgePin)
    {
        if (series.Id == Guid.Empty || series.Revision.CatalogId == Guid.Empty || series.Revision.RevisionId == Guid.Empty ||
            from.Offset != TimeSpan.Zero || to.Offset != TimeSpan.Zero || from >= to || from >= End || to > End || knowledgePin is null)
            throw new MarketDataException("history_context", "History requires an explicit pin and half-open UTC interval.");
        var selected = knowledgePin.Select(key => observations.TryGetValue(key, out var observation) ? observation :
            throw new MarketDataException("missing_observation", "Pinned observation is unavailable.")).ToImmutableArray();
        return selected.Where(o => o.Series == series && o.ObservedAt >= from && o.ObservedAt < to)
            .OrderBy(o => o.ObservedAt).ThenBy(o => o.Key.Id).ToImmutableArray();
    }
}
