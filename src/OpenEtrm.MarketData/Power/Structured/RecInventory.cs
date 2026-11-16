using System.Collections.Immutable;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.MarketData.Power.Structured;

public readonly record struct RecAccountKey(ReferenceKey Registry, Guid Id);
public readonly record struct RecLotKey(ReferenceKey Registry, Guid Id);
public readonly record struct RecFactKey(Guid Id, int Revision);
public readonly record struct RecDeliveryKey(DefinitionRevision Definitions, Guid Id);
public sealed record RecProduct(ReferenceKey Class, ReferenceKey Registry, ReferenceKey Program,
    ReferenceKey Technology, ReferenceKey Geography, QuantitySpecification Certificates);
public sealed record RecEligibility(RecProduct Product, DateOnly VintageFrom, DateOnly VintageTo);
public sealed record RecLot(RecLotKey Key, RecProduct Product, DateOnly VintageFrom, DateOnly VintageTo);
public sealed record RecRange(RecLotKey Lot, long From, long To);
public sealed record RecEvidence(ReferenceKey Source, Guid Id);

public abstract record RecInventoryAction;
public enum RecReceiptKind { Issuance = 1, IncomingTransfer }
public sealed record RecReceipt(RecLot Lot, RecRange Range, RecEvidence Evidence, RecReceiptKind Kind) : RecInventoryAction;
public sealed record RecAllocation(RecRange Range, RecDeliveryKey Delivery, RecEligibility Eligibility) : RecInventoryAction;
public sealed record RecRelease(RecRange Range, RecFactKey Allocation) : RecInventoryAction;
public sealed record RecTransfer(RecRange Range, RecFactKey Allocation, RecAccountKey Destination, RecEvidence Evidence) : RecInventoryAction;
public sealed record RecRetirement(RecRange Range, PartyKey Beneficiary, ReferenceKey Purpose, RecEvidence Evidence) : RecInventoryAction;

public sealed record RecInventoryFact(RecFactKey Key, DateTimeOffset EffectiveAt, DateTimeOffset KnownAt, RecInventoryAction Action, long BusinessOrder);
public sealed record RecInventoryRequest(Guid RequestId, Guid BusinessId, int ExpectedGeneration,
    DateTimeOffset EffectiveAt, RecInventoryAction Action, string Implementation);
public sealed record RecFactOutcome(RecFactKey Fact, bool IsBusinessNoOp);
public sealed record RecRequestReceipt(RecInventoryRequest Request, RecFactOutcome Outcome);
public sealed record RecInventoryLog(RecAccountKey Account, ImmutableArray<RecInventoryFact> Facts,
    ImmutableArray<RecRequestReceipt> Requests)
{
    public static RecInventoryLog Empty(RecAccountKey account) => new(account, [], []);
}
public sealed record RecInventoryContext(ReferenceRevision References, RecAccountKey Account,
    DateTimeOffset EffectiveAt, DateTimeOffset KnownAt, string SelectionPolicy);
public enum RecHoldingState { Available = 1, Allocated, Transferred, Retired }
public sealed record RecHoldingSegment(RecLot Lot, RecRange Range, RecHoldingState State,
    RecFactKey? Allocation, RecFactKey? Disposition)
{
    public ExactQuantity Quantity => ExactQuantity.FromQuantity(new(ExactDecimal.Parse((Range.To - Range.From).ToString(System.Globalization.CultureInfo.InvariantCulture)), Lot.Product.Certificates.Key));
    public bool Owned => State is RecHoldingState.Available or RecHoldingState.Allocated;
}
public sealed record RecInventoryView(RecInventoryContext Context, ImmutableArray<RecInventoryFact> SelectedFacts,
    ImmutableArray<RecHoldingSegment> Segments);
public sealed record RecApplyResult(RecInventoryLog Log, RecFactOutcome Outcome);

