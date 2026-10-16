# Project instructions

Read `docs/architecture.md` and `docs/plan.md` before changing the application.
The architecture distinguishes agreed requirements from proposed implementation
choices. Update the decision record when a decision changes.

## Public repository

- Write original implementation and use neutral, explicitly synthetic examples.
- Do not copy private source trees, history, datasets, operational receipts,
  credentials, prompts or configuration into this repository.
- Do not include customer/company names, competing business-product names or
  comparisons in source, documentation, fixtures or commit messages. Retain the
  exact technical identifiers and attribution required by dependencies/licenses.
- Inspect the complete staged diff, generated files and commit identity before
  publishing. Never publish local settings, secrets or test accounts.
- Preserve copyright and required license notices.
- Keep architecture drafts and implementation changes local until the user
  explicitly approves publication. Do not push unapproved changes.

## Architecture

- Use an unmodified database and public, reproducible dependencies.
- Retain independent, reusable sides and explicit instrument memberships.
- Apply shocks to immutable market scenarios, never to individual trades.
- Treat pricers as black boxes with declared dependencies and explicit inputs.
- Quantity scaling is a declared capability, separate from market linearity.
- Futures are baseline products; preserve variation-margin state and outstanding
  exposure separately. A forward valuation alone does not implement futures.
- Core reference relationships use exact-version foreign keys, not free-text
  names or arbitrary JSON relationships. Keep public catalogs synthetic and
  placeholders non-executable; real data has separate usage/redistribution rights.
- UI and agent entry points use the same authorized business operations.
- Model/provider-specific types must not enter domain or calculation contracts.
- Numerical policy, units, model versions and snapshot identity are calculation
  inputs. Missing information must not become a successful default result.
- Historical context carries business/effective time and a resolved knowledge
  cutoff through every business read, join, calculation and agent operation.
  Never silently substitute current data or historical permissions.

## Verification and review

- Use isolated disposable resources and synthetic data. Do not operate on
  existing applications or production when testing.
- Run relevant correctness and integration checks before publishing changes.
- Obtain independent adversarial review for changes involving authorization,
  temporal behavior, async execution, numerical correctness, scenario reuse or
  release/deployment boundaries. Resolve findings before publication.
- Benchmarks must identify workload, unique contracts, scenarios, evaluated work,
  memory and environment. Do not infer performance from trade count alone.
- Document actual capability and remaining work; a design is not evidence that a
  feature is implemented or qualified for production.
