using System.Text.Json;
using System.Text.Json.Nodes;
using OpenEtrm.Api;
using OpenEtrm.MarketData;

internal static class PointTraderMarkReceiptChecks
{
    internal static void Run()
    {
        var catalog=Guid.NewGuid();var operation=Guid.NewGuid();var observation=Guid.NewGuid();var previous=Guid.NewGuid();
        var point=new PointTraderMarkPoint(catalog,Guid.NewGuid(),Guid.NewGuid(),"synthetic_marks",DateTimeOffset.Parse("2020-12-19T16:00:00Z"));
        var sourceEvent="synthetic-imported-event";
        var target=new PointTraderMarkTarget(point.DefinitionRevisionId,Guid.NewGuid(),Guid.NewGuid(),"synthetic_curve",Guid.NewGuid(),point.SeriesId,
            point.Source,"synthetic_quote","2020-12-19T16:00:00Z",sourceEvent,PointTraderMarkIdentity.Revision(point,sourceEvent,previous),previous);
        var command=PointTraderMarkCommands.Normalize(catalog,JsonSerializer.SerializeToElement(new PointTraderMarkCommand(
            PointTraderMarkCommands.Policy,target,"20","Synthetic evidence",null),PointTraderMarkCommands.Json));
        JsonObject Outcome(bool changed=true)=>JsonSerializer.SerializeToNode(new{
            operationId=operation,observationId=observation,changed,target.DefinitionRevisionId,target.ReferenceCatalogId,target.ReferenceRevisionId,target.ContractId,
            target.SeriesId,target.Source,target.Quote,target.ObservedAt,target.SourceEventId,sourceRevisionId=target.SourceRevisionToken,
            previousObservationId=previous,value="20",knowledgeEventOrder=15,publicationXid="789"},PointTraderMarkCommands.Json)!.AsObject();
        void Require(JsonObject outcome)=>PointTraderMarkReceipts.Require(catalog,operation,command,JsonSerializer.SerializeToElement(outcome));
        Require(Outcome());Require(Outcome(false));
        var noop=Outcome(false);noop["observationId"]=previous;noop["sourceRevisionId"]="opaque-imported-revision";noop["previousObservationId"]=null;Require(noop);
        foreach(var field in new[]{"operationId","observationId","definitionRevisionId","referenceCatalogId","referenceRevisionId","contractId","seriesId"})
        {var wrong=Outcome();wrong[field]=Guid.NewGuid();if(field=="observationId")wrong[field]=Guid.Empty;Reject(()=>Require(wrong));}
        foreach(var field in new[]{"source","quote","sourceEventId","sourceRevisionId","observedAt","value","publicationXid"})
        {var wrong=Outcome();wrong[field]="synthetic-other";Reject(()=>Require(wrong));}
        var stale=Outcome();stale["previousObservationId"]=null;Reject(()=>Require(stale));
        var fakeChanged=noop.DeepClone().AsObject();fakeChanged["changed"]=true;Reject(()=>Require(fakeChanged));
        var fakeNoop=noop.DeepClone().AsObject();fakeNoop["observationId"]=Guid.NewGuid();Reject(()=>Require(fakeNoop));
        foreach(var order in new[]{0,-1}){var wrong=Outcome();wrong["knowledgeEventOrder"]=order;Reject(()=>Require(wrong));}
        Console.WriteLine("PASS point receipt: exact point, amount, real publication identity and distinct predecessor acknowledgement relations");
    }
    static void Reject(Action action)
    {
        try{action();throw new Exception("A conflicting or unattested point receipt was accepted.");}
        catch(MarketDataException error)when(error.Code=="point_trader_mark_source"){}
    }
}
