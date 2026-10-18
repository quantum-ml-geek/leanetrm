# Identity and authorization foundation

Status: current security persistence, six role templates and PostgreSQL RLS are
implemented locally and tested in disposable resources. Credential verification,
production sign-in and credential lifecycle are not yet implemented. Workspace
administration and atomic durable access audit now exist in the owned preview. The runnable market workbench is explicitly loopback-only with simulated
test identities; see the [preview boundary](implementation.md#disposable-local-market-workbench).

## Principals and login kinds

Humans, services and agents have separate stable principal IDs. Identity bindings
map exact verified issuer/subject pairs to a principal and a matching login kind:
`HumanInteractive`, `ServiceCredential` or `AgentCredential`. An agent has its own
credential/login binding. IDs, display names and model-generated claims are not
credentials. Principal identity/kind cannot be edited in place.

The authentication adapter must verify signature/credentials, issuer, audience,
expiry and permitted login flow before supplying verified claims. Issuance,
rotation, session management and credential revocation integration remain work;
credential rotation should preserve principal identity. Never log raw credentials
or capability tokens. There are no seeded users, passwords, grants or universal
administrator accounts in the migrations. The owned disposable preview fixture
separately provisions six clearly labeled synthetic test identities and scoped
grants; these never establish a production login boundary.

## Common roles and scoped authority

[CommonRoles.cs](../src/OpenEtrm.Security/CommonRoles.cs) and
[0003_security.sql](../db/migrations/0003_security.sql) install these templates:

| Role | Intended permissions |
| --- | --- |
| Viewer | Read scoped market data |
| Trader | Read, book/amend trades and delegate within authority |
| Risk Analyst | Read, run valuations/scenarios and delegate within authority |
| Market Data Editor | Read, import observations, write market/reference drafts and delegate within authority |
| Market Data Approver | Read, freeze definitions and approve/publish qualified changes |
| Access Administrator | Manage identities/access and create scoped delegations |

Migration 0011 adds explicit `ReadTrades` to Trader and Risk Analyst. The bounded
futures booking, holdings and actor-owned request-status operations are implemented;
Viewer and Access Administrator have no implicit trading read. Current scope is
workspace-wide, with no per-book exceptions. Historical inputs never restore old
permissions, and denied reads clear displayed holdings while preserving uncertain
request identities. Latest-head booking amendments require current AmendTrade
authority and expected-revision concurrency. Generic valuation and financial
publication remain future operations. Storage sealing is not financial approval
or publication. Maker/checker approval rules remain part of those future commands.

Role assignments bind exact tenant/workspace scopes and half-open UTC intervals.
Revoked grants, disabled principals and suspended workspace memberships confer no authority. Access administration
has no implicit market-data access. This first implementation has no wildcard,
role inheritance, group hierarchy or book-level exception rules. Installation
operators must provision explicit verified identities and memberships; application
administration uses separately authorized, current workspace commands.

A market catalog belongs to one explicit workspace. Reference catalogs have one
owner scope and explicitly configured read-only shares; recipient editors cannot
write shared drafts. Sharing currently covers the catalog's retained revisions;
it is not an activation, publication or data-rights grant. Unmapped catalogs deny
access. Reference/market relationships use exact-version foreign keys and every
reference/market table has RLS enabled and forced.

## Database request boundary

The migration creates three isolated PostgreSQL roles:

- `openetrm_runtime`: no login, table ownership, superuser or RLS-bypass authority.
  A provisioned application login inherits its narrow privileges.
- `openetrm_authenticator`: no login, with only the capability-issuance operation.
  Its separately provisioned trusted login is used after authentication.
- `openetrm_security_owner`: no login; owns private security state/routines and
  has narrowly granted market/reference access with RLS bypass for those routines.
  It is never granted to runtime or authenticator roles.

The trusted authenticator issues an opaque, short-lived request capability from
verified issuer/subject/login-kind claims and an explicit workspace/delegation.
The runtime binds it to its exact database login, backend PID and transaction ID.
The private mapping, rather than caller-set session variables, establishes identity.
Runtime cannot issue capabilities, read their table, assume privileged roles or
change security tables. Capabilities must remain internal to the trusted server.

A committed binding cannot be reused in another transaction. A rolled-back binding
can be retried while unexpired and must revalidate current authority. Tokens have
at most five minutes' lifetime. There is no automatic cleanup job yet; that belongs
to service integration. Pool reuse without a fresh binding confers no access.

Only read-committed runtime transactions are supported. Admission locks the current
security epoch in share mode; every control-plane mutation updates that epoch and
must serialize with active requests. Revocation either precedes admission or waits
for the admitted transaction to finish. This coarse fence favors a simple verified
boundary; it is not a scalability result. Use bounded request transactions when
integrating the service.

Capability expiry is checked using actual trusted time after admission lock waits.
Each permission evaluation captures actual current UTC time for grant/delegation
and context expiry. Historical market selectors cannot restore old authority.
Runtime has no direct state-column update permission. The permission-checked
market sealing routine still validates exact references and bundle completeness.

## Agents

An agent action requires all of: the agent's own current scoped grants, an explicit
unrevoked delegation with matching scope/time/permissions, and the enabled
non-agent delegator's current grants for both the action and `CreateDelegations`.
Missing delegation never falls back to a human/service identity. Chained delegation
and autonomous agent modes are unsupported in this first slice.

The managed authorization decision retains actual actor, effective delegator,
delegation ID, security revision, scope, permission and check time. It is evidence,
not a reusable bearer capability. Durable audit must retain both identities and
commit the operation/outcome alongside its economic context when commands exist.

## Remaining integration gates

1. Implement verified authentication and protected capability exchange on separate
   trusted authenticator/runtime connections; never expose arbitrary SQL or accept
   principal IDs, scopes, times or login-kind claims directly from clients/agents.
2. Load actual resource ownership and current grants into authorized operations;
   align database and managed authorization and commit business/audit writes.
3. Integrate initial-admin provisioning, verified identity linking, credential
   lifecycle, delegation authoring and any additional approval policy. The current
   preview admin commands manage six fixed roles; `ManageAccess` does not permit
   arbitrary SQL, role editing, credential issuance or cross-workspace elevation.
4. Add end-to-end credential lifecycle, request deadlines, job-phase reauthorization,
   capability cleanup and migration/operational role provisioning.

The managed evaluator still cannot authenticate caller-supplied state/time/scope;
those are trusted server inputs. The SQL fence protects database transactions,
not arbitrary external work. RLS is complementary to application business rules.

## Schedule authoring boundary

The independent schedule editor uses existing WriteMarketDefinitions for draft
saves and SealMarketDefinitions for publication. Readers can inspect published
versions and workspace drafts but cannot mutate them. Candidate contract previews
remain private session artifacts. Published rows and stable reference identities
have storage guards; runtime lacks publication-state update privilege. The publish
operation rechecks current authority after admission and row-lock waits. Its
committed publication prefix is scoped to the market catalog and does not disclose
another scope's publication count. Historical schedule views still require current
read authority. This is a bounded schedule workflow, not whole-application temporal
or authentication-provider qualification.

## Historical contexts use current access

Schedule knowledge certificates and retained temporal contexts use forced RLS
under the same current catalog/workspace permissions as source facts. A context
identifier is a replay identity, not a credential or delegation. The context
operation rechecks read permission after locks and after its certification work.
Published schedule mutation still requires the existing scoped sealing permission;
reading history does not grant editing or publication. Raw runtime SQL cannot
modify certificate/context stores or call the private commit-time helper.

Owned database tests exercise revocation after a context is retained: HTTP replay
returns 403 and direct historical RLS returns no rows. Restoring current permission
allows the exact retained result again. Capability expiry during a blocked capture
also rejects it. These tests do not replace future external credential verification
or production credential/deployment qualification.

## Workspace administration and historical database views

Migrations 0009/0010 extend the current boundary. A market context binds once per
request and restricts both market and reference reads at the database. Historical
writes are denied by restrictive policies and the permission-checked definer
paths. The same exact cutoff covers separate certified schedule and market
prefixes. Receipt timestamps cannot make an uncommitted price historically visible.

Workspace membership suspension does not edit global principal status. Directory,
role changes and audit are scoped to the admitted tenant/workspace. Private tables
have forced RLS and no runtime table grants; only narrow definer operations are
callable. Administrative mutation requires both ManageIdentities and ManageAccess,
exclusive epoch admission before any shared admission, current-clock checks and an
expected target version. Agent delegation requirements still apply. Business read
rights are independent of administration. Member creation requires explicit kind
and roles; removal of all roles on another member is permitted and denies business
access. Roles have no inheritance or wildcard behavior.

The same administrative operation ID/payload/actor/scope returns its original
outcome. Another payload or actor conflicts. Account changes and append-only audit
commit together. Last-admin removal and self-removal of administrative rights are
rejected. Retrying an uncertain browser request uses its original identity; an
unknown response never becomes proof of rollback. UI caches clear on denied reload.

Authentication remains simulated and restricted to loopback. Preview registration
binds only the invalid synthetic issuer; it must not be exposed as real signup.
No migration installs users, credentials, grants, memberships or a default admin.
Upgrading an existing grant installation requires verified membership mappings;
the fresh-install migration rejects unqualified existing grants.

Named blotter layouts are current presentation state. Forced RLS restricts their
rows to the bound human principal, tenant and workspace; every API operation
requires current ReadTrades authority. No actor or workspace identifier is
accepted in the layout operation. The API validates the supported schema,
limits named views, serializes each account's writes and checks expected versions.
Saved settings cannot select financial contexts or confer business access. UI
layout metadata clears on identity changes even before a market date is selected.

Raw futures/swap business operations require current reference-catalog read
authority before evaluating new economic or calendar terms. Remembered exact IDs
do not preserve revoked access. Actor-owned accepted-command replay/status remain
current trade-control operations. Discount-default reads additionally retain the
selected historical reference/market-definition visibility.
