namespace OpenEtrm.Shared.Temporal;

// Date-valued business coordinates and UTC knowledge coordinates are distinct.
public sealed record BitemporalRange
{
    public DateOnly EffectiveFrom {get;}
    public DateOnly EffectiveTo {get;}
    public DateTimeOffset KnownFrom {get;}
    public DateTimeOffset KnownTo {get;}
    public static DateTimeOffset OpenEnd {get;}=new(9999,12,31,0,0,0,TimeSpan.Zero);
    public BitemporalRange(DateOnly effectiveFrom,DateOnly effectiveTo,DateTimeOffset knownFrom,DateTimeOffset knownTo)
    {
        if(effectiveFrom>=effectiveTo || knownFrom.Offset!=TimeSpan.Zero || knownTo.Offset!=TimeSpan.Zero ||
            knownFrom>=knownTo || knownTo>OpenEnd)
            throw new TemporalException("temporal_interval","Supply ordered, half-open effective dates and UTC knowledge instants.");
        EffectiveFrom=effectiveFrom;EffectiveTo=effectiveTo;KnownFrom=knownFrom;KnownTo=knownTo;
    }
    public bool Contains(DateOnly effectiveAt,DateTimeOffset knownAt)
    {
        if(knownAt.Offset!=TimeSpan.Zero)throw new TemporalException("temporal_context","Knowledge context must be UTC.");
        return EffectiveFrom<=effectiveAt && effectiveAt<EffectiveTo && KnownFrom<=knownAt && knownAt<KnownTo;
    }
}
