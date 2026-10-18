# Shared scenario calculation benchmark

This synthetic in-process benchmark qualifies the current managed calculation
path, not database/service throughput or production capacity. Run it from the
repository with the pinned SDK:

```sh
dotnet run --project tests/OpenEtrm.MarketData.Checks -c Release -- --risk-benchmark /tmp/leanetrm-risk-benchmark.json
```

Each workload has independently marked base and contract-specific basis inputs,
with explicit output = base + basis mappings and two books. All quantities,
execution bases and absolute bumps are synthetic. One factor is the shared base;
the three-factor workload also bumps two individual basis inputs independently.
Seven scenarios means one base and three separate up/down pairs, not a joint shock.

One warm-up precedes five sequential samples with empty within-run valuation
caches. Fixture/model/position construction is excluded. The measured engine
includes curve building, black-box pricing, position scaling, exact delta/gamma,
book aggregation and comparison of every position and book total with a separately
prepared reference. The reference builds each complete scenario from independent
synthetic input datasets and evaluates a direct mark formula per position; it
does not use the engine's affected-node or unit-valuation reuse. Its mark-evaluation
counter is distinct from actual `IUnitPricer.Evaluate` calls in the engine.

Local observation on 2026-10-18: macOS 26.6.2, Arm64, 14 logical processors,
.NET 10.0.13, Release build, single-threaded calculation. This was an unisolated
local host; timings are observations, not latency guarantees. Database, identity,
input capture, serialization, persistence, concurrent requests and browser work
are excluded.

| Workload | Positions | Held contracts / unit valuations | Primitive inputs | Factors / scenarios | Engine median | Full-reference median | Engine allocations |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Repeated | 10,000 | 1 | 2 | 1 / 3 | 107.32 ms | 72.08 ms | 64.50 MiB |
| Shared fan-out | 10,000 | 128 | 129 | 3 / 7 | 114.04 ms | 122.90 ms | 161.94 MiB |
| Distinct | 1,000 | 1,000 | 1,001 | 1 / 3 | 26.49 ms | 23.44 ms | 24.84 MiB |

Allocations are median current-thread total allocated bytes per run, including
result verification. They are not retained memory or process peak working set.
The JSON also records sample minimum/maximum and reference allocations.

| Workload | Engine unit-pricer calls | Reference per-position mark evaluations | Curve nodes evaluated / reused | Full-reference curve nodes |
| --- | ---: | ---: | ---: | ---: |
| Repeated | 3 | 30,000 | 7 / 2 | 9 |
| Shared fan-out | 388 | 70,000 | 523 / 1,276 | 1,799 |
| Distinct | 3,000 | 3,000 | 4,003 / 2,000 | 6,003 |

The compiled dependency closures contain 3, 257 and 2,001 nodes respectively.
All work counts include the base evaluation. The engine's `UniqueMarketContracts`
counts exact contracts in declared pricer requests; held contracts and primitive
inputs are separately identified above. No cross-run result cache is measured.

Repeated and distinct workloads are slower than their simple references in this
run despite fewer curve evaluations. The engine retains exact unit cash through
position scaling and pays for typed contracts, dependency checks and reuse
bookkeeping. This benchmark does not isolate those costs individually. The shared
fan-out workload reduces both pricer work and the observed median, but these
results do not establish a universal speedup. Nonlinear black-box correctness has
separate independent checks. The benchmark does not qualify options or settlement
PV. The interactive booking preview still limits its database to 256 trades;
larger authorized service workloads and durable execution require separate
qualification.
