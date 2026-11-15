using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.MarketData.Gas;

internal static class GasCashDelivery
{
    internal static void Require(Side cash,PhysicalGasSide source,string errorCode)
    {
        var clock=cash switch{FixedSide fixedSide=>fixedSide.GasDeliveryClock,FloatingSide floating=>floating.GasDeliveryClock,_=>null};
        if(clock is null||DefinitionIdentity.For(clock)!=DefinitionIdentity.For(source.Quantities.Clock))
            throw new MarketDataException(errorCode,"Cash must retain the exact gas-day clock of its declared physical quantity source.");
    }
}
