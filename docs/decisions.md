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
| D04 | Preserve the independent side architecture | Positions book instruments; instruments have reusable sides through explicit memberships |
| D05 | AI is a first-class application user | Core workflows have discoverable typed operations, not only browser controls |
| D06 | LLM-agnostic boundaries | Provider-specific types stay outside domain/calculation contracts |
| D07 | Deterministic business execution | Models propose; application policy and versioned calculations execute |
| D08 | Robust administration belongs in the foundation | Principals, delegation, policy, current permissions and audit are core requirements |
| D09 | Shock shared primitive factors | All affected computations consume the same immutable scenario |
| D10 | Black-box pricers | Risk does not require knowledge of a model's internal algorithm |
| D11 | Reuse eligible unit results and factor out quantity | Quantity scalability is explicit and independent of market nonlinearity |
| D12 | Declare curve dependencies | Derived gas/power/location values rebuild from approved recipes |
| D13 | Typed values and controlled precision | Money, price, quantity, units, rounding and numerical policy are distinct contracts |
| D14 | Linear products are the initial product scope | Extensibility does not require implementing options/optimization immediately |

## Proposed implementation choices

These are working proposals, not additional user requirements. Resolve them
through the evidence and acceptance criteria in the plan.

| ID | Proposal | Rationale / validation |
| --- | --- | --- |
| P01 | Modular monolith; browser/application/database tiers | Two server components initially; split processes only when measured needs justify it |
| P02 | TypeScript client and managed application service | Familiar public tooling; keep numerical contracts independent of the host |
| P03 | Relational recipe/edge tables and compiled dependency DAG | Shared computation without a graph database |
| P04 | Finite differences and full repricing as the generic risk path | Supports black-box pricers; analytic paths are optional validated accelerators |
| P05 | Within-run reuse first | Demonstrate identity and dependency completeness before cross-run caches |
| P06 | Application revisions as the first knowledge coordinate | Avoid unsupported claims about permanent physical commit timestamps |
| P07 | Trusted typed operators before general scripting | Bounded extension surface with explicit dependencies and versions |
| P08 | One authorized operation catalog for UI, API and MCP | Prevent business-rule and permission drift across clients |

## Clarifications that must survive implementation

- Applying one shock is separate from sharing one valuation. Different contracts
  consume the same shocked market even when they need different computations.
- Do not shock individual positions. Shock factors, rebuild dependencies and run
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

## Choices to resolve before the relevant implementation

| ID | Choice | Required evidence / decision point |
| --- | --- | --- |
| O01 | Working decimal representation, precision and overflow limits | Multiplication/division, units, cancellation and deterministic parallel reduction; representative benchmarks; decide in core milestone |
| O02 | Initial quantity bases and normalized schedule rules | Common quantity/output basis, versioned per-side transformations, total versus rate quantities, one sign convention and payment timing; decide before bookings |
| O03 | Primitive factor schema, quote units and alias rolls | Dated gas and power examples with pillar mappings and no double shocks; decide in scenario milestone |
| O04 | First identity integration and bootstrap flow | Human/agent lifecycle, delegation expiry/revocation/redelegation, MFA/federation integration and credential custody; decide before an exposed application |
| O05 | Company/workspace/book/portfolio scope relationships | Effective capability matrix, delegation and administrative-elevation examples; decide before persistent business operations |
| O06 | Approval thresholds and separation-of-duties defaults | Action classes, exact payloads, authority revalidation and atomic consumption; decide before enabling policy-controlled writes |
| O07 | Wall-clock knowledge-cutoff semantics | Define availability/publication, crashes and time ambiguity; do not expose until specified and tested |
| O08 | Historical engine retention and upgrade compatibility | Replay fixtures across a schema/model upgrade; decide before claiming exact historical replay |
| O09 | Initial model providers and supported capabilities | Common adapter conformance plus task outcomes; product operations remain provider independent |
| O10 | Performance targets and deployment envelope | Reproducible workload and measured cold/warm behavior; agree budgets before performance acceptance |
| O11 | Audit, market-data and conversation retention | Access, redaction, deletion/export obligations and retained replay needs; decide before real data |
| O12 | Advanced P&L explain ordering and cross terms | Reconcile controlled multi-factor movements with full revaluation; later risk milestone |

Open choices are not reasons to stop independent implementation work. Choose
reversible details using documented evidence. Ask for product-policy decisions
when the alternatives change the user's intended behavior.

## Recording changes

When a decision changes, record the reason, affected contracts and compatibility
impact here. Update the architecture and plan to describe the resulting design.
Preserve the meaning of already-retained calculation artifacts; a new model or
numerical policy does not silently reinterpret an old result.
