using System.Collections.Immutable;
using OpenEtrm.Api;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;
using OpenEtrm.MarketData.Risk;
using Npgsql;
using OpenEtrm.MarketData.Power;
using OpenEtrm.Shared.Temporal;

internal static class MarketPreparationReuseChecks
{
    private sealed record Consumer(ImmutableArray<CurveRequest> Inputs,PriceUnit Unit):ApiSidedProbe(Guid.NewGuid(),Unit.Currency,Unit.Quantity,Inputs,
        _=>throw new Exception("Market preparation must not value the consumer Side."),"synthetic_market_consumer_v1")
    {
        public override ReferenceKey Currency=>Unit.Currency;
        public override Quantity UnitQuantity=>new(ExactDecimal.Parse("1"),Unit.Quantity);
        public override UnitPricingContract Declare(UnitValuationContext context)=>new(Id,"synthetic_market_consumer_v1",Inputs,Unit.Quantity,Unit.Currency) { Time = ValuationTimeDependency.Independent };
    }
    internal static void Run()
    {
        RetainedPreparation();
        var fixture=PreviewDataChecks.Fixture(405);
        PreviewData Data()=>new(fixture.Manifest,fixture.Definitions,fixture.References,fixture.Observations);
        var data=Data();
        using var source=NpgsqlDataSource.Create("Host=127.0.0.1;Database=synthetic_unopened;Username=synthetic");
        var database=new PreviewDatabase(fixture.Manifest,source);
        using var connection=source.CreateConnection();
        var frame=fixture.Frame with{ContextId=Guid.NewGuid()};
        var context=new ScheduleContext("2040-01-10",1,frame.At.ToString("O"),frame.ContextId);
        var dependencies=data.Contracts.Take(2).Select(c=>new CurveRequest(new(data.DefinitionRevision,"future"),c.Key)).ToImmutableArray();
        var consumers=new[]{new Consumer(dependencies,PriceUnit.FromQuote(data.Quotes.Single())),new Consumer(dependencies,PriceUnit.FromQuote(data.Quotes.Single()))};
        CustomCurves.PreparationScope? scope=null;
        CustomCurves.PreparedMarket Prepare(int consumer=0,PreviewData? selectedData=null,InputFrame? selectedFrame=null,
            ScheduleContext? selectedContext=null,ImmutableArray<CurveRequest>? selectedDependencies=null,
            ImmutableArray<SchedulePriceTerm>? prices=null,NpgsqlConnection? selectedConnection=null,CancellationToken cancellation=default)
        {
            var read=selectedData??data;var selected=selectedFrame??frame;
            return CustomCurves.PrepareMarket(selectedConnection??connection,database,read,selected,read.Snapshot(selected),selectedContext??context,
                [consumers[consumer]],selectedDependencies??dependencies,CustomCurves.MarketPreparation.ValuationDependencies,cancellation,
                activePrices:prices,preparationScope:scope).GetAwaiter().GetResult();
        }
        static void Require(bool value,string message){if(!value)throw new Exception(message);}
        static string Refusal(Action operation)
        {try{operation();}catch(MarketDataException error){return error.Code;}throw new Exception("Expected a market admission refusal.");}
        Prepare();scope=new();
        var before=GC.GetAllocatedBytesForCurrentThread();
        var first=Prepare();var second=Prepare(1);
        var allocated=GC.GetAllocatedBytesForCurrentThread()-before;
        Console.WriteLine($"Repeated ordinary preparation: {allocated} bytes, {first.Preparation.SourceCompilations+second.Preparation.SourceCompilations} source compilations, two dependencies among 405 loaded quotes.");
        foreach(var dependency in dependencies)
            Require(first.Valuation.Scenario.Price(first.Bindings[dependency])==second.Valuation.Scenario.Price(second.Bindings[dependency]),"Shared ordinary inputs changed an exact price.");
        Require(consumers[0].Id!=consumers[1].Id&&first.Preparation.SourceCompilations+second.Preparation.SourceCompilations==1,
            "Two distinct instruments in one operation must compile identical ordinary market inputs once.");
        Require(Prepare(selectedDependencies:[..dependencies.Reverse()]).Preparation.SourceCompilations==0,"Dependency ordering must not prevent exact set reuse.");
        Require(Prepare(selectedDependencies:[dependencies[0]]).Preparation.SourceCompilations==1,"A different dependency set needs its own preparation.");
        Require(Prepare(selectedData:Data()).Preparation.SourceCompilations==1,"Independent authorized data must not share preparation.");
        using(var other=source.CreateConnection())Require(Prepare(selectedConnection:other).Preparation.SourceCompilations==1,"Another connection must not share preparation.");
        var otherFrame=frame with{ContextId=Guid.NewGuid()};
        Require(Prepare(selectedFrame:otherFrame,selectedContext:context with{ContextId=otherFrame.ContextId}).Preparation.SourceCompilations==1,"Another retained context must prepare independently.");
        var missing=frame with{ObservationIds=frame.ObservationIds.RemoveAt(0)};
        var expectedMissing=Refusal(()=>data.Model.Build(data.Snapshot(missing),dependencies));
        Require(Refusal(()=>Prepare(selectedFrame:missing))==expectedMissing,"A warmed scope must still refuse a missing required pin.");
        var contract=data.Contracts[0] with{Kind=ContractKind.Forward,FuturesSeries=null};var quote=data.Quotes.Single();var index=new ReferenceKey(data.ReferenceRevision,"synthetic_index");
        var fixing=new IndexFixing(index,quote.Key,contract.DeliveryFrom,contract.DeliveryTo,frame.At,
            new(data.DefinitionRevision,Guid.NewGuid()),new(data.ReferenceRevision,"synthetic_source"),IndexFixing.SupportedImplementation);
        var side=new FloatingSide(Guid.NewGuid(),PriceSettlementSelection.CurveTarget(index),quote,new(ExactDecimal.Parse("1"),quote.Quantity),
            contract.DeliveryFrom,contract.DeliveryTo,[fixing],frame.At.AddMonths(3),FloatingAveraging.MonthlyIndexPrice,[new(dependencies[0],contract)],FloatingSide.IndexedImplementation,SyntheticSideCalendars.Dated(true,null,null));
        var price=((SidePaymentSchedule)side.GenerateSchedule()).Payments.Single().Prices.Single();
        var expectedFixing=Refusal(()=>IndexFixingPricing.Resolve(first.Authority,price.Lookup!));
        Require(Refusal(()=>Prepare(prices:[price]))==expectedFixing,"A cached market must still validate this instrument's active fixing.");
        Require(Prepare().Preparation.SourceCompilations==0,"Failed instrument admission must not poison an admitted market.");
        using(var cancelled=new CancellationTokenSource())
        {
            cancelled.Cancel();
            try{Prepare(cancellation:cancelled.Token);throw new Exception("A cache hit ignored cancellation.");}
            catch(OperationCanceledException){}
        }
        scope=new();Require(Prepare().Preparation.SourceCompilations==1,"Another operation requires fresh preparation.");
        Console.WriteLine("PASS ordinary preparation reuse: distinct consumers, exact sets/pins/context/data/connection and active-fixing refusal");
    }
    private static void RetainedPreparation()
    {
        var f=StructuredPowerChecks.Fixture();var one=ExactDecimal.Parse("1");
        var at=DateTimeOffset.Parse("2040-01-31T00:00:00Z");var day=new DateOnly(2040,2,1);var contextId=Guid.NewGuid();
        var quote=f.Data.QuoteRows("energy_price").Single();var unit=new Quantity(one,new(f.Data.ReferenceRevision,"right"));
        var payment=new PaymentRule(PaymentFrequency.Monthly,PaymentDateRule.DaysAfterPeriodEnd,18,null,PaymentDayBasis.CalendarDays,null,DateRoll.Unadjusted,null,PaymentRule.Implementation);
        var calendar=new SideCalendarPolicy(CalendarBinding.NotApplicable(),CalendarBinding.NotApplicable(),CalendarBinding.NotApplicable(),SideCalendarPolicy.Implementation);
        var interval=new DeliveryInterval(at.AddDays(1),at.AddDays(1).AddHours(1),day,0,0,1);
        var side=new FixedSide(Guid.NewGuid(),new OperatingSideTerms(unit,quote,payment,ComponentKind.Payment,
            [new(interval,day,day.AddMonths(1),new(null,new(ExactDecimal.Parse("5"),quote.Quantity)),null)],OperatingSideTerms.SupportedImplementation,calendar),
            new FlatPrice(new(ExactDecimal.Parse("100"),quote)));
        var program=BookedSideProgram.Compile(ScheduleDefinitionCompiler.Generate(side));
        var instrument=new RetainedOperatingInstrument(Guid.NewGuid(),new(f.Data.DefinitionRevision,f.Terms.FacilityCode),unit,quote.Currency,
            [new(side.Id,one,program)]);
        var setup=new ValuationSetup(ValuationMeasure.PresentValue,ImmutableDictionary<Guid,FuturesMarketBinding>.Empty,
            new ExplicitDiscounting(one,DiscountFactorSource.Undiscounted));
        var portfolio=ValuationPortfolio.FromTrades([new Trade(Guid.NewGuid(),Guid.NewGuid(),[new(Guid.NewGuid(),instrument,unit)])],setup);
        var frame=new InputFrame(Guid.NewGuid(),"Synthetic retained programme source",at,new(2040,1,31),[],ImmutableDictionary<string,ImmutableArray<Guid>>.Empty)
            {Source=CatalogueSource.From(f.Data),ContextId=contextId};
        var snapshot=f.Data.Snapshot(frame).WithKnowledge(contextId,at);var context=new ScheduleContext("2040-01-31",1,at.ToString("O"),contextId);
        using var source=NpgsqlDataSource.Create("Host=127.0.0.1;Database=synthetic_unopened;Username=synthetic");
        var database=new PreviewDatabase(f.Manifest,source);using var connection=source.CreateConnection();
        // Both installed native readers supply this retained operating-program
        // shape after source admission. Preparing it must not reinterpret its
        // stored instructions as newly authored dated fixing terms.
        var operating=OperatingPortfolio.PrepareMarket(connection,database,new(f.Data,frame,snapshot,portfolio,[]),context,default).GetAwaiter().GetResult();
        var certificate=RecPortfolio.PrepareMarket(connection,database,new(f.Data,frame,snapshot,portfolio,[]),context,default).GetAwaiter().GetResult();
        foreach(var market in new[]{operating,certificate})
            if(market.Authority.Snapshot.Knowledge?.ContextId!=contextId||!market.Bindings.IsEmpty)
                throw new Exception("Retained contract-only market preparation must preserve its exact source and require no invented fixing or mark input.");
        try
        {
            CustomCurves.PrepareMarket(connection,database,f.Data,frame,snapshot,context,[instrument],[],CustomCurves.MarketPreparation.ValuationDependencies,default).GetAwaiter().GetResult();
            throw new Exception("Unknown retained programme price metadata must not be silently skipped by generic preparation.");
        }
        catch(MarketDataException error)when(error.Code=="schedule_row_kind"){}
        Console.WriteLine("PASS retained operating/certificate source preparation: explicit contract-only inputs, genuine saved Side programs and unknown-program fallback refusal");
    }

}
