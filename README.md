# openetrm
Open Source Commodity Trading Risk Management

An ETRM designed for people and AI agents, with reusable sides, deterministic
valuation and shared market-factor scenarios over a standard relational database.

**Status: architecture and delivery planning. There is no runnable application
yet.** The documents below specify the intended system; they are not claims of
implemented functionality or production qualification.

- [Architecture and domain contracts](docs/architecture.md)
- [Delivery plan and acceptance criteria](docs/plan.md)
- [Decisions, proposals and unresolved choices](docs/decisions.md)

The first working slice will construct linear instruments from reusable sides,
shock a shared gas factor, propagate the resulting market through dependent gas
and power curves, and reprice the affected positions through the same authorized
operations used by the UI and agents. Examples will be explicitly synthetic.

## License

Copyright (c) 2017 zerodrift.

Licensed under the [Apache License, Version 2.0](LICENSE).
