# openetrm
Open Source Commodity Trading Risk Management

An ETRM designed for people and AI agents, with reusable sides, deterministic
valuation and shared market-factor scenarios over a standard relational database.

**Status: foundation implementation. There is no runnable trading application
yet.** The first reference-data migration and disposable-database checks exist.
The wider documents specify the intended system; they are not claims of
implemented product functionality or production qualification.

- [Architecture and domain contracts](docs/architecture.md)
- [Delivery plan and acceptance criteria](docs/plan.md)
- [Decisions, proposals and unresolved choices](docs/decisions.md)
- [Events and lifecycle](docs/lifecycle.md)
- [Historical context and temporal data](docs/context.md)
- [Time, delivery calendars and TOU](docs/time-and-schedules.md)
- [Reference data and futures](docs/reference-data.md)
- [Reference schema and disposable verification](db/README.md)

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
