using System.Text.Json;
using System.Text.Json.Nodes;
using OpenEtrm.Api;
using OpenEtrm.MarketData;

internal static class PointTraderMarkCommandChecks
{
    internal static void Run()
    {
        var catalog=Guid.Parse("11111111-1111-1111-1111-111111111111");
        var point=new PointTraderMarkPoint(catalog,Guid.Parse("22222222-2222-2222-2222-222222222222"),
            Guid.Parse("33333333-3333-3333-3333-333333333333"),"synthetic_marks",DateTimeOffset.Parse("2020-12-19T16:00:00Z"));
        var sourceEvent=PointTraderMarkIdentity.Event(point);
        var target=new PointTraderMarkTarget(point.DefinitionRevisionId,Guid.NewGuid(),Guid.NewGuid(),"synthetic_rights",Guid.NewGuid(),point.SeriesId,
            point.Source,"synthetic_quote","2020-12-19T16:00:00Z",sourceEvent,PointTraderMarkIdentity.Revision(point,sourceEvent,null),null);
        JsonElement Body(string value="20.00",PointTraderMarkTarget? selected=null)=>JsonSerializer.SerializeToElement(
            new PointTraderMarkCommand(PointTraderMarkCommands.Policy,selected??target,value,"  Synthetic publication evidence  ",null),PointTraderMarkCommands.Json);
        var canonical=PointTraderMarkCommands.Normalize(catalog,Body());
        if(canonical.Text("value")!="20"||canonical.Text("evidence")!="Synthetic publication evidence"||
            canonical.GetProperty("target").Text("observedAt")!="2020-12-19T16:00:00.000000Z"||
            canonical.GetProperty("originalInputs").ValueKind!=JsonValueKind.Null)
            throw new Exception("A point command must normalize exact value, time and ASCII-padded evidence while retaining explicit absent input provenance.");
        foreach(var value in new[]{"0","-20.00","0.000000000000000001"})
            if(PointTraderMarkCommands.Normalize(catalog,Body(value)).Text("value")!=ExactDecimal.Parse(value).ToString())
                throw new Exception("Explicit zero and signed values must remain exact strings without a default or implicit rounding.");
        foreach(var value in new[]{"","+20","1e2","01","0.0000000000000000001","1000000000000000000000000"})
            Reject(()=>PointTraderMarkCommands.Normalize(catalog,Body(value)));
        var previous=Guid.NewGuid();var imported=" synthetic:é🙂:event ";
        var correction=target with{ExpectedPreviousObservationId=previous,SourceEventId=imported,
            SourceRevisionToken=PointTraderMarkIdentity.Revision(point,imported,previous)};
        if(PointTraderMarkCommands.Normalize(catalog,Body("20",correction)).GetProperty("target").Text("sourceEventId")!=imported)
            throw new Exception("An imported event identity must remain opaque and byte-exact.");
        Reject(()=>PointTraderMarkCommands.Normalize(catalog,Body(selected:target with{SourceEventId=imported})));
        Reject(()=>PointTraderMarkCommands.Normalize(catalog,Body(selected:target with{SourceRevisionToken="manual_point_revision_v1:"+new string('0',64)})));
        Reject(()=>PointTraderMarkCommands.Normalize(catalog,Body(selected:target with{ObservedAt="2020-12-19T16:00:00.0000001Z"})));
        Reject(()=>PointTraderMarkCommands.Normalize(catalog,Body(selected:target with{ReferenceRevisionId=Guid.Empty})));
        foreach(var field in new[]{"originalInputs","evidence","value","policy","target"})
        {
            var missing=JsonNode.Parse(Body().GetRawText())!.AsObject();missing.Remove(field);
            Reject(()=>PointTraderMarkCommands.Normalize(catalog,JsonSerializer.SerializeToElement(missing)));
        }
        var missingPrevious=JsonNode.Parse(Body().GetRawText())!.AsObject();missingPrevious["target"]!.AsObject().Remove("expectedPreviousObservationId");
        Reject(()=>PointTraderMarkCommands.Normalize(catalog,JsonSerializer.SerializeToElement(missingPrevious)));
        var extra=JsonNode.Parse(Body().GetRawText())!.AsObject();extra["amount"]=20;
        Reject(()=>PointTraderMarkCommands.Normalize(catalog,JsonSerializer.SerializeToElement(extra)));
        var numeric=JsonNode.Parse(Body().GetRawText())!.AsObject();numeric["value"]=20;
        Reject(()=>PointTraderMarkCommands.Normalize(catalog,JsonSerializer.SerializeToElement(numeric)));
        Console.WriteLine("PASS point publication command: explicit closed fields, exact signed decimal strings, deterministic prospective pins and opaque imported events");
    }
    static void Reject(Action action)
    {
        try{action();throw new Exception("An incomplete or conflicting point publication command was accepted.");}
        catch(MarketDataException error)when(error.Code=="point_trader_mark_input"){}
    }
}
