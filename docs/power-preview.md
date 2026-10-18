# Standalone power preview

**Power TOUs** sits alongside the existing curves, rates, schedules and admin
screens. It uses this repository's managed API and isolated stock PostgreSQL.
Check the repository boundary with `python3 tools/check_standalone.py`.

Choose a market date in the header, then open **Power TOUs**. Select a power
curve, delivery period, product example, hours block and grid interval; none of
these economic choices is preselected. The two editable Monday–Sunday grids
separate non-holidays from holidays. Cells support 60, 30, 15 or 5 minutes.
HE/HB changes labels, never interval identity or economics.

TOU products are authored on the same page: editors draft a product (code, name,
market clock, hour-beginning peak window, Saturday flag), approvers publish it,
and published versions never change. The calculation offers each product's latest
published version. Each binds an exact clock rule from a sealed reference
revision. TOU products are current definitions: under a historical market view
they are not readable and the page refuses rather than substituting them. The
preview starts with seven common ISO conventions (PJM, NYISO, ISO-NE: Monday–
Friday HE08–HE23 Eastern prevailing; ERCOT, SPP: HE07–HE22 Central prevailing;
CAISO/WECC: Monday–Saturday HE07–HE22 Pacific prevailing; MISO: HE07–HE22 fixed
EST). Verify them against the product specification before any settlement use. Holidays are the closed dates of the curve's
settlement index calendar inside the delivery period; the calendar must cover
the whole period, and clients cannot supply their own holiday list. An IANA
clock rule's declared tzdb release must equal the release of the installed
zoneinfo data (`+VERSION`, else the `tzdata.zi` header, under `$TZDIR` or the
system directory); otherwise the calculation is refused with `clock_tzdb`. The
disposable preview fixture declares the release installed on its host.

| Seeded product | Non-holiday on-peak | Clock |
|---|---|---|
| PJM, NYISO, ISO-NE | Monday–Friday HE08–23 | Eastern prevailing |
| ERCOT, SPP | Monday–Friday HE07–22 | Central prevailing |
| CAISO / WECC | Monday–Saturday HE07–22 | Pacific prevailing |
| MISO settlement / FTR | Monday–Friday HE07–22 | Fixed UTC−05 |

Holiday on-peak cells are empty. Off-peak is the exact complement. These are
editable examples, not exchange product certification. The fixed-clock MISO
example does not define every product associated with that market. The PJM
mask follows [Manual 15, section 12.4](https://www.pjm.com/-/media/DotCom/documents/manuals/m15-redline.pdf).
Qualify real product specifications independently before live settlement.

UTC boundaries retain operating date, local hour, offset and repeat occurrence.
Fall has 25 actual hourly intervals, with the repeated local hour twice, rather
than a fictitious HE25. Spring has 23; fixed EST retains 24. Missing/ambiguous
midnight boundaries and transitions cutting through a cell fail explicitly.

## Calculation contract

The preview consumes the actual selected native curve value and dated member
under current authorization. It requires an explicitly designated synthetic power
commodity, an outright price per MWh with multiplier one, and a compatible
single-index settlement target. Reference/definition pins and captured clock
rules accompany the result.

The example explicitly allocates that quote flat to selected intervals. It does
not construct a calibrated hourly curve or change the curve's stored profile.
Generated all-in prices have no invented LMP decomposition. The managed
settlement class separately accepts energy, congestion and loss components and
checks their exact sum against total LMP.

For flat MW, MWh is MW × actual elapsed hours. Average prices are duration weighted
and cash is the sum of interval MWh × price. Integer/rational intermediates
remain exact, including five-minute durations. The required
`duration_weighted_flat_mw_to_even_v1` policy rounds price reports to 18 digits
and final cash to two, ties to even, after aggregation. It also returns the exact
cash numerator/denominator. Signed quantities and negative prices retain signs.
Hour and energy reports round to 18 fractional digits under that versioned
policy; cash is calculated from exact intermediates, never these report strings.
Hourly diagnostic aggregation requires complete UTC hours and does not replace
a contractually named published hourly price.

Price type (Test, Official or a user label) and timing (End of day, Intraday or a
user label) are independent required classifications. A label never promotes
generated data into an official publication.

## Scope

This is an **unsaved synthetic calculation**. Durable mask publication, product
bindings, settlement imports, official revision eligibility and historical clock
publication remain work. Historical market-context mode rejects this calculation
rather than substituting installed current rules for historical authority.
Current-input mode captures the installed rules once for its calculation receipt.

The fixture uses actual MWh/MW reference units and retains its synthetic currency;
it does not convert user databases. No tables were added for this preview.
Variable volume, metered sub-hour quantity, shaping calibration and futures
variation margin are outside this flat-MW example. The domain, HTTP and browser
checks cover DST, holidays, partitioning, exact arithmetic, reference validation,
editable grids, current access and the original curve screens.

## Continuation checklist

The standalone slice above is implemented and tested. The remaining authoring
and business requirements are:

- Extend the grid editor with rectangular painting and spreadsheet copy/paste.
  Reject overflowing or malformed pastes instead of truncating or filling cells.
  Numeric cells must distinguish an explicit zero from an unknown blank.
- Reuse a suitable numeric grid for month-by-hour shaping weights. Editing and
  validation alone must not claim calibrated prices or applied quantity shaping.
- Provide standalone date-range/membership queries and browser examples for
  spring, autumn, fixed-clock and empty selections, independently of which
  monthly contracts happen to be in the curve fixture. Zero selected hours is a
  valid mask query; an average settlement over zero duration is undefined.
- Extend explicit clock capture and replay, holiday coverage validation and
  non-hour transition scenarios before claiming general clock support. The
  current compiler rejects transitions that cut through a chosen interval.
- Exercise varying generated sub-hour prices and LMP components in the browser,
  including gaps, duplicates, negative values and classification mismatches.
  The current UI generates flat total prices; component validation and hourly
  aggregation currently have managed checks rather than a component editor.
- Qualify explicit peak/off-peak constituent selection, locational combinations
  and forward/fixing boundaries. Keep exact mappings and units, fail on gaps or
  ambiguous overlaps, and count the deal's energy once.
- Add effective/known history to TOU product publication so historical views
  can use the products that were in force; today products are current-only.

These are pending items, not assertions of completed capability. Continue from
the existing standalone domain, API, reference links and checks; do not replace
the curve, schedule or administration foundation with a different application.
