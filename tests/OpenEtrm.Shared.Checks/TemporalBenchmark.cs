using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using OpenEtrm.Shared.Collections;
using OpenEtrm.Shared.Temporal;

// A small repeatable microbenchmark, not a portfolio or concurrent-load claim.
internal static class TemporalBenchmark
{
    private sealed record Result(string Operation, int OperationsPerSample, double MedianNs, double MinNs,
        double MaxNs, double MedianAllocatedBytesPerOperation);
    public static void Run(string? outputPath)
    {
        var from = new DateOnly(2020, 1, 1); var to = new DateOnly(2030, 1, 1);
        var coveredDays = to.DayNumber - from.DayNumber;
        var dates = Enumerable.Range(0, coveredDays).Select(from.AddDays)
            .Where(d => d.DayOfWeek is not DayOfWeek.Saturday and not DayOfWeek.Sunday).ToArray();
        var business = DateSet.Create(from, to, dates);
        var holidaysA = DateSet.Create(from, to, Enumerable.Range(0, 120).Select(i => from.AddDays(10 + i * 23)));
        var holidaysB = DateSet.Create(from, to, Enumerable.Range(0, 120).Select(i => from.AddDays(17 + i * 29)));
        var unionCount = holidaysA.Dates.Concat(holidaysB.Dates).Distinct().Count();
        var grids = new ImmutablePool<UtcGrid>(4);
        var grid = grids.Intern(UtcGrid.Uniform(new(2026, 1, 1, 0, 0, 0, TimeSpan.Zero),
            new(2027, 1, 1, 0, 0, 0, TimeSpan.Zero), TimeSpan.FromHours(1), 8760));
        // Explicit synthetic UTC weekday/time window; no market-clock compiler.
        var slots = Enumerable.Range(0, grid.Count).Where(i => grid.Start(i).Hour is >= 7 and < 19 &&
            grid.Start(i).DayOfWeek is not DayOfWeek.Saturday and not DayOfWeek.Sunday).ToArray();
        var mask = grid.Select(slots);
        var pool = new ImmutablePool<DateSet>(4);
        business = pool.Intern(business);
        var duplicate = DateSet.Create(from, to, dates);
        var bindings = Enumerable.Range(0, 10_000).Select(_ => pool.Intern(duplicate)).ToArray();
        if (pool.Count != 1 || bindings.Any(v => !ReferenceEquals(v, business))) throw new Exception("Sharing failed.");

        var results = new List<Result>();
        void Measure(string name, int operations, Func<int, long> run, long expected)
        {
            run(Math.Min(operations, 10_000));
            var times = new double[7]; var allocations = new double[7];
            for (var i = 0; i < times.Length; i++)
            {
                var before = GC.GetAllocatedBytesForCurrentThread();
                var start = Stopwatch.GetTimestamp(); var checksum = run(operations);
                var elapsed = Stopwatch.GetElapsedTime(start).TotalNanoseconds;
                var allocated = GC.GetAllocatedBytesForCurrentThread() - before;
                if (checksum != expected) throw new Exception($"Benchmark correctness check failed: {name}.");
                times[i] = elapsed / operations; allocations[i] = (double)allocated / operations;
            }
            Array.Sort(times); Array.Sort(allocations);
            results.Add(new(name, operations, times[3], times[0], times[^1], allocations[3]));
            Console.WriteLine($"{name}: median {times[3]:F1} ns/op; {allocations[3]:F1} allocated bytes/op");
        }
        const int lookups = 1_000_000;
        var dateOracle = dates.ToHashSet();
        var expectedMembers = Enumerable.Range(0, lookups).LongCount(i => dateOracle.Contains(from.AddDays(i % coveredDays)));
        Measure("warm_date_membership", lookups, n => {
            long sum = 0; for (var i = 0; i < n; i++) if (business.Contains(from.AddDays(i % coveredDays))) sum++; return sum;
        }, expectedMembers);
        var slotOracle = slots.ToHashSet();
        var expectedSlots = Enumerable.Range(0, lookups).LongCount(i => slotOracle.Contains(i % grid.Count));
        Measure("warm_hourly_mask_membership", lookups, n => {
            long sum = 0; for (var i = 0; i < n; i++) if (mask.Contains(i % grid.Count)) sum++; return sum;
        }, expectedSlots);
        Measure("warm_intern_same_reference", lookups, n => {
            long sum = 0; for (var i = 0; i < n; i++) if (ReferenceEquals(pool.Intern(business), business)) sum++; return sum;
        }, lookups);
        Measure("warm_intern_equal_payload", 100_000, n => {
            long sum = 0; for (var i = 0; i < n; i++) if (ReferenceEquals(pool.Intern(duplicate), business)) sum++; return sum;
        }, 100_000);
        const int rolls = 250_000;
        var expectedRolls = Enumerable.Range(0, rolls).Sum(i => {
            var day = from.AddDays(i % (coveredDays - 7));
            while (!dateOracle.Contains(day)) day = day.AddDays(1);
            return (long)day.DayNumber;
        });
        Measure("warm_following_roll", rolls, n => {
            long sum = 0; for (var i = 0; i < n; i++) sum += DateRolling.Adjust(from.AddDays(i % (coveredDays - 7)), business, DateRoll.Following).DayNumber; return sum;
        }, expectedRolls);
        Measure("calendar_union_120_plus_120", 10_000, n => {
            long sum = 0; for (var i = 0; i < n; i++) sum += holidaysA.Union(holidaysB).Count; return sum;
        }, unionCount * 10_000L);
        Measure("cold_ten_year_business_date_payload", 500, n => {
            long sum = 0; for (var i = 0; i < n; i++) sum += DateSet.Create(from, to, dates).Count; return sum;
        }, dates.Length * 500L);
        Measure("cold_one_year_hourly_grid", 200, n => {
            long sum = 0; for (var i = 0; i < n; i++) sum += UtcGrid.Uniform(grid.Start(0), grid.End(grid.Count - 1), TimeSpan.FromHours(1), 8760).Count; return sum;
        }, grid.Count * 200L);
        Measure("cold_one_year_hourly_mask", 500, n => {
            long sum = 0; for (var i = 0; i < n; i++) sum += grid.Select(slots).Count; return sum;
        }, slots.Length * 500L);
        using var process = Process.GetCurrentProcess();
        var peakWorkingSet = process.PeakWorkingSet64;
        var report = new {
            runtime = RuntimeInformation.FrameworkDescription, os = Environment.OSVersion.VersionString,
            architecture = RuntimeInformation.ProcessArchitecture.ToString(), logicalProcessors = Environment.ProcessorCount,
            samples = 7, uniqueContracts = 0, scenarios = 0,
            workload = "Synthetic temporal utilities only; single-thread measured loops; no database or pricing.",
            constructionNote = "cold_* constructs a new payload after runtime warm-up; it does not measure process startup or cold JIT.",
            coveredDays, businessDates = business.Count, hourlyIntervals = grid.Count, selectedHourlyIntervals = mask.Count,
            bindings = bindings.Length, uniqueDatePayloads = pool.Count,
            rawDateBufferBytes = business.Count * sizeof(int), rawGridBufferBytes = (grid.Count + 1) * sizeof(long),
            rawMaskBufferBytes = ((grid.Count + 63) / 64) * sizeof(ulong),
            bufferNote = "Raw backing arrays only; excludes headers, bindings, metadata and pool overhead.",
            managedBytesAfterGc = GC.GetTotalMemory(true), peakProcessWorkingSetBytes = peakWorkingSet > 0 ? (long?)peakWorkingSet : null,
            memoryNote = "Managed bytes cover the benchmark process, not incremental payload retention. A null process peak means unavailable.",
            results
        };
        if (outputPath is not null) File.WriteAllText(outputPath, JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
        Console.WriteLine($"{bindings.Length} bindings share {pool.Count} date payload; date/grid/mask backing bytes {report.rawDateBufferBytes}/{report.rawGridBufferBytes}/{report.rawMaskBufferBytes}.");
        GC.KeepAlive(bindings);
    }
}
