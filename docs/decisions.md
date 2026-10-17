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
| D31 | Never assume intent or silently use defaults | Financial modes/policies and applied context choices are explicit; missing, ambiguous or conflicting behavior raises a structured error |
| D32 | All-in marks and spread-dependent prices have distinct declared semantics | No inferred base dependency or implied spread; incompatible mark types cannot silently change a recipe |
| D33 | Determine risk through deterministic shocked PV results | Rebuild declared dependencies and evaluate base/up/down PV; no allocation from spread size, price proportions or inferred relationships |
| D34 | Dated market contracts own identifiable histories; curves are cross-sections | Stable factor histories support explicit aligned samples; rolling references retain dated constituents and their versioned selection rule |
| D35 | Curves own common specifications; dated contracts own their specific terms | Commodity, yield and composite/algorithmic curves use typed compatible constituents; detailed storage records need not be public business objects |
| D36 | Compose curves through explicit versioned source bindings at every depth | Basis/base orientation, operations, parameters and delivery mappings are declared; forwards may consume futures; reject cycles |
| D37 | Separate curve construction from settlement targets | Consuming a futures input does not transfer its cash lifecycle to a forward; each index/formula, fixing and payment convention remains explicit |
| D38 | Source expiry requires an explicit transition rule | Freeze eligible final facts, use a specified transition or end eligibility; no implicit roll, current-price substitution or historical rewrite |
| D39 | Establish units/money and current authorization with the market foundation | Typed quantities/prices/currency amounts and explicit cash rounding; permissions must precede exposed operations |
| D40 | Agents have their own principal identities and agent login kind | Verify distinct credential/login binding; delegated actions retain agent actor and delegator identities |
| D41 | Use generic typed series/observations instead of a heat-rate-specific table | Prices and numeric ratios have retained dated observations; constants and dependencies are explicit |
| D42 | Supply common role templates with exact scoped assignments | Viewer, Trader, Risk Analyst, Market Data Editor/Approver and Access Administrator; identities and roles are separate |
| D43 | Keep the next slice bounded | Generic series/curves, exact retained input pins and current database isolation precede APIs; full historical selectors and broader algorithms follow |
| D44 | Organize the user interface around market data and familiar business labels | Browse futures and forward curves by commodity or market type; keep internal identifiers and implementation terminology out of visible screens |
| D45 | Keep time zone and evolving personal customizations in a user profile | Remember presentation preferences separately from financial inputs and authority; account-wide persistence follows verified sign-in |
| D46 | Put a compact date/time context at the top of the application | Display minutes without changing exact retained instants or version identity; distinguish same-time versions and repeated local times without showing GUIDs |
| D47 | Separate business references, market setup and internal storage concepts | Present business definitions separately from versioned pricing/delivery configuration; hide join/version machinery without weakening integrity or permissions |
| D48 | Use typed locations with explicit geography | Reuse the location/type relationship for pipelines, nodes, hubs, regions and delivery points; support supplied GPS points without inventing coordinates, route/area geometry or topology |
| D49 | Require a current consumer or concrete executable baseline case for each table/value/dependency | Retire speculative catalogs safely; keep future breadth in the plan and record actual reference/setup uses |
| D50 | Include a basic interest-rate curve in the synthetic setup | Dated zero-rate samples retain histories and produce discount factors under explicitly selected conventions |
| D51 | Keep units and the used rate conventions project-owned | Avoid a large financial-library dependency for the bounded baseline; qualify new conventions with independent exact-result tests |
| D52 | Explain composite/basis curve prices with a per-contract diagram and calculation table | Use boxes for one contract and connected contract/price tables for all; group identical mappings visually while retaining explicit row exceptions and exact evaluated values under the selected market date |
| D53 | Keep collapsible navigation and ordinary-table filtering as presentation state | Remember layout per user; scope transient table filters to the displayed authorized context, keep exact values and leave connected worksheet mappings complete |
| D54 | Allow explicitly selected daily and monthly contracts in one curve | Retain dated constituent histories and versioned resolution/membership rules; daily-to-monthly base-price projection and source-expiry transitions are explicit, with no inferred daily marks, averaging or automatic roll |
| D55 | Bind BALMO basis to its explicitly quoted benchmark and exact remaining period | A matching BALMO benchmark is distinct from a full-month future's frozen final; a BALMO quote cannot supply daily marks without a qualified shaping rule, and changing the period start creates a different dated contract |
| D56 | Advance the current contract at its selected expiry milestone through its retained sequence | Pin the exact event role/instant; the synthetic futures example uses last trading. The next sequence entry becomes current; farther-end listing is independent. Preserve historical pins and reject missing milestones, eligibility or prices without substitution |
| D57 | Support reusable retained schedules supplied as rows or produced by explicit deterministic definitions | People, code and agents consume the same pinned dates; generators and parameterized schedule references preserve provenance and validation without requiring a general scripting language |
| D58 | Separate named schedule definitions may share identical immutable typed date payloads | Retain each definition's meaning, provenance, coverage and occurrence links; canonical sharing does not merge obligations, historical versions or calculation identities |
| D59 | Assign explicit symbolic shortcuts to reusable named schedules | A shortcut binds a pinned schedule, relative position and date role; sides/instruments and later dashboards/risk use a common resolver. Combine/compare/diff remain coding benefits, not a mandatory calendar UI |
| D60 | Build date schedules before binding dated-contract fields | Standard and typed custom fields retain explicit schedule references and resolved values; preserve occurrence mappings, reject cycles and keep existing series/milestone identities authoritative |
| D61 | Support business-day arithmetic on date-valued references | Expressions such as `oe.ng1 + 1bd` use an explicitly bound versioned calendar/date rule, with no inferred clock/calendar or hidden adjustment; positive/negative movement now counts strictly beyond the base; zero offsets remain unsupported instead of choosing a policy |
| D62 | Design the date foundation around typed immutable data and native operations | A small common sequence contract exposes selection, generation, movement, adjustment and comparison over distinct typed views. Calendars and policies are explicit inputs; each supported operation requires a concrete consumer and independent checks |
| D63 | Use standard business names while distinguishing schedule anchors from business-day adjustments | Proposed `RollConvention` describes unadjusted recurring anchors; `BusinessDayConvention` adjusts a closed date. A calendar can bind an explicit adjustment policy; business-day movement and contract expiry advancement retain separate semantics |
| D64 | Exercise generated dates in private curve contract drafts before publication | A bounded monthly anchor editor supplies indexed references to start/end and last trading. Keep expressions, resolved values, calendar snapshots and exact source pins; existing curve templates are not required; qualification, dependent mappings and durable bitemporal activation remain separate work |
| D65 | Use `oe.name` as canonical exposed date references | Namespace aliases are an optional future authoring convenience; definitions store canonical names. Period fields use start/end, and a single result uses date |
| D66 | Save independent schedules before using them in curve/contract date fields | Draft labels/rules are editable; publication freezes an exact version. Editing published terms creates the next draft. Stable identity, effective intervals, scoped committed publication views and supported engine pins preserve earlier resolution |
| D67 | Establish certified effective/knowledge contexts alongside current RLS | The schedule slice uses retained engine commit timestamps, a closed certification watermark, scoped prefix snapshots and immutable context receipts. Context IDs convey no permissions; historical reads obey current scope and revocation |
| D68 | Fail explicitly when timestamp history cannot be certified | Qualify fresh primary installations with tracking enabled; verify full transaction epoch and timeline before engine lookup, retain certificates, reject finer-than-storage precision and refuse missing history or clock regressions. Other domains and operational migrations remain separately qualified work |
| D69 | Apply one certified market environment across existing business screens | Sealed definition/observation events have a separate commit-certified prefix at the same exact cutoff as schedules. Temporal RLS filters market/reference closure; historical contexts are read-only, explicit correction selection never substitutes sources and main valuation dates must match the context |
| D70 | Scope administration to workspace memberships and current authority | Membership suspension does not globally disable a principal. Private narrow operations, exclusive first admission, exact request identities, expected versions and atomic append-only audit protect account/role changes. Administration does not imply business-data access; preview registration is not production authentication |


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
| P13 | Internally distinguish typed observations, reusable value definitions and curve membership | Storage proposal supports the agreed Curve/MarketContract/MarketObservation domain; exact decomposition remains under review |
| P14 | Select snapshot inputs by explicit requirement and role/use class | First proposed subset permits one coherent variable selection per factor, plus separately pinned frozen facts; reject incompatible views |
| P15 | First implemented exact arithmetic mode uses 18 fractional digits and magnitude below 10^24 | Checked integer arithmetic rejects precision loss/overflow; broader numerical policies remain O01 |
| P16 | First managed security evaluator uses exact scoped role grants and intersected agent delegation | Deny by default; managed current-state inputs and SQL transaction fencing are implemented; verified authentication/API/admin integration remains |
| P17 | Bind trusted database identity through private transaction capabilities | Isolated authenticator/runtime roles; exact session login/PID/transaction binding, no caller-set identity variable |
| P18 | Serialize current security changes against admitted database requests | Coarse epoch fence; actual-current expiry checks after admission waits; qualify throughput before broader use |
| P19 | Implement the used day-count and compounding rules in a small project-owned module | Explicit Actual/365 Fixed, simple compounding and UTC valuation-date basis; exact rational intermediates and named ties-to-even output policy; no external financial-library dependency |
| P20 | Store currently supported rate convention identifiers on the interest specification | Separate day-count/compounding catalogs have no independent consumer; no default or broad catalog import |
| P21 | Compose the mixed-period example from separate daily-only and monthly-only source curves | Use an explicit selection/splice operator retaining original dated identities and lineage; keep named BALMO windows distinct from directly quoted period contracts; see examples/curve-composition-rollover.md |
| P22 | Implement a schedule-backed relative-contract resolver before a broad date language | Reuse dated futures-series/milestone references; agents may maintain validated rows, with a bounded optional generator materializing the same input contract; see schedules-and-contract-sequences.md |
| P23 | Use a small typed, compiled temporal kernel for date sets, ordered occurrences and interval selections | Compose calendars and roll/TOU rules explicitly; measure compact arrays/bitsets and shared immutable payloads before choosing storage/cache breadth or claiming speed |

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
| O24 | Market identity, value types and reference extensions | Review market-model.md; specify commodity measurement bases, quote/cash precision, per-day lots, locations/index components and typed market/static operand FKs before migration |
| O25 | Supported input/history/settlement policy inventory | Qualify role-specific selection, correction identity, variable/frozen inputs, sampling, publication and finality rules; reject unsupported combinations before activation |
| O26 | Remaining-day window and schedule qualification | Expiry-based current-contract advancement is agreed in D56. Choose current delivery month versus month containing next delivery day for daily/BALMO views; qualify clock/package boundaries, sequence coverage, listing eligibility and bounded generator parameters |

Open choices are not reasons to stop independent implementation work. Choose
reversible details using documented evidence. Ask for product-policy decisions
when the alternatives change the user's intended behavior.

## Recording changes

When a decision changes, record the reason, affected contracts and compatibility
impact here. Update the architecture and plan to describe the resulting design.
Preserve the meaning of already-retained calculation artifacts; a new model or
numerical policy does not silently reinterpret an old result.
