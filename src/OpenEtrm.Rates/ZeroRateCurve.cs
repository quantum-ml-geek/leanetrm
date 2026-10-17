using System.Collections.Immutable;
using OpenEtrm.MarketData;

namespace OpenEtrm.Rates;

public sealed record RatePillar(SeriesKey Series,DateOnly Maturity);
public sealed record ZeroRateDefinition(CurveKey Key,ReferenceKey Specification,ReferenceKey Currency,
    string DayCount,string Compounding,string Implementation,string DateBasis,ReferenceKey Source,ImmutableArray<RatePillar> Pillars);
public sealed record ZeroRateValue(SeriesKey Series,DateOnly Maturity,string AnnualRate,string RatePercent,string DiscountFactor,string DisplayDiscountFactor,int Days,ObservationKey Observation);
public sealed record ZeroRateBuild(Guid SnapshotId,DateOnly ReferenceDate,ReferenceKey Currency,string NumericalPolicy,ImmutableArray<ZeroRateValue> Values);

// Explicit dated zero-rate inputs and conventions. No automatic date adjustment,
// interpolation, implicit rate convention or global mutable evaluation date.
public sealed class ZeroRateCurve
{
    public const string Policy=RateConventions.Policy;
    private readonly ZeroRateDefinition definition;
    public ZeroRateCurve(ZeroRateDefinition definition)
    {
        this.definition=definition;
        if(definition.DayCount!="actual_365_fixed"||definition.Compounding!="simple"||definition.Implementation!=RateConventions.Implementation||definition.DateBasis!="valuation_utc_date")
            Fail("unsupported_rate_convention","The requested rate conventions are not supported.");
        if(definition.Key.Revision.CatalogId==Guid.Empty||definition.Key.Revision.RevisionId==Guid.Empty||string.IsNullOrWhiteSpace(definition.Key.Code)||
           definition.Specification.Revision!=definition.Currency.Revision||definition.Source.Revision!=definition.Currency.Revision||
           definition.Currency.Revision.CatalogId==Guid.Empty||definition.Currency.Revision.RevisionId==Guid.Empty||
           string.IsNullOrWhiteSpace(definition.Specification.Code)||string.IsNullOrWhiteSpace(definition.Currency.Code)||string.IsNullOrWhiteSpace(definition.Source.Code))
            Fail("rate_definition","The exact rate definition references are incomplete.");
        if(definition.Pillars.IsDefaultOrEmpty||definition.Pillars.Select(p=>p.Series).Distinct().Count()!=definition.Pillars.Length)
            Fail("rate_definition","Supply distinct explicit dated rate samples.");
        DateOnly? previous=null;
        foreach(var pillar in definition.Pillars)
        {
            if(pillar.Series.Revision!=definition.Key.Revision||pillar.Series.Id==Guid.Empty||pillar.Maturity.Year is <1901 or >2199||previous is {} date&&pillar.Maturity<=date)
                Fail("rate_definition","Rate maturities and exact series references must be supported and strictly increasing.");
            previous=pillar.Maturity;
        }
    }
    public ZeroRateBuild Build(MarketSnapshot snapshot)
    {
        if(snapshot.Definitions!=definition.Key.Revision||snapshot.Id==Guid.Empty||snapshot.ValuationAt.Offset!=TimeSpan.Zero||snapshot.MarketCutoff.Offset!=TimeSpan.Zero||
           snapshot.MarketCutoff>snapshot.ValuationAt||snapshot.MarketCutoff>=new DateTimeOffset(9999,12,31,0,0,0,TimeSpan.Zero)||
           snapshot.SelectionPolicy!=InputSelectionPolicy.ExactPinnedFinalObservationsNoAgeFiltering||snapshot.Selections.IsDefault)
            Fail("rate_snapshot","Select an exact supported UTC rate context.");
        var date=DateOnly.FromDateTime(snapshot.ValuationAt.UtcDateTime);
        if(date.Year is <1901 or >2199)Fail("rate_date","The rate implementation supports dates from 1901 through 2199.");
        var selections=new Dictionary<InputKey,MarketObservation>();
        foreach(var selection in snapshot.Selections)
            if(!selections.TryAdd(selection.Input,selection.Observation))Fail("observation_conflict","Repeated rate input selection is not allowed.");
        var values=ImmutableArray.CreateBuilder<ZeroRateValue>();
        foreach(var pillar in definition.Pillars)
        {
            if(pillar.Maturity<=date)Fail("rate_maturity","Rate maturity must follow the selected valuation date.");
            if(!selections.TryGetValue(new(pillar.Series,InputUse.Variable),out var observation))Fail("missing_observation","A selected rate sample is missing.");
            if(observation!.Series!=pillar.Series||observation.Key.CatalogId!=definition.Key.Revision.CatalogId||observation.Key.Id==Guid.Empty||
               observation.Source!=definition.Source||observation.Role!=ObservationRole.Parameter||observation.State!=PublicationState.Final||
               observation.ObservedAt.Offset!=TimeSpan.Zero||observation.ObservedAt>snapshot.MarketCutoff)
                Fail("rate_observation","The rate observation does not match the exact source, time and finality requirements.");
            if(observation.Value.CompareTo(ExactDecimal.Parse("-0.1"))<0||observation.Value.CompareTo(ExactDecimal.Parse("1"))>0)
                Fail("rate_domain","The supported annual decimal rate range is -0.1 to 1.");
            var factor=RateConventions.SimpleActual365Fixed(date,pillar.Maturity,observation.Value);
            values.Add(new(pillar.Series,pillar.Maturity,observation.Value.ToString(),(observation.Value*ExactDecimal.Parse("100")).ToString(),
                factor.Factor,factor.DisplayFactor,factor.Days,observation.Key));
        }
        return new(snapshot.Id,date,definition.Currency,Policy,values.ToImmutable());
    }
    private static void Fail(string code,string message)=>throw new MarketDataException(code,message);
}
