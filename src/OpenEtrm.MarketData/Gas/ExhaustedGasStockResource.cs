using System.Collections.Immutable;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Risk;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.MarketData.Gas;

// A depleted lot can still have a source-known reservation release to process.
// Its exact resource Side survives without a commodity valuation dependency.
[EconomicDefinition("gas_exhausted_stock_resource_v2")]
internal sealed record ExhaustedGasStockResource:SidedInstrument
{
    public AccountingPositionKey Position {get;}
    public ReferenceKey QuantitySpecification {get;}
    public ReferenceKey PaymentCurrency {get;}
    public MarketSnapshot Source {get;}
    private ExhaustedGasStockSide ResourceSide=>(ExhaustedGasStockSide)Sides[0].Side;
    public override ReferenceKey Currency=>PaymentCurrency;
    public override Quantity UnitQuantity=>new(ExactDecimal.Parse("1"),QuantitySpecification);
    internal override bool SupportsSettlement=>false;
    public ExhaustedGasStockResource(AccountingPositionKey position,ReferenceKey quantity,ReferenceKey currency,MarketSnapshot source)
        :base(Identity(position,source),[new(new ExhaustedGasStockSide(Identity(position,source),position,quantity,currency,source),ExactDecimal.Parse("1"))])
    {Position=position;QuantitySpecification=quantity;PaymentCurrency=currency;Source=source;}
    private static Guid Identity(AccountingPositionKey position,MarketSnapshot source)=>ContractIdentity.FromCanonical(
        $"gas_exhausted_stock_resource_v1:{(int)position.Owner.Kind}:{position.Owner.Id:D}:{position.BindingId:D}:{position.BookId:D}:{source.Id:D}");
    public override void ValidateBinding(Quantity quantity,DeliveryCoverage? coverage)
    {
        base.ValidateBinding(quantity,coverage);
        if(quantity.Specification!=QuantitySpecification||quantity.Amount!=default)throw ExhaustedGasStockSide.Error();
    }
    public override void ValidateValuationState(IBindingValuationState? state)=>ResourceSide.RequireState(state);
    public override UnitPricingContract Declare(UnitValuationContext context)
    {
        ResourceSide.RequireContext(context.Snapshot,context.BindingState,context.IsLifecycleProjection);
        return new(Id,"gas_exhausted_stock_resource_side_v2",[],QuantitySpecification,Currency){Time=ValuationTimeDependency.Independent};
    }
    internal override UnitPricingContract DeclareScope(UnitValuationContext context,bool lifecycle)=>Declare(context);
}

[EconomicDefinition("gas_exhausted_stock_side_v1")]
internal sealed record ExhaustedGasStockSide:ValueSide
{
    public AccountingPositionKey Position {get;}
    private MarketSnapshot Source {get;}
    [IdentityField]public AccountingOwnerKind OwnerKind=>Position.Owner.Kind;
    [IdentityField]public Guid OwnerId=>Position.Owner.Id;
    [IdentityField]public Guid BindingId=>Position.BindingId;
    [IdentityField]public Guid? BookId=>Position.BookId;
    [IdentityField]public Guid SourceSnapshotId=>Source.Id;
    [IdentityField]public ReferenceKey QuantitySpecification=>UnitQuantity.Specification;
    [IdentityField]public ReferenceKey PaymentCurrency=>Currency;
    internal ExhaustedGasStockSide(Guid id,AccountingPositionKey position,ReferenceKey quantity,ReferenceKey currency,MarketSnapshot source)
        :base(id,currency,new(ExactDecimal.Parse("1"),quantity),"gas_exhausted_stock_resource_side_v2",[new(0,ComponentKind.Holding,null,null,null,null,null)])
    {Position=position;Source=source;}
    internal void RequireState(IBindingValuationState? state)
    {
        if(state is not ProjectedGasStockValuation stock||stock.Position!=Position||stock.Quantity.Specification!=QuantitySpecification||
            stock.Quantity.Amount!=default||stock.KnownSchedule is not {} schedule||schedule.Operations.IsDefaultOrEmpty||schedule.Operations.Any(p=>p is null||p.Use!=GasKnownStockUse.Release))
            throw Error();
        stock.Validate();
    }
    internal void RequireContext(MarketSnapshot snapshot,IBindingValuationState? state,bool projected)
    {if(!projected||!Source.HasSameInputs(snapshot))throw Error();RequireState(state);}
    protected override ImmutableArray<ScheduleRowValue> Evaluate(SideValuationContext context,IReadOnlyList<ScheduleRow> rows)
    {
        RequireContext(context.Snapshot,context.BindingState,context.UnitEvaluation.IsLifecycleProjection);
        var zero=ExactMoney.Parse("0",Currency);return [Value(rows[0],zero,zero,context.UnitEvaluation.CalculationAt)];
    }
    internal static MarketDataException Error()=>new("gas_projection_stock","A zero-stock resource requires its exact depleted native binding, accepted release schedule and projection-only source context.");
}
