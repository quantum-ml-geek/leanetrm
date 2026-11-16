using System.Text.Json;
using System.Text.Json.Nodes;
using OpenEtrm.Api;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Gas;

internal static class GasParkLoanPortfolioChecks
{
    internal static void Run()
    {
        var catalog=Guid.NewGuid();var reference=Guid.NewGuid();var revision=Guid.NewGuid();var definition=Guid.NewGuid();
        JsonElement Agreement(string fee,string direction,string service,string perspective,int principal)=>JsonSerializer.SerializeToElement(new{
            implementation=GasParkAndLoanTerms.Version,reconciliationRequired=false,terms=new{serviceKind=service,perspective,principalDirection=principal,
                definitionRevisionId=definition,referenceCatalogId=reference,referenceRevisionId=revision,
                quantity="synthetic_energy",location="synthetic_point",currency="synthetic_currency",markCurve="synthetic_mark",markContractId=Guid.NewGuid(),
                advanceAt="2040-12-19T00:00:00Z",returnAt="2040-12-24T00:00:00Z",fixedFeeAmount=fee,feeDirection=direction,
                feeDueAt=fee=="0"?null:"2040-12-26T00:00:00Z",titlePolicy=GasCommodityLoan.TitleTransfer,
                returnPolicy=GasParkAndLoanTerms.EqualQuantity,returnTiming=GasParkAndLoanTerms.ReturnsAfterAdvance,carrying="nominal_mark_v1",feeRecognition="accepted_advance_v1"}});
        var positive=GasParkLoanPortfolio.Terms(catalog,Agreement("18","receive","loan","customer",1));
        if(positive.SignedFixedFee.Amount!=ExactDecimal.Parse("18")||positive.Mark.Curve.Revision.RevisionId!=definition||
            positive.Point.Revision.CatalogId!=reference||positive.Point.Revision.RevisionId!=revision)
            throw new Exception("A service portfolio must retain the exact native point, mark version and independent signed fixed fee.");
        var zero=GasParkLoanPortfolio.Terms(catalog,Agreement("0","pay","park","customer",-1));
        if(zero.FeeDueAt is not null||zero.FeeDirection!=ExactDecimal.Parse("-1"))
            throw new Exception("A zero fee must preserve its explicitly saved pay direction and absent due instant.");
        Reject(()=>GasParkLoanPortfolio.Terms(catalog,Agreement("18","pay","loan","customer",1)));
        Reject(()=>GasParkLoanPortfolio.Terms(catalog,Agreement("18","receive","loan","provider",1)));
        Reject(()=>GasParkLoanPortfolio.Terms(catalog,Agreement("18","unknown","loan","customer",1)));
        var unknownFeeRule=JsonNode.Parse(Agreement("18","receive","loan","customer",1).GetRawText())!.AsObject();
        unknownFeeRule["terms"]!["feeRecognition"]="unknown";
        Reject(()=>GasParkLoanPortfolio.Terms(catalog,JsonSerializer.SerializeToElement(unknownFeeRule)));
        unknownFeeRule["terms"]!.AsObject().Remove("feeRecognition");
        Reject(()=>GasParkLoanPortfolio.Terms(catalog,JsonSerializer.SerializeToElement(unknownFeeRule)));
        var stale=JsonNode.Parse(Agreement("18","receive","loan","customer",1).GetRawText())!.AsObject();
        stale["reconciliationRequired"]=true;
        try{GasParkLoanPortfolio.Terms(catalog,JsonSerializer.SerializeToElement(stale));}
        catch(MarketDataException e)when(e.Code=="gas_park_loan_reconciliation")
        {Console.WriteLine("PASS Park and Loan portfolio: corrected evidence refuses complete value under its selected knowledge cutoff");return;}
        throw new Exception("A complete scheduled service value cannot ignore corrected native source evidence.");
    }

    private static void Reject(Action action)
    {try{action();}catch(MarketDataException e)when(e.Code=="gas_park_loan_context"){return;}throw new Exception("Expected gas_park_loan_context.");}
}
