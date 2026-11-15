using System.Collections.Immutable;
using System.Text.Json;
using Npgsql;
using OpenEtrm.MarketData.Gas;

namespace OpenEtrm.Api;

internal static partial class GasOwnedSetup
{
    private static async Task<GasSetup> OperatorQuantitySetup(NpgsqlConnection connection,PreviewDatabase database,LifecycleDiscoveryRequest request,CancellationToken ct)
    {
        var target=request.Target!;var context=request.Context;
        var claimId=target.Handler is GasOperatorQuantityActions.Handler or GasOperatorQuantityActions.ClaimSourceHandler?target.BindingId:target.ScopeId;
        var source=await GasOperatorQuantityActions.ReadSource(connection,database,context,claimId,ct);
        var accountId=source.Id("accountId");
        if((target.Handler is GasOperatorQuantityActions.Handler or GasOperatorQuantityActions.ClaimSourceHandler)&&target.ScopeId!=accountId)
            throw GasOwnedOperations.Error("Retain this exact operator account and claim.");
        var state=await GasOwnedOperations.Read(connection,database,context,accountId,ct);
        var account=state.GetProperty("accounts").EnumerateArray().Single(row=>row.Id("id")==accountId);
        var policies=await PreviewDatabase.Rows(connection,"SELECT row_to_json(p)::text FROM lifecycle.action_policies p WHERE p.catalog_id=$1 AND p.action=$2 ORDER BY p.id,p.revision",
            [database.Manifest.CatalogId,GasOperatorQuantityActions.Action],ct);
        var choices=state.GetProperty("policies").EnumerateArray().Where(row=>row.Id("account_id")==accountId&&row.Text("action")==GasOperatorQuantityActions.Action)
            .OrderByDescending(row=>Int(row,"revision")).Take(1).Select(binding=>
            {
                var policy=policies.Single(row=>row.Id("id")==binding.Id("policy_id")&&Int(row,"revision")==Int(binding,"policy_revision"));
                return new GasFormPolicy(policy.Id("id").ToString(),"Manual operator correction · revision "+Int(policy,"revision"),Int(policy,"revision"),GasOperatorQuantityActions.Action,accountId.ToString());
            }).ToImmutableArray();
        JsonElement? known=null;JsonElement? ordinary=null;
        if(target.Handler==GasOperatorQuantityActions.ConsumptionSourceHandler||target.Handler==GasOperatorQuantityActions.SettlementSourceHandler&&
            source.GetProperty("settlements").EnumerateArray().Any(row=>row.Id("id")==target.BindingId&&row.GetProperty("consumptionId").ValueKind!=JsonValueKind.Null))
        {
            var books=source.GetProperty("accounts").EnumerateArray().Select(row=>row.Id("book_id")).Distinct().ToArray();
            known=await LifecycleNative.Read(connection,"SELECT security.read_gas_owned_known_history($1,$2,$3,$4::uuid[])::text",ct,
                database.Manifest.CatalogId,context.ContextId,context.AsOf,books);
            if(target.Handler==GasOperatorQuantityActions.ConsumptionSourceHandler)
            {
                var use=source.GetProperty("consumptions").EnumerateArray().SingleOrDefault(row=>row.Id("id")==target.BindingId);
                if(use.ValueKind!=JsonValueKind.Object||!use.GetProperty("editable").GetBoolean())
                    throw GasOwnedOperations.Error("Select an exact editable ordinary use in this operator claim's dependency source.");
                var owner=source.GetProperty("positions").EnumerateArray().Single(row=>row.Id("id")==use.Id("lotId")).Id("account_id");
                ordinary=await GasOwnedQuantityReconciliationActions.ReadChoices(connection,database,context,owner,ct);
            }
        }
        var form=OperatorQuantityForm(context,target,state,source,known,ordinary);
        return new(context,[Choice(accountId.ToString(),account.Text("code"),accountId)],choices,
            ImmutableDictionary<string,GasForm>.Empty.Add(GasOperatorQuantityActions.Action,form),ImmutableDictionary<string,GasForm>.Empty){Target=target};
    }

