using OpenEtrm.MarketData.Trading;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Risk;
using System.Collections.Immutable;

internal static class InstrumentSideAlignmentChecks
{
    internal static void Run()
    {
        var exemptions=new[]{typeof(FuturesContract),typeof(FuturesOptionInstrument)};
        var instruments=typeof(Instrument).Assembly.GetTypes().Where(type=>!type.IsAbstract&&typeof(Instrument).IsAssignableFrom(type)).ToArray();
        var missing=instruments.Where(type=>!exemptions.Contains(type)&&!typeof(SidedInstrument).IsAssignableFrom(type)).OrderBy(type=>type.Name).ToArray();
        if(missing.Length!=0)
            throw new Exception("Every non-exchange Instrument must compose real Side memberships: "+string.Join(", ",missing.Select(type=>type.Name)));
        if(exemptions.Any(type=>!instruments.Contains(type)))throw new Exception("The only sideless exemptions must remain the real listed futures and futures-option instruments.");
        var f=new Fixture();var direct=new SidelessValue(f.R("currency"),f.R("gas_quantity"));
        Refuse(()=>_=new TradeInstrument(Guid.NewGuid(),direct,direct.UnitQuantity));
        var raw=new RiskPosition(Guid.NewGuid(),Guid.NewGuid(),Guid.NewGuid(),direct.Id,direct.UnitQuantity,
            new(new Money(default,direct.Currency),direct.UnitQuantity.Specification),new(default,direct.Currency));
        Refuse(()=>_=new ValuationPortfolio([direct],[raw],new(ValuationMeasure.PresentValue,ImmutableDictionary<Guid,FuturesMarketBinding>.Empty,null)));
        SidedInstrument empty=new TimedCashPayment(f.R("currency"),f.Snapshot().ValuationAt);
        empty=empty with{Sides=[]};
        Refuse(()=>_=new TradeInstrument(Guid.NewGuid(),empty,empty.UnitQuantity));
        Console.WriteLine("PASS instrument Side alignment: every non-exchange family requires Side composition");
    }
    private static void Refuse(Action use)
    {
        try{use();}catch(MarketDataException error)when(error.Code=="instrument_sides"){return;}
        throw new Exception("A held or raw-risk non-exchange model must require genuine nonempty Side memberships before declaration or PV.");
    }
    // Deliberately malformed extension: advertised size support cannot bypass
    // the mandatory Side execution contract.
    private sealed record SidelessValue(ReferenceKey Money,ReferenceKey Quantity):Instrument(Guid.NewGuid())
    {
        public override ReferenceKey Currency=>Money;
        public override Quantity UnitQuantity=>new(ExactDecimal.Parse("1"),Quantity);
        public override bool SupportsQuantityScaling=>true;
        public override UnitPricingContract Declare(UnitValuationContext context)=>throw new Exception("A malformed Instrument must refuse before declaration.");
    }
}
