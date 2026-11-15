using System.Collections.Immutable;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using Npgsql;
using OpenEtrm.Api;
using OpenEtrm.MarketData;

internal static class GasOperatorQuantityChecks
{
    private static void Endpoint(LifecycleActionRequest request)=>_=request;
    internal static void Contract()
    {
        var schema=AssistantOperations.Schema(typeof(GasOperatorQuantityChecks).GetMethod(nameof(Endpoint),BindingFlags.NonPublic|BindingFlags.Static)!);
        var contracts=schema["body"]!["properties"]!["selection"]!["contracts"]!;
        if(contracts["gas_operator_quantity_reconciliation"] is not JsonObject contract||contract["contract"]!.GetValue<string>()!="GasOperatorQuantitySelection"||
            contract["additionalProperties"]!.GetValue<bool>())
            throw new Exception("The assistant must describe the same closed operator selection consumed by the shared lifecycle action.");
        var selection=JsonSerializer.SerializeToNode(new{implementation="gas_operator_quantity_reconciliation_v1",rootClaimId=Guid.NewGuid(),
            claims=new[]{new{claimId=Guid.NewGuid(),expectedRevision=1,quantity="3",evidenceId=Guid.NewGuid(),sourceAllocation="preserve_unallocated_source_quantity_v1",
                settlements=new[]{new{settlementId=Guid.NewGuid(),expectedRevision=1,quantity="1",evidenceId=Guid.NewGuid(),sourceObservationId=(Guid?)null,
                    expectedReceiptRevision=(int?)null,expectedConsumptionRevision=(int?)null,lotId=(Guid?)null,reservationId=(Guid?)null,sourceAllocation="preserve_unallocated_source_quantity_v1"}}}},
            consumptions=Array.Empty<object>(),cashout=new{ordering="replay_original_settlement_publication_prefix_v1",adjustmentDueAt=(DateTimeOffset?)null},evidence="Synthetic explicit selection"})!;
        _=selection.Deserialize<GasOperatorQuantitySelection>(GasOwnedOperations.Json)??throw new Exception("The explicit nullable operator tuple was refused.");
        var extra=selection.DeepClone();extra["unexpected"]=true;
        var omitted=selection.DeepClone();omitted["claims"]![0]!["settlements"]![0]!.AsObject().Remove("sourceObservationId");
        var nested=selection.DeepClone();nested["cashout"]!["unexpected"]=true;
        foreach(var invalid in new[]{extra,omitted,nested})
        {
            try{_=invalid.Deserialize<GasOperatorQuantitySelection>(GasOwnedOperations.Json);throw new Exception("The operator wire contract silently accepted an unknown field or omitted nullable decision.");}
            catch(JsonException){}
        }
        Console.WriteLine("PASS closed operator command: assistant selection, exact nullable decisions and unknown-field refusal");
    }
    internal static async Task Run(string path)
    {
        using var document=JsonDocument.Parse(File.ReadAllText(path));var fixture=document.RootElement;
        var manifest=fixture.GetProperty("manifest").Deserialize<PreviewManifest>(LifecycleNative.Json)!;
        var host=Path.GetFullPath(fixture.Text("host"));
        if(!host.StartsWith("/private/tmp/oetrm-ref-",StringComparison.Ordinal)&&!host.StartsWith("/tmp/oetrm-ref-",StringComparison.Ordinal))
            throw new Exception("Operator correction checks require an owned disposable PostgreSQL cluster.");
        var login=new NpgsqlConnectionStringBuilder{Host=host,Port=55439,Database="postgres",Username="preview_runtime",Timezone="UTC",Pooling=false};
        await using var database=new PreviewDatabase(manifest,new NpgsqlConnectionStringBuilder(login.ConnectionString){Username="preview_authenticator"},login);
        var context=new LifecycleReadContext(fixture.Id("contextId"),fixture.Instant("at"),new(2020,12,20),Guid.NewGuid());
        var frame=new InputFrame(context.SnapshotId!.Value,"Synthetic operator correction",context.AsOf,context.BusinessDate,[],ImmutableDictionary<string,ImmutableArray<Guid>>.Empty,context.ContextId);
        var operations=new LifecycleOperations(database,id=>id==frame.Id?frame:throw new Exception("The operator correction replaced its selected source frame."));
        var request=new LifecycleActionRequest(fixture.Id("operationId"),context,
            new("gas_operator_quantity_reconciliation",fixture.Id("accountId"),fixture.Id("rootClaimId")),
            "gas.operator.reconcile_quantity",fixture.Id("policyId"),1,false,new('0',64),fixture.GetProperty("selection").Clone());
        var review=await database.WithIdentity("trader",null,(connection,ct)=>operations.Preview(connection,request,ct),default);
        var outcome=review.Details.GetProperty("outcome");
        if(review.Details.Text("quantityUnit")!=fixture.Text("quantityUnit")||review.Details.Text("currency")!=fixture.Text("currency")||
            !review.Details.GetProperty("willChange").GetBoolean()||review.Details.GetProperty("sources").GetArrayLength()!=2||
            outcome.GetProperty("cashChanges").GetArrayLength()!=2)
            throw new Exception("The default registry must review the complete explicit shared-source operator correction.");
        var cash=outcome.GetProperty("cashChanges").EnumerateArray().ToArray();
        if(!cash.Select(row=>row.Text("amount")).Order().SequenceEqual(new[]{"-0.13","0.13"})||
            cash.Any(row=>row.Id("positionId")!=request.Target.BindingId||row.Instant("dueAt")!=fixture.Instant("adjustmentDueAt")))
            throw new Exception("Operator review did not retain the independently rounded dated cash deltas.");
        var selected=outcome.GetProperty("claims").EnumerateArray().Single(row=>row.Id("claimId")==request.Target.BindingId);
        var settlements=selected.GetProperty("settlements").EnumerateArray().ToArray();
        if(!settlements.Select(row=>row.Text("currentQuantity")).SequenceEqual(new[]{"0.875","2.125"})||
            !settlements.Select(row=>row.Text("cashAmount")).SequenceEqual(new[]{"0.88","2.14"}))
            throw new Exception("Operator review lost the original causal settlement order and cumulative rounding.");
        var setup=await database.WithIdentity("trader",null,(connection,ct)=>GasOwnedSetup.Read(connection,database,new(context,request.Target),ct),default);
        var fields=setup.Forms[request.Action].Fields;
        var claims=fields.Single(field=>field.Name=="claims");
        if(setup.Configuration.Count!=0||claims.MinItems!=1||claims.Variants is not {} variants||
            !variants.Any(row=>row.Target.BindingId==request.Target.BindingId)||
            !variants.Any(row=>row.Target.BindingId==fixture.Id("otherClaimId"))||
            fields.Single(field=>field.Name=="cashout").Fields.Single(field=>field.Name=="adjustmentDueAt").Nullable!=true)
            throw new Exception("Operator setup must expose explicit lazy root/peer claims and the nullable dated cash adjustment contract.");
        var claimTarget=claims.Variants!.Value.Single(row=>row.Target.BindingId==request.Target.BindingId).Target;
        var claimSetup=await database.WithIdentity("trader",null,(connection,ct)=>GasOwnedSetup.Read(connection,database,new(context,claimTarget),ct),default);
        var claimFields=claimSetup.Forms[request.Action].Fields;
        var tuple=JsonSerializer.SerializeToElement(claimFields.Single(field=>field.Name=="observedClaim").Choices.Single().Value);
        if(tuple.Id("claimId")!=request.Target.BindingId||tuple.GetProperty("expectedRevision").GetInt32()!=1||tuple.TryGetProperty("quantity",out _)||
            claimFields.Single(field=>field.Name=="quantity").Kind!="text")
            throw new Exception("Selecting an observed claim must pin its revision and require an explicit quantity.");
        var stepVariants=claimFields.Single(field=>field.Name=="settlements").Variants!.Value;
        if(stepVariants.Length!=2)throw new Exception("Operator forms must retain the complete settlement prefix.");
        var stepSetup=await database.WithIdentity("trader",null,(connection,ct)=>GasOwnedSetup.Read(connection,database,new(context,stepVariants[0].Target),ct),default);
        var stepFields=stepSetup.Forms[request.Action].Fields;
        var stepTuple=JsonSerializer.SerializeToElement(stepFields.Single(field=>field.Name=="observedSettlement").Choices.Single().Value);
        if(stepTuple.GetProperty("expectedRevision").GetInt32()!=2||stepTuple.GetProperty("expectedReceiptRevision").ValueKind!=JsonValueKind.Null||
            stepTuple.GetProperty("expectedConsumptionRevision").ValueKind!=JsonValueKind.Null||stepTuple.TryGetProperty("quantity",out _)||
            stepFields.Single(field=>field.Name=="quantity").Kind!="text"||stepFields.Single(field=>field.Name=="sourceObservationId").Choices.Length!=1)
            throw new Exception("Cashout forms must retain exact nullable counterpart revisions and the selected final source without supplying a quantity.");
        var accepted=request with{PreviewHash=review.Hash};
        try
        {
            await database.WithIdentity("trader",null,(connection,ct)=>operations.Execute(connection,accepted with{PreviewHash=new('f',64)},ct),default);
            throw new Exception("Operator correction accepted an unreviewed proposal.");
        }
        catch(MarketDataException error)when(error.Code=="gas_quantity_stale_review"){}
        var first=await database.WithIdentity("trader",null,(connection,ct)=>operations.Execute(connection,accepted,ct),default);
        var evicted=new LifecycleOperations(database,_=>throw new Exception("A retained operator correction receipt reloaded source."));
        var retry=await database.WithIdentity("trader",null,(connection,ct)=>evicted.Execute(connection,accepted,ct),default);
        if(first.Outcome.GetRawText()!=retry.Outcome.GetRawText()||!first.Outcome.GetProperty("changed").GetBoolean())
            throw new Exception("Operator correction did not retain its exact native first outcome.");
        var acknowledgement=await database.WithIdentity("trader",null,(connection,ct)=>evicted.Execute(connection,accepted with{OperationId=Guid.NewGuid()},ct),default);
        if(acknowledgement.Outcome.GetProperty("changed").GetBoolean()||!acknowledgement.Outcome.GetProperty("semanticAcknowledgement").GetBoolean())
            throw new Exception("The existing operator fact created another financial effect.");
        Console.WriteLine("PASS managed operator quantity: default registry, lazy exact claim/settlement forms, shared source, causal rounded cash, stale review and retained first outcomes");
    }
}
