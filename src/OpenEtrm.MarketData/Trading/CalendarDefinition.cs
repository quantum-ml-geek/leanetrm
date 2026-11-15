using System.Collections.Immutable;
using OpenEtrm.Shared.Temporal;

namespace OpenEtrm.MarketData.Trading;

[EconomicDefinition("calendar_exception_v1")]
public sealed record CalendarException([property:IdentityField]DateOnly Date,[property:IdentityField]bool Open);

[EconomicDefinition("calendar_publication_proof_v1")]
public sealed record CalendarPublicationProof([property:IdentityField]Guid CatalogId,[property:IdentityField]int EventOrder,
    [property:IdentityField]DateTimeOffset KnownFrom);

// Captured by an authorized exact-reference reader. No runtime clock or current
// reference lookup participates in calendar generation or its economic identity.
[EconomicDefinition(Implementation)]
public sealed record CalendarDefinition
{
    public const string Implementation="captured_calendar_definition_v1";
    public const int MaximumDays=36600;
    [IdentityField] public ReferenceKey Key { get; }
    [IdentityField] public DateOnly From { get; }
    [IdentityField] public DateOnly To { get; }
    // ISO weekdays: bit zero is Monday, bit six is Sunday.
    [IdentityField] public int WeekendMask { get; }
    [IdentityField] public ImmutableArray<CalendarException> Exceptions { get; }
    public string Digest=>DefinitionIdentity.For(this).Digest;
    public DateSet BusinessDays { get; }
    public CalendarPublicationProof? Publication { get; }

    public CalendarDefinition(ReferenceKey key,DateOnly from,DateOnly to,int weekendMask,
        ImmutableArray<CalendarException> exceptions,string implementation,CalendarPublicationProof? publication=null)
    {
        if(key.Revision.CatalogId==Guid.Empty||key.Revision.RevisionId==Guid.Empty||string.IsNullOrWhiteSpace(key.Code)||
            from>=to||to.DayNumber-from.DayNumber>MaximumDays||weekendMask is <0 or >127||exceptions.IsDefault||
            exceptions.Any(e=>e is null||e.Date<from||e.Date>=to)||exceptions.Select(e=>e.Date).Distinct().Count()!=exceptions.Length||
            implementation!=Implementation||publication is {} proof&&(proof.CatalogId==Guid.Empty||proof.EventOrder<=0||!TradingInstant.IsSupported(proof.KnownFrom)))
            throw new MarketDataException("calendar_definition","Supply an exact calendar reference, bounded coverage, explicit weekend mask and distinct dated open/closed exceptions.");
        Key=key;From=from;To=to;WeekendMask=weekendMask;Exceptions=[..exceptions.OrderBy(e=>e.Date)];Publication=publication;
        var overrides=Exceptions.ToDictionary(e=>e.Date,e=>e.Open);
        BusinessDays=DateSet.Create(from,to,Enumerable.Range(0,to.DayNumber-from.DayNumber).Select(from.AddDays)
            .Where(day=>overrides.TryGetValue(day,out var open)?open:(weekendMask&(1<<(((int)day.DayOfWeek+6)%7)))==0));
    }

    public void RequireCoverage(DateOnly from,DateOnly to)
    {
        if(from>=to||from<From||to>To)throw Coverage();
    }
    public DateOnly Adjust(DateOnly anchor,DateRoll convention)
    {
        try{return DateRolling.Adjust(anchor,BusinessDays,convention);}
        catch(TemporalException error){throw new MarketDataException(error.Code=="roll_convention"?error.Code:"calendar_coverage",error.Message);}
    }
    public DateOnly Advance(DateOnly anchor,int days)
    {
        try{return DateRolling.Advance(anchor,BusinessDays,days);}
        catch(TemporalException error){throw new MarketDataException(error.Code=="business_offset"?error.Code:"calendar_coverage",error.Message);}
    }
    public void RequireSameDefinition(CalendarDefinition other)
    {
        if(other is null||DefinitionIdentity.For(this)!=DefinitionIdentity.For(other))
            throw new MarketDataException("calendar_definition_mismatch","The captured calendar does not match its exact retained definition.");
    }
    // Peak products apply their own weekly mask. Weekends must not be turned into
    // holidays here: a six-day product may deliver on a calendar's Saturday.
    public ImmutableArray<DateOnly> Closures(DateOnly from,DateOnly to)
    {
        RequireCoverage(from,to);
        return [..Exceptions.Where(e=>!e.Open&&e.Date>=from&&e.Date<to).Select(e=>e.Date)];
    }
    private static MarketDataException Coverage()=>new("calendar_coverage","The exact calendar does not cover the requested dates.");
}
