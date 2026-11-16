using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using Npgsql;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Calculation;
using OpenEtrm.MarketData.Options;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Risk;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

/// <summary>The option sensitivities a volatility-surface fit computes, every member stated: the policy, the price bump and
/// the agreement of its estimates, the volatility bump, and for a working snapshot the calendar clock one day is counted on.</summary>
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record OptionSensitivityRequest([property:JsonRequired]string Policy,[property:JsonRequired]PnlBumpSelection Bump,
    [property:JsonRequired]string VolatilityBump,[property:JsonRequired]ClockRule? Clock);

// What one fit computes its analytics under, as admission pinned it: the selection, the instant one calendar day runs to
// (none where no clock could be read) and what the surface states of both.
internal sealed record OptionSensitivityPlan(OptionSensitivitySelection Selection,ClockChange? Day,SurfaceSensitivities Stated);

// The value and sensitivities of a fitted surface's series. Admission pins the selection and the clock; the fit values
// each expiry's solved series as one-contract holdings through the shared valuation layers.
internal static class OptionSurfaceAnalytics
{
    internal const string VolatilityBump="0.01",RequestClock="request",ConventionClock="close_convention";
    private static readonly JsonSerializerOptions Json=new(JsonSerializerDefaults.Web);
    // The selection a page may send back. It is offered, never filled in: a fit names its selection in full.
    internal static object Offered=>new{policy=FuturesOptionSensitivities.Policy,bump=TradingPnlReport.Offered,volatilityBump=VolatilityBump};

    private sealed record PinnedClock(string Source,ClockRule Rule,string Zone,string? Session,int? SessionVersion,string? Name,string? Calendar);
    private sealed record Pinned(string Policy,PnlBumpSelection Bump,string VolatilityBump,PinnedClock? Clock);

    // What admission retains of a request. A recorded close states its convention, whose calendar clock one day is counted
    // on, so its request names none; where that clock cannot be read no day is selected. A working snapshot belongs to no
    // convention, so its request names one of the offered clocks.
    internal static JsonObject Pin(OptionSensitivityRequest? request,CloseConvention? convention)
    {
        if(request is null)throw Error("State the option sensitivity selection of the fit.");
        Select(request.Policy,request.Bump,request.VolatilityBump);
        if(convention is not null&&request.Clock is not null)
            throw Error("This fit is at a recorded close: one calendar day is counted on its close convention's calendar clock. Name no clock.");
        if(convention is null&&(request.Clock is null||!TradingPnlReport.Clocks().Contains(request.Clock)))
            throw Error("This fit is at a working snapshot, which has no close convention. Name one of the offered calendar clocks.");
        var clock=convention is null?new PinnedClock(RequestClock,request.Clock!,ReferenceClockJson.Zone(request.Clock!),null,null,null,null):
            convention.Clock is {} rule?new(ConventionClock,rule,ReferenceClockJson.Zone(rule),convention.Session,convention.SessionVersion,convention.Name,convention.Calendar):null;
        return JsonSerializer.SerializeToNode(new Pinned(request.Policy,request.Bump,request.VolatilityBump,clock),Json)!.AsObject();
    }

    // The plan a fit at this valuation instant runs, from what its admission pinned.
    internal static OptionSensitivityPlan Plan(JsonNode? pinned,DateTimeOffset at)
    {
        Pinned read;
        try{read=pinned.Deserialize<Pinned>(Json)??throw new JsonException();}
        catch(JsonException e){throw new MarketDataException("option_sensitivity_policy","The fit retains no supported option sensitivity selection.",e);}
        var selection=Select(read.Policy,read.Bump,read.VolatilityBump);
        // A pinned clock this host cannot count a day on (another time-zone release, or a next day whose local time does not
        // occur once) selects no day: the surface is still fitted and its thetas are missing.
        ClockChange? day=null;
        if(read.Clock is {} clock)
            try{day=ClockChange.NextCalendarDay(at,PowerClock.FromRule(clock.Rule,TimeZoneDatabase.Installed()));}
            catch(MarketDataException){}
        return new(selection,day,new(read.Policy,read.Bump.Ticks,read.Bump.PriceSteps,read.Bump.AbsoluteTolerance,read.Bump.DeltaRelativeTolerance,
            read.Bump.GammaRelativeTolerance,selection.VolatilityBump,read.Clock?.Source,read.Clock?.Zone,day?.At));
    }

    private static OptionSensitivitySelection Select(string? policy,PnlBumpSelection? bump,string? volatilityBump)
    {
        if(policy!=FuturesOptionSensitivities.Policy||volatilityBump!=VolatilityBump)
            throw Error($"Select the {FuturesOptionSensitivities.Policy} policy and a volatility bump of {VolatilityBump}.");
        try
        {
            var selected=TradingPnlReport.Select(bump);
            return new(selected.Bump,selected.Delta,selected.Gamma,ExactDecimal.Parse(VolatilityBump));
        }
        catch(MarketDataException e)when(e.Code=="pnl_factor_bump"){throw new MarketDataException("option_sensitivity_policy",e.Message,e);}
    }

