# Standalone power preview

**Power TOUs** sits alongside the existing curves, rates, schedules and admin
screens. It uses this repository's managed API and isolated stock PostgreSQL.
Check the repository boundary with `python3 tools/check_standalone.py`.

Choose a market date in **Curves & prices**, then open **Power TOUs**. Select a
power curve, contract and product example. The two editable Monday–Sunday grids
separate non-holidays from holidays. Cells support 60, 30, 15 or 5 minutes.
Supply holiday dates separately; blank explicitly means none. Payment calendars
are separate. HE/HB changes labels, never interval identity or economics.
Choose an exact quantity specification for **Flat MW** or **Total MWh**. Total
energy also requires an allocation; the supported choice is flat MW across the
selected intervals. Decimal display places belong to this unsaved example and
are editable for quantities, prices and money.

| Product example | Non-holiday on-peak | Clock |
|---|---|---|
| PJM | Monday–Friday HE08–23 | Eastern prevailing |
| ERCOT | Monday–Friday HE07–22 | Central prevailing |
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
`duration_weighted_power_quantity_to_even_v2` policy rounds price reports to 18 digits
and final cash to two, ties to even, after aggregation. It also returns the exact
cash numerator/denominator. Signed quantities and negative prices retain signs.
Hour and energy reports round to 18 fractional digits under that versioned
policy; cash is calculated from exact intermediates, never these report strings.
Hourly diagnostic aggregation requires complete UTC hours and does not replace
a contractually named published hourly price.

Total MWh is conserved rather than multiplied by hours. Each interval retains an
`ExactQuantity` with its exact quantity specification and rational share of total
selected duration. A 1-MWh total over 23 hours therefore has 1/23 MWh in each hour,
without rounding those shares before settlement. Signed totals, exact price
denominators and final overflow checks use the same typed amount operations.
Display rows retain the exact decimal price and rational energy separately from
formatted text. The selected reference revision must contain its quantity
definitions; a supplemental unit catalog is not an implicit cross-version bridge.

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
variation margin and persistence of these quantity rules on booked sides are
outside this example. The domain, HTTP and browser
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
- Add durable TOU drafts/publications and exact product/calendar/clock bindings
  under existing current permissions and effective/known history. These are
  required before the unsaved example can become stored market configuration.

These are pending items, not assertions of completed capability. Continue from
the existing standalone domain, API, reference links and checks; do not replace
the curve, schedule or administration foundation with a different application.
