# Power contract forms and operating conventions

Status: local proposal, 2026-11-15. This supplements the
[structured power product design](structured-power-products.md). It identifies
industry distinctions to preserve in future executable contracts; it adds no
implementation, dependency, market rule or default policy.

Industry terminology describes commercial rights, not a universal calculation.
Select the actual agreement and market conventions first, then compose the
existing independent Side model. The public sources below support the product
and market distinctions; the capture, workflow and acceptance requirements are
proposed OpenETRM design choices.

## Commercial forms

**Solar:** distinguish physical delivery from a financial PPA, and independently
distinguish pay-as-produced volume from a fixed or shaped delivery profile. A
financial PPA can settle a price difference while physical electricity supply
and balancing remain separate arrangements. REC ownership is an additional
contract term. These dimensions should remain separate entry choices.
[EPA financial PPA description](https://www.epa.gov/green-power-markets/financial-ppa),
[European Commission PPA guidance, recital 9](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32026H0917).

**Thermal generation:** a toll commonly exchanges periodic capacity payments for
specified output/dispatch rights, with the toller supplying or paying for fuel
and additional variable payments as agreed. The plant operator's physical
responsibilities remain distinct from the toller's commercial dispatch right.
Capture the actual responsibility allocation rather than deriving it from the
word toll. [Federal Reserve energy-tolling description, section 3920.0.4.4](https://www.federalreserve.gov/publications/files/bhc-3900-3980.pdf).

**Battery storage:** a storage toll can give the buyer charging/discharging rights
while the project owner receives access/capacity and operating payments. Full
and partial rights are different contracts. Selecting a storage PPA, toll,
capacity-only service or revenue-sharing arrangement does not establish the same
energy ownership or dispatch control.
[Public energy-storage program recommendations, tolling discussion](https://www.maine.gov/energy/sites/maine.gov.energy/files/inline-files/GEO%20Energy%20Storage%20Program%20Recommendations_Feb%2026.2024.pdf).

The proposed entry classification is:

| Selected commercial form | Explicit contractual basis | Consequence for the Side composition |
| --- | --- | --- |
| Physical solar PPA | Generated, allocated or fixed-profile energy delivered at an agreed point | Delivery and payment schedules; firming/replacement obligations only where contracted |
| Financial solar PPA / contract for differences | Defined price difference and specified volume source/profile | Cash payment schedules; generation may be a quantity input without electricity delivery to that counterparty |
| Solar output-right agreement | Identified available-output entitlement and actual control/marketing rights | Output and access-payment schedules, plus any granted environmental rights; no invented fuel obligation |
| Physical thermal toll | Defined conversion/dispatch right, fuel and output responsibilities | Linked fuel/output, availability and variable/start-payment schedules |
| Storage toll / storage service agreement | Defined access window, power/energy envelope, energy ownership and operating rights | Charge/custody, discharge and payment schedules supported by one state trajectory |
| Financial toll or revenue-based contract | Explicit reference prices, quantities, dispatch benchmark and payment formula | Cash schedules tied to that benchmark; no inferred physical dispatch authority |
| Capacity or resource-adequacy sale | Exact eligible product, accredited quantity, delivery/performance period and obligation | Capacity/performance schedules distinct from energy sales and resource-access fees |
| Bundled or unbundled REC sale | Exact eligibility, generation vintage, quantity and delivery/retirement obligation | Certificate and payment schedules with separate inventory evidence |

An ordinary solar PPA remains a PPA in the product catalog. The internal
resource-right composition can support a solar toll where the agreement grants
those rights. Neither an availability fee nor a technology label alone proves
that it does. Market language and legal classification can vary; a UI label
must not silently supply missing terms.

## Agreement and confirmation capture

Keep Trade → Instrument → Side → retained whole-term SideSchedule. Each proposed
contract version should expose and retain the applicable terms below through the
same managed entry, preview, booking and amendment operations:

| Term group | Required distinctions |
| --- | --- |
| Agreement identity and scope | Legal agreement/confirmation reference and authorized version, parties, economic perspective, resource/right, effective term, commercial-operation/delivery commencement and any conditions precedent |
| Allocated products | Energy, capacity/resource adequacy, ancillary services and environmental attributes; who owns, markets and settles each, including an explicit retained/excluded choice |
| Delivery and quantity | Point of delivery and meter boundary, generated versus net export, MW versus MWh, produced percentage/quantity basis or fixed profile, clocks, losses and allocation rules |
| Control and notices | Operator, scheduling/dispatch party, permissible instructions, notice/response windows, accepted commitments, curtailment authority and balancing responsibility |
| Pricing and cash | Fixed/indexed/contingent terms, exact contractual index, observation/finality rules, fee quantity/time basis, payment dates, contractual netting and rounding |
| Performance | Availability definition and measurement window, exclusions, planned/forced outages, tests, heat-rate or storage-capacity/efficiency guarantees, degradation/augmentation responsibility and admitted remedies |
| Environmental delivery | REC entitlement and eligibility, generation vintage, compliance/use period where applicable, custody/transfer, substitution and retirement purpose/beneficiary |

Broader legal-document management, contingent commencement, test protocols,
general remedies and credit/collateral workflows remain separate consumers. A
bounded version can require a known commencement date and explicitly absent
unsupported contingencies. It cannot accept an agreement containing them and
discard their economics. No broad agreement or fee table is justified until an
executable consumer needs its exact relationships.

For thermal tolls, retain contract-guaranteed fuel owed separately from actual
fuel consumed and identify who bears differences. For storage, specify whether
efficiency, auxiliary consumption, usable capacity and cycle limits are measured
at the AC interconnection, equipment terminals or another declared boundary.
An augmentation promise does not automatically restore modeled capacity; its
implementation and evidence must be explicit. Availability and performance
payments use their own agreed basis, not a universal proportional haircut.

For thermal operation, distinguish **unit commitment** (whether and when the
unit starts, stays online or shuts down) from **economic dispatch** (its output
within those commitments and limits). The familiar **spark spread** compares
electricity price with gas cost at a selected heat rate. It is a gross margin
diagnostic; it does not include every operating cost or establish the value of
a dispatch right. The heat rate and delivery mapping must be the selected
contract/model inputs, never an imported industry benchmark.
[Unit-commitment and dispatch modeling research](https://www.nrel.gov/docs/fy14osti/60623.pdf),
[EIA spark-spread explanation](https://www.eia.gov/TodayinEnergy/detail.php?id=9911).

## Contractual schedules and operational records

The SideSchedule defines the contractual instructions and possible occurrences
for the whole term. Operational scheduling records select planned and accepted
quantities under those instructions; they do not replace the retained schedule.
Keep these proposed record roles distinct:

| Record role | Meaning and calculation use |
| --- | --- |
| Forecast | Expected production, prices or physical availability under a stated information cutoff; no evidence of an accepted instruction or delivered energy |
| Submitted schedule/nomination | A proposed market/operator instruction with its issue time, effective delivery, exact quantity and request identity |
| Award/accepted instruction | The committed market/operator outcome, linked to the submitted version where applicable; an operator-origin instruction instead retains its own exact source identity and authority/rule. Authorized changes preserve that lineage and constrain remaining choices |
| Telemetry/meter | Observed power, energy, fuel or state with boundary, quality, effective interval and publication/revision evidence |
| Contractual adjustment | Deemed energy, losses, authorized curtailment compensation or other admitted adjustment; separately derived from retained evidence |
| Settlement assessment | Expected charge/credit under a selected rule and price/meter revision; distinct from an accepted payable/receivable |
| Statement/acceptance/payment | External statement evidence, the application's accepted cash state and actual payment/reconciliation, each with its own lineage |

Deemed generation can affect a contractual payment without rewriting physical
meter data. It also does not automatically qualify as issued REC generation.
Outages and forecast revisions expose changed feasibility and any required
resubmission; they do not erase earlier accepted instructions or delivery duties.
Unknown telemetry quality and a missing initial physical state cannot become a
successful assumption that the resource is fully available.

The same resource/plan calculation supplies coupled quantities to every affected
Side. Each Side retains its own roots, prices and payment dates; the instrument
aggregates their contributions. Shared physical limits need one feasible plan
even where different counterparties hold different rights. External submission,
market-resource registration and acknowledgement protocols are later executable
boundaries, not capabilities established by recording these fields.

## Energy, capacity and services

Retain four distinct quantities: resource nameplate power, available operating
power/energy, accredited capacity for a selected product/period and contracted
entitlement. A toll capacity fee is a resource-access payment; it does not by
itself create accredited capacity or sell a market capacity product.

Energy, reserve/regulation and capacity rights can interact. A storage service
needs the required duration, headroom/footroom, state of charge and activation
rules. Reserved MW is not delivered MWh; deployment can create additional energy
and state transitions. Solar plus storage also consumes shared import/export
limits and charging-origin evidence. These are concrete joint-feasibility needs:
CAISO documents state-of-charge and shared-interconnection constraints in its
[October 2026 battery report](https://www.caiso.com/documents/2025-special-report-on-battery-storage-oct-28-2026.pdf).

Do not transplant one market's resource categories, accreditation percentages,
reserve duration or settlement intervals into another market. Each supported
market/product rule needs its own retained version and numerical/operational
cases. The initial energy-only toll must expressly state which other products
are retained by the owner or excluded; it cannot show their revenue as available.

## Settlement and corrections

Maintain separate contractual settlement and wholesale-market settlement.
A PPA can price delivered energy against one contract index while a scheduling
party's market position has separate day-ahead and real-time outcomes. A meter,
an index publication, an operator statement and an accepted cash determination
are distinct evidence.

For example, ISO New England describes real-time settlement of metered deviations
from day-ahead obligations, with preliminary prices permitted in certain initial
settlements and final-price reconciliation afterward. This is evidence for an
explicit provisional/reconciled lifecycle, not permission to substitute any
missing final in the existing contracts.
[ISO New England real-time energy settlement](https://www.iso-ne.com/markets-operations/settlements/understand-bill/item-descriptions/rt-energy).

The proposed workflow is: resolve eligible evidence; calculate gross occurrence
amounts and agreed netting; reconcile external statements; accept supported cash
determinations; record payments; reconcile eligible corrections. An initial-price
rule, finality criteria, revision selection, correction amount and due-date policy
must be explicit. Where preliminary inputs are supported, their status remains
visible through assessments and accepted cash. Existing final-only fixing
contracts retain their meaning until a separately qualified version is selected.
Meter, price and fee corrections retain the original assessments/acceptances;
the replacement/correction operation cannot count both a new total and the old
total as additional cash.

REC settlement independently checks certificate eligibility and actual transfer
or retirement. Energy delivery or cash payment alone does not establish a
renewable-use claim. Contracts must allocate the attributes explicitly and avoid
double claims. Track delivery to an owner separately from qualifying retirement
for a named beneficiary/purpose. Generation vintage, retirement date and an
applicable compliance/use period remain distinct; one is not inferred from
another. Voluntary and compliance eligibility require their selected rules.
[EPA double-counting guidance](https://www.epa.gov/green-power-markets/double-counting).

## Additional acceptance cases

These are proposed independent cases, not implemented tests. Quantities are
synthetic; arithmetic examples explicitly omit discounting and other charges.

| Case | Required result |
| --- | --- |
| Product selection | A solar physical PPA, a financial PPA and an output-right agreement retain different delivery/control terms even if all reference the same asset and price |
| Firm profile | A contract requiring 10 MWh with only 8 eligible generated MWh exposes 2 MWh of replacement obligation; it does not invent generation or an executed replacement purchase |
| Deemed generation | Under an explicit example rule, 8 metered MWh plus 2 deemed MWh produce 10 payment MWh but only 8 physical MWh; an actual-generation-only REC rule admits only those 8 MWh |
| Guaranteed versus actual fuel | At 4 MWh output, explicit guaranteed heat rate 7 and actual heat rate 7.5 MMBtu/MWh yield 28 contractual and 30 actual MMBtu, with zero startup/no-load additions in this case; the 2 MMBtu difference follows the selected responsibility rule |
| Product separation | An access fee based on 50 MW does not override a retained accreditation of 35 MW or reserve that capacity for a second buyer; an unactivated reserve award creates no delivered-energy actual |
| Initial and final prices | For a producer under an explicitly admitted two-settlement rule: 10 DA MWh at 40 plus an actual deviation of −2 MWh at preliminary RT price 70 gives 260; a final RT price of 80 gives 240 and a correction of −20. Retain both knowledge states and exactly one correction effect |
| Availability payment | Different explicit availability/remedy conventions can produce different payments from the same outage evidence; entry refuses an absent convention |
| Rights and external actions | Capturing a financial toll provides no dispatch authority; a submitted plan is not an accepted award; operator-origin dispatch retains its own evidence without an invented submission; repeated delivery of one acknowledgement has one effect |

Implement these controls with each named product slice in the main delivery
sequence. Exact market integrations, arbitrary contingencies, revenue sharing,
performance remedies, ancillary services, provisional cash acceptance and credit
support remain unsupported until their own consumers and independent checks
exist. The common Side architecture is retained throughout; familiar product
labels alone do not establish those capabilities.
