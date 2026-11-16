using System.Text.Json;
using OpenEtrm.Api;
using OpenEtrm.MarketData;

internal static class GasParkLoanActionChecks
{
    internal static void Run()
    {
        var id=Guid.Parse("a1000000-0000-0000-0000-000000000101");
        var at=new DateTimeOffset(2031,1,2,12,0,0,TimeSpan.Zero);
        var request=new LifecycleActionRequest(id,new(id,at,new(2031,1,2)),new(GasParkLoanActions.Handler,id,id),GasParkLoanActions.Advance,id,1,false,new('0',64),
            JsonSerializer.SerializeToElement(new{expectedVersion=4,agreementEvidenceId=id.ToString().ToUpperInvariant(),evidenceId=id,
                claimEvidenceId=(Guid?)null,lotId=(Guid?)null,reservationId=(Guid?)null,effectiveAt="2031-01-02T12:00:00.1234560+00:00"}));
        var normalized=GasParkLoanActions.Normalize(request);
        if(normalized.Selection.GetProperty("effectiveAt").GetString()!="2031-01-02T12:00:00.123456Z"||
            normalized.Selection.GetProperty("agreementEvidenceId").GetString()!=id.ToString()||
            normalized.Selection.GetProperty("lotId").ValueKind!=JsonValueKind.Null)
            throw new Exception("The real UI's exact UTC candidate must normalize to the closed native instant and identity contract.");
        void Reject(JsonElement body)
        {
            try{GasParkLoanActions.Normalize(request with{Selection=body});}
            catch(MarketDataException){return;}
            throw new Exception("Missing, unknown or non-UTC service action inputs must refuse before native mutation.");
        }
        Reject(JsonSerializer.SerializeToElement(new{expectedVersion=4,agreementEvidenceId=id,evidenceId=id,lotId=(Guid?)null,reservationId=(Guid?)null,effectiveAt="2031-01-02T12:00:00Z"}));
        Reject(JsonSerializer.SerializeToElement(new{expectedVersion=4,agreementEvidenceId=id,evidenceId=id,claimEvidenceId=(Guid?)null,lotId=(Guid?)null,reservationId=(Guid?)null,effectiveAt="2031-01-02T12:00:00Z",unreviewed="x"}));
        Reject(JsonSerializer.SerializeToElement(new{expectedVersion=4,agreementEvidenceId=id,evidenceId=id,claimEvidenceId=(Guid?)null,lotId=(Guid?)null,reservationId=(Guid?)null,effectiveAt="2031-01-02T06:00:00-06:00"}));
        Console.WriteLine("PASS Park and Loan lifecycle transport: canonical UTC candidates, exact identities, explicit nulls and closed typed selections");
    }
}
