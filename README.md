# openetrm

Work in this standalone repository for the public application. The local
**Power TOUs** page uses its native curve API and stock PostgreSQL preview;
see [the power example and its limits](docs/power-preview.md).
Run `python3 tools/check_standalone.py` to check dependency boundaries.

Open Source Commodity Trading Risk Management

An ETRM designed for people and AI agents, with reusable sides, deterministic
valuation and shared market-factor scenarios over a standard relational database.

**Status: foundation plus a local synthetic market workbench.** A TypeScript
browser client and managed API read real PostgreSQL data through restricted RLS
logins and build commodity curves using exact arithmetic. A separate interest-rate
example uses explicitly selected day-count/compounding rules for discount factors. The disposable preview
supports pinned input selections, contract histories, observation corrections,
per-contract pricing diagrams and reference inspection. Shared historical contexts and workspace user/role administration are implemented
in the loopback preview. Production sign-in, trading and risk workflows remain
unimplemented. See the [preview command and implemented
scope](docs/implementation.md). The wider documents specify the intended system;
they are not claims of implemented functionality or production qualification.

- [Architecture and domain contracts](docs/architecture.md)
- [Delivery plan and acceptance criteria](docs/plan.md)
- [Decisions, proposals and unresolved choices](docs/decisions.md)
- [Events and lifecycle](docs/lifecycle.md)
- [Historical context and temporal data](docs/context.md)
- [Time, delivery calendars and TOU](docs/time-and-schedules.md)
- [Reference data and futures](docs/reference-data.md)
- [Market-data contracts](docs/market-data.md)
- [Market model proposal and key linkages](docs/market-model.md)
- [Reference schema and disposable verification](db/README.md)
- [Current implementation and verification](docs/implementation.md)
- [Business scenarios, settlement gaps and proposed shocker](docs/business-scenarios.md)
- [Identity, agent login kinds and authorization](docs/security.md)

The first working slice will include futures and fixed/floating linear
instruments from reusable sides,
shock a shared gas factor, propagate the resulting market through dependent gas
and power curves, and reprice the affected trades through the same authorized
operations used by the UI and agents. Examples will be explicitly synthetic.

The intended eventual hosted domain is leanetrm.com. No hosted service or
deployment is implied by this repository's current status.

## License

Copyright (c) 2017 zerodrift.

Licensed under the [Apache License, Version 2.0](LICENSE).
