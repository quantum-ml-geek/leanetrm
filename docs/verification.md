# Local verification and continuous integration

Run verification from a clean checkout using public dependencies and the supplied
synthetic fixtures. No existing database or application is a verification target.

## Required tools

- The exact .NET SDK in `global.json`.
- The exact Node version in `.node-version`, including its bundled npm.
- Python 3 with assertions enabled; the hosted job uses Ubuntu's Python 3.12.
- Installed stock PostgreSQL 16+ binaries, including `initdb`, `pg_ctl` and `psql`.
- An installed Chromium-compatible browser. Keep its normal sandbox enabled.

Run as an ordinary user, not root. PostgreSQL's shared system service is not used.
The existing preview launcher allocates private Unix-socket-only clusters and
checks their data directory before applying migrations or loading fixtures.

```sh
python3 tools/check_all.py \
  --pg-bin /path/to/postgresql/bin \
  --dotnet /path/to/dotnet \
  --browser /path/to/browser
```

The command checks its orchestration, standalone dependency boundaries and owned
process cleanup; installs the locked frontend dependencies without install scripts;
builds and checks the frontend; restores every managed check project in locked mode;
and runs the managed, rate, temporal and schedule checks. It then runs the stock
database schema suite, standard HTTP/storage/adapter checks, owned browser scenarios
and mixed-period HTTP checks. A failing child command stops the run with a nonzero
status. Python optimization is rejected because it disables assertions used by the
existing verification scripts.

The standard and mixed previews use different disposable clusters. The browser
runner uses fresh temporary profiles and accepts only the launcher's verified
owned target. Normal completion removes the owned application, browser and database
resources. Unconfirmed teardown retains the private directory and fails the check.

## Hosted job

[The workflow](../.github/workflows/ci.yml) uses `ubuntu-24.04` hosted runners on
pushes, pull requests and manual dispatch. Checkout and tool-setup actions are
pinned to exact commits. The workflow has read-only repository access, does not
persist checkout credentials and requires no repository secrets. It runs the same
`check_all.py` command as local verification. It does not publish packages or
deploy the application.

The job uses the runner image's stock PostgreSQL 16 binaries and installed Chrome;
it does not start the image's shared PostgreSQL service. SDK, Node and application
dependency versions are pinned. The hosted image, PostgreSQL patch, browser,
Python, ICU and time-zone data can change. Their versions are recorded in the job
log, so this is a reproducible command and input set rather than a frozen OS image.

Hosted qualification passed on 2026-10-17 in
[run 39064855342](https://github.com/zerodrift/leanetrm/actions/runs/39064855342)
at commit `e7f9b4cafcd4855336cfbf8501d1122d5745339e`. The complete command passed
on Ubuntu 24.04 image `20261012.334.1`, .NET 10.0.402, Node 24.22.0, stock
PostgreSQL 16.15 and Chrome 155.0.8059.39 with its normal sandbox enabled. This
included 198 standard and 24 mixed HTTP checks, 50 browser checks and the existing
managed/frontend/schema/storage/adapter suites. Both disposable previews completed
teardown. This qualifies the verification command on that runner, not production
readiness.

Browser profiles remain under the preview owner's temporary root until its owned
process group has stopped. A regression checks that a live descendant can still
finish writing after the browser parent exits; parent exit alone does not permit
profile deletion.

Local qualification on 2026-10-17 passed the complete command from a fresh macOS
arm64 checkout with empty npm/NuGet caches, .NET 10.0.402, Node 24.22.0 and stock
PostgreSQL 16.14. This included 198 standard and 24 mixed HTTP checks, 49 browser
checks and the existing managed/schema suites. Workflow syntax and three runner
behavior checks also passed. The subsequent profile-lifetime correction passed
the standard preview and all 50 browser checks locally before the hosted rerun.
