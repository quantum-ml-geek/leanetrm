# Shared Read Definitions and Ungated Ordinary Reads Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make each read D404 already covers exist once in the managed backend, served by ordinary HTTP without holding the session gate and by the response channel, with a recorded timing baseline.

**Architecture:** `PrepareAsyncRead` in `Program.cs` already writes each covered read as capture (under the session gate), execute and recheck. It becomes `PrepareRead`, the only definition of those reads. Their HTTP routes stop carrying a second copy and delegate to it through one runner that captures under the gate, executes without it and authorizes again before answering. The channel keeps D404's worker and publication path.

**Tech Stack:** C# / .NET 10 minimal API, Npgsql, PostgreSQL 18, TypeScript (presentation only), Python 3.12 check tooling.

**Spec:** [docs/superpowers/specs/2026-11-16-non-blocking-page-reads-design.md](../specs/2026-11-16-non-blocking-page-reads-design.md). This plan implements its delivery steps 0 and 1 only. Channel changes, page loads, and each page group get their own plans. Page-navigation timings are taken in the page-load plan before its first change; nothing here alters a page.

## Global Constraints

- No page behaviour changes in this plan. `web/src` changes are limited to removing unused operations.
- No new dependency, table, migration or configuration value.
- Commands, context selection, profile selection and any handler that assigns session state stay under the session gate.
- A delegated assistant invocation (`AssistantInvocation` feature present) keeps the gated path: capture, execute and answer inside the session gate, no second transaction. It is still refused on the channel.
- An ungated HTTP read's publish step requires the sign-in unexpired and the profile unchanged, then, in a fresh transaction, the read's permissions and its recheck. It does not use `AsyncReadVisibility`.
- At most two ungated HTTP reads per session run at once (`PreviewSession.MaximumReads=2`). A further read waits within its request deadline; it is not refused. The hosted application pool is capped at 8 connections (`HostedConfiguration.RequireBudget(value,new(5,30,8))`).
- HTTP status codes, refusal codes and response bodies of the affected routes do not change. Each route keeps its own argument refusal (for example `MarketDataException("position_facts","Supply the selected context.")`) before it delegates.
- `trading/workspace` with `Progressive` and `trading/workspace/stream` keep the existing `Concurrent` helper unchanged.
- TDD: each task writes its failing check first. Commit with `git commit -s`.
- Synthetic data only; no customer or competing-product names in code, tests, docs or commit messages.

## Review Focus

1. A profile switch while an ungated read executes: the read must answer 403 `access_denied`, never the earlier profile's data. Pinned in Task 2 (unit) and Task 5 (HTTP).
2. A third and later ordinary read of one session issued together: each must wait and complete, none refused, and the session gate must be free meanwhile. Pinned in Task 2 and Task 5.
3. A request aborted or timed out while waiting for a slot or while executing: the slot and the gate must both be released, so the next request of that session proceeds. Pinned in Task 2.
4. An assistant tool call to a route this plan changes: its result, recorded outcome and replay must be unchanged. Pinned in Task 5 by the existing assistant checks, plus a grep step for `RecordOutcome`.
5. `/history` on a session whose frames are not yet discovered: ordinary HTTP must still discover them and answer; the channel must still refuse `async_workspace_not_ready`. Pinned in Task 5.

## File Structure

| File | Responsibility |
| --- | --- |
| `tools/benchmark_page_reads.py` (create) | Baseline timings of covered reads over both transports. |
| `tools/run_preview.py` (modify) | `--page-read-benchmark` flag, wired like `--blotter-stream-benchmark`. |
| `src/OpenEtrm.Api/UngatedRead.cs` (create) | The runner: slot, capture under gate, execute, publish under gate. No database or HTTP types. |
| `src/OpenEtrm.Api/ReadAuthority.cs` (create) | The fresh-transaction permission, sign-in and recheck step shared by HTTP publish and channel delivery. |
| `src/OpenEtrm.Api/AsyncReadContract.cs` (modify) | `ReadInput`, `ReadPlan`, `ReadOutcome` (renamed); typed `Input(operation,body)`; eight operations removed. |
| `src/OpenEtrm.Api/AsyncReads.cs`, `AsyncReadChannel.cs` (modify) | Use the renamed types and `ReadAuthority`. |
| `src/OpenEtrm.Api/Program.cs` (modify) | `PrepareRead`; `ServeRead(c,operation,body)` helper; 18 routes delegate; `PreviewSession.Reads`. |
| `tests/OpenEtrm.Api.Checks/UngatedReadChecks.cs` (create) | Runner behaviour without a database. |
| `tests/OpenEtrm.Api.Checks/AsyncReadContractChecks.cs` (modify) | Typed input equals decoded input; removed operations refused. |
| `tools/check_async_workbench_http.py` (modify) | Ungated HTTP behaviour against PostgreSQL. |
| `web/src/async-read-client.ts`, `tests/browser/async-read-probe.mjs`, `web/tests/async-read-client.test.mjs` (modify) | Drop the eight unused operations. |
| `docs/async-reads.md`, `docs/decisions.md`, `docs/operational-limits.md`, `docs/verification.md` (modify) | Record what is then true. |

