# Jobs, workers and infrastructure

Status: bounded local implementation. Real Docker Swarm execution, recovery and
production deployment have not been qualified. This document describes the
implemented slice of the broader [execution contract](architecture.md#11-durable-execution-and-failure-semantics).

## Implemented operations

Jobs & Infrastructure is ordinary navigation for authenticated workspace members.
People see their own jobs; a current workspace `ManageJobs` grant permits managing
other jobs in that workspace. An explicitly registered `ManageAllJobs` installation
operator can manage jobs across scopes. Shared node projections contain approved
names, health, availability, capacity and observation times; they contain no host
addresses, credentials, raw Docker configuration, job inputs or logs.

The managed API exposes:

| Operation | Contract |
| --- | --- |
| `GET /api/jobs?page=0` | Authorized jobs, 100 per page, recent run metadata, profiles and shared infrastructure |
| `POST /api/jobs/create` | Exact request identity and explicit execution terms |
| `POST /api/jobs/control` | Pause, resume, cancel or run again, with expected job version |
| `POST /api/infrastructure/availability` | Pause/resume scheduling or drain an idle approved worker node, with exact node version |
| `POST /api/infrastructure/resolve` | Preserve observed availability and fence a previous uncertain conditional node update |

All writes use the existing authenticated identity transaction and request-token
boundary. Retain the original request identity and body after a lost response.
Exact retries return the retained result; changed payloads conflict. A known first-attempt
rejection can discard its pending request. Once a response is uncertain, later
authorization/policy rejections preserve that original identity until reconciled. The UI retains uncertain requests in
session storage, separately for each signed-in workspace/account.

The supported schedule is explicitly UTC, once or a fixed interval of 60 through
31,536,000 seconds. Its selected policies are `run_once` for misfires and `forbid`
for overlap. Recurrences advance to the first future instant on their original
interval grid. Expiry, timeout and maximum attempts are required. The owner has
at most 64 outstanding jobs across workspaces, including paused/blocked jobs and
physical runs awaiting termination. Reactivation acquires the same capacity.

Two operations are executable:

- `worker_check` verifies that the separate .NET worker can claim and complete a
  durable job through its restricted database identity. It performs no business
  calculation. It permits one through three fenced attempts.
- `swarm_job` launches the approved image's own entry point using `bounded_exit_v1`.
  A zero-exit container task means this process operation completed; it asserts no
  financial result or committed business effect. Only one create is admitted per
  run. The client cannot supply commands, environment variables, credentials,
  mounts, ports or arbitrary Docker options.

## Identity and database boundaries

Migrations 0034 and 0035 seed no workers, operators, profiles, credentials or jobs.
Every automation table has enabled and forced RLS. Runtime accounts cannot write
the tables directly. Narrow database operations derive actor, owner and scope
from a verified transaction context; caller-supplied ownership is rejected.

`RunJobs` is included in the six common role templates. `ManageJobs` is included
in the access-administrator template. `LaunchWorkloads` and `ManageInfrastructure`
require explicit grants. Infrastructure mutation additionally requires an
unexpired `automation.installation_operators` registration with capability
`ManageInfrastructure`; workspace administration alone is insufficient. Agent
infrastructure delegation is rejected in this slice.

An agent scheduling through a verified agent context needs its own enabled
membership and role grant, an exact current delegation permitting `RunJobs`, and
a delegator still entitled to both `RunJobs` and `CreateDelegations`. Image launch
also requires `LaunchWorkloads` on both identities and the delegation. Jobs retain
the agent owner and exact delegation. Disabling membership, revoking authority,
expiry or disabling a profile prevents later execution/publication.

The trusted worker login belongs only to `openetrm_scheduler`, without superuser,
RLS bypass, application/authenticator roles or ownership of application tables.
`automation.workers` binds its actual PostgreSQL `session_user` to one enabled
service principal, workspace and kind (`scheduler` or `controller`). That service
principal needs current `RunJobs` authority. It cannot choose another owner or
claim another workspace. The controller additionally needs the exact enabled
`automation.clusters` registration bound to its login.

The authorization epoch serializes admissions against explicit revocation.
Functions recheck current service authority after lock waits, including natural
grant expiry. Claims use database time, a lease, worker identity and monotonic
fence. Expired/superseded claims cannot publish results. Cleanup of previously
owned compute is separate from permission to start work.

## Image and maintenance contract

An immutable execution-profile version records its workspace, name, image digest,
architecture/variant, internal Swarm network, workload-node pool label, CPU,
memory and process bounds, and `bounded_exit_v1` protocol. Only its enabled flag
can change. Approval/provisioning is an installation operation; there is no public
profile-authoring endpoint yet.

The controller checks the registry descriptor is a single-platform manifest,
checks the manager's locally available exact digest and platform, and rejects
inherited image volumes. Index digests and unavailable qualification evidence
are rejected. Workload placement requires Linux, the approved architecture,
worker role and exact pool label. The network must be an internal Swarm network
labelled `openetrm.profile` with the exact profile ID.

Workloads use UID/GID 1654, read-only root filesystems, no additional privileges,
all capabilities dropped, a 16 MiB temporary filesystem, bounded local logging,
resource limits and no task restart policy. They expose no ports. They receive
no database, model-provider, application or Docker credentials. The supported
Engine protocol is API v1.47; actual Engine enforcement remains a qualification
requirement. Containers are not a qualified hostile-code isolation boundary.

The durable one-use launch admission commits before Docker submission. A lost
create response reconciles the deterministic owned service name; it never causes
another create. A known service ID cannot be replaced by a same-name clone.
Inspection rejects extra security/network authority outside the retained spec.
Task evidence must match the exact service/profile; successful completion also
requires an identified container and zero exit code. Owned terminal services are
removed individually, without pruning unrelated resources.

An uncertain admitted create can remain unresolved indefinitely. Missing service
and task history do not prove that partitioned compute stopped. Such work retains
its reservation, displays an unknown/intervention-required outcome, and blocks
maintenance. There is no qualified external stop-attestation recovery operation
yet. Fair polling prevents one uncertain run from starving other jobs or cleanup.
Swarm can reschedule physical tasks independently; this slice does not grant
those tasks business authority or establish exactly-once business effects.

Availability commands require a fresh node observation and exact Docker version.
Only ready, explicitly labelled workload workers can be changed. Managers and
unregistered infrastructure are not eligible. Drain additionally requires no
nonterminal tasks on the target node. It does not implement database failover.
Launch and maintenance admission share a cluster lock. Pending maintenance blocks
new launch admission; prepared, unremoved workloads block new maintenance.

An uncertain node update blocks subsequent cluster maintenance. An authorized
operator can preserve the currently observed availability using its current
version and a reserved maintenance-fence label. Only confirmation of the higher
version and matching label completes reconciliation, fencing delayed older
conditional updates. Original intent and resolution provenance remain recorded.
Committed external dispatch is the authorization boundary: an already admitted
bounded command can finish after revocation; later admissions are rejected.

## Running the separate services

Use the pinned SDK in `global.json`. For either worker kind:

```sh
dotnet restore src/OpenEtrm.Worker --locked-mode
dotnet build src/OpenEtrm.Worker --no-restore
dotnet src/OpenEtrm.Worker/bin/Debug/net10.0/OpenEtrm.Worker.dll
```

Supply protected files and explicit settings outside the repository:

| Setting | Required value |
| --- | --- |
| `OPENETRM_WORKER_CONNECTION_FILE` | Restricted PostgreSQL login connection string with one explicit host; network connections require `SSL Mode=VerifyFull` and the selected root certificate |
| `OPENETRM_WORKER_POLL_SECONDS` | Integer 1–60 |
| `OPENETRM_WORKER_LEASE_SECONDS` | Integer 5–120; controller additionally requires poll + six HTTP timeouts + 15 seconds |
| `OPENETRM_SWARM_CONFIG_FILE` | Controller only: protected JSON shown below |

```json
{
  "endpoint": "https://manager.synthetic.invalid:2376/",
  "clusterId": "syntheticcluster00000000001",
  "clientCertificateFile": "/run/secrets/swarm-client.pem",
  "clientKeyFile": "/run/secrets/swarm-key.pem",
  "rootCertificateFile": "/run/secrets/swarm-root.pem",
  "httpTimeoutSeconds": 5
}
```

This is a synthetic schema example, not deployable configuration. The controller
verifies cluster identity, the server hostname and its private certificate chain,
uses mutual TLS and refuses redirects. Its management certificate is privileged;
only this trusted process receives it. The scheduler has no Docker connection.

For an image build, publish the worker into a new external staging directory as
`worker/`, copy `deploy/worker.Dockerfile` there as `Dockerfile`, and copy `LICENSE`
and `LICENSES/`. Retain the version-matched Npgsql notice. Build using the reviewed
platform and record the resulting immutable image digest. No image is built,
published or deployed by the local verification tools.

The attested hosted application image also includes the published worker and its
version-matched provider notice. Its normal entry point remains the API; the
worker stack explicitly selects the worker entry point from that same image.
`deploy/swarm-workers.yaml` is the separate-service stack template. Every image,
secret/network name, replica count, poll and lease setting must be supplied
explicitly. Create separately scoped service logins, memberships/grants, worker
bindings and the controller cluster registration before starting it. Store only
the corresponding connection/certificate files in external Swarm secrets. Use
separate database and control networks, private PostgreSQL TLS and authenticated
manager access. Node labels select disjoint scheduler/controller placement; the
API's eligible nodes must exclude those control roles when separate placement is
required. The template creates no database, application, workload network or
host-maintenance access and does not migrate the existing hosted Compose release.

## Verification and remaining work

The owned PostgreSQL checks exercise real migrations, identities, RLS, delegated
agent scheduling, revocation, stale/expired claims, lock waits, cancellation,
idempotency, cross-workspace quota races, fair reconciliation and a separate .NET
worker. The controller lifecycle uses a synthetic Docker HTTP handler against the
real disposable database. Gateway checks cover lost create responses, immutable
identity, overprivileged specs, task evidence and image/platform qualification.
HTTP and owned-browser checks cover ordinary shared visibility and restricted
controls. Stack rendering checks use no daemon and establish configuration only.

Run these through `tools/check_all.py`; `tools/check_deployment.py` also validates
the Swarm template. No existing application/database/Swarm is used for testing.

Remaining work includes real disposable Swarm failure/recovery qualification,
host reboot and Docker Engine restart through an explicitly selected management
provider, full agent/provider execution and scoped tool-credential exchange,
child-agent ancestry/budget enforcement, broader schedule editing/calendars,
scheduled financial operations with pinned historical contexts, external stop
attestations, workload artifacts/logs and a qualified Swarm release migration.
