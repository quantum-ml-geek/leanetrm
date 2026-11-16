using System.Collections.Immutable;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power.Structured;
using OpenEtrm.MarketData.Trading;

internal static class RecInventoryChecks
{
    public static int Run()
    {
        var f = new Fixture(); var log = RecInventoryLog.Empty(f.Account);
        var receipt = f.Request(log, new RecReceipt(f.Lot, f.Range(0, 100), f.Evidence(), RecReceiptKind.Issuance));
        var issued = RecInventory.Apply(log, receipt, f.Known);
        log = issued.Log;
        Count(f.View(log), RecHoldingState.Available, "100");
        var retry = RecInventory.Apply(log, receipt, f.Known.AddHours(1));
        if (retry.Log != log || retry.Outcome != issued.Outcome) throw new Exception("A request retry must return its first outcome without another fact or request.");
        var equal = f.Request(log, new RecReceipt(f.Lot, f.Range(0, 100), f.Evidence(), RecReceiptKind.Issuance));
        var duplicate = RecInventory.Apply(log, equal, f.Known.AddMinutes(1));
        if (!duplicate.Outcome.IsBusinessNoOp || duplicate.Outcome.Fact != issued.Outcome.Fact || duplicate.Log.Facts.Length != 1)
            throw new Exception("The certificate receipt's business identity is independent of request and evidence identities.");
        log = duplicate.Log;
        Reject("rec_request_conflict", () => RecInventory.Apply(log, receipt with { Action = new RecReceipt(f.Lot, f.Range(0, 101), f.Evidence(), RecReceiptKind.Issuance) }, f.Known.AddMinutes(2)));
        var allocation = f.Request(log, new RecAllocation(f.Range(0, 60), f.Delivery, f.Eligible));
        var allocated = RecInventory.Apply(log, allocation, f.Known.AddMinutes(2)); log = allocated.Log;
        Count(f.View(log), RecHoldingState.Available, "40"); Count(f.View(log), RecHoldingState.Allocated, "60");
        Reject("rec_inventory_unavailable", () => RecInventory.Apply(log, f.Request(log, new RecRetirement(f.Range(0, 1), f.Beneficiary, f.R("voluntary_use"), f.Evidence())), f.Known.AddMinutes(3)));
        Reject("rec_inventory_unavailable", () => RecInventory.Apply(log, f.Request(log, new RecAllocation(f.Range(50, 80), f.Delivery, f.Eligible)), f.Known.AddMinutes(3)));
        var transfer = f.Request(log, new RecTransfer(f.Range(0, 60), allocated.Outcome.Fact, f.Destination, f.Evidence()));
        log = RecInventory.Apply(log, transfer, f.Known.AddMinutes(3)).Log;
        Count(f.View(log), RecHoldingState.Transferred, "60");
        log = RecInventory.Apply(log, f.Request(log, new RecRetirement(f.Range(60, 100), f.Beneficiary, f.R("voluntary_use"), f.Evidence())), f.Known.AddMinutes(4)).Log;
        var final = f.View(log); Count(final, RecHoldingState.Available, "0"); Count(final, RecHoldingState.Retired, "40");
        if (final.Segments.Any(s => s.Owned)) throw new Exception("Transferred and retired certificates cannot remain owned inventory.");
        Reject("rec_inventory_unavailable", () => RecInventory.Apply(log, f.Request(log, new RecRetirement(f.Range(99, 100), f.Beneficiary, f.R("voluntary_use"), f.Evidence())), f.Known.AddMinutes(5)));
        var beforeTransfer = RecInventory.Evaluate(log, f.Context with { KnownAt = f.Known.AddMinutes(2) });
        Count(beforeTransfer, RecHoldingState.Allocated, "60"); Count(beforeTransfer, RecHoldingState.Available, "40");
        var reordered = RecInventory.Evaluate(log with { Facts = [.. log.Facts.Reverse()] }, f.Context);
        if (!reordered.Segments.SequenceEqual(final.Segments)) throw new Exception("Knowledge replay must not depend on insertion/enumeration order.");

        var empty = RecInventoryLog.Empty(f.Account);
        Reject("rec_inventory_unavailable", () => RecInventory.Apply(empty, f.Request(empty, new RecAllocation(f.Range(0, 1), f.Delivery, f.Eligible)), f.Known));
        Reject("rec_inventory_unavailable", () => RecInventory.Apply(empty, f.Request(empty, new RecTransfer(f.Range(0, 1), new(Guid.NewGuid(), 1), f.Destination, f.Evidence())), f.Known));
        var initial = RecInventory.Apply(empty, receipt, f.Known).Log;
        var forged=f.Request(initial,new RecRetirement(f.Range(0,1),f.Beneficiary,f.R("voluntary_use"),f.Evidence()));
        var mismatchedReceipt=initial with{Requests=initial.Requests.Add(new(forged,issued.Outcome))};
        Reject("rec_request_conflict",()=>RecInventory.Apply(mismatchedReceipt,forged,f.Known.AddMinutes(1)));
        Reject("rec_eligibility", () => RecInventory.Apply(initial, f.Request(initial, new RecAllocation(f.Range(0, 1), f.Delivery, f.Eligible with { Product = f.Product with { Program = f.R("other_program") } })), f.Known.AddMinutes(1)));
        Reject("rec_eligibility", () => RecInventory.Apply(initial, f.Request(initial, new RecAllocation(f.Range(0, 1), f.Delivery, f.Eligible with { VintageFrom = new(2036, 1, 1), VintageTo = new(2037, 1, 1) })), f.Known.AddMinutes(1)));
        Reject("rec_inventory_overlap", () => RecInventory.Apply(initial, f.Request(initial, new RecReceipt(f.Lot, f.Range(50, 101), f.Evidence(), RecReceiptKind.Issuance)), f.Known.AddMinutes(1)));
        Reject("rec_generation_conflict", () => RecInventory.Apply(initial, f.Request(empty, new RecRetirement(f.Range(0, 1), f.Beneficiary, f.R("voluntary_use"), f.Evidence())), f.Known.AddMinutes(1)));

        var changed = receipt with { RequestId = Guid.NewGuid(), ExpectedGeneration = 1, Action = new RecReceipt(f.Lot, f.Range(0, 120), f.Evidence(), RecReceiptKind.Issuance) };
        var revised = RecInventory.Apply(initial, changed, f.Known.AddMinutes(1));
        if (revised.Log.Facts.Length != 2 || revised.Outcome.Fact != new RecFactKey(receipt.BusinessId, 2)) throw new Exception("Changed business facts append an explicit revision.");
        Count(RecInventory.Evaluate(revised.Log, f.Context with { KnownAt = f.Known }), RecHoldingState.Available, "100");
        Count(f.View(revised.Log), RecHoldingState.Available, "120");
        var reassert = RecInventory.Apply(revised.Log, receipt with { RequestId = Guid.NewGuid(), ExpectedGeneration = 2 }, f.Known.AddMinutes(2));
        if (!reassert.Outcome.IsBusinessNoOp || reassert.Outcome.Fact.Revision != 1 || reassert.Log.Facts.Length != 2)
            throw new Exception("Reasserting an earlier fact returns it without restoring it as the current revision.");
        Count(f.View(reassert.Log), RecHoldingState.Available, "120");
        Reject("rec_knowledge", () => RecInventory.Apply(initial, changed, f.Known));
        Reject("rec_context", () => RecInventory.Evaluate(initial, f.Context with { SelectionPolicy = "unknown" }));
        Reject("rec_context", () => RecInventory.Evaluate(initial, f.Context with { Account = f.Destination }));
        Reject("rec_range", () => RecInventory.Apply(initial, f.Request(initial, new RecRetirement(f.Range(1, 1), f.Beneficiary, f.R("voluntary_use"), f.Evidence())), f.Known.AddMinutes(1)));
        Reject("rec_evidence", () => RecInventory.Apply(initial, f.Request(initial, new RecRetirement(f.Range(0, 1), f.Beneficiary, f.R("voluntary_use"), new(f.R("registry_feed"), Guid.Empty))), f.Known.AddMinutes(1)));
        var released = RecInventory.Apply(allocated.Log, f.Request(allocated.Log, new RecRelease(f.Range(0, 60), allocated.Outcome.Fact)), f.Known.AddMinutes(3)).Log;
        var reallocated = RecInventory.Apply(released, f.Request(released, new RecAllocation(f.Range(0, 60), f.Delivery with { Id = Guid.NewGuid() }, f.Eligible)), f.Known.AddMinutes(4)).Log;
        Count(f.View(reallocated), RecHoldingState.Allocated, "60");
        var returned = RecInventory.Apply(log, f.Request(log, new RecReceipt(f.Lot, f.Range(0, 60), f.Evidence(), RecReceiptKind.IncomingTransfer)) with { EffectiveAt = f.Effective.AddMinutes(1) }, f.Known.AddMinutes(5)).Log;
        Count(f.View(returned), RecHoldingState.Available, "60"); Count(f.View(returned), RecHoldingState.Retired, "40");
        Reject("rec_inventory_overlap", () => RecInventory.Apply(log, f.Request(log, new RecReceipt(f.Lot, f.Range(0, 60), f.Evidence(), RecReceiptKind.Issuance)) with { EffectiveAt = f.Effective.AddMinutes(1) }, f.Known.AddMinutes(5)));
        var invalid = initial with { Facts = initial.Facts.Add(new(new(Guid.NewGuid(), 1), f.Effective, f.Known.AddMinutes(1), receipt.Action)) };
        Reject("rec_inventory_overlap", () => RecInventory.Apply(invalid, f.Request(invalid, receipt.Action), f.Known.AddMinutes(2)));
        var fine = RecInventoryLog.Empty(f.Account);
        fine = RecInventory.Apply(fine, f.Request(fine, new RecReceipt(f.Lot, f.Range(0, 10), f.Evidence(), RecReceiptKind.Issuance)), f.Known).Log;
        var a = RecInventory.Apply(fine, f.Request(fine, new RecAllocation(f.Range(1, 8), f.Delivery, f.Eligible)), f.Known.AddMinutes(1)); fine = a.Log;
        fine = RecInventory.Apply(fine, f.Request(fine, new RecTransfer(f.Range(1, 4), a.Outcome.Fact, f.Destination, f.Evidence())), f.Known.AddMinutes(2)).Log;
        fine = RecInventory.Apply(fine, f.Request(fine, new RecRelease(f.Range(4, 8), a.Outcome.Fact)), f.Known.AddMinutes(3)).Log;
        var b = RecInventory.Apply(fine, f.Request(fine, new RecAllocation(f.Range(5, 9), f.Delivery, f.Eligible)), f.Known.AddMinutes(4)); fine = b.Log;
        fine = RecInventory.Apply(fine, f.Request(fine, new RecTransfer(f.Range(5, 9), b.Outcome.Fact, f.Destination, f.Evidence())), f.Known.AddMinutes(5)).Log;
        foreach (var pair in new[] { (0L, 1L), (4L, 5L), (9L, 10L) })
            fine = RecInventory.Apply(fine, f.Request(fine, new RecRetirement(f.Range(pair.Item1, pair.Item2), f.Beneficiary, f.R("voluntary_use"), f.Evidence())), f.Known.AddMinutes(6)).Log;
        fine = RecInventory.Apply(fine, f.Request(fine, new RecReceipt(f.Lot, f.Range(1, 4), f.Evidence(), RecReceiptKind.IncomingTransfer)), f.Known.AddMinutes(7)).Log;
        var expectedStates = new[] { RecHoldingState.Retired, RecHoldingState.Available, RecHoldingState.Available, RecHoldingState.Available,
            RecHoldingState.Retired, RecHoldingState.Transferred, RecHoldingState.Transferred, RecHoldingState.Transferred, RecHoldingState.Transferred, RecHoldingState.Retired };
        var fineView = f.View(fine);
        for (var certificate = 0; certificate < expectedStates.Length; certificate++)
        {
            var holding = fineView.Segments.Single(s => s.Range.From <= certificate && s.Range.To > certificate);
            if (holding.State != expectedStates[certificate]) throw new Exception("Range replay differs from the independent per-certificate ownership oracle.");
        }
        Console.WriteLine("PASS REC inventory: evidence-backed range ownership, allocation/transfer/retirement, idempotency and knowledge revisions");
        return 1;
    }
    private static void Count(RecInventoryView view, RecHoldingState state, string expected)
    {
        var count = view.Segments.Where(s => s.State == state).Sum(s => s.Range.To - s.Range.From);
        if (count.ToString(System.Globalization.CultureInfo.InvariantCulture) != expected) throw new Exception($"Expected {expected} {state}; received {count}.");
    }
    private static void Reject(string code, Action action)
    { try { action(); } catch (MarketDataException e) when (e.Code == code) { return; } throw new Exception("Expected " + code); }
    private sealed class Fixture
    {
        public ReferenceRevision References { get; } = new(Guid.NewGuid(), Guid.NewGuid());
        public DateTimeOffset Effective { get; } = DateTimeOffset.Parse("2035-07-01T12:00:00Z");
        public DateTimeOffset Known { get; } = DateTimeOffset.Parse("2035-07-01T13:00:00Z");
        public RecAccountKey Account { get; }
        public RecAccountKey Destination { get; }
        public RecProduct Product { get; }
        public RecLot Lot { get; }
        public RecEligibility Eligible { get; }
        public RecDeliveryKey Delivery { get; } = new(new(Guid.NewGuid(), Guid.NewGuid()), Guid.NewGuid());
        public PartyKey Beneficiary { get; } = new(Guid.NewGuid(), Guid.NewGuid(), 1);
        public ReferenceKey R(string code) => new(References, code);
        public RecRange Range(long from, long to) => new(Lot.Key, from, to);
        public RecEvidence Evidence() => new(R("registry_feed"), Guid.NewGuid());
        public RecInventoryContext Context => new(References, Account, Effective.AddDays(1), Known.AddDays(1), RecInventory.SelectionPolicy);
        public RecInventoryView View(RecInventoryLog log) => RecInventory.Evaluate(log, Context);
        public RecInventoryRequest Request(RecInventoryLog log, RecInventoryAction action) => new(Guid.NewGuid(), Guid.NewGuid(), log.Facts.Length, Effective, action, RecInventory.Implementation);
        public Fixture()
        {
            Account = new(R("registry"), Guid.NewGuid()); Destination = new(R("registry"), Guid.NewGuid());
            Product = new(R("solar_certificate"), R("registry"), R("voluntary_program"), R("solar"), R("synthetic_region"),
                new(R("certificate_quantity"), R("power"), R("generation_certificate"), R("rec"), R("certificate")));
            Lot = new(new(R("registry"), Guid.NewGuid()), Product, new(2035, 6, 1), new(2035, 7, 1));
            Eligible = new(Product, new(2035, 1, 1), new(2036, 1, 1));
        }
    }
}
