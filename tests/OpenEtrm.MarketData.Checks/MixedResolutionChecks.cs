using System.Collections.Immutable;
using System.Globalization;
using OpenEtrm.MarketData;

// Synthetic managed-core acceptance case. It neither selects production market
// conventions nor adds a calendar, historical knowledge resolver or scenario API.
internal static class MixedResolutionChecks
{
    public static int Run(string? csvPath = null, bool showExample = false)
    {
        var passed = 0;
        void Check(string label, Action check)
        {
            check(); passed++; Console.WriteLine($"PASS mixed resolution: {label}");
        }
        var f = new MixedResolutionFixture();
        var model = f.Model();
        var frames = f.Frames;
        var first = frames[0];
        var firstDaily = f.Daily(new(2026, 1, 16));
        var nextDaily = f.Daily(new(2026, 1, 17));
        var firstBalmo = f.Balmo(first.Day.AddDays(1));
        var march = f.Monthly(new(2026, 3, 1));
        CurveRequest Delivery(int id) => new(f.C("location_delivery"), f.K(id));
        CurveRequest Balmo(int id) => new(f.C("location_balmo"), f.K(id));
        string Price(MarketSnapshot snapshot, CurveRequest request) => model.Build(snapshot, [request]).Values[0].Value.ToString();

        foreach (var frame in frames)
        {
            var captured = frame;
            Check($"complete explicit daily/monthly view on {frame.Day:yyyy-MM-dd}", () =>
            {
                var requests = f.View(captured);
                var build = model.Build(f.Snapshot(captured), requests);
                Equal(build.Values.Length, requests.Length);
                var periods = requests.Select(r => f.Periods[r.Contract]).OrderBy(p => p.From).ToArray();
                for (var i = 1; i < periods.Length; i++) Equal(periods[i - 1].To, periods[i].From);
                Equal(periods[0].From, captured.Day.AddDays(1));
                Equal(periods[^1].To, new DateOnly(captured.Day.Year, captured.Day.Month, 1).AddMonths(3));
                Equal(periods.Count(p => p.Kind == "Daily"), DateTime.DaysInMonth(captured.Day.Year, captured.Day.Month) - captured.Day.Day);
                Equal(periods.Count(p => p.Kind == "Monthly"), 2);
                Equal(build.Evaluations.All(e => e.Use == InputUse.Variable), true);
            });
        }
        var snapshot = f.Snapshot(first);
        Check("daily and BALMO use distinct matching benchmarks", () =>
        {
            Equal(Price(snapshot, Delivery(firstDaily)), "3.25");
            Equal(Price(snapshot, Delivery(nextDaily)), "3.261");
            Equal(Price(snapshot, Balmo(firstBalmo)), "3.4");
            Equal(Price(snapshot, Delivery(march)), "3.85");
            var trace = model.Build(snapshot, [Balmo(firstBalmo)]).Evaluations;
            Equal(trace.Length, 3);
            Equal(trace.All(e => f.Periods[e.Result.Request.Contract].Kind == "BALMO"), true);
            Equal(trace.All(e => e.Use == InputUse.Variable), true);
        });
        Check("daily benchmark change affects that day only; BALMO and all-in stay independent", () =>
        {
            var changed = f.Change(snapshot, f.S(firstDaily + 1000), "0.10");
            Equal(Price(changed, Delivery(firstDaily)), "3.35");
            Equal(Price(changed, Delivery(nextDaily)), "3.261");
            Equal(Price(changed, Balmo(firstBalmo)), "3.4");
            Equal(Price(changed, Delivery(march)), "3.85");
            Equal(Price(changed, new(f.C("location_all_in"), f.K(firstDaily))), "4.5");
            Equal(Price(f.Change(snapshot, f.S(firstDaily + 1000), "-0.10"), Delivery(firstDaily)), "3.15");
            Equal(Price(snapshot, Delivery(firstDaily)), "3.25");
        });
        Check("BALMO benchmark change moves BALMO without inventing daily exposure", () =>
        {
            var changed = f.Change(snapshot, f.S(firstBalmo + 1000), "0.10");
            Equal(Price(changed, Balmo(firstBalmo)), "3.5");
            Equal(Price(changed, Delivery(firstDaily)), "3.25");
            Equal(Price(changed, Delivery(nextDaily)), "3.261");
            Equal(Price(f.Change(snapshot, f.S(firstBalmo + 1000), "-0.10"), Balmo(firstBalmo)), "3.3");
        });
        Check("an expired monthly future's final cannot silently become the BALMO base", () =>
        {
            var final = snapshot.Selections.Single(s => s.Input.Series == f.S(3000));
            Equal(final.Input.Use, InputUse.FrozenFact);
            Equal(final.Observation.Value.ToString(), "2.8");
            Equal(Price(f.Change(snapshot, f.S(3000), "0.50"), Balmo(firstBalmo)), "3.4");
            Equal(Price(snapshot with { Selections = snapshot.Selections.Remove(final) }, Balmo(firstBalmo)), "3.4");
            var missing = snapshot with { Selections = snapshot.Selections.Where(s => s.Input.Series != f.S(firstBalmo + 1000)).ToImmutableArray() };
            Reject("missing_observation", () => model.Build(missing, [Balmo(firstBalmo)]));
            Reject("source_expired", () => model.Build(snapshot, [new(f.C("expired_monthly_future"), f.K(3000))]));
        });
        Check("a BALMO quote cannot fill a missing daily benchmark", () =>
        {
            var missing = snapshot with { Selections = snapshot.Selections.Where(s => s.Input.Series != f.S(firstDaily + 1000)).ToImmutableArray() };
            Equal(Price(missing, Balmo(firstBalmo)), "3.4");
            Reject("missing_observation", () => model.Build(missing, [Delivery(firstDaily)]));
        });
        Check("monthly basis cannot fill a missing daily basis", () =>
        {
            var missing = snapshot with { Selections = snapshot.Selections.Where(s => s.Input.Series != f.S(firstDaily)).ToImmutableArray() };
            Equal(Price(missing, Delivery(march)), "3.85");
            Reject("missing_observation", () => model.Build(missing, [Delivery(firstDaily)]));
        });
        Check("missing mapping is rejected rather than matched by date", () =>
        {
            var curve = f.Curves.Single(c => c.Key == f.C("location_delivery"));
            var invalid = curve with { Inputs = curve.Inputs.SetItem(0, curve.Inputs[0] with {
                Mappings = curve.Inputs[0].Mappings.Where(m => m.Target != f.K(firstDaily)).ToImmutableArray() }) };
            Reject("mapping_coverage", () => f.Model(f.Curves.Replace(curve, invalid)));
        });
        Check("mapping BALMO into a day requires an explicit future shaping implementation", () =>
        {
            var curve = f.Curves.Single(c => c.Key == f.C("location_delivery"));
            var dailyIds = f.DeliveryIds.Where(id => f.Periods[f.K(id)].Kind == "Daily").ToArray();
            var invalid = curve with { Constituents = dailyIds.Select(f.K).ToImmutableArray(), Inputs = [
                new(InputSlot.Base, f.C("benchmark_balmo"), SourceExpiryRule.RequireLive,
                    dailyIds.Select(id => new ConstituentMapping(f.K(id), f.K(firstBalmo + 1000))).ToImmutableArray()),
                curve.Inputs[1] with { Mappings = curve.Inputs[1].Mappings.Where(m => dailyIds.Contains(f.Id(m.Target))).ToImmutableArray() }] };
            Reject("unsupported_mapping", () => f.Model(f.Curves.Replace(curve, invalid)));
        });
        Check("mapping a full-month future into BALMO is not an equal-period dependency", () =>
        {
            var curve = f.Curves.Single(c => c.Key == f.C("location_balmo"));
            var invalid = curve with { Inputs = curve.Inputs.SetItem(0, new(
                InputSlot.Base, f.C("expired_monthly_future"), SourceExpiryRule.FreezeFinalFuture,
                curve.Constituents.Select(k => new ConstituentMapping(k, f.K(3000))).ToImmutableArray())) };
            Reject("unsupported_mapping", () => f.Model(f.Curves.Replace(curve, invalid)));
        });
        Check("old BALMO keeps its fixed delivery dates and expires at its declared cutoff", () =>
        {
            var contract = f.Contracts.Single(c => c.Key == f.K(firstBalmo));
            var before = snapshot with { ValuationAt = contract.Expiry.AddTicks(-1) };
            Equal(Price(before, Balmo(firstBalmo)), "3.4");
            Reject("source_expired", () => model.Build(before with { ValuationAt = contract.Expiry }, [Balmo(firstBalmo)]));
            Equal(contract.DeliveryFrom, new DateOnly(2026, 1, 16));
            Equal(contract.DeliveryTo, new DateOnly(2026, 2, 1));
        });
        Check("month roll selects new dated contracts and preserves the earlier frame", () =>
        {
            var feb = frames.Single(x => x.Day == new DateOnly(2026, 2, 1));
            Equal(Price(f.Snapshot(feb), Delivery(f.Daily(new(2026, 2, 2)))), "3.55");
            Equal(Price(f.Snapshot(feb), Balmo(f.Balmo(new(2026, 2, 2)))), "3.65");
            Equal(f.View(first).Select(r => r.Contract).Intersect(f.View(feb).Select(r => r.Contract)).Count(), 1); // March only.
            Equal(Price(snapshot, Delivery(firstDaily)), "3.25");
        });
        Check("retained monthly history spans mid-month to following month-end", () =>
        {
            var snapshots = frames.Select(f.Snapshot).ToArray();
            var observations = snapshots.SelectMany(s => s.Selections).Select(s => s.Observation).Distinct().ToArray();
            var archive = new ObservationArchive(observations);
            var pin = observations.Select(o => o.Key).ToImmutableHashSet();
            var history = archive.ReadPinnedHistory(f.S(march + 1000), first.At, frames[^1].At.AddTicks(1), pin);
            Equal(history.Length, 8);
            Equal(history[0].ObservedAt, first.At);
            Equal(history[^1].ObservedAt, frames[^1].At);
            Equal(history[0].Value.ToString(), "3.6");
            Equal(history[^1].Value.ToString(), "3.75");
            var earlier = archive.ReadPinnedHistory(f.S(march + 1000), first.At, frames[^1].At.AddTicks(1),
                snapshots[0].Selections.Select(s => s.Observation.Key).ToImmutableHashSet());
            Equal(earlier.Length, 1);
            var daily = archive.ReadPinnedHistory(f.S(f.Daily(new(2026,1,30)) + 1000), first.At, frames[^1].At.AddTicks(1), pin);
            Equal(string.Join(",", daily.Select(o => o.Value.ToString())), "3.24,3.07,3.09,3.2");
        });
        Check("captured frame replays after a later observation revision", () =>
        {
            var changed = f.Change(snapshot, f.S(firstBalmo + 1000), "0.125");
            Equal(Price(changed, Balmo(firstBalmo)), "3.525");
            Equal(Price(snapshot, Balmo(firstBalmo)), "3.4");
            Equal(snapshot.Selections.Single(s => s.Input.Series == f.S(firstBalmo + 1000)).Observation.Key ==
                changed.Selections.Single(s => s.Input.Series == f.S(firstBalmo + 1000)).Observation.Key, false);
        });
        Check("future observation cannot leak into an earlier market cutoff", () =>
        {
            var changed = snapshot with { Selections = snapshot.Selections.SetItem(0, snapshot.Selections[0] with {
                Observation = snapshot.Selections[0].Observation with { ObservedAt = first.At.AddMinutes(1) } }) };
            Reject("observation_cutoff", () => model.Build(changed, [Delivery(firstDaily)]));
        });
        Check("reuse includes exactly the requested dependency closure", () =>
        {
            CurveRequest direct = new(f.C("benchmark_delivery"), f.K(firstDaily + 1000));
            var build = model.Build(snapshot, [Delivery(firstDaily), direct]);
            Equal(build.EvaluatedConstituents, 3);
            Equal(build.Evaluations.Count(e => e.Result.Request == direct), 1);
            Equal(build.Values[0].Lineage.Count, 2);
            var reversed = model.Build(snapshot, [direct, Delivery(firstDaily)]);
            Equal(reversed.Values[1].Value, build.Values[0].Value);
            Equal(reversed.Values[1].Lineage.SetEquals(build.Values[0].Lineage), true);
        });
        Check("units and spread interpretation remain enforced", () =>
        {
            var spread = f.Quotes.Single(q => q.Kind == QuoteKind.Basis);
            Reject("spread_type", () => f.Model(quotes: f.Quotes.Replace(spread, spread with { Kind = QuoteKind.Outright })));
            Reject("spread_type", () => f.Model(quotes: f.Quotes.Replace(spread, spread with { Currency = f.R("other_currency") })));
        });
        var csv = new List<string> { "Market date,Kind,Delivery from,Delivery to (exclusive),Benchmark,Basis,Outright,Currency,Unit" };
        foreach (var frame in frames)
        {
            var requests = f.View(frame);
            if (frame.Day.Day < DateTime.DaysInMonth(frame.Day.Year, frame.Day.Month))
                requests = requests.Add(Balmo(f.Balmo(frame.Day.AddDays(1))));
            var build = model.Build(f.Snapshot(frame), requests);
            foreach (var value in build.Values)
            {
                var period = f.Periods[value.Request.Contract];
                var evaluation = build.Evaluations.Single(e => e.Result.Request == value.Request);
                string Input(InputSlot slot) => build.Evaluations.Single(e =>
                    e.Result.Request == evaluation.Inputs.Single(i => i.Slot == slot).Source).Result.Value.ToString();
                csv.Add($"{frame.Day:yyyy-MM-dd},{period.Kind},{period.From:yyyy-MM-dd},{period.To:yyyy-MM-dd},{Input(InputSlot.Base)},{Input(InputSlot.Spread)},{value.Value},USD,MMBtu");
            }
            if (showExample)
            {
                var daily = build.Values.FirstOrDefault(v => f.Periods[v.Request.Contract].Kind == "Daily");
                var balmo = build.Values.FirstOrDefault(v => f.Periods[v.Request.Contract].Kind == "BALMO");
                Console.WriteLine($"EXAMPLE {frame.Day:yyyy-MM-dd}: daily buckets {requests.Count(r => f.Periods[r.Contract].Kind == "Daily")}, monthly buckets 2, first daily {daily?.Value.ToString() ?? "none"}, BALMO {balmo?.Value.ToString() ?? "none"} USD/MMBtu");
            }
        }
        if (csvPath is not null)
        {
            File.WriteAllLines(csvPath, csv);
            Console.WriteLine($"Synthetic price rows written: {csv.Count - 1}");
        }
        Console.WriteLine($"{passed} mixed-resolution managed checks passed.");
        return passed;
    }

