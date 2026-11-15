using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

public sealed partial class SwapStore
{
    internal static SwapSettlementInputs ProjectionSettlement(ResolvedSwapHolding holding,
        string duePolicy,string recognitionPolicy)
    {
        if(holding.Settlement is {} accepted)return accepted;
        var zero=ExactMoney.Parse("0",holding.Instrument.Currency);
        return new(holding.Row.Id("trade_id"),holding.Row.Id("binding_id"),holding.Quantity,[],zero,zero,
            SettlementCompletions(holding.Instrument),duePolicy,recognitionPolicy);
    }
}
