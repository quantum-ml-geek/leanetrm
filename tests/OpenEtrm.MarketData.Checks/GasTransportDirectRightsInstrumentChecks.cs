using System.Collections.Immutable;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Calculation;
using OpenEtrm.MarketData.Gas;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Risk;
using OpenEtrm.MarketData.Trading;

internal static class GasTransportDirectRightsInstrumentChecks
{
    const string ExpiryPolicy=GasTransportDirectRightsPolicy.ExpiryAtThrough;
    public static void Run()
    {
        var f=new GasTransportDirectRightsChecks.MarkFixture("20");
        var source=(ConnectedSource)f.Service.Expression;
        var captured=new CapturedPriceSource(source.Request,ConnectedValuation.Prepare(f.Base,f.Snapshot),f.Service.Key);
        var through=f.At.AddDays(1);var id=Guid.NewGuid();
        var instrument=new GasTransportDirectRightsInstrument(id,f.Terms,f.State,through,ExpiryPolicy,null,captured,f.Mark,f.Evaluation);
        var alternate=new GasTransportDirectRightsChecks.MarkFixture("20",otherPackage:true);
        var wrongRequest=((ConnectedSource)alternate.Gas.Expression).Request;
        var aliased=new CapturedPriceSource(wrongRequest,ConnectedValuation.Prepare(alternate.Base,alternate.Snapshot),alternate.Service.Key);
        Reject("gas_transport_rights_mark",()=>new GasTransportDirectRightsInstrument(Guid.NewGuid(),alternate.Terms,alternate.State,
            through,ExpiryPolicy,null,aliased,alternate.Mark,alternate.Evaluation));
        Reject("gas_transport_rights_expiry",()=>new GasTransportDirectRightsInstrument(Guid.NewGuid(),f.Terms,f.State,
            through,"",null,captured,f.Mark,f.Evaluation));
        if(instrument.SupportsQuantityScaling||!instrument.SupportsWholePosition)
            throw new Exception("A current whole-contract PV must explicitly opt in without asserting size scalability.");
        var setup=new ValuationSetup(ValuationMeasure.PresentValue,ImmutableDictionary<Guid,FuturesMarketBinding>.Empty,null);
        Trade Hold(Instrument value,string quantity="1",TradeExecution? execution=null,DeliveryCoverage? coverage=null)=>new(Guid.NewGuid(),Guid.NewGuid(),
            [new(Guid.NewGuid(),value,new(ExactDecimal.Parse(quantity),value.UnitQuantity.Specification),execution,coverage:coverage)]);
        ValuationPortfolio Portfolio(Trade trade)=>ValuationPortfolio.FromTrades([trade],setup);
        var trade=Hold(instrument);var portfolio=Portfolio(trade);
        PreparedConnectedPortfolioRisk Prepare(params ValuationPortfolio[] groups)=>RiskEngine.PrepareConnected(captured.Valuation,
            ImmutableDictionary<CurveRequest,CurvePointKey>.Empty.Add(source.Request,f.Service.Key),[..groups]);
        var prepared=Prepare(portfolio);
        var bump=new ConnectedRiskBump(CurveShockCoordinate.MarketQuote,new PointCurveTarget(f.Service.Key.Curve,[f.Service.Key.PointId]),
            f.Service.Unit,ExactDecimal.Parse("1"),ConnectedRiskBump.Convention);
        var detailed=RiskEngine.CalculateExact(prepared,[bump],RiskEngine.ExactNumericalPolicy);
        var value=detailed.Groups.Single().Factors.Single().Positions.Single().Values;
        Equal(value.Base,"20");Equal(value.Up,"21");Equal(value.Down,"19");
        var summary=RiskEngine.CalculateExact(prepared,[bump],RiskEngine.ExactNumericalPolicy,detail:RiskDetail.Books);
        if(!summary.Groups.Single().Factors.Single().Totals.SequenceEqual(detailed.Groups.Single().Factors.Single().Totals))
            throw new Exception("Whole-position holding and book summaries must reprice to the same values.");
        var shifted=RiskEngine.WithShifts(prepared,[f.Move(f.Service,"3")]);
        Equal(RiskEngine.CalculateExact(shifted,[],RiskEngine.ExactNumericalPolicy).Groups.Single().BaseValues.Single().Value,"23");
        OrdinaryQuotePath("20","21","19");OrdinaryQuotePath("-20","-19","-21");
        Reject("valuation_time_unsupported",()=>RiskEngine.CalculateExact(RiskEngine.WithClock(prepared,new(f.At.AddMicroseconds(1),ClockChange.FrozenInputs)),[],RiskEngine.ExactNumericalPolicy));

        foreach(var quantity in new[]{"0","-1","0.5","2","100"})
            Reject("risk_whole_position",()=>Hold(instrument,quantity));
        Reject("risk_whole_position",()=>Hold(instrument,coverage:new(f.At,through)));
        var legacy=new Fixture();var future=legacy.Model().BindFutures(Guid.NewGuid(),new(legacy.C("future"),legacy.K(1)),"cash",FuturesMarketBinding.Implementation);
        var execution=new FuturesExecution(future,new UnitPrice(ExactDecimal.Parse("3"),future.Quote),legacy.Snapshot().ValuationAt,FuturesSettlementState.Unprocessed);
        Reject("risk_whole_position",()=>Hold(instrument,execution:execution));
        var position=portfolio.Positions.Single();
        foreach(var quantity in new[]{"0","-1","0.5","2"})
            Reject("risk_whole_position",()=>new ValuationPortfolio([instrument],[position with{Quantity=new(ExactDecimal.Parse(quantity),f.Terms.PackageQuantity)}],setup));
        Reject("risk_whole_position",()=>new ValuationPortfolio([instrument],[position with{Coverage=new(f.At,through)}],setup));
        foreach(var measure in new[]{ValuationMeasure.ExecutionPnl,ValuationMeasure.UnpaidCashPresentValue})
        {
            Reject("valuation_measure",()=>ValuationPortfolio.FromTrades([trade],setup with{Measure=measure}));
            Reject("valuation_measure",()=>new ValuationPortfolio([instrument],[position],setup with{Measure=measure}));
        }
        Reject("risk_whole_position",()=>Portfolio(new(trade.Id,trade.BookId,[trade.Instruments[0],new(Guid.NewGuid(),instrument,trade.Instruments[0].Quantity)])));
        Reject("risk_whole_position",()=>Prepare(portfolio,Portfolio(Hold(instrument))));
        var unsupported=new Unsupported(Guid.NewGuid(),f.Terms.Currency,f.Terms.PackageQuantity);
        Reject("risk_quantity_scaling",()=>Hold(unsupported));
        Reject("risk_quantity_scaling",()=>new ValuationPortfolio([unsupported],[position with{ValuationId=unsupported.Id}],setup));

        var expiry=new GasTransportDirectRightsExpiry(Guid.NewGuid(),f.State,Guid.NewGuid(),through,through,f.Context.KnownAt);
        var closed=new GasTransportDirectRightsInstrument(Guid.NewGuid(),f.Terms,f.State,through,ExpiryPolicy,expiry,null,null,null);
        var closedContext=new ResolvedCalculationContext(Guid.NewGuid(),"synthetic_closed_rights",through,through.AddDays(1),through,through);
        var resolver=new TemporalCurveBindings([],[]);
        var empty=ConnectedScenario.Base(ConnectedCurves.Compile([],[],closedContext,resolver));
        var emptySnapshot=new MarketSnapshot(Guid.NewGuid(),f.Definition,through,through,InputSelectionPolicy.ExactPinnedFinalObservationsNoAgeFiltering,[])
            .WithKnowledge(closedContext.ContextId,closedContext.KnownAt);
        var closedPrepared=RiskEngine.PrepareConnected(ConnectedValuation.Prepare(empty,emptySnapshot),ImmutableDictionary<CurveRequest,CurvePointKey>.Empty,[Portfolio(Hold(closed))]);
        var closedRun=RiskEngine.CalculateExact(closedPrepared,[],RiskEngine.ExactNumericalPolicy);
        Equal(closedRun.Groups.Single().BaseValues.Single().Value,"0");
        if(!closedRun.Groups.Single().Contracts.Single().Dependencies.IsEmpty)
            throw new Exception("A sealed expired rights owner needs no invented mark.");
        Reject("gas_transport_rights_expiry",()=>new GasTransportDirectRightsInstrument(Guid.NewGuid(),f.Terms,f.State,through,ExpiryPolicy,
            expiry with{State=f.State with{CapacityVersionId=Guid.NewGuid()}},null,null,null));
        Reject("gas_transport_rights_expiry",()=>new GasTransportDirectRightsInstrument(Guid.NewGuid(),f.Terms,f.State,through,ExpiryPolicy,
            expiry with{Through=through.AddDays(1)},null,null,null));
        Reject("gas_transport_rights_expiry",()=>new GasTransportDirectRightsInstrument(Guid.NewGuid(),f.Terms,f.State,through,ExpiryPolicy,
            expiry with{PreviousLiveStateId=Guid.Empty},null,null,null));
        Reject("gas_transport_rights_mark",()=>new GasTransportDirectRightsInstrument(Guid.NewGuid(),f.Terms,f.State,through,ExpiryPolicy,null,null,null,null));
        Reject("gas_transport_rights_expiry_required",()=>new GasTransportDirectRightsInstrument(Guid.NewGuid(),f.Terms,f.State,f.At,ExpiryPolicy,null,captured,f.Mark,f.Evaluation));
        Equal(Combined(instrument,f.Base,f.Snapshot),"307.5");
        Equal(Combined(instrument,f.Shift(f.Service,"1"),f.Snapshot),"308.5");
        Equal(Combined(instrument,f.Shift(f.Gas,"1"),f.Snapshot),"407.5");
        Equal(Combined(closed,f.ReadContext(closedContext),emptySnapshot with{Selections=f.Snapshot.Selections}),"287.5");
        Equal(Combined(closed,f.ReadContext(closedContext),emptySnapshot with{Selections=f.Snapshot.Selections},paid:true),"300");
        Console.WriteLine("PASS whole Transport position: real held Trade/shared risk PV, exact one package, no execution/scaling/duplication and sealed explicit expiry");

        ExactMoney Combined(Instrument rights,ConnectedScenario scenario,MarketSnapshot snapshot,bool paid=false)
        {
            var cash=new TimedCashPayment(f.Terms.Currency,f.At);var binding=Guid.NewGuid();var gas=(ConnectedSource)f.Gas.Expression;
            var stock=new GasCommodityHoldingInstrument(Guid.NewGuid(),gas.Request,f.Gas.Unit.Quantity,f.Terms.Currency,null,GasHoldingCarrying.Nominal);
            var combined=new Trade(Guid.NewGuid(),Guid.NewGuid(),[new(Guid.NewGuid(),rights,rights.UnitQuantity),
                new(binding,cash,new(ExactDecimal.Parse("-12.5"),cash.Currency)),new(Guid.NewGuid(),stock,new(ExactDecimal.Parse("100"),f.Gas.Unit.Quantity))]);
            var owner=new AccountingPositionKey(combined.Id,binding,combined.BookId);
            var history=paid?ImmutableArray.Create(new AccountingFlow(Guid.NewGuid(),1,owner,f.At,f.At,ExactMoney.Parse("-12.5",cash.Currency),AccountingFlowKind.EconomicCash)):[];
            var state=new RecordedCashValuation(combined,binding,history,RecordedCashValuation.Policy,snapshot.Knowledge!.ContextId,snapshot.Knowledge.KnownAt);
            var selected=setup with{BindingStates=ImmutableDictionary<MeasureBinding,IBindingValuationState>.Empty.Add(new(combined.Id,binding),state)};
            var all=RiskEngine.PrepareConnected(ConnectedValuation.Prepare(scenario,snapshot),ImmutableDictionary<CurveRequest,CurvePointKey>.Empty
                .Add(source.Request,f.Service.Key).Add(gas.Request,f.Gas.Key),[ValuationPortfolio.FromTrades([combined],selected)]);
            return RiskEngine.CalculateExact(all,[],RiskEngine.ExactNumericalPolicy).Groups.Single().BaseValues.Single().Value;
        }
    }
    static void OrdinaryQuotePath(string mark,string up,string down)
    {
        var f=new GasTransportDirectRightsChecks.MarkFixture(mark);var source=(ConnectedSource)f.Service.Expression;
        var market=f.Model().Build(f.Snapshot,[source.Request]);
        var point=market.Graph.Plan.Points.Values.Single(p=>p.Expression is ConnectedSource direct&&direct.Request==source.Request).Key;
        var captured=new CapturedPriceSource(source.Request,ConnectedValuation.Prepare(market.Graph,f.Snapshot),point);
        var rights=new GasTransportDirectRightsInstrument(Guid.NewGuid(),f.Terms,f.State,f.At.AddDays(1),ExpiryPolicy,null,captured,
            f.Mark with{Point=point},new(market.Graph.Plan.Context,market.Graph.Id,ConnectedCurves.NumericalPolicy));
        var trade=new Trade(Guid.NewGuid(),Guid.NewGuid(),[new(Guid.NewGuid(),rights,rights.UnitQuantity)]);
        var portfolio=ValuationPortfolio.FromTrades([trade],new(ValuationMeasure.PresentValue,ImmutableDictionary<Guid,FuturesMarketBinding>.Empty,null));
        var bump=new QuoteBump(source.Input,source.Quote.Key,f.Service.Unit,ExactDecimal.Parse("1"),QuoteBump.Convention);
        var result=RiskEngine.CalculateExact(RiskEngine.Prepare(market,[portfolio]),[bump],RiskEngine.ExactNumericalPolicy,detail:RiskDetail.Holdings);
        var values=result.Groups.Single().Factors.Single().Positions.Single().Values;
        Equal(values.Base,mark);Equal(values.Up,up);Equal(values.Down,down);
    }
    sealed record Unsupported(Guid Identity,ReferenceKey Money,ReferenceKey Package):Instrument(Identity)
    {
        public override ReferenceKey Currency=>Money;
        public override Quantity UnitQuantity=>new(ExactDecimal.Parse("1"),Package);
        public override UnitPricingContract Declare(UnitValuationContext context)=>throw new Exception("An unsupported holding must refuse before declaration.");
    }
    static void Equal(ExactMoney actual,string expected)
    {
        if(actual!=ExactMoney.Parse(expected,actual.Currency))throw new Exception($"Expected {expected}, got {actual.ToExactString()}.");
    }
    static void Reject(string code,Action action)
    {
        try{action();throw new Exception("Expected "+code+".");}catch(MarketDataException error)when(error.Code==code){}
    }
}
