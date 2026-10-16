# Delivery plan and acceptance criteria

Status: design baseline reviewed on 2026-10-16. Milestone 0 is complete; no
application implementation milestones below are complete.

This plan separates the first runnable foundation from later product breadth.
Each milestone produces a reviewable working result with tests and documented
limits. It is not a promise to deliver all future capabilities in one commit.

Read [the architecture](architecture.md) and [decision record](decisions.md) for
the contracts these milestones must preserve.

## Milestone 0 — Record and review the design

Deliver:

- Domain vocabulary, side ownership and definition/version boundaries.
- Shared factor scenarios, black-box pricers and quantity-scaling contracts.
- Curve dependencies, units, precision and historical input semantics.
- Administration, delegation, provider boundaries and durable execution rules.
- Public-content instructions, proposed choices and open decisions.

Acceptance:

- Independent adversarial review covers numerical reuse, authorization, temporal
  semantics, execution failures and public release boundaries.
- Review findings are resolved or explicitly recorded as unresolved decisions.
- Documentation clearly distinguishes requirements, proposals and implementation.
- Links and the complete outgoing diff are checked before publication.

## Milestone 1 — Build and prove the deterministic core

Build an independent core library with no database, network or model-provider
dependency. Pin the supported runtime/toolchain and dependencies.

Deliver:

- Typed monetary amounts, prices, quantities, units and coefficients.
- A documented bounded numerical policy, canonical decimal input/output,
  conversion rules, overflow/error behavior and explicit rounding boundaries.
- Independent versioned side definitions, memberships, instruments and positions.
- A minimal explicit dated schedule/normalized-shape contract; automatic calendar
  breadth is not required to prove the core.
- Fixed/floating linear valuation against an explicit immutable market context.
- Quantity-scaling declarations and structured errors for unsupported behavior.
- Versioned inspect/compose/preview/scenario request and response schemas, written
  for both human and agent clients from the beginning.

Initial pricing conventions:

- Explicit dated buckets and a declared total-quantity basis are the smallest
  supported shape. Rate/per-occurrence quantities are enabled only with their
  own normalization and time-integration tests.
- Start with single-currency cashflows and aggregation. Unsupported FX or
  cross-currency configurations return a structured error.
- Future observations use explicitly bound forward inputs; observations already
  fixed under the contract's schedule require the appropriate available realized
  fixing. A missing fixing never silently falls back to a forward quote.
- Undiscounted valuation is an explicit named mode. Discounted valuation requires
  pinned discount inputs for the payment dates; it cannot silently use one when
  those inputs are absent.
- Explicit versioned transformations normalize each side to the common position
  quantity basis. Pay/receive labels do not add a sign beyond the signed
  membership coefficient and position quantity.
- Reject unsupported pricing/lifecycle conventions until their semantics and
  tests exist; a linear product label is not evidence of complete coverage.

Acceptance:

1. Construct a fixed/floating instrument from two independent sides.
2. Reuse one side across multiple instruments without sharing membership weights
   or position quantities.
3. Preserve correct units through price-times-quantity and heat-rate conversion.
4. Reject incompatible currencies/units, unsupported precision, overflow and
   missing inputs.
5. Prove positive, negative and zero quantity behavior and signed coefficients.
6. Prove normalized shapes share calculations only when the required inputs agree.
7. Prove settlement/aggregation rounding follows the declared contract.
8. Prove repeated evaluation of the same input manifest gives the same outputs.
9. Verify aggregation is identical across input enumeration, worker counts and
   execution scheduling under the documented reduction policy.
10. Test future forwards, realized fixings, missing fixings, explicit discount
    modes, incompatible quantity bases and unsupported currency configurations.

Independent review focuses on numeric policy, identity and false quantity reuse.

## Milestone 2 — Shared scenarios and dependency propagation

Deliver:

- Dated primitive factor identities and explicit prompt-alias resolution.
- Typed, versioned curve recipes and a validated compiled dependency plan.
- Synthetic gas base/basis and power conversion/location examples.
- Base/up/down factor overlays over an immutable market snapshot.
- A black-box unit-pricer contract with declared dependencies.
- Repricing, delta/gamma and scenario P&L with explicit units and bump conventions.
- Within-run reuse and instrumentation of actual evaluated work.

Acceptance:

1. Apply an absolute base-gas shock once in each scenario.
2. Propagate through location gas, heat-rate-derived power and location power.
3. Reprice different dependent contracts against that same scenario; do not
   mutate or separately shock positions.