    // The fitted surface with each calibrated series' analytics and the selection they were computed under, and the fit's
    // observations with those the analytics read beyond them. The series of one expiry share one underlying future and are
    // valued together; a series that did not calibrate has none.
    internal static async Task<(VolSurfaceResult Surface,ImmutableArray<Guid> ObservationIds,int TreePrices)> Attach(NpgsqlConnection connection,PreviewDatabase database,PreviewData data,InputFrame frame,
        MarketSnapshot snapshot,ScheduleContext context,VolSurfaceInputs fitted,OptionSensitivityPlan plan,CancellationToken ct)
    {
        var calibrations=fitted.Calibrations;var before=calibrations.Bindings.Values.Sum(b=>b.TreePrices);
        // Each expiry's market is prepared in turn on the one connection.
        var expiries=new List<(PreparedConnectedPortfolioRisk? Prepared,ImmutableDictionary<Guid,FuturesOptionMarketBinding> Bindings)>();
        foreach(var expiry in fitted.Listed.Where(o=>calibrations.Bindings.ContainsKey(o.Id)).GroupBy(o=>(o.Series.Terms.ExpiryAt,Underlying:o.Series.UnderlyingSeries.Code))
            .OrderBy(g=>g.Key.ExpiryAt).ThenBy(g=>g.Key.Underlying,StringComparer.Ordinal))
        {
            ct.ThrowIfCancellationRequested();
            var bindings=expiry.ToImmutableDictionary(o=>o.Id,o=>calibrations.Bindings[o.Id]);
            var solved=expiry.Where(o=>bindings[o.Id].Calibration is SolvedVolatility).ToArray();
            PreparedConnectedPortfolioRisk? prepared=null;
            if(solved.Length>0)
            {
                var portfolio=ValuationPortfolio.FromTrades(FuturesOptionSensitivities.UnitHoldings(solved),new(ValuationMeasure.PresentValue,
                    ImmutableDictionary<Guid,FuturesMarketBinding>.Empty,null){OptionBindings=bindings});
                var dependencies=portfolio.Declare(snapshot).SelectMany(c=>c.Dependencies).Distinct().ToImmutableArray();
                var market=await CustomCurves.PrepareMarket(connection,database,data,frame,snapshot,context,portfolio.Instruments,dependencies,
                    CustomCurves.MarketPreparation.ValuationDependencies,ct);
                prepared=RiskEngine.PrepareConnected(market.Valuation,market.Bindings,[portfolio],market.Authority,ct);
            }
            expiries.Add((prepared,bindings));
        }
        // The expiries are independent and their valuation touches no connection, so they are valued in parallel, as the
        // series' calibrations are. Every outcome is kept in expiry order and the first failure in that order is the fit's,
        // exactly as a sequential pass would fail and never as a parallel AggregateException.
        var outcomes=expiries.AsParallel().AsOrdered().Select(expiry=>
        {
            try{return(Series:FuturesOptionSensitivities.Calculate(expiry.Prepared,expiry.Bindings,plan.Selection,plan.Day,ct),Error:(Exception?)null);}
            catch(Exception error){return(Series:default(ImmutableArray<OptionSeriesSensitivities>),Error:error);}
        }).ToArray();
        if(outcomes.FirstOrDefault(o=>o.Error is not null).Error is {} failure)System.Runtime.ExceptionServices.ExceptionDispatchInfo.Throw(failure);
        var codes=fitted.Listed.ToDictionary(o=>o.Id,o=>o.Series.Key.Code);
        var analytics=outcomes.SelectMany(o=>o.Series).ToDictionary(series=>codes[series.InstrumentId]);
        var surface=fitted.Result with{Sensitivities=plan.Stated,
            Series=[..fitted.Result.Series.Select(s=>analytics.TryGetValue(s.Series.Code,out var found)?s with{Analytics=found}:s)]};
        return(surface,[..fitted.ObservationIds.Concat(RolledDiscountPoints(calibrations,fitted.Listed,analytics,codes,snapshot,plan.Day)).Distinct().Order()],
            calibrations.Bindings.Values.Sum(b=>b.TreePrices)-before);
    }

    // A theta discounts each series' expiry from the day's instant, which rolls the calibration's factor by the curve's
    // factor to that instant. The curve points that factor was read from are inputs of the stored thetas, as the points
    // behind each discount to expiry are inputs of the fit.
    private static IEnumerable<Guid> RolledDiscountPoints(FuturesOptionCalibrations calibrations,ImmutableArray<FuturesOptionInstrument> listed,
        Dictionary<string,OptionSeriesSensitivities> analytics,Dictionary<Guid,string> codes,MarketSnapshot snapshot,ClockChange? day)
    {
        if(day is null)return [];
        var decayed=listed.Where(o=>analytics.TryGetValue(codes[o.Id],out var series)&&series.Theta.Value is not null).ToArray();
        return calibrations.Discounting.SelectMany(currency=>
        {
            ImmutableArray<SidePaymentKey> expiries=[..decayed.Where(o=>o.Currency==currency.Key)
                .Select(o=>new SidePaymentKey(o.Id,0,o.Series.Terms.ExpiryAt,o.Currency){Timing=ValueTimingKind.Instant})];
            return expiries.IsEmpty?[]:currency.Value.ResolveForValuation(expiries,snapshot,day.At,day.Policy).SelectMany(factor=>factor.ClockRoll?.AnchorObservations??[]);
        }).Select(observation=>observation.Id);
    }

    private static MarketDataException Error(string message)=>new("option_sensitivity_policy",message);
}
