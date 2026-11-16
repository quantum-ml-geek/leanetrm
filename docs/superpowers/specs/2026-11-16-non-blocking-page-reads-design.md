# Non-blocking page reads: second round of D404

Status: proposed 2026-11-16. Nothing here is implemented or measured.

## Why

D404 ([async-reads.md](../../async-reads.md)) lets a page submit a named read by
POST and receive its result later on one SSE channel. It covers 26 operations on
Market curves, the main-window Blotter and core Risk. Reading the code after
that change shows the workbench still waits in four places:

| Where | What waits |
| --- | --- |
| Page navigation (`act`, `web/src/app.ts`) | Every page except Market, Blotter and Risk loads inside the global `busy` gate, which disables every control outside `[data-own-controls]` until the first load ends. |
| Ordinary HTTP reads (`Locked`, `Program.cs`) | About 160 routes hold the per-session gate for their whole database run, so one slow read delays every other ordinary request of that session. |
| Coverage | About 180 reads are ordinary HTTP. Lifecycle, Physical operations, Physical power, REC, Facilities, custom curves, P&L and every trade ticket use the channel for nothing. |
| The channel itself | A result is serialized, parsed, cloned and serialized again as a string; it is sent uncompressed; a read in flight when its channel reaches five minutes is rejected. |

`PrepareAsyncRead` writes each read it covers a second time beside its HTTP
handler, sharing only the projection. Extending the channel the same way would
write every remaining read twice.

No timing of any of this exists. D404's qualification is a correctness result
and says so.

## Goals

1. No page disables its controls or the sidebar while a read is pending.
2. No read holds the session gate while it runs its database work.
3. Each read is defined once in the managed backend and served by both
   transports with the same projection, the same exact financial values and
   the same refusals.
4. On every page, the reads that price, value, project or preview arrive on the
   response channel. Small reads stay ordinary HTTP and stop blocking.
5. The channel sends each result's bytes once, compressed, and does not fail a
   read because the channel aged.
6. Before-and-after timings on a named synthetic workload are recorded.

## What does not change

- Commands, their request identities, transaction ordering and uncertain-outcome
  recovery (D238). Status reads that reconcile a command stay serialized with it.
- Identity bootstrap, profile and market-context selection, and any read that
  assigns session state (for example frame discovery in `workspace/navigation`):
  these stay under the session gate.
- The transport. Submission is HTTP and delivery is SSE; D151 stands and no
  WebSocket library is added. No new dependency. The event contract does
  change (see Channel changes) and takes a new protocol identifier.
- No durable delivery or replay. A disconnected read is rejected and explicitly
  requested again, as now.
- Two active reads per channel, four channels per session and 64 per scope,
  until measurements justify a different bound.
- Delegated assistant invocations keep their classified ordinary operations and
  are still refused on the channel.
- The Blotter's progressive row stream, the live-context stream and the
  assistant turn stream keep their own paths.
- Retained Risk job admission and reports. Their status polling stays for now
  (see Later rounds).

## What would make this a failure

- The channel becoming a path-based proxy for arbitrary endpoints.
- A result shown for an account, context or selection the person has left.
- A cached authorization decision standing in for a fresh check.
- A read silently replayed, or a default result standing in for a refused one.
- Any pricing, unit or schedule rule moving into TypeScript.

## Approaches

Three were considered.

**A. Copy each remaining read into `PrepareAsyncRead`.** This is how D404 was
built. It is the quickest start for a handful of reads, but it leaves the gate
on ordinary reads and the navigation gate in place, and it doubles the code for
every read it reaches.

**B. Route every read through the channel by path.** One generic dispatcher
would cover all pages at once. D404 forbids exactly this, and small catalog
reads would pay an extra submission and a publication recheck to gain nothing
that releasing the gate does not already give them.

**C. Shared read definitions, ungated HTTP reads, heavy reads on the channel.**
Each read is defined once; the HTTP route and the channel operation are two
ways to run it. Page loads leave the global gate. Only reads that do real work
move to the channel.

Chosen 2026-11-16: C, including the heavy-read rollout that A would have done
by hand. A's duplication is removed rather than extended.

## Design

### One read definition

A read is a named, versioned definition with four parts:

- its typed request and the permissions it requires;
- **capture**: under the session gate, turn the request and the session's
  current profile, context, frames and live selection into an immutable
  selection. Nothing else reads the session;
- **execute**: on a database connection bound to the captured identity, with no
  session gate held, produce the projection and the exact coordinates it read;
- **recheck**: in a fresh transaction, confirm the read's permissions and the
  definition's own check of what it read.

Definitions live in a finite registry compiled into the API. A route or a
channel operation exists only for a registered definition.

The two transports run a definition as follows.