4. Verify the synthetic 0.10 USD/MMBtu, 7 MMBtu/MWh and 10,000 MWh case produces
   7,000 USD undiscounted scenario P&L under the stated fixed inputs.
5. Verify direct gas/basis and inherited power exposures use the right units.
6. Leave an unrelated factor's dependent computations unchanged and unexecuted
   where independence is proven.
7. Demonstrate a shared derived node is evaluated once per scenario.
8. Demonstrate eligible unit calculations are reused across quantities, while
   different shapes/terms have distinct valuation identities.
9. Compare reuse results with a slow independent full-portfolio repricing path.
10. Verify quote-input shocks and direct output-curve shocks are distinct requests.
11. Reject cycles, incomplete mappings and missing data; never return default zero.
12. Use a synthetic nonlinear black-box test pricer to prove scenario machinery
    does not assume market linearity. This test is not an option-product release.
13. Retain actual dated contracts so a prompt roll creates a new context and does
    not change a previously retained run.
14. Reject zero/invalid bumps, incompatible shock units, unsupported percentage
    conventions and insufficient numerical resolution with structured errors.

Independent review focuses on shock propagation, units, finite-difference
cancellation, cache identity and missing dependencies.

## Milestone 3 — Persist operations with administration and history

Deliver:

- Reproducible stock-database setup and versioned additive migrations.
- Separate administrative/migration and unprivileged runtime connections.
- Principal lifecycle, agent/service identities and a scoped capability matrix.
- Explicit provisioning with no published default credentials.
- Versioned domain records, application revisions and immutable input manifests.
- Typed read, compose, preview, book, amend, calculate and request-status operations.
- Atomic idempotency records and append-only application audit.
- Current-authorization checks across historical reads, results and exports.

Acceptance:

1. Provision a new isolated installation using only documented public artifacts.
2. Book an instrument/position atomically through an authorized operation.
3. Resolve a duplicate request to its original outcome; reject a reused request
   identity with a different payload.
4. Recover after an uncertain response without creating another booking.
5. Reject stale expected versions and preserve earlier revisions after amendments.
6. Verify backdated changes do not rewrite an earlier input manifest or result.
7. Verify users/agents cannot cross workspace/book/portfolio scope or inspect
   hidden definitions through searches, errors, counts, caches or exports.
8. Complete a revoke and verify subsequent operations and cached/historical reads
   are denied; cover revoke/restore and pooled connection reuse.
9. Verify runtime database credentials cannot bypass the intended data boundary.
10. Verify administrative capability does not silently imply business-data access.
11. Verify approvals, where configured, bind the exact scope/payload/version and
    cannot be reused after their meaning changes. Atomically consume single-use
    approvals; test concurrent requests with different identities and an expired,
    disabled or no-longer-authorized approver.
12. Restart the service and retain bookings, audit, request outcomes and run inputs.
13. Test delegated scope intersection, expiry, revocation and disallowed
    redelegation, including attempts to inspect another principal's request status.

Historical reads initially select application revisions. Do not implement a
wall-clock historical selector by pretending pre-commit row timestamps are
permanent commit records.

Independent review covers authorization, temporal behavior, transaction races,
idempotency and migration/release boundaries.

## Milestone 4 — Durable runs and a usable browser slice

Deliver:

- Durable run states, worker ownership/fencing, bounded concurrency and restart
  recovery over pinned inputs.
- Progress, diagnostics, cooperative cancellation and request reconciliation.
- Browser flows for identity, scoped reference selection, side/instrument
  composition, positions, market recipes, risk results and administration.
- Calculation receipts with explainable dependency paths and input provenance.

Acceptance:

1. Complete the first synthetic trading/risk workflow through the browser.
2. Show base/up/down values, risk units and the path from factor to position.
3. Show where unit computations were reused and how quantity was applied.
4. Show errors and partial runs explicitly; do not present incomplete portfolio
   totals as successful complete risk.
5. Interrupt a worker and resume/reconcile without duplicate committed results.
6. Reject publication from a worker that has lost its execution fence.
7. Verify cancellation-requested and cancelled are distinct, truthful states.
   Race cancellation against successful publication in both orders and assert one
   terminal result; stale workers cannot overwrite the outcome.
8. Revoke access during queued/running work and verify it cannot publish or return
   results under revoked authority. Include revoke/restore and a revoke committing
   between an earlier permission check and the attempted publication commit.
9. Verify a schema/model upgrade does not rewrite old receipts or claim replay
   using a different engine. Report unsupported replay honestly.

Independent review covers asynchronous behavior, result publication, current
authorization and retained-version boundaries.

## Milestone 5 — AI-operated application

