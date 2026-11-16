using System.Collections.Immutable;
using OpenEtrm.MarketData.Power;

namespace OpenEtrm.MarketData.Trading;

public sealed record ScheduleOperatingPriceEvidence(CurveRequest Market,ReferenceKey Quote,ExactUnitPrice Price,
    ImmutableHashSet<ObservationKey> Lineage):ScheduleSourceEvidence;

public sealed partial class ScheduleMarketSources
{
    public static ScheduleMarketSources ForOperating(CurveBuild basis)=>new(basis.Graph.Plan.Context,basis,null,null,
        IntervalKnowledgePolicy.ResolvedCutoff,PendingActualsPolicy.RequireActuals,[],[]);

    private (ExactUnitPrice Price,SchedulePriceFacts State,ScheduleSourceEvidence Evidence) OperatingPrice(BookedSideInstruction instruction,CurveBuild market)
    {
        var request=instruction.Bindings.Single(b=>b.Port=="market").Market!.Value;
        var quote=instruction.Bindings.Single(b=>b.Port=="quote").Reference!.Value;
        var price=market.Pricing.Price(request,default);RequireUnit(price,instruction.Output);
        return(price,SchedulePriceFacts.Projected,new ScheduleOperatingPriceEvidence(request,quote,price,market.Pricing.Lineage(request,default)));
    }
}