    private static void Equal<T>(T actual, T expected) where T : notnull
    {
        if (!actual.Equals(expected)) throw new Exception($"Expected {expected}; got {actual}.");
    }
    private static void Reject(string code, Action action)
    {
        try { action(); } catch (MarketDataException error) when (error.Code == code) { return; }
        throw new Exception($"Expected rejection: {code}.");
    }
}

internal sealed class MixedResolutionFixture
{
    public sealed record Frame(int Number, DateOnly Day, string DailyAnchor, string BasisAnchor,
        string BalmoBase, string BalmoBasis, string MonthlyAnchor)
    {
        public DateTimeOffset At => new(Day.ToDateTime(new TimeOnly(18, 0), DateTimeKind.Utc));
    }
    public sealed record Period(string Kind, DateOnly From, DateOnly To);
    public ImmutableArray<Frame> Frames { get; } = [
        new(1, new(2026,1,15), "2.94", "0.134", "3.20", "0.20", "3.6"),
        new(2, new(2026,1,27), "2.77", "0.152", "3.09", "0.22", "3.62"),
        new(3, new(2026,1,28), "2.79", "0.161", "3.12", "0.22", "3.63"),
        new(4, new(2026,1,29), "2.90", "0.180", "3.22", "0.23", "3.64"),
        new(5, new(2026,1,31), "2.95", "0.180", "3.25", "0.24", "3.65"),
        new(6, new(2026,2,1), "3.38", "0.148", "3.45", "0.20", "3.7"),
        new(7, new(2026,2,15), "3.19", "0.154", "3.40", "0.21", "3.72"),
        new(8, new(2026,2,28), "3.20", "0.160", "3.41", "0.22", "3.75")];
    public DefinitionRevision Revision { get; } = new(Guid.Parse("91000000-0000-0000-0000-000000000001"), Guid.Parse("91000000-0000-0000-0000-000000000002"));
    public ReferenceRevision Reference { get; } = new(Guid.Parse("92000000-0000-0000-0000-000000000001"), Guid.Parse("92000000-0000-0000-0000-000000000002"));
    public ReferenceKey R(string code) => new(Reference, code);
    public CurveKey C(string code) => new(Revision, code);
    public ContractKey K(int n) => new(Revision, Guid.Parse($"93000000-0000-0000-0000-{n:000000000000}"));
    public SeriesKey S(int n) => new(Revision, Guid.Parse($"94000000-0000-0000-0000-{n:000000000000}"));
    public int Id(ContractKey key) => int.Parse(key.Id.ToString("N")[20..], CultureInfo.InvariantCulture);
    public int Daily(DateOnly day) => 1 + day.DayNumber - new DateOnly(2026,1,16).DayNumber;
    public int Monthly(DateOnly start) => 100 + start.Month;
    public int Balmo(DateOnly start) => 200 + start.DayNumber - new DateOnly(2026,1,16).DayNumber;
    public ImmutableDictionary<ContractKey, Period> Periods { get; }
    public ImmutableArray<int> DeliveryIds { get; }
    public ImmutableArray<int> BalmoIds { get; }
    public ImmutableArray<MarketContract> Contracts { get; }
    public ImmutableArray<Curve> Curves { get; }
    public ImmutableArray<QuoteSpecification> Quotes { get; }
    public ImmutableArray<MarketSeries> Series { get; }
    public MixedResolutionFixture()
    {
        var periods = new Dictionary<int, Period>();
        for (var d = new DateOnly(2026,1,16); d < new DateOnly(2026,3,1); d = d.AddDays(1))
            periods.Add(Daily(d), new("Daily", d, d.AddDays(1)));
        foreach (var month in new[] { 2, 3, 4 })
            periods.Add(100 + month, new("Monthly", new(2026,month,1), new DateOnly(2026,month,1).AddMonths(1)));
        DeliveryIds = periods.Keys.Order().ToImmutableArray();
        foreach (var frame in Frames.Where(f => f.Day.Day < DateTime.DaysInMonth(f.Day.Year, f.Day.Month)))
            periods.Add(Balmo(frame.Day.AddDays(1)), new("BALMO", frame.Day.AddDays(1), new DateOnly(frame.Day.Year,frame.Day.Month,1).AddMonths(1)));
        BalmoIds = periods.Keys.Except(DeliveryIds).Order().ToImmutableArray();
        foreach (var pair in periods.ToArray()) periods.Add(pair.Key + 1000, pair.Value);
        periods.Add(3000, new("Monthly future", new(2026,1,1), new(2026,2,1)));
        Periods = periods.ToImmutableDictionary(p => K(p.Key), p => p.Value);
        // Explicit fixture-only last-mark time: 09:00 UTC at first delivery date.
        Contracts = Periods.Select(p => p.Key == K(3000)
            ? new MarketContract(p.Key, ContractKind.Future, p.Value.From, p.Value.To, FutureExpiry, R("synthetic_future_jan"))
            : new MarketContract(p.Key, ContractKind.Forward, p.Value.From, p.Value.To,
                new(p.Value.From.ToDateTime(new TimeOnly(9,0), DateTimeKind.Utc)), null)).ToImmutableArray();
        QuoteSpecification Quote(string code, QuoteKind kind) => new(R(code), kind, R("usd"), R("gas_mmbtu"),
            D("1"), D("0.001"), D("0.001"), D("-1000"), D("1000"));
        Quotes = [Quote("gas_out", QuoteKind.Outright), Quote("gas_basis", QuoteKind.Basis)];
        var curves = new List<Curve>();
        void Group(string suffix, ImmutableArray<int> ids)
        {
            var members = ids.Select(K).ToImmutableArray();
            var bases = ids.Select(id => K(id + 1000)).ToImmutableArray();
            Curve Direct(string code, string quote, string location, ImmutableArray<ContractKey> constituents, SettlementTarget target) =>
                new(C(code), R(quote), R(location), R("uniform_fixed_utc_0900"), target, CurveRule.Direct,
                    constituents, [], ObservationRole.TraderMark, R("synthetic_marks"), null);
            // Settlement target identity only: this fixture does not implement
            // daily fixing aggregation, BALMO settlement or payments.
            curves.Add(Direct("benchmark_" + suffix, "gas_out", "benchmark_hub", bases,
                new(SettlementKind.Index, R("benchmark_daily_index"), null)));
            curves.Add(Direct("basis_" + suffix, "gas_basis", "location_hub", members,
                new(SettlementKind.IndexDifference, R("location_daily_index"), R("benchmark_daily_index"))));
            curves.Add(new(C("location_" + suffix), R("gas_out"), R("location_hub"), R("uniform_fixed_utc_0900"),
                new(SettlementKind.Index, R("location_daily_index"), null), CurveRule.Add, members,
                [new(InputSlot.Base, C("benchmark_" + suffix), SourceExpiryRule.RequireLive,
                    ids.Select(id => new ConstituentMapping(K(id), K(id + 1000))).ToImmutableArray()),
                 new(InputSlot.Spread, C("basis_" + suffix), SourceExpiryRule.RequireLive,
                    ids.Select(id => new ConstituentMapping(K(id), K(id))).ToImmutableArray())], null, null, null));
        }
        Group("delivery", DeliveryIds); Group("balmo", BalmoIds);
        curves.Add(new(C("location_all_in"), R("gas_out"), R("location_hub"), R("uniform_fixed_utc_0900"),
            new(SettlementKind.Index, R("location_daily_index"), null), CurveRule.Direct, DeliveryIds.Select(K).ToImmutableArray(),
            [], ObservationRole.TraderMark, R("synthetic_marks"), null));
        curves.Add(new(C("expired_monthly_future"), R("gas_out"), R("benchmark_hub"), R("uniform_fixed_utc_0900"),
            new(SettlementKind.FutureSeries, null, null), CurveRule.Direct, [K(3000)], [],
            ObservationRole.DailySettlement, R("synthetic_marks"), null));
        Curves = curves.ToImmutableArray();
        Series = Curves.Where(c => c.Rule == CurveRule.Direct).SelectMany(c => c.Constituents.Select(k =>
            new MarketSeries(S(Id(k) + (c.Key.Code == "location_all_in" ? 2000 : 0)), k, c.Quote, null))).ToImmutableArray();
    }
    private static ExactDecimal D(string value) => ExactDecimal.Parse(value);
    private static DateTimeOffset FutureExpiry => new(2025,12,28,19,30,0,TimeSpan.Zero);
    public CurveModel Model(ImmutableArray<Curve>? curves = null, ImmutableArray<QuoteSpecification>? quotes = null) => new(
        Revision, Reference, [new(R("gas_mmbtu"),R("gas"),R("gas_energy"),R("mmbtu"),R("energy"))],
        quotes ?? Quotes, Contracts, curves ?? Curves,
        [new(R("synthetic_future_jan"),R("gas_mmbtu"),R("usd"),D("1"),D("0.001"),R("benchmark_hub"),R("uniform_fixed_utc_0900"),
            new(2026,1,1),new(2026,2,1),FutureExpiry,R("gas_mmbtu"),D("10000"),LotBasis.FixedTotal)], [], Series);
    public ImmutableArray<CurveRequest> View(Frame frame) => DeliveryIds.Where(id =>
    {
        var period = Periods[K(id)];
        var first = new DateOnly(frame.Day.Year,frame.Day.Month,1);
        return period.Kind == "Daily" ? period.From > frame.Day && period.From < first.AddMonths(1)
            : period.From >= first.AddMonths(1) && period.From < first.AddMonths(3);
    }).Select(id => new CurveRequest(C("location_delivery"),K(id))).ToImmutableArray();
    public MarketSnapshot Snapshot(Frame frame)
    {
        var selections = Series.Where(s => Contracts.Single(c => c.Key == s.Contract).Expiry > frame.At).Select(s =>
        {
            var contract = s.Contract!.Value;
            var period = Periods[contract];
            var id = Id(contract);
            var benchmark = id >= 1000;
            // Deterministic synthetic marks emitted independently per series.
            // These offsets are fixture data, never a production shaping rule.
            var day = D(period.From.Day.ToString(CultureInfo.InvariantCulture));
            var value = s.Key == S(id + 2000) ? D("4.5") : period.Kind switch {
                "Daily" => benchmark ? D(frame.DailyAnchor) + day * D("0.01") : D(frame.BasisAnchor) + day * D("0.001"),
                "BALMO" => benchmark ? D(frame.BalmoBase) : D(frame.BalmoBasis),
                "Monthly" => benchmark ? D(frame.MonthlyAnchor) : D("0.25"),
                _ => throw new InvalidOperationException("Unknown synthetic period.") };
            return new SelectedObservation(new(s.Key, InputUse.Variable), new(
                new(Revision.CatalogId, Guid.Parse($"95000000-0000-0000-0000-{frame.Number * 10000 + IdFromSeries(s.Key):000000000000}")),
                s.Key, R("synthetic_marks"), ObservationRole.TraderMark, PublicationState.Final, frame.At, value));
        }).ToImmutableArray();
        // Keep a separately pinned expired monthly final available. It must not
        // satisfy a missing daily or BALMO mark merely because it is present.
        selections = selections.Add(new(new(S(3000), InputUse.FrozenFact), new(
            new(Revision.CatalogId, Guid.Parse("95000000-0000-0000-0000-000000003000")), S(3000), R("synthetic_marks"),
            ObservationRole.FinalContractSettlement, PublicationState.Final, FutureExpiry.AddMinutes(5), D("2.8"))));
        return new(Guid.Parse($"96000000-0000-0000-0000-{frame.Number:000000000000}"), Revision, frame.At, frame.At,
            InputSelectionPolicy.ExactPinnedFinalObservationsNoAgeFiltering, selections);
    }
    private static int IdFromSeries(SeriesKey key) => int.Parse(key.Id.ToString("N")[20..], CultureInfo.InvariantCulture);
    public MarketSnapshot Change(MarketSnapshot original, SeriesKey series, string amount) => original with {
        Id = Guid.NewGuid(), Selections = original.Selections.Select(s => s.Input.Series == series ? s with {
            Observation = s.Observation with { Key = new(Revision.CatalogId, Guid.NewGuid()), Value = s.Observation.Value + D(amount) }
        } : s).ToImmutableArray() };