---

### Task 1: Baseline timing benchmark

**Files:**
- Create: `tools/benchmark_page_reads.py`
- Modify: `tools/run_preview.py` (flag beside `--blotter-stream-benchmark`, lines 76 and 188-191)
- Modify: `docs/verification.md` (dated record)

**Interfaces:**
- Produces: `run(url, query, psql, environment, manifest) -> dict`, the JSON report printed by `--page-read-benchmark`.

- [ ] **Step 1: Write `tools/benchmark_page_reads.py`**, modelled on `tools/benchmark_blotter_stream.py` (same fixture, seeding and environment helpers) and on `Stream` in `tools/check_async_workbench_http.py` for the channel. On the standard example at one retained context, after one unmeasured warm-up per operation, take 7 samples of each of `evaluate`, `history`, `trading/directory`, `trading/workspace`, `trading/blotter`, `portfolio/risk/catalog` and `portfolio/risk`, alternating ordinary HTTP and the channel. The report is:

```python
{"benchmark":"page_reads_v1","workload":{...as benchmark_blotter_stream names it...},"environment":environment(),
 "reads":[{"operation":"trading.workspace.v1","http":{"medianMs":0.0,"maxMs":0.0,"wireBytes":0},
           "channel":{"medianMs":0.0,"maxMs":0.0,"wireBytes":0}}],
 "sameSessionWait":{"heldRead":"portfolio/risk","probe":"access","medianMs":0.0,"maxMs":0.0},
 "otherSessionWait":{"heldRead":"portfolio/risk","probe":"access","medianMs":0.0,"maxMs":0.0}}
```

`wireBytes` is the body as sent, with `Accept-Encoding: gzip` on HTTP. `sameSessionWait` times `GET access` issued 50 ms after an ordinary `portfolio/risk` read of the same session starts; `otherSessionWait` is the same probe from a second session, as the control. End the script with an assertion that every number is finite and positive.

- [ ] **Step 2: Add `--page-read-benchmark` to `tools/run_preview.py`** with the same exclusivity and output rules as `--blotter-stream-benchmark`.

- [ ] **Step 3: Run it**

Run: `python3 tools/run_preview.py --pg-bin /path/to/postgresql/bin --dotnet /path/to/dotnet --page-read-benchmark`
Expected: exit 0 and one JSON report. `sameSessionWait.medianMs` should be near the held read's duration; `otherSessionWait.medianMs` near the probe's own.

- [ ] **Step 4: Record the report** in `docs/verification.md` as a dated baseline, naming machine, PostgreSQL, .NET and the workload.

- [ ] **Step 5: Commit**

```bash
git add tools/benchmark_page_reads.py tools/run_preview.py docs/verification.md
git commit -s -m "Measure covered page reads on both transports before ungating them"
```

### Task 2: The ungated read runner

**Files:**
- Create: `src/OpenEtrm.Api/UngatedRead.cs`
- Modify: `src/OpenEtrm.Api/AsyncReadContract.cs` (rename `AsyncReadInput`→`ReadInput`, `AsyncReadPlan`→`ReadPlan`, `AsyncReadOutcome`→`ReadOutcome` everywhere they are used)
- Modify: `src/OpenEtrm.Api/Program.cs` (`PreviewSession`, near line 2855; rename `PrepareAsyncRead`→`PrepareRead`)
- Create: `tests/OpenEtrm.Api.Checks/UngatedReadChecks.cs`
- Modify: `tests/OpenEtrm.Api.Checks/Program.cs` (add `--ungated-reads`; also run it under `--async-reads`, which `tools/check_all.py:20` already invokes)

**Interfaces:**
- Produces:

```csharp
public sealed partial class PreviewSession
{
    public const int MaximumReads=2;
    internal SemaphoreSlim Reads {get;}=new(MaximumReads,MaximumReads);
}
internal static class UngatedRead
{
    // profile is the session's profile at capture. authorize runs with the session gate held.
    internal static Task<object> Run(PreviewSession session,Func<PreviewSession,ReadPlan> capture,
        Func<string,ReadPlan,ReadOutcome,CancellationToken,Task> authorize,CancellationToken ct);
}
```