| Step | Ordinary HTTP | Response channel |
| --- | --- | --- |
| Admit | Wait for a session read slot, take the gate, capture, release. | Take the gate, capture, release, answer 202. |
| Execute | In the request, no gate held. | On a detached worker with explicit inputs only. |
| Publish | Take the gate; require the sign-in unexpired and the profile unchanged; in a fresh transaction require the permissions and run the definition's recheck; write the response. | As D404: gate, the channel's profile, context and live selection unchanged, authorize, recheck with the worker's sealed evidence, write the event. |

The HTTP column is the contract the existing `Concurrent` helper already
applies to the progressive trading workspace and the Blotter row stream,
generalized to any definition. Its session match stays sign-in and profile
only: an ungated read's inputs are an immutable capture of the snapshot the
request named, so a later context change or live update does not make the
result wrong, and the page's own fence discards a result it no longer wants.
The Blotter row stream keeps its path and its fence. The channel column is
D404's behaviour, reached through the definition instead of a second
hand-written handler.

The sealed evidence collector (`AsyncReadVisibility`) stays a channel
mechanism. A read may be given a channel operation only once the collector
records what that read touches; several pages in the table below have no such
recording today, and adding it is part of moving them.

**Session read slots.** The session gate is today what limits a session to one
database connection for ordinary requests. Ungated reads take one of two
per-session slots instead, and wait for one within the request deadline rather
than being refused. The bound is a fixed contract value like the channel's two
active reads, not a configuration value. It is two because the hosted
application pool is capped at eight connections; a session then uses at most
four at once across both transports.

**Session preparation.** A handler that assigns session state is not a read for
this purpose and stays `Locked`. Where an existing HTTP read first prepares the
session, as `/history` discovers frames, that preparation stays a gated step of
the HTTP route before capture; the channel operation still refuses an
unprepared session, as D404's `async_workspace_not_ready` does.

### Channel changes

- **One encoding.** The worker's UTF-8 result is kept as bytes and written into
  the event as raw JSON. It is not parsed, cloned or turned into a string. The
  16 MiB cap applies to those bytes.
- **Refusals.** A failed event carries the refusal the ordinary route would
  have answered: its status, code, message and structured details, produced by
  the same mapping as HTTP. Today the channel maps five exception kinds and
  turns the rest into a generic failure, which would discard what a preview's
  refusal says. The protocol identifier becomes `async_reads_v2`; the earlier
  one is not kept.
- **Compression.** The `async-reads/events` response is gzip-compressed with a
  flush after each event. The live-context and assistant streams are unchanged.
- **Retire before expiry.** The channel-opening receipt states the age after
  which the page must send nothing further on that channel: the lifetime less
  the read limit, the delivery limit and a margin. Past that age the client
  waits for its active reads, then renews, exactly as it already does at the
  128-identity limit. Server lifetimes are unchanged.
- **Unused operations.** The seven statistical Risk operations and
  `trading.position.v1` have no caller on the channel and are removed from the
  allowlist. Their ordinary routes remain.

### Page behaviour

- Every page's first load runs the way Market, Blotter and Risk already do:
  detached from `act`, with its own abort signal and its own read state on the
  page region. Navigation never waits for it, and leaving the page aborts it.
- Reads a view makes after its first load (a refresh, a changed selection, a
  preview) leave `act` as well. `lifecycle/preview`, for example, runs inside
  `act` today, so moving it to the channel alone would still disable every
  control.
- `act` and the global `busy` flag remain for commands and context changes
  only. This reworks most view modules; it is the largest part of the change.
- Each view owns its controls and its pending state. A region whose account or
  context changed is cleared, never left showing values from the selection it
  replaced. A result is installed only if its owner, generation, account and
  context still match, using the fences the views already keep.
- Reads that do not depend on each other are sent together. The known cases
  are Administration's three reads, Interval series `values` and `changes`, and
  Risk `scope` and `setup`.
- The amount-display formatting read becomes an ungated read, so formatting a
  result no longer queues behind other requests.
- Pop-out Blotter and Position windows keep ordinary HTTP. They gain from
  ungated reads without holding another long-lived connection, which matters
  where the page is served over HTTP/1.1 and a browser allows six connections
  per origin.

While a page loads, the person sees:

```
 Sidebar (clickable)   | Lifecycle
 ----------------------+------------------------------------
  Market               |  Actions            Reading…
  Blotter              |  (empty until this context's
  Risk                 |   result arrives)
 > Lifecycle           |  Policies           Ready
  Physical operations  |  [rows]
```

### Reads that move to the channel

A read moves when it runs a valuation, pricing, risk, projection, preview or
P&L, or returns a page-sized result. By page, the first set is:

