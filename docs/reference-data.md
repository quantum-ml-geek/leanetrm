# Reference data and futures

Status: approved baseline requirements with an initial schema implementation and
55 disposable-database checks passing. No booking, valuation, activation or historical publication service is
implemented by the schema alone.

## Required foundation

Reference data is a core application module, not a collection of optional seed
files or arbitrary JSON attributes. The initial schema provides these families:

| Family | Definitions and relationships |
| --- | --- |
| Currencies | Currency identity and display minor units; contractual rounding is separate |
| Units | Dimensions, units, commodity-compatible units and explicit multiplicative conversions |
| Commodities | Commodity identity, quantity dimension and permitted units |
| Locations | Typed locations and explicit commodity/location relationships |
| Venues | Exchanges and clearing houses, separately identified |
| Time | Versioned market clocks, calendars and dated business-day overrides |
| Rates | Separate FX, interest, heat-rate and commodity-price index definitions |
| Conventions | Day-count and compounding definitions |
| Futures | Product terms, dated contract series, milestone states and supporting evidence |
| Provenance | Source identity, retrieval metadata, evidence and distribution review status |

Business relationships use foreign keys, including the catalog and exact reference
revision. Codes and names are labels/keys; a string naming an absent currency,
unit, location, commodity, exchange or product is not a valid relationship.
Imports, agents and UI writes face the same database constraints. Referenced rows
cannot be cascade-deleted or silently replaced. Structured extension payloads
cannot replace these core relationships with an entity/attribute/value model.

Dimensional consistency is enforced where it can be expressed relationally:
commodity units match the commodity dimension; conversion endpoints share a
dimension; product lot and quote units belong to their commodity. Constraints
also reject invalid numeric ranges, duplicate identities and incompatible null
combinations. Economic qualification still validates conversion consistency,
calendar coverage, source disagreements and model-supported behavior.

The initial commodity table declares one canonical quantity dimension per
commodity. Volume-versus-energy measurement bases for the same commodity require
a later explicit measurement-basis model and state-dependent conversion inputs;
they must not be modeled as an unconditional unit conversion. This baseline
restriction must be resolved before those mixed-basis products are enabled.

## Reference revisions and history

The first storage contract is an immutable reference-revision bundle inside a
catalog. Every row and foreign key carries the same catalog/revision. Creating a
new revision retains the old one; it does not update rows used by existing runs.
This favors straightforward, coherent reference snapshots over independent
latest-row selection. Reference volume and snapshot-copy costs must be measured
before introducing finer-grained storage/reuse.

Draft revisions accept inserts. Definitions are append-only; corrections use a
new revision. Sealing stops further inserts and retains a complete bundle. A seal
is a storage freeze, not approval, activation, entitlement or historical knowledge
publication. Reference revision IDs will be included in resolved context manifests.

The schema's creation/retrieval timestamps are audit/source metadata. They are
not `known_from` and do not implement the unresolved knowledge-publication
protocol in [context.md](context.md). Business-effective selection and retained
publication intervals must be implemented before historical date selectors or
approved definitions can be exposed. No current/latest fallback is permitted.

Catalog namespaces are not an implemented authorization boundary. Workspace
ownership, current access, approval evidence, licensing grants and secure import,
export and activation operations remain application/persistence milestones.

## Futures are baseline products

The initial trading slice must include futures as well as fixed/floating linear
contracts. Keep three levels distinct:

1. A product definition specifies venue, commodity/location, quote currency and
   unit, quote multiplier, lot unit/basis, tick conventions and settlement method.
2. A dated series identifies an actual delivery period under one exact product
   revision. A prompt alias resolves to this dated identity for every run.
3. A Trade owns the signed contract quantity, execution/basis and lifecycle facts.
   The reusable product/series never acquires a trade's settlement state.

An immutable Instrument delegates economics and schedule behavior to its sides.
Future lifecycle settlement events update the Trade's outstanding/realized state.
The scenario mechanism still shocks dated market factors and reprices affected
instruments; it does not mutate contracts or Trade quantities.

