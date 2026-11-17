using System.Collections.Immutable;
using System.Text.Json;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Gas;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

internal sealed record ServiceSideComposition(ImmutableArray<InstrumentSideGroup> Groups,string? Reason=null);

internal static class GasServiceSidePresentation
{
    internal static ServiceSideComposition ParkLoan(Guid catalog,JsonElement agreement,bool draft=false)
    {
        var terms=GasParkLoanPortfolio.ContractTerms(catalog,agreement);
        var committed=new Quantity(agreement.Number("quantity"),terms.Quantity);
        var accepted=agreement.GetProperty("advance").ValueKind!=JsonValueKind.Null;
        var reconciliation=agreement.GetProperty("reconciliationRequired").GetBoolean();
        var contract=GasParkAndLoanValuation.ContractualComponents(terms,committed);
        var components=contract;var balance=agreement.Text("implementation")==GasParkLoanBalanceFeeTerms.Version;
        if(balance&&!reconciliation)
        {
            var fee=GasParkLoanBalanceFeeAdapter.Read(terms,agreement);
            try
            {
                var remaining=GasParkLoanBalanceFeeValuation.Components(terms,fee.Terms,fee.Source,fee.CumulativeDeterminedTotal);
                components=accepted?[..contract,..remaining]:remaining;
            }
            catch(MarketDataException error)when(error.Code=="gas_balance_fee_advance_window")
            {components=contract;}
        }
        var groups=ImmutableArray.CreateBuilder<InstrumentSideGroup>();
        foreach(var component in components)
        {
            var history=(accepted||reconciliation)&&contract.Contains(component);
            var cash=component.Role==GasParkAndLoanValuation.FeeRole;
            var name=cash?(balance?"Undetermined fee plan":"Independent fixed fee"):
                component.Role==GasParkAndLoanValuation.AdvanceRole?"Principal advance":"Principal return";
            var state=history?"Contractual terms retained; accepted principal and fee belong to independent native owners.":
                balance?"Current remaining service plan; determined cash belongs to independent native owners.":"Contractual service component before accepted advance.";
            var label=history?"Contractual "+name.ToLowerInvariant():name;
            var binding=draft?(Guid?)null:GasParkAndLoanValuation.ComponentBinding(agreement.Id("instrumentId"),component.Role);
            if(cash)
                groups.Add(Cash((TimedCashPayment)component.Instrument,binding,label,component.Quantity,terms.FeeDirection,state));
            else
            {
                var instrument=(GasCommodityHoldingInstrument)component.Instrument;
                var direction=component.Role==GasParkAndLoanValuation.AdvanceRole?terms.AdvanceDirection:-terms.AdvanceDirection;
                groups.Add(InstrumentSidePresentation.Describe(instrument,binding,label,[new(0,label,"Gas principal claim",
                    direction.CompareTo(default)>0?"Company receives gas":"Company delivers gas",[new("Principal terms",[
                        new("Signed contract quantity",component.Quantity.Amount.ToString()+" "+terms.Quantity.Code),new("Point",terms.Point.Code),
                        new("Contractual advance",Instant(terms.AdvanceAt),"instant"),new("Contractual return due",Instant(terms.ReturnAt),"instant"),
                        new("Plan instant",Instant(instrument.HoldingSide.ReturnAt!.Value),"instant"),new("Composition",state)])])],ServiceTicketFieldGroups.Principal));
            }
        }
        return new(groups.ToImmutable());
    }

    internal static ServiceSideComposition Custody(Guid catalog,JsonElement agreement,bool draft=false)
    {
        var state=GasParkCustodyAdapter.Read(catalog,agreement,draft);var terms=state.Terms;
        if(terms.FixedFee.Amount==default)return new([],"This zero-fee custody agreement has no financial instrument. Custody performance and customer title remain separate.");
        if(state.Cash is {} cash)
            return new([Cash(cash.Instrument,cash.BindingId,"Independent accepted custody fee",cash.Quantity,terms.FeeDirection,
                "Accepted ordinary cash; custody returns do not remove this instrument. Bank-payment revisions remain separate.")]);
        var instrument=new TimedCashPayment(terms.Currency,terms.FeeDueAt!.Value);
        return new([Cash(instrument,draft?null:GasParkAndLoanValuation.ComponentBinding(agreement.Id("instrumentId"),GasParkAndLoanValuation.FeeRole),
            "Conditional custody fee",new(terms.SignedFixedFee.Amount,terms.Currency),terms.FeeDirection,
            "Contractual fee conditional on accepted custody; this does not assert acceptance, payment or owned gas.")]);
    }

