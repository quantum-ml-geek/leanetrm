using System.Collections.Immutable;
using OpenEtrm.MarketData;

internal static class ContractSequenceChecks
{
    public static void Run()
    {
        var passed = 0;
        void Check(string name, Action action) { action(); passed++; Console.WriteLine($"PASS {name}"); }
        void Equal<T>(T actual, T expected) where T : notnull
        { if (!actual.Equals(expected)) throw new Exception($"Expected {expected}; got {actual}."); }
        void Reject(string code, Action action)
        {
            try { action(); } catch (MarketDataException e) when (e.Code == code) { return; }
            throw new Exception($"Expected {code}.");
        }
        DateTimeOffset U(int day, int hour = 0) => new(2026, 1, day, hour, 0, 0, TimeSpan.Zero);
        var revision = new DefinitionRevision(Guid.NewGuid(), Guid.NewGuid());
        var reference = new ReferenceRevision(Guid.NewGuid(), Guid.NewGuid());
        var key = new CurveKey(revision, "gas_future");
        ContractSequenceEntry Entry(int n, int roll, DateTimeOffset? eligible = null) => new(n,
            new(new(revision, Guid.NewGuid()), ContractKind.Future, new(2026, n + 1, 1), new(2026, n + 2, 1), U(roll, 19), new(reference, $"gas_{n}")),
            eligible ?? U(1), new(2026, 1, roll));
        var entries = new[] { Entry(1, 10), Entry(2, 20), Entry(3, 30) };
        ContractSequence Sequence(IEnumerable<ContractSequenceEntry>? rows = null) => new(key, reference, U(1), U(30, 19), rows ?? entries);

        Check("shortcut resolves exact contract and selected date before and at expiry", () =>
        {
            var alias = new ScheduleShortcut("oe.ng1", "Gas prompt", Sequence(), 1, ScheduleDateRole.DeliveryStart);
            var before = alias.Resolve(U(10, 19).AddTicks(-1));
            var at = alias.Resolve(U(10, 19));
            Equal(before.Contract, entries[0].Contract.Key); Equal(before.Date, new DateOnly(2026, 2, 1));
            Equal(at.Contract, entries[1].Contract.Key); Equal(at.Date, new DateOnly(2026, 3, 1));
            Equal(at.Sequence, key); Equal(at.References, reference); Equal(at.Symbol, "oe.ng1");
            Equal(at.ValuationAt, U(10, 19)); Equal(at.RuleVersion, "expiry_ordinal_v1");
            Equal(before.Contract, entries[0].Contract.Key); // Later resolution cannot rewrite its receipt.
        });
        Check("ordinal follows retained order across several expiries", () =>
        {
            var sequence = Sequence();
            Equal(new ScheduleShortcut("oe.ng2", "Second", sequence, 2, ScheduleDateRole.DeliveryEnd).Resolve(U(10, 19)).Date, new DateOnly(2026, 5, 1));
            Equal(new ScheduleShortcut("oe.ng1", "Prompt", sequence, 1, ScheduleDateRole.LastTradingDate).Resolve(U(21)).Date, new DateOnly(2026, 1, 30));
        });
        Check("a symbol has no inferred ordinal and date role", () =>
        {
            Equal(new ScheduleShortcut("oe.ng1", "Explicit second", Sequence(), 2, ScheduleDateRole.DeliveryStart).Resolve(U(2)).Contract, entries[1].Contract.Key);
            Reject("shortcut_symbol", () => new ScheduleShortcut("ng1", "Prompt", Sequence(), 1, ScheduleDateRole.DeliveryStart));
            Reject("shortcut_symbol", () => new ScheduleShortcut("#NG1", "Prompt", Sequence(), 1, ScheduleDateRole.DeliveryStart));
            Reject("shortcut_definition", () => new ScheduleShortcut("oe.ng1", " ", Sequence(), 1, ScheduleDateRole.DeliveryStart));
            Reject("shortcut_definition", () => new ScheduleShortcut("oe.ng1", "Prompt", Sequence(), 0, ScheduleDateRole.DeliveryStart));
            Reject("shortcut_definition", () => new ScheduleShortcut("oe.ng1", "Prompt", Sequence(), 1, (ScheduleDateRole)0));
        });
        Check("coverage, horizon and UTC context are explicit", () =>
        {
            var alias = new ScheduleShortcut("oe.ng1", "Prompt", Sequence(), 1, ScheduleDateRole.DeliveryStart);
            Reject("sequence_coverage", () => alias.Resolve(U(1).AddTicks(-1)));
            Reject("sequence_coverage", () => alias.Resolve(U(30, 19)));
            Reject("sequence_context", () => alias.Resolve(U(2).ToOffset(TimeSpan.FromHours(1))));
            Reject("sequence_horizon", () => new ScheduleShortcut("oe.ng3", "Third", Sequence(), 3, ScheduleDateRole.DeliveryStart).Resolve(U(10, 19)));
        });
        Check("ineligible expected contracts cannot be skipped", () =>
        {
            var later = entries[1] with { EligibleFrom = U(15) };
            var sequence = Sequence([entries[0], later, entries[2]]);
            Reject("sequence_ineligible", () => new ScheduleShortcut("oe.ng1", "Prompt", sequence, 1, ScheduleDateRole.DeliveryStart).Resolve(U(11)));
            Reject("sequence_ineligible", () => new ScheduleShortcut("oe.ng2", "Second", sequence, 2, ScheduleDateRole.DeliveryStart).Resolve(U(11)));
            Equal(new ScheduleShortcut("oe.ng1", "Prompt", sequence, 1, ScheduleDateRole.DeliveryStart).Resolve(U(15)).Contract, later.Contract.Key);
        });
        Check("missing business date cannot be replaced with the UTC roll date", () =>
        {
            var sequence = Sequence([entries[0] with { LastTradingDate = null }, entries[1], entries[2]]);
            Reject("sequence_date", () => new ScheduleShortcut("oe.ng1", "Prompt", sequence, 1, ScheduleDateRole.LastTradingDate).Resolve(U(2)));
            Equal(new ScheduleShortcut("oe.ng1", "Prompt", sequence, 1, ScheduleDateRole.DeliveryStart).Resolve(U(2)).Date, new DateOnly(2026, 2, 1));
        });
        Check("invalid pins, ordering, duplicates and missing eligibility fail at compilation", () =>
        {
            Reject("sequence_definition", () => Sequence([]));
            Reject("sequence_definition", () => Sequence([entries[1], entries[0], entries[2]]));
            Reject("sequence_definition", () => Sequence([entries[0], entries[2]]));
            Reject("sequence_definition", () => Sequence([entries[0], entries[1] with { Contract = entries[0].Contract }, entries[2]]));
            Reject("sequence_definition", () => Sequence([entries[0] with { EligibleFrom = default }, entries[1], entries[2]]));
            Reject("sequence_definition", () => Sequence([entries[0] with { Contract = entries[0].Contract with { Key = new(new(Guid.NewGuid(), Guid.NewGuid()), Guid.NewGuid()) } }, entries[1], entries[2]]));
        });
        Check("compiled sequence owns its rows and revised schedules preserve earlier results", () =>
        {
            var source = entries.ToArray(); var sequence = Sequence(source);
            source[0] = source[0] with { Contract = source[0].Contract with { Expiry = U(12) } };
            Equal(sequence.Entries[0].Contract.Expiry, U(10, 19));
            var correctedRevision = new DefinitionRevision(revision.CatalogId, Guid.NewGuid());
            var correctedReferences = new ReferenceRevision(reference.CatalogId, Guid.NewGuid());
            var corrected = new ContractSequence(new(correctedRevision, key.Code), correctedReferences, U(1), U(30, 19), source.Select(e => e with {
                Contract = e.Contract with { Key = new(correctedRevision, e.Contract.Key.Id), FuturesSeries = new(correctedReferences, e.Contract.FuturesSeries!.Value.Code) } }));
            Equal(new ScheduleShortcut("oe.ng1", "Prompt", sequence, 1, ScheduleDateRole.DeliveryStart).Resolve(U(11)).Contract, entries[1].Contract.Key);
            Equal(new ScheduleShortcut("oe.ng1", "Prompt", corrected, 1, ScheduleDateRole.DeliveryStart).Resolve(U(11)).Contract.Id, entries[0].Contract.Key.Id);
        });
        Check("adding a far-end contract does not change prompt selection", () =>
        {
            var nextRevision = new DefinitionRevision(revision.CatalogId, Guid.NewGuid());
            var nextReferences = new ReferenceRevision(reference.CatalogId, Guid.NewGuid());
            var extended = new ContractSequence(new(nextRevision, key.Code), nextReferences, U(1), U(31),
                entries.Append(Entry(4,31)).Select(e => e with { Contract = e.Contract with { Key = new(nextRevision, e.Contract.Key.Id),
                    FuturesSeries = new(nextReferences, e.Contract.FuturesSeries!.Value.Code) } }));
            Equal(new ScheduleShortcut("oe.ng1", "Prompt", extended, 1, ScheduleDateRole.DeliveryStart).Resolve(U(2)).Contract.Id, entries[0].Contract.Key.Id);
        });
        Check("one futures series cannot appear as two distinct contracts", () =>
            Reject("sequence_definition", () => Sequence([entries[0], entries[1] with {
                Contract = entries[1].Contract with { FuturesSeries = entries[0].Contract.FuturesSeries } }, entries[2]])));
        Check("parallel resolutions repeat without a global clock or price lookup", () =>
        {
            var shortcut = new ScheduleShortcut("oe.ng1", "Prompt", Sequence(), 1, ScheduleDateRole.DeliveryStart);
            var expected = shortcut.Resolve(U(21));
            Parallel.For(0, 100, _ => Equal(shortcut.Resolve(U(21)), expected));
        });
        Console.WriteLine($"{passed} contract sequence checks passed.");
    }
}
