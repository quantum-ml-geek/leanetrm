# Decisions and unresolved choices

Status: design record, not implementation evidence.
The architecture is in [architecture.md](architecture.md); delivery scope is in
[plan.md](plan.md).

## Agreed requirements

| ID | Decision | Consequence |
| --- | --- | --- |
| D01 | Public project under Apache-2.0 | Preserve license/attribution; review all published material |
| D02 | Fresh implementation/history, with synthetic examples | Private sources, datasets and operational history are not imported |
| D03 | Vanilla PostgreSQL | No custom server fork or mandatory private runtime dependency |
| D04 | Preserve the independent side architecture | Trades reference immutable instruments; instruments have reusable sides through explicit memberships |
| D05 | AI is a first-class application user | Core workflows have discoverable typed operations, not only browser controls |
| D06 | LLM-agnostic boundaries | Provider-specific types stay outside domain/calculation contracts |
| D07 | Deterministic business execution | Models propose; application policy and versioned calculations execute |
| D08 | Robust administration belongs in the foundation | Principals, delegation, policy, current permissions and audit are core requirements |
| D09 | Shock shared primitive factors | All affected computations consume the same immutable scenario |
| D10 | Black-box pricers | Risk does not require knowledge of a model's internal algorithm |
| D11 | Reuse eligible unit results and factor out quantity | Quantity scalability is explicit and independent of market nonlinearity |
| D12 | Declare curve dependencies | Derived gas/power/location values rebuild from approved recipes |
| D13 | Typed values and controlled precision | Money, price, quantity, units, rounding and numerical policy are distinct contracts |
| D14 | Futures and fixed/floating linear products are the initial product scope | Futures settlement/variation-margin semantics are required; options/optimization remain later breadth |
| D15 | Sides own schedule generation and PV behavior | Each side computes its contribution from its schedule; instruments combine schedules and valuations |
| D16 | An option side can reference sibling sides | Explicit context-bound dependencies preserve a flat instrument-side topology |
| D17 | Physical and financial sides can form a composite | Delivery terms/activity and financial settlement remain separately modeled |
| D18 | Lifecycle is a core design concern | Amendments, due events and expiry must have explicit retained transitions |
| D19 | Portfolio contains books; book contains trades | Business ownership and aggregation follow this hierarchy |
| D20 | Trade owns instrument-to-quantity bindings and lifecycle directly | Multiple instruments can belong to one trade without another quantity-bearing domain class |
| D21 | Economic equivalence governs definition reuse | Equal canonical instrument economics can share a definition without merging trade quantities or lifecycle state |
| D22 | Bitemporal historical environment is a baseline requirement | Select business/effective time and what was known; include trades, relationships and market data |
| D23 | Context governs the whole business environment | Resolve once and propagate the same immutable selection through UI, API, agents, calculations, joins and exports |
| D24 | Temporal names are effective_from/effective_to and known_from/known_to | Point queries use effective_at and known_at; keep contract effective/delivery attributes distinct |
| D25 | Temporal intervals are half-open, with UTC knowledge timestamps and a finite open-end sentinel | Document [from,to) in column comments, use consistent suffixes and reserve the selected upper-bound convention |
| D26 | Persist instants in UTC and display them in the user's selected time zone | Date-only terms remain dates; display preferences cannot change economic meaning |
| D27 | Core reference tables and referential integrity belong in the starting application | Currencies, units, commodities, locations, venues, calendars, rates and futures use database-enforced exact-version relationships |
| D28 | Public futures catalogs contain generic placeholders and synthetic examples | Real definitions require sourced verification, ongoing maintenance and installation-specific data rights; no placeholder booking/valuation |
| D29 | leanetrm.com is the intended eventual hosted domain | Hosting and data-use/distribution permissions are separate later operational work |
| D30 | Use C#/.NET, TypeScript and stock PostgreSQL | Pin runtime/dependencies during implementation; numerical contracts remain independent of application frameworks |

