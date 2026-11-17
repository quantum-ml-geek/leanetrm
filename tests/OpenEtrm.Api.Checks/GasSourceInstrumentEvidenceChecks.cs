using System.Text.Json;
using OpenEtrm.Api;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Gas;
using OpenEtrm.MarketData.Trading;

internal static class GasSourceInstrumentEvidenceChecks
{
    internal static void Run()
    {
        var reference=new ReferenceRevision(Guid.NewGuid(),Guid.NewGuid());
        var currency=new ReferenceKey(reference,"synthetic_currency");var quantity=new ReferenceKey(reference,"synthetic_quantity");
        var at=TradingInstant.Parse("2040-02-01T13:02:03.123456Z","gas_source_evidence");
        var cash=new TimedCashPayment(currency,at);
        var cashEvidence=JsonSerializer.SerializeToElement(new{instrument=cash},RiskJobs.Json).GetProperty("instrument");
        Fields(cashEvidence,"implementation","id","paymentCurrency","paymentAt","timing","economicDefinition","modelVersion");
        if(cashEvidence.GetProperty("implementation").GetString()!="timed_cash_source_definition_v1"||cashEvidence.GetProperty("id").GetGuid()!=cash.Id||
            cashEvidence.GetProperty("paymentAt").GetDateTimeOffset()!=at||cashEvidence.GetProperty("timing").GetString()!="instant"||
            cashEvidence.GetProperty("paymentCurrency").GetProperty("revision").GetProperty("revisionId").GetGuid()!=reference.RevisionId||
            cashEvidence.GetProperty("economicDefinition").GetProperty("canonical").GetString()!=cash.EconomicIdentity.Canonical||
            cashEvidence.GetProperty("modelVersion").GetString()!=CashPaymentInstrument.ModelVersion)
            throw new Exception("Cash source evidence must retain its native identity, exact currency revision, microsecond due time, timing and complete model definition.");
        var later=JsonSerializer.SerializeToElement(new TimedCashPayment(currency,at.AddTicks(10)),RiskJobs.Json);
        if(later.GetProperty("paymentAt").GetDateTimeOffset()!=at.AddTicks(10)||later.GetProperty("economicDefinition").GetRawText()==cashEvidence.GetProperty("economicDefinition").GetRawText())
            throw new Exception("A one-microsecond change in source cash terms must change the retained definition evidence.");
        var definition=new DefinitionRevision(Guid.NewGuid(),Guid.NewGuid());var mark=new CurveRequest(new(definition,"synthetic_mark"),new(definition,Guid.NewGuid()));
        var stock=new GasCommodityHoldingInstrument(Guid.NewGuid(),mark,quantity,currency,at,GasHoldingCarrying.CurrencyCurve);
        var stockEvidence=JsonSerializer.SerializeToElement(new{originalInstrument=stock},RiskJobs.Json).GetProperty("originalInstrument");
        Fields(stockEvidence,"implementation","id","mark","quantitySpecification","paymentCurrency","returnAt","carrying","economicDefinition","modelVersion");
        if(stockEvidence.GetProperty("implementation").GetString()!="gas_holding_source_definition_v1"||stockEvidence.GetProperty("id").GetGuid()!=stock.Id||
            stockEvidence.GetProperty("mark").GetProperty("contract").GetProperty("id").GetGuid()!=mark.Contract.Id||
            stockEvidence.GetProperty("quantitySpecification").GetProperty("code").GetString()!=quantity.Code||
            stockEvidence.GetProperty("paymentCurrency").GetProperty("revision").GetProperty("catalogId").GetGuid()!=reference.CatalogId||
            stockEvidence.GetProperty("returnAt").GetDateTimeOffset()!=at||stockEvidence.GetProperty("carrying").GetString()!="CurrencyCurve"||
            stockEvidence.GetProperty("economicDefinition").GetProperty("canonical").GetString()!=stock.EconomicIdentity.Canonical||
            stockEvidence.GetProperty("modelVersion").GetString()!=GasCommodityHoldingSide.ModelVersion)
            throw new Exception("Physical source evidence must retain its original holding, exact mark, units, carrying terms and canonical model definition.");
        var nominal=JsonSerializer.SerializeToElement(new GasCommodityHoldingInstrument(Guid.NewGuid(),mark,quantity,currency,null,GasHoldingCarrying.Nominal),RiskJobs.Json);
        if(nominal.GetProperty("returnAt").ValueKind!=JsonValueKind.Null||nominal.GetProperty("carrying").GetString()!="Nominal")
            throw new Exception("An owned holding must retain explicit absence of a return date and its selected nominal carrying law.");
        Console.WriteLine("PASS exact source instrument evidence: native cash/stock definitions, microseconds, reference versions and explicit carrying without execution graphs");
    }
    static void Fields(JsonElement value,params string[] names)
    {
        if(!value.EnumerateObject().Select(field=>field.Name).ToHashSet(StringComparer.Ordinal).SetEquals(names))
            throw new Exception("Source definition evidence requires its complete explicit immutable field contract.");
    }
}