| Page | Reads |
| --- | --- |
| Blotter tickets | `futures/price`, `swaps/price`, `futures/draft-risk`, `swaps/draft-risk`, `swaps/preview`, `futures/amend-preview`, `swaps/settlement/pnl`, `tickets/preview`, `tickets/amend-preview`, `crude/preview`, `lng/preview`, `ppa/preview`, `ppa/directory`, `ppa/break-even` |
| Lifecycle | `lifecycle/view`, `lifecycle/preview` |
| Physical operations | `gas/operations/preview`, `gas/billing/preview`, `crude/operations/invoice/preview` |
| Facilities, REC, Physical power | `facilities/quantities/preview`, `rec/trades/valuation`, `rec/trades/preview`, `physical/power-trades/valuation`, `physical/power-trades/preview`, `physical/power-trades/hedges`, `physical/power-facilities/preview` |
| Curves and configuration | `custom-curves/preview`, `custom-curves/effective-preview`, `custom-curves/component-history`, `curve-definitions/preview`, `contract-price-terms/preview`, `price-publications/power/preview`, `interval-curves/values`, `power/preview`, `crude-setup/preview` |
| Risk and Jobs | `portfolio/risk/economic/history`, `portfolio/risk/economic/cash-funding`, `risk/definitions/{id}/latest`, `jobs/pilot-close/results` |

`portfolio/pnl/run` retains an in-memory artifact for a later save and needs
its own admission before it can leave the gate; it is not in the first set.

Every other read becomes an ungated ordinary read through its definition.

## Order of delivery

Each step is its own change and leaves the application working.

0. Record baseline timings (see Evidence).
1. Shared definitions and ungated HTTP for the operations D404 already covers;
   remove `PrepareAsyncRead`'s duplicates and the unused operations. No page
   changes.
2. Channel changes: one encoding, compression, retire before expiry.
3. First loads leave the global gate on every page, and amount display is
   ungated. In-page reads are untouched here.
4. One change per page group, each doing three things for its pages: every
   read gets a definition and is ungated; the reads in the table above gain
   channel operations; the views' in-page reads leave `act`, with independent
   reads sent together. The groups are Blotter tickets; Lifecycle and Physical
   operations; Facilities, REC and Physical power; curves, schedules and
   configuration; Risk, Dashboard and Jobs; and Reference, Parties, Options,
   Volatility surfaces, Administration and AI settings.

Each step amends D404's record in `docs/decisions.md` and
`docs/async-reads.md` to what is then true.

## Evidence

- **Timings.** On the synthetic exchange example, before step 1 and after each
  later step: time from choosing a page to its controls being usable, time the
  sidebar is disabled, latency of each moved read on both transports, bytes on
  the wire and managed allocation for the largest Blotter workspace result. The
  ordinary `trading/workspace` response is already gzip-compressed, so its
  baseline bytes differ by transport before any change. The record names the
  workload, machine, contracts and scenarios, as the benchmark rule in
  AGENTS.md requires.
- **Equality.** Every definition with a channel operation is checked for the
  same projection, exact financial values and refusals over ordinary HTTP and
  over the channel, extending the existing async workbench check.
- **Independence.** An ordinary session request completes while an ungated read
  of the same session waits in the database, for HTTP as D404 already checks
  for the channel. A third concurrent ungated read of one session waits for a
  slot and then completes.
- **Fences.** A profile switch or sign-in expiry during an ungated read refuses
  its result, as does a permission revoked between execution and publication.
  On the channel a source hidden in that interval refuses it too. A context
  change during an ungated HTTP read returns the result for the snapshot the
  request named, and the page does not install it.
- **Channel age.** A read submitted near the retirement age completes; reads
  after it go to the renewed channel.
- **Browser.** With a page's reply held, the sidebar and other pages stay
  usable, and the held page shows its own pending state.
- **Review.** The change touches authorization and asynchronous execution, so
  it gets independent adversarial review before publication.

## Left to the builder

Type and member names; the registry's shape; confirming, read by read, that a
handler assigns no session state before it is ungated; the retirement margin;
test names and the measurement tooling; the next free decision number.

## Proposed here, not yet decided by the owner

- Pop-out windows stay on ordinary HTTP.
- The eight unused operations are removed rather than given callers.
- Command-status reads stay serialized with their commands.
- Compression applies to the response-channel stream only.
- An ungated HTTP read authorizes again in a fresh transaction before it
  answers, as `Concurrent` does, rather than relying on the read's own
  transaction alone.
- Two ungated reads per session at once, waiting rather than refusing.
- The channel's failed events carry the full HTTP refusal, under a new
  protocol identifier.

## Later rounds (not part of this change)

- Push retained Risk and volatility-fit job status over the channel instead of
  polling. It needs a database notification and therefore a schema release.
- Revisit the bound of two active reads per channel once timings exist.
- Carry the live-context and assistant streams on the same connection.
