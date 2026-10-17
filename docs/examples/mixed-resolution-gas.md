# Mixed daily/monthly gas curves and BALMO

Status: executable managed-core and **disposable browser preview** case.
The preview persists the exported managed fixture
through the existing schema and authorized API. Every date, price, clock and cutoff is synthetic;
none is an actual exchange, publisher or product specification.

## Run the example

With the SDK pinned in `global.json`:

```sh
dotnet run --project tests/OpenEtrm.MarketData.Checks -- --mixed-resolution
# Optionally write all 87 synthetic price rows to a new output file:
dotnet run --project tests/OpenEtrm.MarketData.Checks -- --mixed-resolution /tmp/mixed-resolution-prices.csv
```

The command runs 24 checks and prints eight cross-sections. The full managed
suite includes these checks too. The implementation is in
[MixedResolutionChecks.cs](../../tests/OpenEtrm.MarketData.Checks/MixedResolutionChecks.cs).
The optional file contains market date, period kind, exact half-open delivery
period, benchmark price, basis, built outright, currency and unit. It excludes
internal identifiers. It is synthetic test output, not an import of market data.

For the browser, using installed PostgreSQL binaries and the pinned SDK:

```sh
python3 tools/run_preview.py --pg-bin /path/to/postgresql/bin --dotnet /path/to/dotnet --example mixed-gas
# Run the isolated HTTP checks and remove their owned database afterward:
python3 tools/run_preview.py --pg-bin /path/to/postgresql/bin --dotnet /path/to/dotnet --example mixed-gas --check
```

Open the printed loopback URL and choose **Explore sample prices**. Use
**Location gas · daily & monthly** for the strip, or **Location gas · balance of
month** for the independently quoted remaining period. Change the market date in
the header. Price sources and How it's priced support one contract or all
contracts. Profile → Preview access allows the simulated editor to save changes.
The basic interest-rate example remains available; the default `standard` dataset
still contains the original futures and power examples in a separate preview.

All new previews keep frozen copies of their built web assets in their own
temporary directories. Starting or rebuilding another preview does not change
those assets. The launcher removes only its owned database, files and processes.

## Select explicit delivery windows

For this fixture, the named selection is **remaining current delivery month
daily; next two months monthly**. It excludes today's begun delivery day. It is
not a production default or a definition of the next listed futures contract.
Every listed frame is at 18:00 UTC, after the explicitly selected operating-day
start of 09:00 UTC. The saved market cutoff equals that valuation instant.

| Market date in 2026 | Daily delivery days | Monthly tail | First daily outright | Separate BALMO outright |
| --- | --- | --- | --- | --- |
| January 15 | January 16–31 | February, March | 3.250 | 3.400 |
| January 27 | January 28–31 | February, March | 3.230 | 3.310 |
| January 28 | January 29–31 | February, March | 3.270 | 3.340 |
| January 29 | January 30–31 | February, March | 3.410 | 3.450 |
| January 31 | None | February, March | — | — |
| February 1 | February 2–28 | March, April | 3.550 | 3.650 |
| February 15 | February 16–28 | March, April | 3.520 | 3.610 |
| February 28 | None | March, April | — | — |

Prices are USD/MMBtu. The all-contract daily/monthly view has contiguous,
non-overlapping coverage from the next delivery day through the monthly tail.
BALMO is an alternative separately quoted period, not an extra daily/monthly
position or an additional bucket to add to that coverage. An empty daily window
at month-end is intentional, with no substitute or automatic roll.

Each saved frame supplies immutable explicit per-curve request lists to the API.
Neither the browser nor the server infers a roll from missing inputs. This does
not implement an automatic production membership-rule resolver. Definitions retain both daily
and monthly contracts; their selected cross-section does not mutate them.

## Match the base to the quoted spread

```text
daily outright[d] = benchmark daily forward[d] + location daily basis[d]
BALMO outright[p] = benchmark BALMO forward[p] + location BALMO basis[p]
monthly outright[m] = benchmark monthly forward[m] + location monthly basis[m]
```

