using System.Collections.Immutable;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Trading;
using OpenEtrm.Shared.Temporal;
using OpenEtrm.Shared.Numerics;
using OpenEtrm.MarketData.Risk;

internal static class OperatingSideChecks
{
    public static int Run()
    {
        var passed=0;
        void Check(string name,Action action){action();passed++;Console.WriteLine("PASS operating sides: "+name);}
        void Reject(string code,Action action)
        {try{action();}catch(MarketDataException error)when(error.Code==code){return;}throw new Exception("Expected "+code);}
        void Equal(ExactMoney value,string expected)
        {if(value.ToMoney().Amount.ToString()!=expected)throw new Exception($"Expected {expected}, got {value.ToExactString()}");}
        OperatingQuantityInputs Inputs(MarketSnapshot snapshot,DateTimeOffset knownAt,ImmutableArray<OperatingQuantityCell> cells)=>
            new(snapshot,knownAt,cells,IntervalKnowledgePolicy.ResolvedCutoff);
        var f=new Fixture();var unbound=f.Snapshot();var snapshot=unbound.WithKnowledge(Guid.NewGuid(),unbound.ValuationAt);var one=ExactDecimal.Parse("1");
        var right=new Quantity(one,f.R("right_count"));var resource=new AssetKey(f.Revision,"synthetic_unit");
        var plan=new OperatingPlanReference(f.Revision,Guid.NewGuid(),1);
        var interval=new DeliveryInterval(Fixture.Utc("2041-01-01T00:00:00Z"),Fixture.Utc("2041-01-01T01:00:00Z"),new(2041,1,1),0,0,1);
        var power=new OperatingOutputPort(plan,resource,OperatingOutputKind.EnergyOutput,f.Quotes[2].Quantity);
        var fuel=new OperatingOutputPort(plan,resource,OperatingOutputKind.FuelInput,f.Quotes[0].Quantity);
        var rule=new PaymentRule(PaymentFrequency.Monthly,PaymentDateRule.DaysAfterPeriodEnd,1,null,PaymentDayBasis.CalendarDays,
            null,DateRoll.Unadjusted,null,PaymentRule.Implementation);
        var calendars=new SideCalendarPolicy(CalendarBinding.NotApplicable(),CalendarBinding.NotApplicable(),CalendarBinding.NotApplicable(),SideCalendarPolicy.Implementation);
        OperatingSideTerms Terms(QuoteSpecification quote,OperatingQuantityTerm quantity)=>new(right,quote,rule,ComponentKind.Payment,
            [new(interval,new(2041,1,1),new(2041,2,1),quantity,null)],OperatingSideTerms.SupportedImplementation,calendars);
        var output=new FixedSide(Guid.NewGuid(),Terms(f.Quotes[2],new(power,null)),new FlatPrice(new(ExactDecimal.Parse("60"),f.Quotes[2])));
        var gas=new FixedSide(Guid.NewGuid(),Terms(f.Quotes[0],new(fuel,null)),new FlatPrice(new(ExactDecimal.Parse("3"),f.Quotes[0])));
        var variable=new FixedSide(Guid.NewGuid(),Terms(f.Quotes[2],new(power,null)),new FlatPrice(new(ExactDecimal.Parse("2"),f.Quotes[2])));
        var inputs=Inputs(snapshot,snapshot.ValuationAt,[new(power,interval,ExactQuantity.FromQuantity(new(ExactDecimal.Parse("5"),power.Quantity)),VolumeState.Forecast,Guid.NewGuid(),snapshot.ValuationAt),
            new(fuel,interval,ExactQuantity.FromQuantity(new(ExactDecimal.Parse("35"),fuel.Quantity)),VolumeState.Forecast,Guid.NewGuid(),snapshot.ValuationAt)]);
        var context=new SideValuationContext(snapshot,new ExplicitDiscounting(one,DiscountFactorSource.Undiscounted)).WithOperatingQuantities(inputs);
        var instrument=new OperatingRightInstrument(Guid.NewGuid(),resource,right,f.Quotes[0].Currency,
            [new(output,one),new(gas,ExactDecimal.Parse("-1")),new(variable,ExactDecimal.Parse("-1"))]);
        Check("independent fixed sides consume one plan and aggregate native energy and fuel exactly",()=>Equal(instrument.PV(context).PresentValue,"185"));
        Check("common schedule inspection preserves exact operating coordinates and signed holding amounts",()=>
        {
            var view=output.PV(context).InspectSchedule("synthetic-operating-schedule",ExactDecimal.Parse("2"),new SignedRatio(-1,1),
                day=>new DateTimeOffset(day.ToDateTime(TimeOnly.MinValue,DateTimeKind.Utc)));
            var page=view.Read(0,10);var row=page.Rows.Single();
            if(page.Manifest!="synthetic-operating-schedule"||view.ContextId!=snapshot.Knowledge!.ContextId||row.Start!=interval.Start||
                row.End!=interval.End||row.Quantity!="-10"||row.Amount!="-600"||row.PresentValue!="-600"||row.Lifecycle.Cash!="NotTracked")
                throw new Exception("The common inspector must retain the evaluated interval, signed holding value and independent cash state.");
        });
        Check("operating terms require explicit calendar applicability and reject unused owned calendars",()=>
        {
            Reject("side_calendar_policy",()=>new FixedSide(Guid.NewGuid(),output.OperatingDefinition! with{CalendarPolicy=null!},output.Price));
            Reject("side_calendar_applicability",()=>new FixedSide(Guid.NewGuid(),output.OperatingDefinition! with{CalendarPolicy=SyntheticSideCalendars.Dated(false)},output.Price));
        });
        Check("operating cash remains nominal throughout its UTC payment day",()=>
        {
            var literal=new FixedSide(Guid.NewGuid(),Terms(f.Quotes[2],new(null,new(ExactDecimal.Parse("5"),power.Quantity))),output.Price);
            var paymentDay=snapshot with{ValuationAt=literal.GenerateSchedule().Rows[0].PaymentAt.AddHours(12)};
            Equal(literal.PV(new SideValuationContext(paymentDay,new ExplicitDiscounting(ExactDecimal.Parse("0.5"),DiscountFactorSource.Explicit))).PresentValue,"300");
            Reject("side_payment_factors",()=>literal.PV(new SideValuationContext(paymentDay,new InvalidPaymentDayFactors())));
        });
        Check("literal access/start payments have independent schedules and apply once",()=>
        {
            var feeQuote=f.Quotes[0] with{Key=f.R("right_fee"),Quantity=right.Specification};
            var feeTerms=Terms(feeQuote,new(null,right));
            var start=new FixedSide(Guid.NewGuid(),feeTerms,new FlatPrice(new(ExactDecimal.Parse("10"),feeQuote)));
            var access=new FixedSide(Guid.NewGuid(),feeTerms,new FlatPrice(new(ExactDecimal.Parse("20"),feeQuote)));
            var complete=new OperatingRightInstrument(Guid.NewGuid(),resource,right,feeQuote.Currency,
                instrument.Sides.Add(new(start,ExactDecimal.Parse("-1"))).Add(new(access,ExactDecimal.Parse("-1"))));
            Equal(complete.PV(context).PresentValue,"155");
            Equal(start.PV(context).PresentValue,"10");Equal(access.PV(context).PresentValue,"20");
        });
        Check("schedule generation retains references independently of evaluated quantities",()=>
        {
            var row=output.GenerateSchedule().Rows.Single();
            if(row.QuantityReference is not OperatingScheduleQuantity source||source.Source.Port!=power||row.Interval!=interval||row.GeneratedDate is null)
                throw new Exception("The structural row lost its exact source, native interval or generated payment rule.");
            var result=(OperatingSideValuation)output.PV(context);
            if(result.Rows.Single().OperatingEvidence?.EvidenceId!=inputs.Cells[0].EvidenceId||result.Rows[0].QuantityState!=VolumeState.Forecast)
                throw new Exception("Valued row must retain selected evidence and its state.");
        });
        Check("nonterminating operating quantities remain rational until final cash",()=>
        {
            var fractional=inputs.Cells[0] with{Quantity=ExactQuantity.FromQuantity(new(one,power.Quantity)).Scale(new ExactRatio(1,3))};
            var fractionContext=context.WithOperatingQuantities(Inputs(snapshot,snapshot.ValuationAt,[fractional,inputs.Cells[1]]));
            Equal(output.PV(fractionContext).PresentValue,"20");
        });
        Check("a new selected quantity context cannot reuse a cached side value",()=>
        {
            Equal(instrument.PV(context).PresentValue,"185");
            var corrected=inputs.Cells[0] with{Quantity=ExactQuantity.FromQuantity(new(ExactDecimal.Parse("6"),power.Quantity)),EvidenceId=Guid.NewGuid()};
            var changed=context.WithOperatingQuantities(Inputs(snapshot,snapshot.ValuationAt,[corrected,inputs.Cells[1]]));
            Equal(instrument.PV(changed).PresentValue,"243");
            Equal(instrument.PV(context).PresentValue,"185");
        });
        Check("missing, duplicate, incompatible and later-known evidence fail explicitly",()=>
        {
            Reject("operating_quantity_missing",()=>gas.PV(context.WithOperatingQuantities(Inputs(snapshot,snapshot.ValuationAt,[inputs.Cells[0]]))));
            Reject("operating_inputs",()=>Inputs(snapshot,snapshot.ValuationAt,[inputs.Cells[0],inputs.Cells[0]]));
            Reject("operating_inputs",()=>Inputs(snapshot,snapshot.ValuationAt,[inputs.Cells[0] with{KnownAt=snapshot.ValuationAt.AddSeconds(1)}]));
            Reject("operating_context",()=>Inputs(snapshot,snapshot.ValuationAt.AddHours(1),[inputs.Cells[0] with{KnownAt=snapshot.ValuationAt.AddMinutes(1)}]));
            Reject("operating_inputs",()=>Inputs(snapshot,snapshot.ValuationAt,[inputs.Cells[0] with{State=VolumeState.Metered}]));
            Reject("operating_inputs",()=>Inputs(snapshot,snapshot.ValuationAt,[inputs.Cells[0] with{Quantity=inputs.Cells[1].Quantity}]));
            Reject("operating_context",()=>context.WithOperatingQuantities(Inputs(snapshot with{ValuationAt=snapshot.ValuationAt.AddMinutes(1)},snapshot.ValuationAt,inputs.Cells)));
            Reject("operating_inputs",()=>output.PV(new SideValuationContext(snapshot,new ExplicitDiscounting(one,DiscountFactorSource.Undiscounted))));
        });
        Check("floating operating quantities reprice against the shared immutable market scenario",()=>
        {
            var request=new CurveRequest(f.C("local_power"),f.K(5));
            var terms=Terms(f.Quotes[2],new(power,null));terms=terms with{Periods=[new(interval,new(2041,1,1),new(2041,2,1),new(power,null),request)]};
            var floating=new FloatingSide(Guid.NewGuid(),terms);
            var bump=new QuoteBump(new(f.S(1),InputUse.Variable),f.Quotes[0].Key,PriceUnit.FromQuote(f.Quotes[0]),ExactDecimal.Parse("0.1"),QuoteBump.Convention);
            var scenarios=f.Model().BuildScenarios(snapshot,floating.Dependencies,[bump]);
            var discount=new ExplicitDiscounting(one,DiscountFactorSource.Undiscounted);
            var original=new SideValuationContext(scenarios.Base,discount).WithOperatingQuantities(inputs);
            var up=new SideValuationContext(scenarios.Factors[0].Up,discount).WithOperatingQuantities(inputs);
            var down=new SideValuationContext(scenarios.Factors[0].Down,discount).WithOperatingQuantities(inputs);
            Equal(floating.PV(original).PresentValue,"145.5");Equal(floating.PV(up).PresentValue,"149");Equal(floating.PV(down).PresentValue,"142");
            if(!floating.Dependencies.SequenceEqual([request]))throw new Exception("The side lost its declared price reference.");
        });
        Check("exact economic identity includes source versions while prior fixed-side identity stays stable",()=>
        {
            var same=new FixedSide(Guid.NewGuid(),output.OperatingDefinition!,output.Price);
            if(DefinitionIdentity.For(output)!=DefinitionIdentity.For(same))throw new Exception("Side identity must exclude caller IDs.");
            var altered=power with{Plan=plan with{Version=2}};
            var changed=new FixedSide(Guid.NewGuid(),Terms(f.Quotes[2],new(altered,null)),output.Price);
            if(DefinitionIdentity.For(output)==DefinitionIdentity.For(changed))throw new Exception("Selected source version must enter side identity.");
            var ordinary=new FixedSide(Guid.NewGuid(),new UnitPrice(one,f.Quotes[0]),new(one,f.Quotes[0].Quantity),new(2041,1,1),new(2041,2,1),
                Fixture.Utc("2041-02-02T00:00:00Z"),FixedSide.Implementation,f.Quotes[0],SyntheticSideCalendars.Dated(false));
            if(DefinitionIdentity.For(ordinary).Canonical.Contains("OperatingDefinition",StringComparison.Ordinal))
                throw new Exception("Adding a new supported mode must not reinterpret existing canonical terms.");
        });
        Check("cross-resource plans, overlapping rows and multiplied exclusive rights refuse",()=>
        {
            var elsewhere=power with{Resource=new(f.Revision,"another_unit")};
            var wrong=new FixedSide(Guid.NewGuid(),Terms(f.Quotes[2],new(elsewhere,null)),output.Price);
            Reject("operating_plan",()=>new OperatingRightInstrument(Guid.NewGuid(),resource,right,f.Quotes[0].Currency,[new(wrong,one)]));
            Reject("operating_terms",()=>new FixedSide(Guid.NewGuid(),Terms(f.Quotes[2],new(power,new(one,power.Quantity))),output.Price));
            Reject("operating_grid",()=>new FixedSide(Guid.NewGuid(),output.OperatingDefinition! with{Periods=[output.OperatingDefinition!.Periods[0],output.OperatingDefinition.Periods[0]]},output.Price));
            Reject("operating_right_quantity",()=>new TradeInstrument(Guid.NewGuid(),instrument,new(ExactDecimal.Parse("2"),right.Specification)));
            _=new TradeInstrument(Guid.NewGuid(),instrument,right);
        });
        Check("native repeated-hour labels and explicit payment-factor ownership are retained",()=>
        {
            var repeated=interval with{Occurrence=2};
            var row=new OperatingSidePeriod(repeated,new(2041,1,1),new(2041,2,1),new(power,null),null);
            var side=new FixedSide(Guid.NewGuid(),output.OperatingDefinition! with{Periods=[row]},output.Price);
            var selected=inputs.Cells[0] with{Interval=repeated};
            Equal(side.PV(context.WithOperatingQuantities(Inputs(snapshot,snapshot.ValuationAt,[selected]))).PresentValue,"300");
            Reject("operating_grid",()=>new FixedSide(Guid.NewGuid(),output.OperatingDefinition with{Periods=[new(interval with{Occurrence=0},new(2041,1,1),new(2041,2,1),new(power,null),null)]},output.Price));
            var due=snapshot with{ValuationAt=Fixture.Utc("2041-02-02T00:00:00Z")};
            Reject("side_payment_due",()=>output.PV(new SideValuationContext(due,new ExplicitDiscounting(one,DiscountFactorSource.Undiscounted))));
        });
        Check("published quantities cannot advance the certified knowledge carried by the snapshot",()=>
        {
            var certified=snapshot.WithKnowledge(Guid.NewGuid(),snapshot.ValuationAt);
            Reject("operating_context",()=>Inputs(unbound,unbound.ValuationAt,[]));
            var ended=interval with{Start=snapshot.ValuationAt.AddHours(-1),End=snapshot.ValuationAt};
            var meter=inputs.Cells[0] with{Interval=ended,State=VolumeState.Metered,KnownAt=snapshot.ValuationAt.AddMinutes(1)};
            Reject("operating_context",()=>Inputs(certified,snapshot.ValuationAt.AddHours(1),[meter]));
            var corrected=certified.WithKnowledge(certified.Knowledge!.ContextId,snapshot.ValuationAt.AddHours(1));
            _=Inputs(corrected,corrected.Knowledge!.KnownAt,[meter]);
            Reject("operating_inputs",()=>Inputs(certified,snapshot.ValuationAt,[meter with{KnownAt=ended.Start}]));
            Reject("operating_context",()=>new OperatingQuantityInputs(certified,snapshot.ValuationAt.AddHours(1),[],IntervalKnowledgePolicy.ValuationInstant));
            _=new OperatingQuantityInputs(corrected,corrected.ValuationAt,[],IntervalKnowledgePolicy.ValuationInstant);
        });
        Check("standalone side admission rejects a quote with cross-revision currency or native quantity",()=>
        {
            var foreign=new ReferenceRevision(Guid.NewGuid(),Guid.NewGuid());
            var mixed=f.Quotes[2] with{Currency=new(foreign,"currency"),Quantity=new(foreign,"energy")};
            Reject("operating_terms",()=>new FixedSide(Guid.NewGuid(),Terms(mixed,new(null,new(one,mixed.Quantity))),output.Price));
        });
        Check("hypothetical supplied quantities do not manufacture published evidence or knowledge",()=>
        {
            var hypothetical=OperatingQuantityInputs.Scenario(unbound,[new(power,interval,inputs.Cells[0].Quantity)],OperatingQuantityInputs.ScenarioImplementation);
            var selected=new SideValuationContext(unbound,new ExplicitDiscounting(one,DiscountFactorSource.Undiscounted)).WithOperatingQuantities(hypothetical);
            var result=(OperatingSideValuation)output.PV(selected);
            Equal(result.PresentValue,"300");
            if(result.Rows[0].OperatingEvidence is not null||hypothetical.KnownAt is not null||hypothetical.KnowledgePolicy is not null||!hypothetical.Cells.IsEmpty)
                throw new Exception("Hypothetical calculations must not assert source publication or a certified evidence cutoff.");
            Reject("operating_scenario",()=>OperatingQuantityInputs.Scenario(unbound,[],"unknown"));
            Reject("operating_scenario",()=>OperatingQuantityInputs.Scenario(unbound,[new(power,interval,inputs.Cells[1].Quantity)],OperatingQuantityInputs.ScenarioImplementation));
        });
        return passed;
    }
    private sealed class InvalidPaymentDayFactors:ISideDiscounting
    {
        public ImmutableArray<SidePaymentFactor> Resolve(ImmutableArray<SidePaymentKey> payments,MarketSnapshot snapshot)=>
            [..payments.Select(payment=>new SidePaymentFactor(payment,ExactDecimal.Parse("0.5"),snapshot,DiscountFactorSource.Explicit))];
    }
}
