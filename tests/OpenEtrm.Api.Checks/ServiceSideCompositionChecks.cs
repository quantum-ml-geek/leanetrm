using System.Text.Json;
using System.Text.Json.Nodes;
using OpenEtrm.Api;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Gas;
using OpenEtrm.MarketData.Trading;

internal static class ServiceSideCompositionChecks
{
    internal static void Run()
    {
        PrincipalContract();CustodyCash();TransportRights();
    }

    static void PrincipalContract()
    {
        var catalog=Guid.NewGuid();var binding=Guid.NewGuid();
        var agreement=JsonSerializer.SerializeToElement(new{implementation=GasParkAndLoanTerms.Version,instrumentId=binding,quantity="720",
            reconciliationRequired=false,advance=(object?)null,terms=new{serviceKind="loan",perspective="customer",principalDirection=1,
                definitionRevisionId=Guid.NewGuid(),referenceCatalogId=Guid.NewGuid(),referenceRevisionId=Guid.NewGuid(),
                quantity="synthetic_quantity",location="synthetic_point",currency="synthetic_currency",markCurve="synthetic_mark",markContractId=Guid.NewGuid(),
                advanceAt="2032-01-15T10:00:00Z",returnAt="2032-01-17T10:00:00Z",fixedFeeAmount="-12.5",feeDirection="pay",feeDueAt="2032-01-19T10:00:00Z",
                titlePolicy=GasCommodityLoan.TitleTransfer,returnPolicy=GasParkAndLoanTerms.EqualQuantity,returnTiming=GasParkAndLoanTerms.ReturnsAfterAdvance,
                carrying="nominal_mark_v1",feeRecognition=GasParkAndLoanTerms.FeeAtAdvance}});
        var terms=GasParkLoanPortfolio.Terms(catalog,agreement);var components=GasParkAndLoanValuation.ContractualComponents(terms,new(ExactDecimal.Parse("720"),terms.Quantity));
        var original=GasServiceSidePresentation.ParkLoan(catalog,agreement);var draft=GasServiceSidePresentation.ParkLoan(catalog,agreement,true);
        if(original.Reason is not null||original.Groups.Length!=3||draft.Groups.Any(group=>group.BindingId is not null))
            throw new Exception("A Park and Loan draft must expose both actual principal Side definitions and its independent fixed fee without an invented owner.");
        for(var index=0;index<components.Length;index++)
        {
            var component=components[index];var group=original.Groups[index];
            if(component.Instrument is not SidedInstrument instrument||group.InstrumentId!=instrument.Id||group.BindingId!=GasParkAndLoanValuation.ComponentBinding(binding,component.Role)||
                group.Sides.Single().SideId!=instrument.Sides.Single().Side.Id||group.FieldGroupId!=(component.Role==GasParkAndLoanValuation.FeeRole?"fee":"principal"))
                throw new Exception("Contract structure must use the exact reusable component Side and its retained declared component binding.");
        }
        var completed=JsonNode.Parse(agreement.GetRawText())!.AsObject();completed["advance"]=JsonSerializer.SerializeToNode(new{id=Guid.NewGuid()});
        completed["reconciliationRequired"]=true;
        var retained=GasServiceSidePresentation.ParkLoan(catalog,JsonSerializer.SerializeToElement(completed));
        if(!retained.Groups.Select(group=>(group.InstrumentId,group.BindingId)).SequenceEqual(original.Groups.Select(group=>(group.InstrumentId,group.BindingId)))||
            retained.Groups.Any(group=>!Text(group).Contains("Contractual",StringComparison.Ordinal))||
            !retained.Groups.All(group=>Text(group).Contains("independent native",StringComparison.Ordinal)))
            throw new Exception("Accepted principal must retain its saved contractual Side identities with explicit historical/independent-owner labels even when current value requires reconciliation.");
    }

