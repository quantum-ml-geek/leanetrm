using System.Collections.Immutable;
using System.Globalization;
using System.Text.Json;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

// An exchange event remains a source fact. Sample execution eligibility is a
// separately retained, versioned approval; it never changes instrument identity.
public sealed class FuturesAdmission
{
    public const string Usage="generated_prices_sample_trades_v1";
    public const string ExactFirst="exchange_first_trade_instant_v1";
    public const string AfterDate="after_source_first_trade_date_v1";
    private readonly ILookup<string,JsonElement> sources,milestones,admissions,clockRules;
    private readonly Dictionary<string,PowerClock> clocks=new(StringComparer.Ordinal);

    public FuturesAdmission(IReadOnlyDictionary<string,ImmutableArray<JsonElement>> references)
    {
        ILookup<string,JsonElement> Index(string table,string key)=>references.GetValueOrDefault(table,[]).ToLookup(row=>row.Text(key));
        sources=Index("sources","code");milestones=Index("futures_milestones","series_code");
        admissions=Index("futures_execution_admissions","series_code");clockRules=Index("clock_rules","code");
    }

    public DateTimeOffset Require(JsonElement product,JsonElement series,JsonElement curve,string implementation)
    {
        try
        {
            if(product.Text("definition_state")=="synthetic"&&series.Text("definition_state")=="synthetic"&&curve.OptionalText("direct_role")=="daily_settlement")
            {
                var first=One(milestones[series.Text("code")].Where(row=>row.Text("milestone")=="first_trading"));
                if(first.OptionalText("event_at") is null)throw Invalid();
                return EligibleFrom(series.Text("code"));
            }
            var admission=Admission(series.Text("code"));
            if(product.Text("definition_state")!="candidate"||series.Text("definition_state")!="candidate"||
                implementation!=FuturesMarketBinding.GeneralImplementation||admission.Text("usage_policy")!=Usage||
                admission.Text("execution_venue")!="central_limit_order_book"||curve.OptionalText("direct_role")!="trader_mark")throw Invalid();
            var source=One(sources[curve.Text("direct_source_code")]);
            var approval=One(sources[admission.Text("qualification_source_code")]);
            if(source.Text("kind")!="synthetic"||!source.Text("locator").StartsWith("generated:pilot-close-v1/",StringComparison.Ordinal)||
                approval.Text("kind")!="manual_entry"||!Hash(source.OptionalText("content_sha256"))||!Hash(approval.OptionalText("content_sha256")))throw Invalid();
            return EligibleFrom(series.Text("code"));
        }
        catch(Exception error) when(Malformed(error)){throw Invalid();}
    }

    public DateTimeOffset EligibleFrom(string series)
    {
        try
        {
            var first=One(milestones[series].Where(row=>row.Text("milestone")=="first_trading"));
            if(first.Text("value_state")!="known")throw Invalid();
            var selected=admissions[series].Where(row=>row.Text("implementation")==FuturesMarketBinding.GeneralImplementation).ToArray();
            if(first.OptionalText("event_at") is not null)
            {
                var exact=SchedulePreview.RequiredMilestoneInstant(first);
                if(selected.Length>0&&(selected.Length!=1||selected[0].Text("eligibility_rule")!=ExactFirst||
                    SchedulePreview.ParseAt(selected[0].Text("eligible_from"))!=exact||selected[0].OptionalText("eligibility_offset_seconds") is not null||
                    selected[0].OptionalText("eligibility_tzdb_version") is not null))throw Invalid();
                return exact;
            }
            var admission=One(selected);
            if(admission.Text("usage_policy")!=Usage||admission.Text("eligibility_rule")!=AfterDate)throw Invalid();
            var clock=One(clockRules[first.Text("clock_code")]);
            var rule=new ClockRule(clock.Text("code"),clock.Text("kind"),clock.OptionalText("fixed_offset_seconds") is {} seconds?int.Parse(seconds,CultureInfo.InvariantCulture):null,
                clock.OptionalText("iana_zone"),clock.OptionalText("tzdb_version"));
            var date=DateOnly.ParseExact(first.Text("business_date"),"yyyy-MM-dd",CultureInfo.InvariantCulture);
            if(date.Year is <2000 or >=2100||!(rule.Kind=="fixed_offset"&&rule.FixedOffsetSeconds==0||
                rule.Kind=="iana"&&rule.IanaZone is "America/New_York" or "America/Chicago" or "America/Los_Angeles"))throw Invalid();
            if(!clocks.TryGetValue(rule.Code,out var captured))
            {
                captured=PowerClock.FromRule(rule,TimeZoneDatabase.Installed());clocks.Add(rule.Code,captured);
            }
            var nextDay=captured.StartOfDay(date.AddDays(1));
            var eligible=nextDay.ToUniversalTime();
            if(SchedulePreview.ParseAt(admission.Text("eligible_from"))!=eligible||
                int.Parse(admission.Text("eligibility_offset_seconds"),CultureInfo.InvariantCulture)!=(int)nextDay.Offset.TotalSeconds||
                admission.OptionalText("eligibility_tzdb_version")!=rule.TzdbVersion)throw Invalid();
            return eligible;
        }
        catch(Exception error) when(Malformed(error)){throw Invalid();}
    }

    private JsonElement Admission(string series)=>One(admissions[series].Where(row=>row.Text("implementation")==FuturesMarketBinding.GeneralImplementation));
    private static JsonElement One(IEnumerable<JsonElement> rows)
    {var selected=rows.Take(2).ToArray();return selected.Length==1?selected[0]:throw Invalid();}
    private static bool Hash(string? value)=>value is {Length:64}&&value.All(c=>c is >= '0' and <= '9' or >= 'a' and <= 'f');
    private static bool Malformed(Exception error)=>error is KeyNotFoundException or InvalidOperationException or FormatException or ArgumentException or OverflowException||
        error is MarketDataException market&&market.Code!="futures_admission";
    private static MarketDataException Invalid()=>new("futures_admission","The exact sourced contract needs qualified terms, generated-mark provenance and an explicit trading eligibility rule.");
}