Capture product terms with explicit units and quote scaling. One contract is not
one physical unit. A price quoted in a currency subunit needs its quote multiplier;
a per-hour lot is not a fixed total MWh lot. Tick values depend on those terms and
the dated delivery shape. Multi-tier/strategy tick rules require explicit future
support; one outright tick does not claim complete venue rule coverage.

Capture first trading, last trading, notice dates, delivery dates and final
settlement separately. Product introduction, series listing and a daily session
opening are different events. A delivery month alone does not determine every
deadline. Store native business dates and applicable clock rules, plus resolved
UTC instants when known. A date-only deadline is not an invented midnight instant.

Every milestone explicitly distinguishes unknown, known and not applicable.
Unknown first-notice data is not the same as a cash-settled contract having no
notice obligation. Date rules, holiday calendars and official series-specific
overrides are retained independently of calculated dates. Missing dates cannot
be replaced with plausible defaults or zeros.

## Accuracy and maintenance

Accuracy is a controlled process, not a permanent claim about a static seed file:

1. Import an entitled source or an authorized manual entry into a new draft.
2. Retain source identity, exact source version/evidence and retrieval metadata.
3. Check dimensions, lot/quote conversion, tick economics and calendar coverage.
4. Compare calculated series dates with authoritative published series dates and
   dated rule changes; record conflicts rather than silently choosing one.
5. Require current scoped approval of exact definition content and usage rights.
6. Freeze and publish a qualified revision through the context protocol; retain
   prior versions, exceptions and verification evidence.
7. Monitor rule/holiday/listing changes and requalify affected future series.

A source being authoritative does not grant redistribution rights. A schema
validation pass, source status label or storage seal does not establish either
economic accuracy or permission to use/distribute that data.

## Public placeholders and installation data

Ship generic schemas, empty placeholders and clearly synthetic fixtures in the
public project. Do not ship real venue catalogs, copied rulebook prose, source
documents, settlement histories or privately licensed reference datasets.
Real definitions belong in installation-specific data loaded under appropriate
permissions. The project's code license does not license third-party data.

Placeholders have an explicit state and missing values; they are never executable
contract definitions. The initial schema intentionally has no active/approved
state. Candidate and synthetic labels are not authorization to book or price.
Activation must validate the complete product, series, clocks/calendars and every
required reference under current authority and applicable data-use permission.

Renaming or omitting the source's name does not establish reuse rights. A hosted
installation also needs its own use/display/distribution review; keeping data out
of source control alone does not resolve hosted-data rights. Source metadata is
not an enforcement mechanism. No redistribution operation is implemented yet.

## Futures valuation and settlement gate

Do not implement a futures holding as an ordinary uncollateralized forward held
unchanged from execution until expiry. Preserve execution economics, last-settled
basis, realized variation margin, unsettled variation and remaining exposure.
The sum must reconcile without counting the same price movement twice.

After settlement, remaining exposure can be nonzero even when the contract's
post-settlement value is zero. Ordinary risk freezes actual historical settlement
facts and shocks only still-variable inputs. Initial model policy must define
which amounts PV includes, cash timing, discounting and any price-alignment or
collateral assumptions. Initial margin is distinct from variation margin.

First enable a documented synthetic fixed-lot convention. Before a real product
is supported, qualify its daily/final settlement, closeout and any delivery/notice
rules. Physically deliverable products require an explicit supported path or an
enforced pre-delivery closeout policy; cash-settled tests do not prove physical
delivery support.

## Verification and remaining work

The migration tests must use a freshly created disposable database and verify
constraints with actual writes: orphan references, cross-revision/catalog links,
dimension mismatches, duplicate keys, invalid numbers, placeholder missingness,
referenced deletions and writes after sealing. Test freeze/write races too.

These storage checks do not qualify the economic model or the temporal resolver.
Further acceptance covers holiday exceptions, date-only versus instant deadlines,
unit/tick economics, pending verification, conflicting sources, expired permissions,
history replay and futures P&L/settlement reconciliation.