    static void CustodyCash()
    {
        var catalog=Guid.NewGuid();var agreement=GasParkCustodyAdapterChecks.Agreement("customer");var source=GasParkCustodyAdapter.Read(catalog,agreement);
        var composition=GasServiceSidePresentation.Custody(catalog,agreement);
        if(composition.Groups is not{Length:1}||composition.Reason is not null||composition.Groups[0].InstrumentId!=source.Cash!.Instrument.Id||
            composition.Groups[0].BindingId!=source.Cash.BindingId||composition.Groups[0].Sides.Single().SideId!=source.Cash.Instrument.CashPaymentSide.Id||
            composition.Groups[0].FieldGroupId!="fee"||!Text(composition.Groups[0]).Contains("Independent",StringComparison.Ordinal))
            throw new Exception("Accepted custody has one genuine independent cash Side with its exact cash binding, and no fabricated gas or title Side.");
        var zero=JsonNode.Parse(agreement.GetRawText())!.AsObject();zero["terms"]!["fixedFeeAmount"]="0";zero["terms"]!["feeDueAt"]=null;zero["cash"]=null;
        var absent=GasServiceSidePresentation.Custody(catalog,JsonSerializer.SerializeToElement(zero));
        if(!absent.Groups.IsEmpty||string.IsNullOrWhiteSpace(absent.Reason)||!absent.Reason.Contains("no financial instrument",StringComparison.OrdinalIgnoreCase))
            throw new Exception("Zero-fee custody must explicitly describe financial-instrument absence while retaining its separate custody performance terms.");
        var invalid=JsonNode.Parse(agreement.GetRawText())!.AsObject();invalid["cash"]=null;
        try{GasServiceSidePresentation.Custody(catalog,JsonSerializer.SerializeToElement(invalid));}
        catch(MarketDataException error)when(error.Code=="gas_custody_source"){return;}
        throw new Exception("Missing required accepted cash must refuse rather than become an empty no-instrument composition.");
    }

    static void TransportRights()
    {
        var f=new GasTransportFinancialAdapterChecks.Fixture();var agreement=GasTransportFinancialAdapter.Read(f.Catalog,f.Row);var market=f.Market("20");
        var priced=GasTransportFinancialAdapter.Instrument(agreement,market.Source,market.Evaluation);
        var composed=GasServiceSidePresentation.Transport(f.Catalog,f.Row);
        var unpriced=f.Change(row=>{row["mark"]=null;row["unpricedReason"]="rights_mark_required";});
        var unmarked=GasServiceSidePresentation.Transport(f.Catalog,unpriced);
        if(composed.Groups.Length!=2||composed.Groups[0].InstrumentId!=priced.Id||composed.Groups[0].BindingId!=agreement.InstrumentId||
            composed.Groups[0].Sides.Single().SideId!=priced.RightsSide.Id||composed.Groups[0].FieldGroupId!="rights"||
            unmarked.Groups[0].InstrumentId!=priced.Id||unmarked.Groups[0].Sides.Single().SideId!=priced.RightsSide.Id||unmarked.Reason is not null||
            composed.Groups[1].BindingId!=agreement.Cash!.BindingId||composed.Groups[1].InstrumentId!=agreement.Cash.Instrument.Id||composed.Groups[1].FieldGroupId!="fee")
            throw new Exception("Unpriced and priced Transport must expose the same state-owned rights Side while preserving the native agreement binding and independent cash definition/binding.");
        var amended=GasServiceSidePresentation.Transport(f.Catalog,f.Amended());
        if(amended.Groups[0].InstrumentId==composed.Groups[0].InstrumentId||amended.Groups[0].Sides.Single().SideId==composed.Groups[0].Sides.Single().SideId||
            amended.Groups[0].BindingId!=composed.Groups[0].BindingId||amended.Groups[1].InstrumentId!=composed.Groups[1].InstrumentId)
            throw new Exception("An accepted new financial state changes the actual rights definition and Side identity without changing its native binding or the independent fee instrument.");
        var incomplete=f.Change(row=>row["terms"]!["rightsValuationPolicy"]="");
        try{GasServiceSidePresentation.Transport(f.Catalog,incomplete);}
        catch(MarketDataException error)when(error.Code=="gas_transport_financial_source"){return;}
        throw new Exception("A malformed rights source cannot acquire an apparently valid structural Side summary.");
    }

    static string Text(InstrumentSideGroup group)=>JsonSerializer.Serialize(group);
}
