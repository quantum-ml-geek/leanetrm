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

## Architecture

- Use an unmodified database and public, reproducible dependencies.
- Retain independent, reusable sides and explicit instrument memberships.
- Apply shocks to immutable market scenarios, never to individual positions.
- Treat pricers as black boxes with declared dependencies and explicit inputs.
- Quantity scaling is a declared capability, separate from market linearity.
- UI and agent entry points use the same authorized business operations.
- Model/provider-specific types must not enter domain or calculation contracts.
- Numerical policy, units, model versions and snapshot identity are calculation
  inputs. Missing information must not become a successful default result.

## Verification and review

- Use isolated disposable resources and synthetic data. Do not operate on
  existing applications or production when testing.
- Run relevant correctness and integration checks before publishing changes.
- Obtain independent adversarial review for changes involving authorization,
  temporal behavior, async execution, numerical correctness, scenario reuse or
  release/deployment boundaries. Resolve findings before publication.
- Benchmarks must identify workload, unique contracts, scenarios, evaluated work,
  memory and environment. Do not infer performance from position count alone.
- Document actual capability and remaining work; a design is not evidence that a
  feature is implemented or qualified for production.