    internal static ServiceSideComposition Transport(Guid catalog,JsonElement agreement,bool draft=false)
    {
        var terms=GasTransportFinancialAdapter.Terms(catalog,agreement);
        Guid stateId;GasTransportDirectRightsState rights;DateTimeOffset through;GasTransportDirectRightsExpiry? expiry;
        GasTransportFinancialCash? cash;
        if(draft)
        {
            var raw=agreement.GetProperty("financialState");stateId=raw.Id("id");
            if(stateId==Guid.Empty||raw.Text("status")!="live"||raw.Id("capacityVersionId")==Guid.Empty)throw Invalid();
            rights=new(agreement.Id("tradeId"),terms.EntitlementId,raw.Id("capacityVersionId"),stateId.ToString("D"));
            through=agreement.GetProperty("terms").Instant("through");expiry=null;cash=null;
        }
        else
        {
            var source=GasTransportFinancialAdapter.Read(catalog,agreement);
            var state=source.State??throw GasTransportFinancialAdapter.Unpriced(source.UnpricedReason??"financial_state_unavailable");
            stateId=state.Id;rights=state.Rights;through=state.Through;expiry=source.Expiry;cash=source.Cash;
        }
        var id=GasTransportFinancialAdapter.ValuationInstrumentId(stateId);
        var side=GasTransportDirectRightsInstrument.DefineSide(id,terms.Rights,rights,through,terms.ExpiryPolicy,expiry);
        var label=expiry is null?"Remaining Transport rights":"Retained closed Transport rights";
        var group=InstrumentSidePresentation.Define(id,[new(side,ExactDecimal.Parse("1"))],draft?null:agreement.Id("instrumentId"),label,[
            new(0,"Whole remaining rights","Commercial entitlement rights","Explicit signed whole-package value",[new("Rights terms",[
                new("Whole packages","1"),new("Package basis",terms.Rights.PackageQuantity.Code),new("Currency",terms.Rights.Currency.Code),
                new("Capacity version",rights.CapacityVersionId.ToString("D")),new("Through",Instant(through),"instant"),
                new("Composition",expiry is null?"The rights Side excludes independent fee cash and owned gas.":"Accepted expiry closes these rights; independent cash remains separately retained.")])])],ServiceTicketFieldGroups.Rights);
        var groups=ImmutableArray.CreateBuilder<InstrumentSideGroup>();groups.Add(group);
        if(cash is not null)
            groups.Add(Cash(cash.Instrument,cash.BindingId,"Independent Transport fee",cash.Quantity,terms.FeeDirection,
                "Ordinary fee cash is independent of rights value and expiry. Bank-payment revisions remain separate."));
        else if(draft&&terms.FixedFee.Amount!=default)
            groups.Add(Cash(new TimedCashPayment(terms.Rights.Currency,terms.FeeDueAt!.Value),null,"Independent Transport fee",
                new(terms.SignedFee.Amount,terms.Rights.Currency),terms.FeeDirection,"The explicit booking fee creates independent ordinary cash."));
        return new(groups.ToImmutable());
    }

    static InstrumentSideGroup Cash(TimedCashPayment instrument,Guid? binding,string label,Quantity quantity,ExactDecimal direction,string state)=>
        InstrumentSidePresentation.Describe(instrument,binding,label,[new(0,label,"Ordinary cash payment",direction.CompareTo(default)<0?"Company pays":"Company receives",
            [new("Cash terms",[new("Signed contract amount",quantity.Amount.ToString()+" "+instrument.Currency.Code),
                new("Due",Instant(instrument.PaymentAt),"instant"),new("Composition",state)])])],ServiceTicketFieldGroups.Fee);
    static string Instant(DateTimeOffset at)=>at.ToString("O",System.Globalization.CultureInfo.InvariantCulture);
    static MarketDataException Invalid()=>new("instrument_side_presentation","Retain the exact accepted or reviewed financial state before describing its actual rights Side.");
}