- [ ] **Step 1: Write the failing checks** in `UngatedReadChecks.Run()`. Build the session as `AsyncReadChecks.DelegatedTransport` does and plans as `AsyncReadChecks.Run` does (`new(AsyncReadContract.Decode(request),async ct=>new(await work(ct),(_,_)=>Task.CompletedTask))`). Each check throws `Exception` with the quoted message on failure:

```csharp
// 1. While Execute waits, session.Gate.Wait(0) succeeds.            "An executing read must not hold the session gate."
// 2. Run returns the plan's value; authorize ran once, after Execute, and saw session.Gate.CurrentCount==0.
//                                                                     "Publication must authorize once under the session gate."
// 3. Three Runs started together with Execute held: capture ran twice; after one is released it runs a third time and
//    all three return.                                               "A third read must wait for a slot, then complete."
// 4. session.Profile changed while Execute waits -> PreviewDeniedException; authorize never ran.
//                                                                     "A read must not answer after its profile changed."
// 5. Session built with new HostedSignIn(digest,DateTimeOffset.UtcNow.AddMilliseconds(100)), Execute outlasts it
//    -> PreviewDeniedException.                                       "A read must not answer after its sign-in ended."
// 6. capture throws, Execute throws, authorize throws (three runs): each rethrows, and afterwards
//    session.Gate.Wait(0) succeeds and session.Reads.CurrentCount==PreviewSession.MaximumReads.
//                                                                     "A failed read must release its gate and slot."
// 7. Two reads hold both slots; a third Run with an already-cancelled token -> OperationCanceledException; capture
//    did not run for it.                                              "A cancelled wait must not capture."
// 8. Session with Profile==null -> PreviewDeniedException before capture.
//                                                                     "A session without a profile cannot read."
```

- [ ] **Step 2: Run to verify it fails**

Run: `dotnet run --project tests/OpenEtrm.Api.Checks -- --ungated-reads`
Expected: build error, `UngatedRead` does not exist.

- [ ] **Step 3: Implement.** Do the three renames, add `PreviewSession.Reads`, then `UngatedRead.Run`: wait for a slot; under the gate read the profile and call `capture`; release; `Execute`; under the gate require `DateTimeOffset.UtcNow<session.Ends` and the same profile, then `authorize`; release the slot in `finally`. Never hold the gate across `Execute`.

- [ ] **Step 4: Run to verify it passes**

Run: `dotnet run --project tests/OpenEtrm.Api.Checks -- --ungated-reads` then `-- --async-reads`
Expected: both exit 0.

- [ ] **Step 5: Commit**

```bash
git add src/OpenEtrm.Api tests/OpenEtrm.Api.Checks
git commit -s -m "Add a runner that executes a read outside the session gate"
```

### Task 3: One authorization step and typed read input

**Files:**
- Create: `src/OpenEtrm.Api/ReadAuthority.cs`
- Modify: `src/OpenEtrm.Api/AsyncReads.cs:109-124` (`Authorize` delegates to `ReadAuthority.Require`)
- Modify: `src/OpenEtrm.Api/AsyncReadContract.cs` (`Decode`)
- Modify: `tests/OpenEtrm.Api.Checks/AsyncReadContractChecks.cs`

**Interfaces:**
- Produces:

```csharp
internal static class ReadAuthority
{
    // In one fresh identity transaction: every permission and sign-in, recheck, every permission and sign-in again, then publish.
    internal static Task Require(PreviewDatabase database,string profile,string? hostedDigest,ImmutableArray<string> permissions,
        CancellationToken ct,Func<NpgsqlConnection,CancellationToken,Task>? recheck=null,Func<CancellationToken,Task>? publish=null);
}
internal static class AsyncReadContract
{
    // The input of an already-typed body. Decode(request) is Input(request.Operation, the body deserialized to that operation's type).
    internal static ReadInput Input(string operation,object body);
}
```

- [ ] **Step 1: Write the failing check** in `AsyncReadContractChecks.Run()`: for each admitted operation, deserialize a synthetic body to its request type, call `Input(operation,typed)` and require `Operation`, `SnapshotId`, `Permissions` and `Context?.SnapshotId` equal those of `Decode(request)` for the same body; `Input("curve.evaluate.v1",new HistoryRequest(...))` and `Input("curve.evaluate.v1",new BuildRequest(Guid.Empty,"synthetic"))` each throw `AsyncReadException` with code `async_request`.

- [ ] **Step 2: Run to verify it fails**