// A pure replay of supplied evidence. Publication certification, authorization,
// persistence and communication with a registry remain the caller's boundary.
public static class RecInventory
{
    public const string Implementation = "rec_inventory_events_v1";
    public const string SelectionPolicy = "latest_knowledge_revision_effective_then_business_order_v2";
    public const int MaximumFacts = 4096;
    public const int MaximumRequests = 8192;
    public static RecApplyResult Apply(RecInventoryLog log, RecInventoryRequest request, DateTimeOffset publishedAt)
    {
        if (log is null || request is null || !Utc(publishedAt) || log.Facts.IsDefault || log.Requests.IsDefault || log.Facts.Any(f => f is null))
            throw Error("rec_context", "Supply an inventory log, explicit command and supported UTC publication coordinate.");
        var references = log.Account.Registry.Revision;
        ValidateRequest(request, references, log.Account);
        var horizon = log.Facts.IsDefaultOrEmpty ? request.EffectiveAt : log.Facts.Select(f => f.EffectiveAt).Append(request.EffectiveAt).Max();
        var context = new RecInventoryContext(references, log.Account, horizon, publishedAt, SelectionPolicy);
        ValidateLog(log, context);
        if (log.Facts.Any(f => f.KnownAt > publishedAt)) throw Error("rec_knowledge", "A publication cannot precede already retained knowledge.");
        Evaluate(log, context);
        var replay = log.Requests.SingleOrDefault(r => r.Request.RequestId == request.RequestId);
        if (replay is not null)
        {
            if (replay.Request != request) throw Error("rec_request_conflict", "A request identity cannot carry a different command.");
            return new(log, replay.Outcome);
        }
        if (log.Requests.Length >= MaximumRequests) throw Error("rec_limit", "The bounded inventory log has reached its request limit.");
        var same = log.Facts.Where(f => f.EffectiveAt == request.EffectiveAt && SameValue(f.Action, request.Action))
            .OrderBy(f => f.KnownAt).ThenBy(f => f.Key.Id).ThenBy(f => f.Key.Revision).FirstOrDefault();
        if (same is not null)
        {
            // Reasserting an older value does not restore it as the head.
            var outcome = new RecFactOutcome(same.Key, true);
            return new(log with { Requests = log.Requests.Add(new(request, outcome)) }, outcome);
        }
        if (request.ExpectedGeneration != log.Facts.Length) throw Error("rec_generation_conflict", "The inventory fact generation changed.");
        if (log.Facts.Length >= MaximumFacts) throw Error("rec_limit", "The bounded inventory log has reached its fact limit.");
        var previous = log.Facts.Where(f => f.Key.Id == request.BusinessId).OrderByDescending(f => f.Key.Revision).FirstOrDefault();
        if (previous is not null && (previous.EffectiveAt != request.EffectiveAt || previous.Action.GetType() != request.Action.GetType() ||
                Range(previous.Action).Lot != Range(request.Action).Lot))
            throw Error("rec_correction", "A revision keeps its original effective occurrence, action kind and lot identity.");
        if (previous is not null && previous.KnownAt > publishedAt) throw Error("rec_knowledge", "A changed business fact cannot precede its retained certified knowledge.");
        var fact = new RecInventoryFact(new(request.BusinessId, previous is null ? 1 : previous.Key.Revision + 1), request.EffectiveAt, publishedAt, request.Action, previous?.BusinessOrder ?? checked(log.Facts.Select(f=>f.BusinessOrder).DefaultIfEmpty(0).Max()+1));
        var applied = new RecFactOutcome(fact.Key, false);
        var next = log with { Facts = log.Facts.Add(fact), Requests = log.Requests.Add(new(request, applied)) };
        // Validate the complete retained effective horizon, including later
        // known commitments, before returning an atomic immutable append.
        Evaluate(next, context);
        return new(next, applied);
    }

