using System.Collections.Immutable;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Gas;
using OpenEtrm.MarketData.Risk;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

internal static partial class GasOwnedProjection
{
    private static ILifecycleProjection Cashout(GasOwnedPosition position,Profile profile,GasOwnedKnownHistory known,
        ImmutableDictionary<DefinitionRevision,GasOwnedProjectionMarket> markets)
    {
        if(profile.Header.Text("implementation") is not(GasCashoutProjectionTerms.Version or GasQuantityProjectionPolicy.KnownVersion)||position.Instrument is not GasCommodityHoldingInstrument instrument||
            !known.Positions.TryGetValue(position.Position.Owner.Id,out var original)||original.Owner!=position.Position||original.AccountId!=position.AccountId||
            original.SettlementMode!="cashout_final_price_v1"||original.Mark!=instrument.Mark||
            !markets.TryGetValue(instrument.Mark.Curve.Revision,out var market))
            throw Error("gas_projection_cashout","Select the versioned cashout model for this exact outstanding native claim and its captured mark source.");
        var future=known.Settlements.Where(s=>s.PositionId==position.Position.Owner.Id&&s.Time.EffectiveAt>market.Snapshot.ValuationAt).ToArray();
        if(future.Length>0)
        {
            var sign=original.Quantity.Amount.CompareTo(default)<0?ExactDecimal.Parse("-1"):ExactDecimal.Parse("1");
            var prior=known.Settlements.Where(s=>s.PositionId==position.Position.Owner.Id&&s.Time.EffectiveAt<=market.Snapshot.ValuationAt)
                .Aggregate(default(ExactDecimal),(a,s)=>a+s.Quantity.Amount);
            if(original.Quantity.Amount-sign*prior!=position.Quantity.Amount||future.Any(s=>s.ReceiptLotId is not null||
                s.ConsumptionId is not null||s.SourceObservationId is null||s.CashId is {} id&&!known.Fees.Any(f=>f.Owner.Owner==position.Position.Owner&&
                    f.Owner.BindingId==id&&f.Owner.BookId==position.Position.BookId&&f.AccountId==position.AccountId&&
                    f.Time.EffectiveAt==s.Time.EffectiveAt&&f.Time.PublicationOrder==s.Time.PublicationOrder)))
                throw Error("gas_projection_known_cashout","An accepted cashout must retain its exact native commodity discharge and original independent cash counterpart.");
            var discount=instrument.Carrying==GasHoldingCarrying.CurrencyCurve&&instrument.ReturnAt>market.Snapshot.ValuationAt?
                market.CurrencyCurves.GetValueOrDefault(instrument.Currency)??throw Error("gas_projection_known_cashout","Retain this claim's exact captured currency carrying curve."):null;
            return new GasAcceptedCashoutLifecycleProjection(position.Position,instrument,position.Quantity,
                new(profile.Header.Text("implementation"),profile.Header.Text("quantity_disposition")),
                [..future.Select(s=>new GasAcceptedCashoutSettlement(s.Id,s.Quantity,s.Time.EffectiveAt,s.Time.PublicationOrder,s.Time.KnownAt))],discount,market.Snapshot);
        }
        if(original.Quantity!=position.Quantity)throw Error("gas_projection_cashout","An uncovered partially settled cashout requires its explicit qualified remaining-prefix expectation.");
        var choices=profile.Cashouts.Where(p=>p.Id("position_id")==position.Position.Owner.Id).ToArray();
        var native=known.Cashouts.Where(p=>p.PositionId==position.Position.Owner.Id).ToArray();
        if(choices.Length!=1||native.Length!=1||native[0].Rounding!="payment_total_half_even_2dp_v1")
            throw Error("gas_projection_cashout","Retain one explicit cashout expectation and the native official-source, fixing, due and rounding contract.");
        var selected=choices[0];var terms=native[0];var definition=new DefinitionRevision(instrument.Mark.Curve.Revision.CatalogId,selected.Id("scenario_definition_revision_id"));
        var scenario=new CurveRequest(new(definition,selected.Text("scenario_curve_code")),new(definition,selected.Id("scenario_contract_id")));
        var policy=new GasCashoutProjectionTerms(profile.Selection.ProfileId,profile.Selection.Revision,new(scenario,terms.Role,terms.ObservedAt),terms.CashDueAt,
            selected.Text("price_interpretation"),selected.Text("cash_carrying"),new(instrument.Currency,ExactDecimal.Parse("0.01"),CashTieRule.ToEven,CashRoundingStage.PaymentTotal));
        var curve=policy.CashCarrying==GasCashoutProjectionTerms.CurrencyCurveCash?
            market.CurrencyCurves.GetValueOrDefault(instrument.Currency)??throw Error("gas_projection_cashout","Capture the exact selected currency curve for this cashout claim and its cash."):null;
        return new GasCashoutLifecycleProjection(position.Position,instrument,position.Quantity,policy,curve,market.Snapshot);
    }
}