## Proposed implementation choices

These are working proposals, not additional user requirements. Resolve them
through the evidence and acceptance criteria in the plan.

| ID | Proposal | Rationale / validation |
| --- | --- | --- |
| P01 | Modular monolith; browser/application/database tiers | Two server components initially; split processes only when measured needs justify it |
| P03 | Relational recipe/edge tables and compiled dependency DAG | Shared computation without a graph database |
| P04 | Finite differences and full repricing as the generic risk path | Supports black-box pricers; analytic paths are optional validated accelerators |
| P05 | Within-run reuse first | Demonstrate identity and dependency completeness before cross-run caches |
| P06 | Committed revision ordering behind the historical date selector | Resolve user dates to certified knowledge prefixes; avoid unsupported physical commit-time claims |
| P07 | Trusted typed operators before general scripting | Bounded extension surface with explicit dependencies and versions |
| P08 | One authorized operation catalog for UI, API and MCP | Prevent business-rule and permission drift across clients |
| P09 | Common interfaces and abstract base classes for instrument/side behavior | Require PV/schedule behavior; share ordinary aggregation and delegate models where appropriate |
| P10 | Typed lifecycle commands and immutable business events over versioned trade state | Domain classes decide behavior; the application authorizes and commits transitions atomically |
| P11 | Versioned local TOU rules with explicit market clocks, compiled to UTC intervals | Distinguish fixed offsets, regional DST rules, source conventions and user display zones; retain schedule provenance |
| P12 | Immutable coherent reference-revision bundles, frozen after draft insertion | Initial storage implementation has exact-revision FKs and tested freeze/write locks; freeze is not activation or historical publication |

## Clarifications that must survive implementation

- Applying one shock is separate from sharing one valuation. Different contracts
  consume the same shocked market even when they need different computations.
- Do not shock individual trades. Shock factors, rebuild dependencies and run
  the affected pricers.
- A factor can be a dependency even when the measured delta is zero.
- Quantity scalability is not the same as a linear market payoff. Future options
  at different strikes are different definitions; identical full option terms can
  still be reusable and quantity scalable where their model permits it.
- A power/gas relationship must be an explicit recipe with units and delivery
  mappings. Correlation alone is not an instruction to propagate a pricing shock.
- A graph database is unnecessary; dependency ordering and reverse indexes are
  still required.
- Computation reuse cannot widen data access or replace current authorization.
- Dates, source availability, effective time and application revisions are
  different coordinates.
- Side schedule generation and valuation are behaviors, not only fields on a
  generic record. Inheritance enforces contracts; composition combines economics.
- Sibling visibility uses declared stable references and the instrument's pinned
  context. It is not unrestricted access to other records or recursive total PV.
- Combining physical and financial schedules preserves event identities, typed
  delivery metadata and explicit quantity links; dates alone are not join keys.
- Portfolio/book/trade are business objects. Instrument quantities and per-trade
  state belong directly to Trade; persistence rows are not additional business
  objects by default.
- Historical context selects effective business state and knowledge independently.
  Market observation/delivery dates and installation knowledge are different
  coordinates. Current authorization still governs historical access.
- Temporal joins include book/trade membership and market/reference bindings.
  Retained immutable definitions alone do not make those relationships historical.

## Choices to resolve before the relevant implementation