    public static RecInventoryView Evaluate(RecInventoryLog log, RecInventoryContext context)
    {
        ValidateLog(log, context);
        // Stable business order is supplied explicitly by the evidence owner.
        // Corrections retain that order; actual certified timestamps can tie.
        // The admitted log carries its certified publication prefix independently
        // of this wall-clock cutoff, so a retained read never invents prior facts.
        var selected = log.Facts.Where(f => f.KnownAt <= context.KnownAt)
            .GroupBy(f => f.Key.Id).Select(g => g.OrderByDescending(f=>f.KnownAt).ThenByDescending(f=>f.Key.Revision).First())
            .Where(f => f.EffectiveAt <= context.EffectiveAt)
            .OrderBy(f => f.EffectiveAt).ThenBy(f => f.BusinessOrder).ToImmutableArray();
        var segments = new List<RecHoldingSegment>();
        foreach (var fact in selected)
        {
            switch (fact.Action)
            {
                case RecReceipt receipt:
                    if (segments.Any(s => s.Range.Lot == receipt.Range.Lot && s.Lot != receipt.Lot))
                        throw Error("rec_eligibility", "A lot cannot carry conflicting product or vintage descriptions.");
                    if (segments.Any(s => Overlap(s.Range, receipt.Range)))
                    {
                        var overlaps = segments.Where(s => Overlap(s.Range, receipt.Range)).ToArray();
                        if (receipt.Kind != RecReceiptKind.IncomingTransfer || overlaps.Any(s => s.State != RecHoldingState.Transferred))
                            throw Error("rec_inventory_overlap", "Issuance cannot repeat certificate identity, and incoming receipts cannot revive owned or retired certificates.");
                        Change(segments, receipt.Range, s => s.State == RecHoldingState.Transferred,
                            s => s with { State = RecHoldingState.Available, Allocation = null, Disposition = null });
                    }
                    else segments.Add(new(receipt.Lot, receipt.Range, RecHoldingState.Available, null, null));
                    break;
                case RecAllocation allocation:
                    Change(segments, allocation.Range, s =>
                    {
                        if (!Eligible(s.Lot, allocation.Eligibility)) throw Error("rec_eligibility", "The owned lot does not satisfy the selected delivery's exact product and vintage.");
                        return s.State == RecHoldingState.Available;
                    }, s => s with { State = RecHoldingState.Allocated, Allocation = fact.Key, Disposition = null });
                    break;
                case RecRelease release:
                    Change(segments, release.Range, s => s.State == RecHoldingState.Allocated && s.Allocation == release.Allocation,
                        s => s with { State = RecHoldingState.Available, Allocation = null, Disposition = null });
                    break;
                case RecTransfer transfer:
                    Change(segments, transfer.Range, s => s.State == RecHoldingState.Allocated && s.Allocation == transfer.Allocation,
                        s => s with { State = RecHoldingState.Transferred, Disposition = fact.Key });
                    break;
                case RecRetirement retirement:
                    Change(segments, retirement.Range, s => s.State == RecHoldingState.Available,
                        s => s with { State = RecHoldingState.Retired, Allocation = null, Disposition = fact.Key });
                    break;
                default: throw Error("rec_action", "The inventory action is unsupported.");
            }
        }
        return new(context, selected, [.. segments.OrderBy(s => s.Range.Lot.Id).ThenBy(s => s.Range.From)]);
    }

    private static void Change(List<RecHoldingSegment> segments, RecRange range, Func<RecHoldingSegment, bool> permitted,
        Func<RecHoldingSegment, RecHoldingSegment> change)
    {
        var selected = segments.Where(s => Overlap(s.Range, range)).ToArray();
        if (selected.Sum(s => Math.Min(s.Range.To, range.To) - Math.Max(s.Range.From, range.From)) != range.To - range.From ||
            selected.Any(s => !permitted(s)))
            throw Error("rec_inventory_unavailable", "The complete certificate range must have the required owned/allocation state.");
        foreach (var segment in selected)
        {
            segments.Remove(segment);
            var from = Math.Max(segment.Range.From, range.From); var to = Math.Min(segment.Range.To, range.To);
            if (segment.Range.From < from) segments.Add(segment with { Range = segment.Range with { To = from } });
            segments.Add(change(segment with { Range = segment.Range with { From = from, To = to } }));
            if (to < segment.Range.To) segments.Add(segment with { Range = segment.Range with { From = to } });
        }
    }