For January 15, the first daily contract is 3.100 + 0.150 = 3.250; the next day
is 3.110 + 0.151 = 3.261. The separately quoted January 16–31 BALMO contract is
3.200 + 0.200 = 3.400. The daily marks are supplied independently of the BALMO
mark. The fixture's deterministic per-series data generator is test data, not a
production shaping rule. Monthly tail inputs here are forward marks, not futures
settlements. Forward curves reference their declared daily index identities;
monthly/BALMO fixing aggregation and settlement execution are not implemented.

Basis orientation is location minus benchmark. Every mapping names an exact
source contract with the same delivery interval and profile. Base and output
locations are explicitly different; spread and output share the location. Typed
quote/quantity references preserve USD per MMBtu with multiplier one and explicit
bounds. The managed core receives resolved reference keys pinned to one exact
reference revision. The browser fixture inserts these relationships through the
existing exact-version FKs and seal validators; no new tables or migrations are
needed. Its HTTP checks evaluate every selected curve on all eight dates against
the managed fixture's prices and exact membership lists.

A directly quoted BALMO contract covers fixed start/end dates. Tomorrow's
remaining-period quote is a different contract when its start date changes.
The fixture explicitly ends mark eligibility at 09:00 UTC on the first delivery
day. No old BALMO contract silently shortens itself. Different cutoffs or a
partial-realization contract require explicit terms and further qualification.

A single BALMO mark cannot determine daily prices. The first executable mapping
still rejects unequal periods: BALMO-to-daily shaping, containing-month projection
and reverse aggregation remain unsupported. Any later mapping must declare the
actual spread benchmark, clock, coverage and transformation. Choosing a full-month
future as the base is valid only for a spread explicitly defined against that
reference and with a qualified mapping; it is not a BALMO fallback.

## Expired monthly future control

An independent January monthly future is included with a synthetic last trading
instant of December 28, 2025 at 19:30 UTC. Its pinned final price, observed five
minutes later, is 2.800. That fact is available throughout the January frames.
Changing that final in an alternate pinned frame, or removing it, leaves the
explicitly benchmarked BALMO result at 3.400. Removing the actual BALMO benchmark
raises `missing_observation` even while the monthly final is present.

Requesting the expired future as a live output raises `source_expired`.
Explicitly mapping it into the unequal BALMO period raises `unsupported_mapping`;
selecting a freeze policy does not bypass delivery validation. The existing core
suite separately tests an eligible equal-period dependency using explicit final
freezing. These checks do not qualify real listing calendars, bidweek or source
publication/knowledge-time selection.

## What the checks establish

- Complete mixed daily/monthly cross-sections on all eight dates, including two
  month-end boundaries and the month rollover, without coverage overlap/gaps.
- Independent up/down changes to daily and BALMO benchmarks affect only their
  declared price dependencies; independent all-in marks retain their own inputs.
  These are price rebuilds, not instrument PV, Greeks or a released scenario API.
- Missing daily/BALMO benchmarks, missing daily basis, missing mappings, unequal
  periods and incompatible units/mark interpretations raise structured errors.
- A fixed dated daily benchmark has four retained observations; a fixed March
  monthly benchmark has eight observations from January 15 through February 28.
  Histories remain attached to those contracts rather than a rolling label.
- Old captured inputs replay unchanged after a later observation revision;
  explicit cutoff and expiry boundaries are enforced. History uses exact pins,
  not an automatic bitemporal resolver or certified publication-time eligibility.
  The browser preserves unavailable samples as explicit gaps with reasons. Exact
  dated history can include saved marks outside a frame's displayed curve window;
  it never substitutes that window's currently selected contracts.
- A requested benchmark shared with its dependent output evaluates once, with
  exact evidence retained. Reordering those requests preserves values/lineage.

The local browser fixture now passes 24 HTTP checks, including editor/viewer and
session boundaries, correction/revision copies preserving period selections,
independent daily/BALMO edits, dated histories, month-end empty states and rates.
Automatic rolling/shaping, mixed futures
and daily-index settlement specifications, index fixings, weighted aggregation,
publication/recording eligibility and trade cash lifecycles need their own explicit
rules and backend checks before those workflows are enabled.