| ID | Choice | Required evidence / decision point |
| --- | --- | --- |
| O01 | Working decimal representation, precision and overflow limits | Multiplication/division, units, cancellation and deterministic parallel reduction; representative benchmarks; decide in core milestone |
| O02 | Initial quantity bases and normalized schedule rules | Common quantity/output basis, versioned per-side transformations, total versus rate quantities, one sign convention and payment timing; decide before bookings |
| O03 | Primitive factor schema, quote units and alias rolls | Dated gas and power examples with pillar mappings and no double shocks; decide in scenario milestone |
| O04 | First identity integration and bootstrap flow | Human/agent lifecycle, delegation expiry/revocation/redelegation, MFA/federation integration and credential custody; decide before an exposed application |
| O05 | Company/workspace/book/portfolio scope relationships | Capability matrix, delegation/elevation and current security classification after historical book transfers; decide before persistent business operations |
| O06 | Approval thresholds and separation-of-duties defaults | Action classes, exact payloads, authority revalidation and atomic consumption; decide before enabling policy-controlled writes |
| O07 | Date-to-knowledge resolution implementation | Mandatory baseline date selector; qualify publication/commit semantics, valid interval storage under timestamp ties/regressions, consistent cross-scope cuts, dependency closure, lag, recovery and retention before exposure |
| O08 | Historical engine retention and upgrade compatibility | Replay fixtures across a schema/model upgrade; decide before claiming exact historical replay |
| O09 | Initial model providers and supported capabilities | Common adapter conformance plus task outcomes; product operations remain provider independent |
| O10 | Performance targets and deployment envelope | Reproducible workload and measured cold/warm behavior; agree budgets before performance acceptance |
| O11 | Audit, market-data and conversation retention | Access, redaction, deletion/export obligations and retained replay needs; decide before real data |
| O12 | Advanced P&L explain ordering and cross terms | Reconcile controlled multi-factor movements with full revaluation; later risk milestone |
| O13 | Option-side contribution and exercise-control accounting | Distinguish extra payoff from control of sibling obligations; choose/test adjustment or joint allocation, option coefficient and controlled quantity fraction without double counting; before option support |
| O14 | Initial physical-side valuation conventions | Define delivery value, payments, quantity sources and commodity-specific location/clock schemas; before physical-product support |
| O15 | Supported lifecycle transitions and state dimensions | Define booking corrections, economic termination, due events, realized fixings and outstanding obligations; before enabling the associated command |
| O16 | Lifecycle occurrence identity and correction rules | Separate occurrence/action/attempt/effect IDs; define corrections, replay compatibility, current dispatch authority and duplicate/stale-job tests; before automatic lifecycle processing |
| O17 | Historical-context UI defaults | Visible date/time boundaries and time zone, simple versus advanced coordinate controls, coverage and lag labels; before historical UI acceptance |
| O18 | Exact supported temporal upper bound | Confirm the proposed reserved 9999-12-31T00:00:00Z sentinel across database, runtime and API; reject real values at/beyond it |
| O19 | First supported TOU and market-clock conventions | Choose product/feed-specific clocks, operating-day boundaries, holiday/DST policies, partial-interval allocation, weighted resolution mappings, rule retention and mixed-clock scope; qualify before automatic TOU or rate schedules |
| O20 | First supported futures valuation and settlement convention | Reconcile execution basis, settled/unsettled variation, remaining value/risk and closeout; decide before futures booking/valuation |
| O21 | Multiple measurement bases for one commodity | Initial schema has one canonical dimension; add explicit volume/energy bases and state-dependent conversion inputs before supporting mixed-basis products |
| O22 | Reference verification, activation and entitlements | Complete source evidence, official series date checks, calendar coverage, scoped content approval and current use/display/distribution grants before real data activation |
| O23 | Reference capture numeric bound compatibility | Initial SQL rejects scale >18, magnitude >=1e24 and nonfinite values without rounding; qualify runtime/API compatibility and needed precision before real imports; this is separate from O01 working arithmetic |

Open choices are not reasons to stop independent implementation work. Choose
reversible details using documented evidence. Ask for product-policy decisions
when the alternatives change the user's intended behavior.

## Recording changes

When a decision changes, record the reason, affected contracts and compatibility
impact here. Update the architecture and plan to describe the resulting design.
Preserve the meaning of already-retained calculation artifacts; a new model or
numerical policy does not silently reinterpret an old result.