    private static void ValidateLog(RecInventoryLog log, RecInventoryContext context)
    {
        if (log is null || context is null || context.SelectionPolicy != SelectionPolicy || context.Account != log.Account ||
            context.References.CatalogId == Guid.Empty || context.References.RevisionId == Guid.Empty ||
            !Utc(context.EffectiveAt) || !Utc(context.KnownAt) || log.Account.Id == Guid.Empty ||
            !Reference(log.Account.Registry, context.References) || log.Facts.IsDefault || log.Requests.IsDefault)
            throw Error("rec_context", "Supply the exact account, reference revision and explicit effective/knowledge selection policy.");
        if (log.Facts.Length > MaximumFacts || log.Requests.Length > MaximumRequests) throw Error("rec_limit", "The inventory log exceeds its bounded input size.");
        if (log.Facts.Any(f => f is null || f.Key.Id == Guid.Empty || f.Key.Revision <= 0 || f.BusinessOrder<=0 || f.BusinessOrder==long.MaxValue || !Utc(f.EffectiveAt) || !Utc(f.KnownAt)) ||
            log.Facts.Select(f => f.Key).Distinct().Count() != log.Facts.Length)
            throw Error("rec_fact", "Facts need unique exact revision identities and supported temporal coordinates.");
        foreach (var fact in log.Facts) ValidateAction(fact.Action, context.References, log.Account);
        if(log.Facts.GroupBy(f=>f.Key.Id).Select(g=>g.First().BusinessOrder).Distinct().Count()!=log.Facts.Select(f=>f.Key.Id).Distinct().Count())
            throw Error("rec_fact","Distinct business occurrences require distinct explicit stable order within an account.");
        foreach (var group in log.Facts.GroupBy(f => f.Key.Id))
        {
            var versions = group.OrderBy(f => f.Key.Revision).ToArray();
            for (var i = 0; i < versions.Length; i++)
            {
                if (versions[i].Key.Revision != i + 1 || i > 0 && versions[i].KnownAt < versions[i - 1].KnownAt)
                    throw Error("rec_knowledge", "Business facts require complete revision lineage with nondecreasing certified knowledge.");
                if (versions[i].BusinessOrder!=versions[0].BusinessOrder || versions[i].EffectiveAt != versions[0].EffectiveAt || versions[i].Action.GetType() != versions[0].Action.GetType() ||
                    Range(versions[i].Action).Lot != Range(versions[0].Action).Lot)
                    throw Error("rec_correction", "A business occurrence retains its original effective coordinate, action kind and lot identity.");
            }
        }
        if (log.Requests.Any(r => r is null || r.Request is null || r.Outcome is null) ||
            log.Requests.Select(r => r.Request.RequestId).Distinct().Count() != log.Requests.Length)
            throw Error("rec_request_conflict", "Request receipts must be distinct and complete.");
        foreach (var receipt in log.Requests)
        {
            ValidateRequest(receipt.Request, context.References, log.Account);
            var fact=log.Facts.SingleOrDefault(f=>f.Key==receipt.Outcome.Fact);
            if(fact is null)throw Error("rec_fact", "A request outcome must point to an exact retained fact revision.");
            if(fact.EffectiveAt!=receipt.Request.EffectiveAt||!SameValue(fact.Action,receipt.Request.Action)||
                !receipt.Outcome.IsBusinessNoOp&&fact.Key.Id!=receipt.Request.BusinessId)
                throw Error("rec_request_conflict","A request receipt must retain the original effective business value and its actual fact outcome.");
        }
    }
    private static void ValidateRequest(RecInventoryRequest request, ReferenceRevision references, RecAccountKey account)
    {
        if (request is null || request.Implementation != Implementation || request.RequestId == Guid.Empty || request.BusinessId == Guid.Empty ||
            request.ExpectedGeneration < 0 || !Utc(request.EffectiveAt))
            throw Error("rec_request", "Supply an exact request/business identity, expected generation, effective coordinate and implementation.");
        ValidateAction(request.Action, references, account);
    }
    private static void ValidateAction(RecInventoryAction action, ReferenceRevision references, RecAccountKey account)
    {
        var range = Range(action);
        if (range is null || range.Lot.Id == Guid.Empty || range.Lot.Registry != account.Registry || range.From < 0 || range.To <= range.From)
            throw Error("rec_range", "Supply a nonempty exact certificate sequence range in this account's registry.");
        switch (action)
        {
            case RecReceipt receipt:
                if (receipt.Lot is null || receipt.Lot.Key != range.Lot || !Enum.IsDefined(receipt.Kind))
                    throw Error("rec_fact", "A received range must refer to its exact supplied lot and explicit issuance/incoming-transfer kind.");
                Product(receipt.Lot.Product, references, account.Registry); Vintage(receipt.Lot.VintageFrom, receipt.Lot.VintageTo); Evidence(receipt.Evidence, references);
                break;
            case RecAllocation allocation:
                if (allocation.Delivery.Id == Guid.Empty || allocation.Delivery.Definitions.CatalogId == Guid.Empty || allocation.Delivery.Definitions.RevisionId == Guid.Empty || allocation.Eligibility is null)
                    throw Error("rec_eligibility", "An allocation needs exact delivery and eligibility versions.");
                Product(allocation.Eligibility.Product, references, account.Registry); Vintage(allocation.Eligibility.VintageFrom, allocation.Eligibility.VintageTo);
                break;
            case RecRelease release: Allocation(release.Allocation); break;
            case RecTransfer transfer:
                Allocation(transfer.Allocation); Evidence(transfer.Evidence, references);
                if (transfer.Destination.Id == Guid.Empty || transfer.Destination.Registry != account.Registry || transfer.Destination == account)
                    throw Error("rec_account", "A confirmed transfer needs a distinct exact destination account in the same registry.");
                break;
            case RecRetirement retirement:
                Evidence(retirement.Evidence, references);
                if (retirement.Beneficiary.CatalogId == Guid.Empty || retirement.Beneficiary.Id == Guid.Empty || retirement.Beneficiary.Revision <= 0 || !Reference(retirement.Purpose, references))
                    throw Error("rec_retirement", "Retirement needs an exact beneficiary version and purpose reference.");
                break;
            default: throw Error("rec_action", "The inventory action is unsupported.");
        }
    }
    private static void Product(RecProduct product, ReferenceRevision references, ReferenceKey registry)
    {
        if (product is null || product.Certificates is null || product.Registry != registry || product.Certificates.Unit.Code != "rec" ||
            new[] { product.Class, product.Registry, product.Program, product.Technology, product.Geography, product.Certificates.Key,
                product.Certificates.Commodity, product.Certificates.MeasurementBasis, product.Certificates.Unit, product.Certificates.Dimension }.Any(k => !Reference(k, references)))
            throw Error("rec_eligibility", "Certificate product, registry, program, technology, geography and quantity require exact selected references.");
    }
    private static void Evidence(RecEvidence evidence, ReferenceRevision references)
    { if (evidence is null || evidence.Id == Guid.Empty || !Reference(evidence.Source, references)) throw Error("rec_evidence", "A receipt, transfer or retirement requires exact supplied evidence."); }
    private static void Vintage(DateOnly from, DateOnly to)
    { if (from.Year < 1901 || to.Year > 2199 || from >= to) throw Error("rec_eligibility", "Generation vintage is an explicit supported half-open date window."); }
    private static void Allocation(RecFactKey allocation)
    { if (allocation.Id == Guid.Empty || allocation.Revision <= 0) throw Error("rec_fact", "Select an exact allocation revision."); }
    private static bool Eligible(RecLot lot, RecEligibility eligibility) => lot.Product == eligibility.Product && lot.VintageFrom >= eligibility.VintageFrom && lot.VintageTo <= eligibility.VintageTo;
    private static bool Reference(ReferenceKey key, ReferenceRevision revision) => key.Revision == revision && !string.IsNullOrWhiteSpace(key.Code);
    private static bool Utc(DateTimeOffset at) => at.Offset == TimeSpan.Zero && at.Ticks % 10 == 0 && at < new DateTimeOffset(9999, 12, 31, 0, 0, 0, TimeSpan.Zero);
    private static bool Overlap(RecRange first, RecRange second) => first.Lot == second.Lot && first.From < second.To && second.From < first.To;
    private static RecRange Range(RecInventoryAction action) => action switch
    {
        RecReceipt receipt => receipt.Range, RecAllocation allocation => allocation.Range, RecRelease release => release.Range,
        RecTransfer transfer => transfer.Range, RecRetirement retirement => retirement.Range,
        _ => throw Error("rec_action", "Supply an implemented inventory action.")
    };
    private static bool SameValue(RecInventoryAction left, RecInventoryAction right) => (left, right) switch
    {
        (RecReceipt a, RecReceipt b) => a.Lot == b.Lot && a.Range == b.Range && a.Kind == b.Kind,
        (RecAllocation a, RecAllocation b) => a.Range == b.Range && a.Delivery == b.Delivery && a.Eligibility == b.Eligibility,
        (RecRelease a, RecRelease b) => a.Range == b.Range && a.Allocation == b.Allocation,
        (RecTransfer a, RecTransfer b) => a.Range == b.Range && a.Allocation == b.Allocation && a.Destination == b.Destination,
        (RecRetirement a, RecRetirement b) => a.Range == b.Range && a.Beneficiary == b.Beneficiary && a.Purpose == b.Purpose,
        _ => false
    };
    private static MarketDataException Error(string code, string message) => new(code, message);
}