    private static GasForm OperatorQuantityForm(LifecycleReadContext context,LifecycleTarget target,JsonElement state,JsonElement source,JsonElement? known,JsonElement? ordinary)
    {
        const string action=GasOperatorQuantityActions.Action;
        var claim=source.GetProperty("claim");var accountId=source.Id("accountId");var claimId=claim.Id("id");
        var account=source.GetProperty("accounts").EnumerateArray().Single(row=>row.Id("id")==accountId);
        var evidence=source.GetProperty("evidence").EnumerateArray().ToArray();
        JsonElement Document(Guid id)=>evidence.Single(row=>row.Id("id")==id);
        string DocumentName(Guid id)=>Document(id).Text("source_key");
        var parent=account.Text("code")+" · "+DocumentName(claim.Id("evidenceId"))+" · "+claimId;
        GasFormField Reference(string name,string label,string[] members,ImmutableArray<GasFormChoice> values)=>new(name,label,"reference",false,values,[],[..members]);
        GasFormField Select(string name,string label,bool nullable,ImmutableArray<GasFormChoice> values)=>new(name,label,"select",nullable,values,[],[]);
        GasFormField Quantity()=>new("quantity","Explicit corrected quantity ("+account.Text("quantity_code")+")","text",false,[],[],[]);
        GasFormField Allocation()=>Select("sourceAllocation","Source allocation contract",false,[
            Choice(GasSourceAllocation.Preserve,"Preserve unused source quantity",GasSourceAllocation.Preserve),
            Choice(GasSourceAllocation.Withdraw,"Withdraw all source allocations",GasSourceAllocation.Withdraw)]);
        GasFormField Evidence(Guid appliedId,DateTimeOffset at)
        {
            var applied=Document(appliedId);
            return Select("evidenceId","Exact source revision",false,[..evidence.Where(row=>row.GetProperty("capturedHead").GetBoolean()&&
                row.Id("account_id")==applied.Id("account_id")&&row.Text("source_key")==applied.Text("source_key")&&
                row.Text("kind")==applied.Text("kind")&&row.Instant("occurred_at")==at).Select(row=>Choice(row.Id("id").ToString(),
                    $"{row.Text("source_key")} · revision {Int(row,"revision")} · document quantity {row.Text("quantity")}",row.Id("id")))]);
        }
        if(target.Handler==GasOperatorQuantityActions.Handler)
        {
            var claims=state.GetProperty("positions").EnumerateArray().Where(row=>row.Id("account_id")==accountId&&row.Text("kind")=="operator_claim");
            var documents=state.GetProperty("evidence").EnumerateArray().ToDictionary(row=>row.Id("id"));
            var uses=source.GetProperty("consumptions").EnumerateArray().Where(row=>row.GetProperty("editable").GetBoolean());
            return new("Correct operator quantity or cashout","RecordGasOwnedHoldings",[
                Select("implementation","Correction contract",false,[Choice(GasOperatorQuantityActions.Version,"Keep recorded claims, settlements and original cash",GasOperatorQuantityActions.Version)]),
                Select("rootClaimId","Selected operator claim",false,[Choice(claimId.ToString(),parent,claimId)]),
                new GasFormField("claims","Claim and complete settlement corrections","array",false,[],[],[]){MinItems=1,MemberLabel="Operator claim",Variants=[..claims.Select(row=>
                    new GasFormVariant(row.Id("id").ToString(),$"{documents[row.Id("evidence_id")].Text("source_key")} · quantity {row.Text("quantity")} {account.Text("quantity_code")} · {row.Id("id")}",new(GasOperatorQuantityActions.ClaimSourceHandler,accountId,row.Id("id")),parent){Action=action})]},
                new GasFormField("consumptions","Related ordinary stock use corrections","array",false,[],[],[]){MemberLabel="Recorded ordinary use",Variants=[..uses.Select(row=>
                    new GasFormVariant(row.Id("id").ToString(),$"{Words(row.Text("kind"))} · {DocumentName(row.Id("evidenceId"))} · quantity {row.Text("quantity")}",
                        new(GasOperatorQuantityActions.ConsumptionSourceHandler,claimId,row.Id("id")),parent){Action=action})]},
                new("cashout","Cashout adjustment terms","object",false,[],[
                    Select("ordering","Settlement order",false,[Choice(GasOperatorQuantityActions.SettlementOrder,"Keep original recorded settlement order and cumulative rounding",GasOperatorQuantityActions.SettlementOrder)]),
                    new("adjustmentDueAt","Adjustment due (choose Not applicable when no cashout is selected)","instant",true,[],[],[])],[]),
                new("evidence","Correction evidence reference","text",false,[],[],[])]);
        }
        if(target.Handler==GasOperatorQuantityActions.ClaimSourceHandler)
            return new("Correct operator claim","RecordGasOwnedHoldings",[
                Reference("observedClaim","Observed claim revision",["claimId","expectedRevision"],[Choice(claimId.ToString(),parent+$" · revision {Int(claim,"expectedRevision")}",new{claimId,expectedRevision=Int(claim,"expectedRevision")})]),
                Quantity(),Evidence(claim.Id("evidenceId"),claim.Instant("effective_at")),Allocation(),
                new GasFormField("settlements","Complete recorded settlement prefix","array",false,[],[],[]){MinItems=source.GetProperty("settlements").GetArrayLength(),MemberLabel="Recorded settlement",
                    Variants=[..source.GetProperty("settlements").EnumerateArray().Select(row=>new GasFormVariant(row.Id("id").ToString(),
                        $"Recorded settlement · quantity {row.Text("quantity")} · revision {Int(row,"expectedRevision")} · {row.Id("id")}",
                        new(GasOperatorQuantityActions.SettlementSourceHandler,claimId,row.Id("id")),parent){Action=action})]}]);
        if(target.Handler==GasOperatorQuantityActions.ConsumptionSourceHandler)
        {
            var use=source.GetProperty("consumptions").EnumerateArray().Single(row=>row.Id("id")==target.BindingId);
            var owner=source.GetProperty("positions").EnumerateArray().Single(row=>row.Id("id")==use.Id("lotId")).Id("account_id");
            return QuantityForms(context,new(GasOwnedQuantityReconciliationActions.ConsumptionSourceHandler,owner,target.BindingId),
                ordinary??throw GasOwnedOperations.Error("Read the exact ordinary use choices."),known??throw GasOwnedOperations.Error("Read the exact resource history."))[GasOwnedQuantityReconciliationActions.Action];
        }
        if(target.Handler!=GasOperatorQuantityActions.SettlementSourceHandler)throw GasOwnedOperations.Error("Select a supported operator correction source.");
        var step=source.GetProperty("settlements").EnumerateArray().SingleOrDefault(row=>row.Id("id")==target.BindingId);
        if(step.ValueKind!=JsonValueKind.Object)throw GasOwnedOperations.Error("Select one exact settlement of this operator claim.");
        int? Revision(string name)=>step.GetProperty(name).ValueKind==JsonValueKind.Null?null:Int(step,name);
        var stockChoices=ImmutableArray.CreateBuilder<GasFormChoice>();
        if(step.GetProperty("consumptionId").ValueKind==JsonValueKind.Null)
            stockChoices.Add(Choice("none","No funding stock or reservation",new{lotId=(Guid?)null,reservationId=(Guid?)null}));
        else
        {
            var history=known??throw GasOwnedOperations.Error("Read this settlement's exact funding stock history.");
            var use=source.GetProperty("consumptions").EnumerateArray().Single(row=>row.Id("id")==step.Id("consumptionId"));
            var positions=history.GetProperty("positions").EnumerateArray().ToDictionary(row=>row.Id("id"));
            var owner=positions[use.Id("lotId")].Id("account_id");var at=step.Instant("effectiveAt");
            var reservations=history.GetProperty("reservations").EnumerateArray().ToArray();var releases=history.GetProperty("releases").EnumerateArray().ToArray();
            foreach(var lot in history.GetProperty("lots").EnumerateArray())
            {
                var position=positions[lot.Id("id")];
                if(position.Id("account_id")!=owner||position.Text("kind")!="owned_stock"||lot.Instant("available_at")>at||
                    lot.Id("id")!=use.Id("lotId")&&position.Number("quantity").CompareTo(default)<=0)continue;
                var label=lot.Id("id").ToString();
                stockChoices.Add(Choice(label+":none",label+" · no reservation",new{lotId=(Guid?)lot.Id("id"),reservationId=(Guid?)null}));
                foreach(var reservation in reservations.Where(row=>row.Id("lot_id")==lot.Id("id")&&row.Instant("effective_at")<=at&&
                    !releases.Any(release=>release.Id("reservation_id")==row.Id("id")&&release.Instant("effective_at")<=at)))
                    stockChoices.Add(Choice(label+":"+reservation.Id("id"),label+" · reservation "+reservation.Text("business_key"),new{lotId=(Guid?)lot.Id("id"),reservationId=(Guid?)reservation.Id("id")}));
            }
        }
        var cashout=step.GetProperty("sourceObservationId").ValueKind!=JsonValueKind.Null;
        var observationChoices=ImmutableArray.CreateBuilder<GasFormChoice>();
        if(cashout)
        {
            var applied=source.GetProperty("observations").EnumerateArray().Single(row=>row.Id("id")==step.Id("sourceObservationId"));
            foreach(var row in source.GetProperty("observations").EnumerateArray().Where(row=>row.GetProperty("capturedHead").GetBoolean()&&row.Text("publication_state")=="final"&&
                row.Id("definition_revision_id")==applied.Id("definition_revision_id")&&row.Id("series_id")==applied.Id("series_id")&&
                row.Text("source_code")==applied.Text("source_code")&&row.Text("role")==applied.Text("role")&&row.Instant("observed_at")==applied.Instant("observed_at")))
                observationChoices.Add(Choice(row.Id("id").ToString(),$"{row.Text("source_code")} · {Words(row.Text("role"))} · price {row.Text("value")}",row.Id("id")));
        }
        return new("Correct recorded operator settlement","RecordGasOwnedHoldings",[
            Reference("observedSettlement","Observed settlement and counterpart revisions",["settlementId","expectedRevision","expectedReceiptRevision","expectedConsumptionRevision"],
                [Choice(step.Id("id").ToString(),$"{parent} · settlement revision {Int(step,"expectedRevision")}",new{settlementId=step.Id("id"),expectedRevision=Int(step,"expectedRevision"),expectedReceiptRevision=Revision("receiptRevision"),expectedConsumptionRevision=Revision("consumptionRevision")})]),
            Quantity(),Evidence(step.Id("evidenceId"),step.Instant("effectiveAt")),
            Select("sourceObservationId","Final cashout price source",!cashout,observationChoices.ToImmutable()),
            Reference("identifiedStock","Funding stock and reservation",["lotId","reservationId"],stockChoices.ToImmutable()),Allocation()]);
    }
}