Run: `dotnet run --project tests/OpenEtrm.Api.Checks -- --async-read-contracts`
Expected: build error, `Input` does not exist.

- [ ] **Step 3: Implement** `Input` by moving `Decode`'s per-operation classification behind the typed body, and move `AsyncReads.Authorize`'s body to `ReadAuthority.Require` unchanged in order and content.

- [ ] **Step 4: Run to verify it passes**

Run: `dotnet run --project tests/OpenEtrm.Api.Checks -- --async-reads`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add src/OpenEtrm.Api tests/OpenEtrm.Api.Checks
git commit -s -m "Share the read authorization step and build read inputs from typed bodies"
```

### Task 4: Remove the eight operations without a caller

The operations are `trading.position.v1`, `portfolio.risk.statistical.setup.v1`, `portfolio.risk.parametric.calculate.v1`, `portfolio.risk.parametric.summary.v1`, `portfolio.risk.historical.calculate.v1`, `portfolio.risk.historical.summary.v1`, `portfolio.risk.historical.sample.v1` and `portfolio.risk.monte_carlo.calculate.v1`. Their ordinary routes stay.

**Files:**
- Modify: `src/OpenEtrm.Api/AsyncReadContract.cs`, `src/OpenEtrm.Api/Program.cs` (`PrepareRead` and `AsyncPortfolioRead` branches)
- Modify: `web/src/async-read-client.ts` (`postOperations`, `snapshotFor`), `tests/browser/async-read-probe.mjs` (`routes`)
- Modify: `tests/OpenEtrm.Api.Checks/AsyncReadContractChecks.cs`, `web/tests/async-read-client.test.mjs`, `tools/check_async_workbench_http.py`, `tools/check_hosted_async_reads.py`
- Modify: `docs/async-reads.md` (18 operations; drop the Statistical Risk row and "one position")

- [ ] **Step 1: Write the failing checks.** C#: each of the eight names, decoded with an otherwise valid body, throws `AsyncReadException` with code `async_operation`. Web test:

```js
for(const path of ['trading/position','portfolio/risk/statistical/setup','portfolio/risk/parametric','portfolio/risk/parametric/summary',
  'portfolio/risk/historical','portfolio/risk/historical/summary','portfolio/risk/historical/sample','portfolio/risk/monte-carlo'])
  assert.equal(asyncReadRequest(path,{}),undefined);
