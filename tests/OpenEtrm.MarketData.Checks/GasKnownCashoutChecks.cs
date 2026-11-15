using System.Collections.Immutable;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Gas;
using OpenEtrm.MarketData.Risk;
using OpenEtrm.MarketData.Trading;

internal static class GasKnownCashoutChecks
{
    internal static void Run()
    {
        var f=new Fixture();var source=f.Snapshot().WithKnowledge(Guid.NewGuid(),Fixture.Utc("2040-12-20T00:00:00Z"));
        var at=source.ValuationAt;var quote=f.Quotes[0];var mark=new CurveRequest(f.C("future"),f.K(1));
        var owner=new AccountingPositionKey(new AccountingOwnerKey(AccountingOwnerKind.NativeHolding,Guid.NewGuid()),Guid.NewGuid(),Guid.NewGuid());
        var instrument=new GasCommodityHoldingInstrument(Guid.NewGuid(),mark,quote.Quantity,quote.Currency,at.AddHours(6),GasHoldingCarrying.Nominal);
        var policy=new GasQuantityProjectionPolicy(GasQuantityProjectionPolicy.KnownVersion,GasQuantityProjectionPolicy.Retain);
        var first=new GasAcceptedCashoutSettlement(Guid.NewGuid(),new(ExactDecimal.Parse("1"),quote.Quantity),at.AddHours(2),1,source.Knowledge!.KnownAt);
        var second=new GasAcceptedCashoutSettlement(Guid.NewGuid(),new(ExactDecimal.Parse("2"),quote.Quantity),at.AddHours(3),2,source.Knowledge.KnownAt);
        PreparedLifecycleProjection Prepare(ImmutableArray<ILifecycleProjection> components,int hours,string cash=LifecycleProjectionPolicy.Outstanding)=>
            LifecycleProjection.Prepare(f.Model(),source,new(new(Guid.NewGuid(),"synthetic_known_cashout",1),f.R("calendar"),[new(DateOnly.FromDateTime(at.AddHours(hours).UtcDateTime),at.AddHours(hours),0)]),
                new(LifecycleProjectionPolicy.Version,LifecycleProjectionPolicy.Hold,cash,LifecycleProjectionPolicy.Nominal,LifecycleProjectionPolicy.Numerics,
                    LifecycleProjectionPolicy.HeldNonPrice,LifecycleProjectionPolicy.DeclaredCurveExpiry,LifecycleProjectionPolicy.RetainPhysical),components,[]);
        foreach(var sign in new[]{1,-1})
        {
            string Signed(string value)=>sign<0?"-"+value:value;
            var commodity=new GasAcceptedCashoutLifecycleProjection(owner,instrument,new(ExactDecimal.Parse(Signed("3")),quote.Quantity),policy,[second,first],null,source);
            Equal(Prepare([commodity],1).Evaluate("before",[]).Values.Single().ResidualValue,Signed("9"));
            Equal(Prepare([commodity],2).Evaluate("partial",[]).Values.Single().ResidualValue,Signed("6"));
            Equal(Prepare([commodity],4).Evaluate("complete",[]).Values.Single().ResidualValue,"0");
            var cashOwner=owner with{BindingId=Guid.NewGuid()};var cash=new TimedCashPayment(quote.Currency,at.AddHours(6));
            var quantity=new Quantity(ExactDecimal.Parse(Signed("3.02")),quote.Currency);
            var state=new RecordedCashValuation(cashOwner,cash,quantity,[new(Guid.NewGuid(),1,cashOwner,at.AddHours(4),source.Knowledge.KnownAt,
                ExactMoney.Parse(Signed("0.25"),quote.Currency),AccountingFlowKind.EconomicCash)],RecordedCashValuation.Policy,source.Knowledge.ContextId,source.Knowledge.KnownAt);
            var born=new GasKnownCashLifecycleProjection(cashOwner,cash,state,at.AddHours(3),source.Knowledge.KnownAt,2,
                new ExplicitDiscounting(ExactDecimal.Parse("1"),DiscountFactorSource.Undiscounted),source);
            Equal(Prepare([born],2).Evaluate("unborn",[]).Values.Single().ResidualValue,"0");
            var unpaid=Prepare([born],5).Evaluate("known_bank",[]).Values.Single();
            Equal(unpaid.OpeningValue,"0");Equal(unpaid.PeriodCash,Signed("0.25"));Equal(unpaid.ResidualValue,Signed("2.77"));
            var carriedCash=new GasKnownCashLifecycleProjection(cashOwner,cash,state,at.AddHours(3),source.Knowledge.KnownAt,2,
                new SavedCurve(source,quote.Currency),source);
            var cashRoll=Prepare([carriedCash],5).Evaluate("dated_native_cash",[]).Values.Single();
            Equal(cashRoll.OpeningValue,"0");Equal(cashRoll.ResidualValue,Signed("2.0775"));Equal(cashRoll.PeriodCash,Signed("0.25"));
            var paid=Prepare([born],8,LifecycleProjectionPolicy.PayAtDue).Evaluate("at_due",[]).Values.Single();
            Equal(paid.PeriodCash,Signed("3.02"));Equal(paid.ResidualValue,"0");
            var total=Prepare([commodity,born],8).Evaluate("combined",[]).Values;
            Equal(total.Select(v=>v.EconomicPnl).Aggregate((a,b)=>a.Add(b)),sign>0?"-5.98":"5.98");
        }
        Reject(()=>new GasAcceptedCashoutLifecycleProjection(owner,instrument,new(ExactDecimal.Parse("3"),quote.Quantity),policy,[first],null,source));
        Reject(()=>new GasAcceptedCashoutLifecycleProjection(owner,instrument,new(ExactDecimal.Parse("3"),quote.Quantity),policy with{Implementation=GasQuantityProjectionPolicy.Version},[first,second],null,source));
        Reject(()=>new GasAcceptedCashoutLifecycleProjection(owner,instrument,new(ExactDecimal.Parse("3"),quote.Quantity),policy,[first with{KnownAt=source.Knowledge.KnownAt.AddSeconds(1)},second],null,source));
        Reject(()=>new GasAcceptedCashoutLifecycleProjection(owner,instrument,new(ExactDecimal.Parse("3"),quote.Quantity),policy,[first,second],
            new ExplicitDiscounting(ExactDecimal.Parse("0.95"),DiscountFactorSource.Explicit),source));
        var carried=new GasCommodityHoldingInstrument(Guid.NewGuid(),mark,quote.Quantity,quote.Currency,at.AddHours(6),GasHoldingCarrying.CurrencyCurve);
        Reject(()=>new GasAcceptedCashoutLifecycleProjection(owner,carried,new(ExactDecimal.Parse("3"),quote.Quantity),policy,[first,second],null,source));
        Reject(()=>new GasAcceptedCashoutLifecycleProjection(owner,carried,new(ExactDecimal.Parse("3"),quote.Quantity),policy,[first,second],
            new SavedCurve(source with{Id=Guid.NewGuid()},quote.Currency),source));
        var discounted=new GasAcceptedCashoutLifecycleProjection(owner,carried,new(ExactDecimal.Parse("3"),quote.Quantity),policy,[first,second],new SavedCurve(source,quote.Currency),source);
        var dated=Prepare([discounted],2).Evaluate("dated_quantity",[]).Values.Single();
        Equal(dated.OpeningValue,"5.4");Equal(dated.ResidualValue,"4.5");
        var zero=second with{Id=Guid.NewGuid(),Quantity=new(default,quote.Quantity),At=at.AddHours(4),PublicationOrder=3};
        var withdrawn=new GasAcceptedCashoutLifecycleProjection(owner,instrument,new(ExactDecimal.Parse("3"),quote.Quantity),policy,[first,second,zero],null,source);
        Equal(Prepare([withdrawn],5).Evaluate("zero_settlement",[]).Values.Single().ResidualValue,"0");
        var lateZero=zero with{At=at.AddDays(12)};
        var completed=new GasAcceptedCashoutLifecycleProjection(owner,instrument,new(ExactDecimal.Parse("3"),quote.Quantity),policy,[first,second,lateZero],null,source);
        Equal(Prepare([completed],11*24).Evaluate("completed_before_mark_expiry",[]).Values.Single().ResidualValue,"0");
        if(completed.MarketUsesFor(at.AddDays(11)).Single().Through!=source.ValuationAt)
            throw new Exception("A retained later zero settlement demanded an already extinguished commodity mark.");
        foreach(var amount in new[]{"0","-1.23"})
        foreach(var dueHours in new[]{2,3,6})
        {
            var cashOwner=owner with{BindingId=Guid.NewGuid()};var cash=new TimedCashPayment(quote.Currency,at.AddHours(dueHours));
            var actual=new RecordedCashValuation(cashOwner,cash,new(ExactDecimal.Parse(amount),quote.Currency),[],RecordedCashValuation.Policy,source.Knowledge.ContextId,source.Knowledge.KnownAt);
            var birth=new GasKnownCashLifecycleProjection(cashOwner,cash,actual,at.AddHours(3),source.Knowledge.KnownAt,2,
                new ExplicitDiscounting(ExactDecimal.Parse("1"),DiscountFactorSource.Undiscounted),source);
            var result=Prepare([birth],8,LifecycleProjectionPolicy.PayAtDue).Evaluate("signed_native_cash",[]).Values.Single();
            Equal(result.ResidualValue,dueHours<3?amount:"0");Equal(result.PeriodCash,dueHours<3?"0":amount);
        }
        Console.WriteLine("PASS known cashout: exact future quantity discharges, independent signed native cash births, original bank payments and explicit unpaid/paid policies");
    }
    private static void Equal(ExactMoney value,string expected)
    {if(value!=ExactMoney.Parse(expected,value.Currency))throw new Exception($"Expected known cashout {expected}; got {value.ToExactString()}.");}
    private static void Reject(Action action)
    {try{action();}catch(MarketDataException e)when(e.Code=="gas_projection_known_cashout"){return;}throw new Exception("Expected incomplete or conflicting known cashout refusal.");}
    private sealed class SavedCurve(MarketSnapshot source,ReferenceKey currency):IProjectionCurrencyCurve
    {
        public ReferenceKey Currency=>currency;
        public MarketSnapshot SourceSnapshot=>source;
        public ProjectionCurrencyCurveKey CurveIdentity{get;}=new(new(source.Definitions,"synthetic_saved_rates"),Guid.NewGuid(),Guid.NewGuid(),1);
        public string TimingPolicy=>RateDiscountTiming.Version;
        private ExactDecimal Factor(DateTimeOffset at)=>ExactDecimal.Parse(at==source.ValuationAt.AddHours(6)?"0.6":at==source.ValuationAt.AddHours(2)||at==source.ValuationAt.AddHours(5)?"0.8":"1");
        public ImmutableArray<SidePaymentFactor> Resolve(ImmutableArray<SidePaymentKey> payments,MarketSnapshot selected)=>
            [..payments.Select(p=>new SidePaymentFactor(p,Factor(p.PaymentAt),selected,DiscountFactorSource.Explicit))];
        public ImmutableArray<SidePaymentFactor> ResolveForValuation(ImmutableArray<SidePaymentKey> payments,MarketSnapshot selected,DateTimeOffset at,string? policy)=>
            [..payments.Select(p=>new SidePaymentFactor(p,Factor(p.PaymentAt).DivideExact(Factor(at)),selected,DiscountFactorSource.Explicit))];
    }
}
