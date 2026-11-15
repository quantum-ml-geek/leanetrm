# Asynchronous workbench reads

D404 uses HTTP submission and one same-origin SSE connection for named business
reads. The server executes the same authorized managed operation as ordinary
HTTP and publishes the same exact result. The client correlates responses by
channel, request ID, operation and snapshot; completion order is independent of
submission order. Each consuming view still validates its selected account,
context and projection before installing a result.

Existing source-admission guards record the exact market/reference coordinates
and book identities touched by one read. This immutable evidence is scoped to
that worker and is checked again in a fresh publication transaction. It is not
an authorization cache. Concurrent workers and nested guards do not share their
evidence. A retained report list rechecks the originally returned job identities,
so a later filtered page cannot authorize an older, broader response.

## Wire contract

| Endpoint | Behavior |
| --- | --- |
| `POST /api/async-reads/channels` | Open with `{clientId}` and return `async_reads_v1`, channel ID and bound profile/context. An explicit new opening replaces and drains that client's previous channel. |
| `GET /api/async-reads/events?channelId=…` | Emit `ready` then correlated terminal `response` events. Same-page admission and session cookies are required. |
| `POST /api/async-reads` | Submit `{channelId, requestId, operation, body}`. HTTP 202 acknowledges admission; only SSE delivers the read result. |
| `POST /api/async-reads/cancel` | Submit `{channelId, requestId}`. The receipt repeats both IDs and reports `cancellation_requested` for admitted work or `not_admitted` after fencing an unadmitted ID against future submission. |

POST requests use the existing CSRF and origin contracts. The exchange example
uses its own API prefix and session scope. Neither arbitrary URLs nor financial
commands are valid operations. A repeated ID with the same normalized typed
input acknowledges the original work; conflicting reuse refuses.

The 25 admitted operations cover these existing consumers:

| Consumer | Reads |
| --- | --- |
| Curves | Evaluation with optional source/workspace detail, history and curve shapes. |
| Trading | Freshness, directory, position pages, one position, workspace, Blotter and futures/swap editors. |
| Risk | Scope, catalog, scenario calculation, dated-factor history and statistical setup. |
| Statistical Risk | Parametric calculation/summary, historical calculation/summary/sample and Monte Carlo calculation. |
| Retained Risk | Recent job list, exact job read and paged statistical archive. |

## Lifecycle and limits

Each workbench page owns a stable random client ID. Separate tabs can read under
the same session without cancelling each other. Reconnect/reset retains the
page's client ID, so lost openings are reclaimed without replacing other tabs.
There are at most four channels per session and 64 per API scope.

The channel admits two active reads, with a client queue of at most 32 additional
reads. Requests carry explicit business inputs. The server retains at most 128
identities per channel, including admitted requests and cancellations received
before admission; the client renews a drained channel before
submitting further requests. Request and serialized-result caps are 32 KiB and
16 MiB. A channel lasts five minutes and uses periodic authorization checks and
heartbeat writes. Work cancellation is cooperative: synchronous graph evaluation
cannot be forcibly preempted by a cancellation token. A serialized-result cap is
not a peak-memory guarantee. Publication evidence is bounded to 512 source or
reference/calendar coordinates, 4,096 original book identities and 4,096 retained
instrument authority proofs.

Changing a selection rejects the old consumer immediately. A submitted
cancellation keeps its execution slot until a terminal server response or an
exact matching `not_admitted` receipt. The latter reserves that ID atomically:
even a delayed submission cannot execute and receives `409 async_request_cancelled`.
Repeated cancellation of that ID returns the same receipt. An unknown cancellation
at the identity limit is refused without promising non-admission. This prevents
a burst of replacement reads from exceeding the execution bound while allowing
an aborted HTTP submission that never reached admission to release its slot.
Disconnect rejects pending reads. A subsequent explicit request establishes a new channel;
there is no silent replay or durable delivery guarantee.

Financial commands retain their existing request identities, transaction ordering
and uncertain-outcome recovery. Retained Risk jobs keep their existing durable
admission and report contracts. Progressive trade rows retain their dedicated
incremental stream. Identity bootstrap and context selection remain explicit
HTTP operations.

## Qualification

Run the owned synthetic qualification with installed stock PostgreSQL 18,
.NET from `global.json`, Python 3.12 or later, and Chromium:

```sh
python3 tools/run_preview.py --pg-bin /path/to/postgresql/bin \
  --dotnet /path/to/dotnet --async-workbench-check \
  --browser-check --browser /path/to/chromium
```

This check belongs to the required `workspace` verification partition. It
compares complete ordinary HTTP and SSE results, proves mixed curve/Risk reads
reach separate database sessions, and checks ordinary session requests while
those reads wait. Browser checks hold actual SSE replies to exercise superseded
curves and navigation during pending trade and VaR/ES setup and calculation
reads. Risk graph execution counters can differ with warm graph reuse; the
comparison excludes only those named work counters and preserves every
financial value, policy, context and response field. Hosted qualification uses
real sign-in cookies and TLS, including logout and sign-in expiry while work is
waiting in the database.

Correctness qualification does not establish production throughput, tail latency
or the maximum supported financial workload. Deployment should preserve the
existing proxy's disabled response buffering and allow the heartbeat interval.