    // Export the tested forward inputs rather than duplicating their prices or
    // delivery rules in the preview's database fixture generator.
    public void ExportPreview(string path)
    {
        var curves = Curves.Where(c => c.Key != C("expired_monthly_future")).ToArray();
        var series = Series.Where(s => s.Contract != K(3000)).ToArray();
        var model = Model();
        var document = new {
            catalogId = Revision.CatalogId, revisionId = Revision.RevisionId,
            referenceCatalogId = Reference.CatalogId, referenceRevisionId = Reference.RevisionId,
            contracts = Contracts.Where(c => c.Kind == ContractKind.Forward).Select(c => new {
                id = c.Key.Id, deliveryFrom = c.DeliveryFrom, deliveryTo = c.DeliveryTo, expiry = c.Expiry }),
            curves = curves.Select(c => new { code = c.Key.Code, quote = c.Quote.Code, location = c.Location.Code,
                indexA = c.Settlement.IndexA!.Value.Code, indexB = c.Settlement.IndexB?.Code,
                rule = c.Rule switch {CurveRule.Direct=>"direct",CurveRule.Add=>"add",_=>throw new InvalidOperationException("Unsupported preview curve rule.")}, members = c.Constituents.Select(k => k.Id),
                inputs = c.Inputs.Select(i => new { slot = i.Slot switch {InputSlot.Base=>"base",InputSlot.Spread=>"spread",_=>throw new InvalidOperationException("Unsupported preview input slot.")}, source = i.Source.Code,
                    expiryRule = i.ExpiryRule switch {SourceExpiryRule.RequireLive=>"require_live",_=>throw new InvalidOperationException("Unsupported preview expiry policy.")},
                    mappings = i.Mappings.Select(m => new { target = m.Target.Id, source = m.Source.Id }) }) }),
            series = series.Select(s => new { id = s.Key.Id, contractId = s.Contract!.Value.Id, quote = s.Quote!.Value.Code }),
            frames = Frames.Select(frame => {
                var snapshot = Snapshot(frame);
                var delivery = View(frame).Select(r => r.Contract).ToArray();
                var balmo = frame.Day.Day < DateTime.DaysInMonth(frame.Day.Year, frame.Day.Month)
                    ? new[] { K(Balmo(frame.Day.AddDays(1))) } : [];
                var views = curves.ToDictionary(c => c.Key.Code, c => {
                    var selected = c.Key.Code.Contains("balmo", StringComparison.Ordinal) ? balmo : delivery;
                    return selected.Select(k => c.Key.Code.StartsWith("benchmark_", StringComparison.Ordinal) ? K(Id(k) + 1000) : k)
                        .Select(k => k.Id).ToArray();
                });
                var requests = View(frame).AddRange(balmo.Select(k => new CurveRequest(C("location_balmo"),k)));
                return new { at = frame.At, curveContracts = views,
                    observations = snapshot.Selections.Where(s => s.Input.Use == InputUse.Variable).Select(s => new {
                        id = s.Observation.Key.Id, seriesId = s.Input.Series.Id, observedAt = s.Observation.ObservedAt,
                        value = s.Observation.Value.ToString() }),
                    expected = model.Build(snapshot, requests).Values.Select(v => new {
                        curve = v.Request.Curve.Code, contractId = v.Request.Contract.Id, value = v.Value.ToString() }) };
            })
        };
        File.WriteAllText(path, System.Text.Json.JsonSerializer.Serialize(document));
    }
}