```

- [ ] **Step 2: Run to verify they fail**

Run: `dotnet run --project tests/OpenEtrm.Api.Checks -- --async-read-contracts` and `npm test --prefix web`
Expected: both fail on the new assertions.

- [ ] **Step 3: Remove** the eight operations from every file listed, including the assertions and HTTP comparisons the two Python checks make for them, and update `docs/async-reads.md`.

- [ ] **Step 4: Run to verify they pass**

Run: the two commands of Step 2, then `git grep -n "parametric.calculate.v1\|historical.sample.v1\|trading.position.v1"`
Expected: both exit 0; the grep finds only the refusal checks.

- [ ] **Step 5: Commit**

```bash
git add -A src web tests tools docs/async-reads.md
git commit -s -m "Remove response-channel operations that no page requests"
```

### Task 5: Covered HTTP routes delegate to the one definition

**Files:**
- Modify: `src/OpenEtrm.Api/Program.cs`: routes `/evaluate` (1456), `/market/curve-shapes` (1464), `/history` (1476), `/futures/editor` (1826), `/trading/positions` (2053), `/trading/freshness` (2074), `/trading/directory` (2097), `/trading/workspace` (2113, non-progressive only), `/trading/blotter` (2170), `/swaps/editor` (2223), `/portfolio/risk/scope` (2305), `/portfolio/risk/catalog` (2313), `/portfolio/risk` (2316), `/portfolio/risk/history` (2328), `/portfolio/risk/jobs` GET (2412), `/portfolio/risk/jobs/{id}` GET (2414), the four `/portfolio/risk/*/archive` GETs (`StatisticalArchive`, 2404), `/options/strategy/analyze` (2482); `PrepareRead` (2690)
- Modify: `tools/check_async_workbench_http.py`
- Modify: `docs/async-reads.md`, `docs/operational-limits.md`

**Interfaces:**
- Consumes: `UngatedRead.Run`, `ReadAuthority.Require`, `AsyncReadContract.Input`, `PrepareRead(PreviewSession,ReadInput)`.
- Produces, as a local function beside `Locked`:

```csharp
// The ordinary route of a registered read. A delegated assistant invocation stays inside the session gate.
Task<IResult> ServeRead(HttpContext c,string operation,object body);
```

- [ ] **Step 1: Write the failing checks** in `tools/check_async_workbench_http.py`, using its existing `holding(psql,environment,sql,fn)` to keep a read waiting in the database:

```python
# While an ordinary POST portfolio/risk of session A waits on LOCK market_data.observations:
check('ordinary request proceeds beside an ungated read', get(A,'access').status==200)          # returns before the lock is released
check('third ordinary read waits', third_read_started_after_first_released)                      # three POST evaluate; the third's reply follows a release
check('profile switch refuses the waiting read', held.status==403 and held.json()['code']=='access_denied')
check('revoked permission refuses the waiting read', revoked.status==403)                        # RunScenario revoked while the read waits, as expires() does for the channel
# With nothing held:
check('history discovers frames over HTTP', post(fresh,'history',body).status==200)              # fresh session, no workspace/navigation first
check('history refuses an unprepared channel', event(fresh,'curve.history.v1')['error']['code']=='async_workspace_not_ready')
```

- [ ] **Step 2: Run to verify they fail**

Run: `python3 tools/run_preview.py --pg-bin /path/to/postgresql/bin --dotnet /path/to/dotnet --async-workbench-check`
Expected: FAIL at "ordinary request proceeds beside an ungated read"; today the probe waits for the gate.

- [ ] **Step 3: Implement `ServeRead`.** With an `AssistantInvocation` feature: `Locked`, `PrepareRead`, `Execute`, answer. Otherwise: `UngatedRead.Run(Session(c), s=>PrepareRead(s,input), authorize, c.RequestAborted)` where `authorize` calls `ReadAuthority.Require(database,profile,hosted is null?null:session.Digest,plan.Input.Permissions,ct,outcome.Recheck)`.

- [ ] **Step 4: Make each listed route delegate.** Keep the route's own argument refusal, then `ServeRead(c,"<operation>",body)`; delete the handler's copy of the read. `/history` first runs its existing frame discovery under `Locked`, then delegates. Before deleting a handler, compare its arguments with its `PrepareRead` branch (`scenario`, `headTrade`, `expectedConvention`, `combinedWorkspace`, `publicationCheck`) and carry any the branch lacks into the branch.

- [ ] **Step 5: Confirm assistant recording is unaffected**

Run: `git grep -n "RecordOutcome\s*=" -- src/OpenEtrm.Api`
Expected: no invocation that records an outcome reaches one of the listed routes. If one does, that route's gated path must pass `WithIdentity` the same result type it passes today.

- [ ] **Step 6: Run to verify everything passes**

Run: the command of Step 2; `dotnet run --project tests/OpenEtrm.Api.Checks -- --async-reads`; `dotnet run --project tests/OpenEtrm.Api.Checks -- --assistant-workspace`; `python3 tools/run_preview.py ... --browser-check --browser /path/to/chromium`
Expected: all exit 0, with the same HTTP-against-channel equality results as before for the 18 operations.

- [ ] **Step 7: Update the documents.** `docs/async-reads.md`: the 18 covered reads have one definition; their ordinary routes run outside the session gate with the publish step above; two per session. `docs/operational-limits.md`: a row for `PreviewSession.MaximumReads`, classed as a fixed contract value like the channel's two active reads.

- [ ] **Step 8: Commit**

```bash
git add src/OpenEtrm.Api/Program.cs tools/check_async_workbench_http.py docs/async-reads.md docs/operational-limits.md
git commit -s -m "Serve covered reads from one definition outside the session gate"
```

### Task 6: Measure, record and review

**Files:**
- Modify: `docs/decisions.md` (a new decision, the next free number, amending D404), `docs/verification.md`

- [ ] **Step 1: Run the benchmark again**

Run: the command of Task 1 Step 3.
Expected: `sameSessionWait.medianMs` falls to about `otherSessionWait.medianMs`; per-read HTTP medians within run-to-run variation of the baseline.

- [ ] **Step 2: Record** both reports side by side in `docs/verification.md`, and the decision in `docs/decisions.md`: covered reads have one definition; their ordinary routes release the session gate under the stated publish step and the two-per-session bound; delegated invocations stay gated; eight unused operations removed.

- [ ] **Step 3: Run the full gate**

Run: `python3 tools/check_all.py` with the tool paths `docs/verification.md` names under Required tools.
Expected: exit 0.

- [ ] **Step 4: Obtain independent adversarial review** of the whole branch, as AGENTS.md requires for authorization and asynchronous execution, and resolve its findings.

- [ ] **Step 5: Commit**

```bash
git add docs/decisions.md docs/verification.md
git commit -s -m "Record ungated covered reads and their measured effect"
```