Design the operation schemas from milestone 3 for agent use; this milestone adds
the model runtime and client adapters rather than a separate business-rule path.

Deliver:

- A discoverable versioned operation catalog with typed inputs/outputs, required
  authority, bounds, temporal context and idempotency behavior.
- API and MCP adapters invoking the same operations as the UI.
- A provider-neutral adapter and capability contract, with at least two adapters
  or an explicitly supported external-agent route plus adapter conformance tests.
- Scoped agent identities, delegation, allowed provider/model routing, protected
  credentials, resource budgets and auditable task progress.
- Exact-payload proposals/approvals and structured validation failures.

Acceptance:

1. An agent discovers permitted operations and available reference definitions.
2. It composes a linear instrument from reusable sides, previews the cashflows,
   resolves missing/ambiguous terms and proposes a booking.
3. It obtains approval only where policy requires it and books exactly once.
4. It shocks a shared factor, runs risk and explains position changes from
   retained calculation evidence.
5. It answers why an unrelated position did not move without inventing inputs.
6. A second provider/agent route completes the same deterministic business task;
   compare state/results, not wording.
7. Denied permissions, stale proposals, malformed tool arguments, provider errors
   and step/budget exhaustion produce controlled outcomes.
8. Untrusted text cannot grant authority, approve a mutation, access secrets or
   redirect data to a disallowed provider.
9. Disconnect after a booking response is lost and reconcile the committed
   request outcome before attempting another mutation.
10. The browser and direct API remain usable without a configured model provider.

Independent review covers delegated authority, data routing, approvals, tool
discovery and provider-failure/retry boundaries.

## Milestone 6 — Performance qualification and public baseline

The baseline release combines milestones 1–5. Record actual capability and limits;
do not imply this is a complete ETRM or production-qualified deployment.

Publish a reproducible benchmark matrix with synthetic workloads:

| Axis | Required cases |
| --- | --- |
| Positions and unique unit definitions | Many copies of a few contracts; many distinct contracts; mixed books |
| Dependency topology | Chains, fan-out, shared children and unaffected branches |
| Scenario breadth | Single-factor up/down, multiple factors and parallel runs |
| Shape | Single period, multiple periods and distinct hourly profiles |
| Cache state | Cold plan/data; within-run reuse; any separately validated warm cache |
| Operations | Calculation, aggregation, persisted receipt and authorized result retrieval |

Record environment, versions, latency distribution, memory, throughput, database
reads and actual curve/pricer execution counts. Agree measurable budgets after
collecting the first representative results. Measure core CPU work separately
from database, serialization and end-to-end latency.

Acceptance:

- Results match the independent full-repricing reference for the supported domain.
- More copies of an eligible unit contract do not cause more unit-pricer calls;
  position scaling/aggregation costs remain visible.
- A single-factor shock executes affected dependencies rather than every curve.
- Resource bounds hold under concurrent requests and cancellation.
- Required tests, independent reviews and public-content checks pass.
- A fresh checkout builds and runs with public dependencies and synthetic data.
- Operator instructions cover initialization, upgrade, backup/restore, credential
  lifecycle and recovery for the actual implemented feature set.

## Later scope

Extend only after the baseline contracts are demonstrated:

- Broader calendars, delivery shapes and schedule authoring.
- Options and exercise rules, volatility inputs and nonlinear model diagnostics.
- Storage/dispatch optimization and capacity-dependent position behavior.
- Advanced fees, quantity tiers and any justified scripting sandbox.
- Multi-factor P&L explain, cross sensitivities and residual attribution.
- Calibration, simulation, validated analytic/automatic differentiation paths.
- Safe cross-run result reuse and incremental market updates.
- Live feed adapters and their entitlement/provenance controls.
- Settlement workflows, richer administration and deployment hardening.

An item in later scope must not be advertised as implemented because an interface
could accommodate it.

## Working and publication discipline

Work in small coherent commits with targeted tests and updated documentation.
The repository already has its own initial commit and a license change; do not
rewrite those commits or import private history to create a cosmetic single
commit. Implementation commits describe only this public project.

Before publishing, inspect all staged files and generated artifacts, dependency
sources/attribution, operational references, credentials, company/customer and
competing product names, commit metadata and the actual diff against the public
branch. Required technical identifiers and license notices stay accurate.

Tests use newly allocated disposable resources and neutral synthetic fixtures.
No existing application, shared test workspace or production system is a test
target. Document what was run and what remains unverified.

Architecture notes are living contracts. Update them when implementation evidence
changes a proposal, and retain the compatibility consequences of the decision.
