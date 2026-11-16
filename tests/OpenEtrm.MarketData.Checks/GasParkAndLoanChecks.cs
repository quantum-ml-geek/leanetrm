using System.Collections.Immutable;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Gas;
using OpenEtrm.MarketData.Risk;
using OpenEtrm.MarketData.Trading;

internal static class GasParkAndLoanChecks
{
    public static void Run()
    {
        var f=new Fixture();var quote=f.Quotes[0];
        var advance=Fixture.Utc("2040-12-19T00:00:00Z");var due=advance.AddDays(5);
        GasParkAndLoanTerms Terms(string service,string perspective,ExactDecimal direction)=>new(
            GasParkAndLoanTerms.Version,service,perspective,GasCommodityLoan.TitleTransfer,GasParkAndLoanTerms.EqualQuantity,
            f.R("location"),quote.Quantity,quote.Currency,new(f.C("future"),f.K(1)),advance,due,
            GasHoldingCarrying.Nominal,new(ExactDecimal.Parse("18"),quote.Currency),direction,due.AddDays(2),GasParkAndLoanTerms.ReturnsAfterAdvance);
        foreach(var (service,perspective,sign) in new[]{
            (GasParkAndLoanTerms.Loan,GasParkAndLoanTerms.Customer,"1"),
            (GasParkAndLoanTerms.Park,GasParkAndLoanTerms.Provider,"1"),
            (GasParkAndLoanTerms.Loan,GasParkAndLoanTerms.Provider,"-1"),
            (GasParkAndLoanTerms.Park,GasParkAndLoanTerms.Customer,"-1")})
        {
            var terms=Terms(service,perspective,ExactDecimal.Parse("-1"));
            Equal(terms.AdvanceDirection,sign);
            Quantity Q(string amount)=>new(ExactDecimal.Parse(amount),quote.Quantity);
            var before=GasParkAndLoanPrincipal.Plan(terms,Q("720"),Q("0"),Q("0"),advance.AddDays(-1));
            Equal(before.RemainingAdvance.Amount,"720");Equal(before.OutstandingReturn.Amount,"0");Equal(before.OverdueReturn.Amount,"0");
            var partial=GasParkAndLoanPrincipal.Plan(terms,Q("720"),Q("720"),Q("270"),due.AddHours(-1));
            Equal(partial.RemainingAdvance.Amount,"0");Equal(partial.OutstandingReturn.Amount,"450");Equal(partial.OverdueReturn.Amount,"0");
            Equal(partial.SignedReturnHolding.Amount,sign=="1"?"-450":"450");
            var overdue=GasParkAndLoanPrincipal.Plan(terms,Q("720"),Q("720"),Q("270"),due.AddDays(1));
            Equal(overdue.OutstandingReturn.Amount,"450");Equal(overdue.OverdueReturn.Amount,"450");
            Equal(GasParkAndLoanPrincipal.Plan(terms,Q("720"),Q("720"),Q("270"),due).OverdueReturn.Amount,"450");
            var complete=GasParkAndLoanPrincipal.Plan(terms,Q("720"),Q("720"),Q("720"),due.AddDays(2));
            Equal(complete.OutstandingReturn.Amount,"0");Equal(complete.SignedReturnHolding.Amount,"0");
            // The fee is a separate amount. Principal performance and gas size
            // never pay, scale or reverse it.
            Equal(before.FixedFee.Amount,"-18");Equal(partial.FixedFee.Amount,"-18");Equal(complete.FixedFee.Amount,"-18");
            Equal(GasParkAndLoanPrincipal.Plan(terms,Q("1440"),Q("1440"),Q("0"),due).FixedFee.Amount,"-18");
            Reject("gas_park_loan_principal",()=>GasParkAndLoanPrincipal.Plan(terms,Q("720"),Q("720"),Q("721"),due));
            Reject("gas_park_loan_principal",()=>GasParkAndLoanPrincipal.Plan(terms,Q("720"),Q("0"),Q("1"),due));
            Reject("gas_park_loan_principal",()=>GasParkAndLoanPrincipal.Plan(terms,Q("720"),Q("721"),Q("0"),due));
            Reject("gas_park_loan_principal",()=>GasParkAndLoanPrincipal.Plan(terms,Q("720"),Q("270"),Q("0"),due));
            Reject("gas_park_loan_principal",()=>GasParkAndLoanPrincipal.Plan(terms,Q("720"),Q("1"),Q("0"),advance.AddMicroseconds(-1)));
            Reject("gas_park_loan_principal",()=>GasParkAndLoanPrincipal.Plan(terms,Q("0"),Q("0"),Q("0"),due));
            Reject("gas_park_loan_principal",()=>GasParkAndLoanPrincipal.Plan(terms,Q("720"),Q("0"),new(default,f.R("other_quantity")),due));
            var accepted=GasParkAndLoanPrincipal.Advance(terms,Q("720"),Q("0"),Q("720"),advance.AddHours(1));
            Equal(accepted.OutstandingReturn.Amount,"720");
            Reject("gas_park_loan_advance",()=>GasParkAndLoanPrincipal.Advance(terms,Q("720"),Q("0"),Q("270"),advance));
            Reject("gas_park_loan_advance",()=>GasParkAndLoanPrincipal.Advance(terms,Q("720"),Q("720"),Q("720"),advance));
            Reject("gas_park_loan_advance",()=>GasParkAndLoanPrincipal.Advance(terms,Q("720"),Q("0"),Q("720"),advance.AddMicroseconds(-1)));
            Equal(GasParkAndLoanPrincipal.Advance(terms,Q("720"),Q("0"),Q("720"),due.AddMicroseconds(-1)).OutstandingReturn.Amount,"720");
            Reject("gas_park_loan_advance",()=>GasParkAndLoanPrincipal.Advance(terms,Q("720"),Q("0"),Q("720"),due));
            Reject("gas_park_loan_advance",()=>GasParkAndLoanPrincipal.Advance(terms,Q("720"),Q("0"),Q("720"),due.AddMicroseconds(1)));
            var returned=GasParkAndLoanPrincipal.Return(terms,Q("720"),Q("720"),Q("0"),advance.AddHours(1),Q("270"),advance.AddHours(2));
            Equal(returned.OutstandingReturn.Amount,"450");
            Reject("gas_park_loan_return",()=>GasParkAndLoanPrincipal.Return(terms,Q("720"),Q("720"),Q("0"),advance.AddHours(1),Q("270"),advance.AddMinutes(30)));
            Reject("gas_park_loan_return",()=>GasParkAndLoanPrincipal.Return(terms,Q("720"),Q("720"),Q("0"),advance.AddHours(1),Q("270"),advance.AddHours(1)));
        }
        var received=Terms(GasParkAndLoanTerms.Park,GasParkAndLoanTerms.Customer,ExactDecimal.Parse("1"));
        Equal(GasParkAndLoanPrincipal.Plan(received,new(ExactDecimal.Parse("720"),quote.Quantity),new(default,quote.Quantity),new(default,quote.Quantity),due).FixedFee.Amount,"18");
        Reject("gas_park_loan_terms",()=>Terms("unknown",GasParkAndLoanTerms.Customer,ExactDecimal.Parse("1")));
        Reject("gas_park_loan_terms",()=>Terms(GasParkAndLoanTerms.Loan,"unknown",ExactDecimal.Parse("1")));
        Reject("gas_park_loan_terms",()=>Terms(GasParkAndLoanTerms.Loan,GasParkAndLoanTerms.Customer,default));
        Composition();NativeHandoff();FeeDeterminationBoundary();
        Console.WriteLine("PASS gas park and loan: both commercial perspectives, exact principal conservation, explicit overdue and independent fixed fee");
    }

    private static void FeeDeterminationBoundary()
    {
        var f=new Fixture();var quote=f.Quotes[0];var advance=Fixture.Utc("2040-12-19T12:00:00Z");
        GasParkAndLoanTerms Terms(string amount,string direction,DateTimeOffset? due)=>new(GasParkAndLoanTerms.Version,
            GasParkAndLoanTerms.Loan,GasParkAndLoanTerms.Customer,GasCommodityLoan.TitleTransfer,GasParkAndLoanTerms.EqualQuantity,
            f.R("location"),quote.Quantity,quote.Currency,new(f.C("future"),f.K(1)),advance,advance.AddDays(5),GasHoldingCarrying.Nominal,
            new(ExactDecimal.Parse(amount),quote.Currency),ExactDecimal.Parse(direction),due,GasParkAndLoanTerms.ReturnsAfterAdvance);
        foreach(var direction in new[]{"-1","1"})
        {
            Reject("gas_park_loan_terms",()=>Terms("18",direction,advance.AddMicroseconds(-1)));
            if(Terms("18",direction,advance).FeeDueAt!=advance||Terms("18",direction,advance.AddMicroseconds(1)).FeeDueAt!=advance.AddMicroseconds(1))
                throw new Exception("The installed fee rule admits an explicit due instant at or after its planned advance.");
            var zero=Terms("0",direction,null);
            if(zero.FeeDueAt is not null||zero.FixedFee.Amount!=default||zero.FeeDirection!=ExactDecimal.Parse(direction))
                throw new Exception("An explicitly zero fee retains no payment due and preserves its independently selected direction.");
            if(zero.FeeRecognition!="accepted_advance_v1"||GasParkAndLoanTerms.FeeAtAdvance!=zero.FeeRecognition||
                !DefinitionIdentity.For(zero).Canonical.Contains("\"FeeRecognition\":\"accepted_advance_v1\"",StringComparison.Ordinal))
                throw new Exception("The explicitly selected installed profile must identify its immutable fee determination rule in economic identity.");
        }
    }

    private static void NativeHandoff()
    {
        var f=new Fixture();var quote=f.Quotes[0];var at=f.Snapshot().ValuationAt;
        var unit=PriceUnit.FromQuote(quote);var mark=new CurveRequest(f.C("future"),f.K(1));
        var bump=new QuoteBump(new(f.S(1),InputUse.Variable),quote.Key,unit,ExactDecimal.Parse("1"),QuoteBump.Convention);
        foreach(var (service,perspective,borrowing) in new[]{
            (GasParkAndLoanTerms.Loan,GasParkAndLoanTerms.Customer,true),
            (GasParkAndLoanTerms.Park,GasParkAndLoanTerms.Provider,true),
            (GasParkAndLoanTerms.Loan,GasParkAndLoanTerms.Provider,false),
            (GasParkAndLoanTerms.Park,GasParkAndLoanTerms.Customer,false)})
        {
            var terms=new GasParkAndLoanTerms(GasParkAndLoanTerms.Version,service,perspective,GasCommodityLoan.TitleTransfer,
                GasParkAndLoanTerms.EqualQuantity,f.R("location"),quote.Quantity,quote.Currency,mark,at.AddDays(1),at.AddDays(4),
                GasHoldingCarrying.Nominal,new(ExactDecimal.Parse("18"),quote.Currency),ExactDecimal.Parse(borrowing?"-1":"1"),
                at.AddDays(7),GasParkAndLoanTerms.ReturnsAfterAdvance);
            var fee=new TimedCashPayment(quote.Currency,terms.FeeDueAt!.Value);
            var stock=new GasCommodityHoldingInstrument(Guid.NewGuid(),mark,quote.Quantity,quote.Currency,null,GasHoldingCarrying.Nominal);
            var claim=new GasCommodityHoldingInstrument(Guid.NewGuid(),mark,quote.Quantity,quote.Currency,terms.ReturnAt,GasHoldingCarrying.Nominal);
            var book=Guid.NewGuid();var owner=new AccountingOwnerKey(AccountingOwnerKind.NativeHolding,Guid.NewGuid());
            var feeBinding=Guid.NewGuid();var feeOwner=new AccountingPositionKey(owner,feeBinding,book);
            var feeQuantity=new Quantity(terms.SignedFixedFee.Amount,quote.Currency);
            ExactGroupedRiskRun Stage(string stockQuantity,string returnQuantity,DateTimeOffset instant,bool paid)
            {
                var snapshot=(f.Snapshot() with{ValuationAt=instant}).WithKnowledge(Guid.NewGuid(),instant);
                var positions=new List<RiskPosition>();var instruments=new List<Instrument>();
                void Hold(Instrument instrument,Quantity quantity,Guid binding)
                {
                    instruments.Add(instrument);positions.Add(new(owner,binding,book,instrument.Id,quantity,
                        new(new Money(default,quote.Currency),quantity.Specification),new(default,quote.Currency)));
                }
                if(stockQuantity!="0")Hold(stock,new(ExactDecimal.Parse(stockQuantity),quote.Quantity),Guid.NewGuid());
                if(returnQuantity!="0")Hold(claim,new(ExactDecimal.Parse(returnQuantity),quote.Quantity),Guid.NewGuid());
                Hold(fee,feeQuantity,feeBinding);
                var allocations=paid?ImmutableArray.Create(new AccountingFlow(Guid.NewGuid(),1,feeOwner,terms.FeeDueAt.Value,
                    instant,ExactMoney.FromMoney(terms.SignedFixedFee),AccountingFlowKind.EconomicCash)):[];
                var state=new RecordedCashValuation(feeOwner,fee,feeQuantity,allocations,RecordedCashValuation.Policy,snapshot.Knowledge!.ContextId,instant);
                var setup=new ValuationSetup(ValuationMeasure.PresentValue,ImmutableDictionary<Guid,FuturesMarketBinding>.Empty,
                    new ExplicitDiscounting(ExactDecimal.Parse("0.95"),DiscountFactorSource.Explicit)){
                    BindingStates=ImmutableDictionary<MeasureBinding,IBindingValuationState>.Empty.Add(new(owner,feeBinding),state)};
                return RiskEngine.CalculateExact(RiskEngine.Prepare(f.Model(),snapshot,[new ValuationPortfolio([..instruments],[..positions],setup)]),
                    returnQuantity=="0"&&stockQuantity=="0"?[]:[bump],RiskEngine.ExactNumericalPolicy);
            }
            void Check(ExactGroupedRiskRun result,string expectedBase,string expectedUp,string expectedDown)
            {
                var group=result.Groups.Single();Equal(group.BaseValues.Single().Value,expectedBase);
                var values=group.Factors.Single().Totals.Single().Values;
                Equal(values.Base,expectedBase);Equal(values.Up,expectedUp);Equal(values.Down,expectedDown);
            }
            // Independent arithmetic at marks 3,4,2. A borrower receives stock
            // and the opposite debt; a lender exchanges its existing stock for
            // an equal claim, then receives independent returned stock.
            if(borrowing)
            {
                Check(Stage("720","-720",at.AddDays(1),false),"-17.1","-17.1","-17.1");
                Check(Stage("450","-450",at.AddDays(2),false),"-17.1","-17.1","-17.1");
                Check(Stage("0","-450",at.AddDays(2),false),"-1367.1","-1817.1","-917.1");
            }
            else
            {
                Check(Stage("0","720",at.AddDays(1),false),"2177.1","2897.1","1457.1");
                Check(Stage("270","450",at.AddDays(2),false),"2177.1","2897.1","1457.1");
                Check(Stage("720","0",at.AddDays(5),false),"2177.1","2897.1","1457.1");
            }
            Equal(Stage("0","0",at.AddDays(5),false).Groups.Single().BaseValues.Single().Value,borrowing?"-17.1":"17.1");
            Equal(Stage("0","0",terms.FeeDueAt.Value,false).Groups.Single().BaseValues.Single().Value,borrowing?"-18":"18");
            Equal(Stage("0","0",terms.FeeDueAt.Value,true).Groups.Single().BaseValues.Single().Value,"0");
        }
    }

    private static void Composition()
    {
        var f=new Fixture();var quote=f.Quotes[0];var at=f.Snapshot().ValuationAt;
        var terms=new GasParkAndLoanTerms(GasParkAndLoanTerms.Version,GasParkAndLoanTerms.Loan,GasParkAndLoanTerms.Customer,
            GasCommodityLoan.TitleTransfer,GasParkAndLoanTerms.EqualQuantity,f.R("location"),quote.Quantity,quote.Currency,
            new(f.C("future"),f.K(1)),at.AddDays(1),at.AddDays(6),GasHoldingCarrying.Nominal,
            new(ExactDecimal.Parse("18"),quote.Currency),ExactDecimal.Parse("-1"),at.AddDays(8),GasParkAndLoanTerms.ReturnsAfterAdvance);
        var quantity=new Quantity(ExactDecimal.Parse("720"),quote.Quantity);var zero=new Quantity(default,quote.Quantity);
        var components=GasParkAndLoanValuation.Components(terms,quantity,zero,at);
        if(components.Length!=3||components.Select(c=>c.Role).Distinct().Count()!=3||
            components.Count(c=>c.Instrument is GasCommodityHoldingInstrument)!=2||components.Count(c=>c.Instrument is TimedCashPayment)!=1)
            throw new Exception("A booked service requires two independent principal members and its separately held fixed cash fee.");
        Equal(components.Single(c=>c.Role==GasParkAndLoanValuation.AdvanceRole).Quantity.Amount,"720");
        Equal(components.Single(c=>c.Role==GasParkAndLoanValuation.ReturnRole).Quantity.Amount,"-720");
        Equal(components.Single(c=>c.Role==GasParkAndLoanValuation.FeeRole).Quantity.Amount,"-18");
        var larger=GasParkAndLoanValuation.Components(terms,new(ExactDecimal.Parse("1440"),quote.Quantity),zero,at);
        Equal(larger.Single(c=>c.Role==GasParkAndLoanValuation.FeeRole).Quantity.Amount,"-18");
        if(!GasParkAndLoanValuation.Components(terms,quantity,quantity,at.AddDays(2)).IsEmpty)
            throw new Exception("Accepted advance must remove every service contribution before native principal and fee owners take over.");
        var first=Guid.NewGuid();var second=Guid.NewGuid();
        if(GasParkAndLoanValuation.ComponentBinding(first,GasParkAndLoanValuation.AdvanceRole)==GasParkAndLoanValuation.ComponentBinding(second,GasParkAndLoanValuation.AdvanceRole)||
            GasParkAndLoanValuation.ComponentBinding(first,GasParkAndLoanValuation.AdvanceRole)==GasParkAndLoanValuation.ComponentBinding(first,GasParkAndLoanValuation.ReturnRole))
            throw new Exception("Each trade-owned principal occurrence requires a separate stable component binding.");
        var repeated=GasParkAndLoanValuation.Components(terms,quantity,zero,at);
        if(!components.Select(c=>c.Instrument.Id).SequenceEqual(repeated.Select(c=>c.Instrument.Id)))
            throw new Exception("Identical retained economics require deterministic reusable instruments.");
        var previewTrade=GasParkAndLoanValuation.PreviewIdentity(Guid.Empty,first,"trade");
        if(previewTrade!=GasParkAndLoanValuation.PreviewIdentity(Guid.Empty,first,"trade")||
            previewTrade==GasParkAndLoanValuation.PreviewIdentity(Guid.Empty,first,"instrument")||
            previewTrade==GasParkAndLoanValuation.PreviewIdentity(Guid.Empty,second,"trade"))
            throw new Exception("Draft owners must retain deterministic, distinct preview identities under their exact selected snapshot.");
        Reject("gas_park_loan_component",()=>GasParkAndLoanValuation.PreviewIdentity(Guid.Empty,Guid.Empty,"trade"));
        Reject("gas_park_loan_component",()=>GasParkAndLoanValuation.PreviewIdentity(Guid.Empty,first,"unknown"));
        _=DefinitionIdentity.For(terms);
        Reject("gas_park_loan_component",()=>GasParkAndLoanValuation.ComponentBinding(first,"unknown"));
        Reject("gas_park_loan_component",()=>GasParkAndLoanValuation.ComponentBinding(Guid.Empty,GasParkAndLoanValuation.FeeRole));
        Reject("gas_park_loan_terms",()=>GasParkAndLoanValuation.Components(null!,quantity,zero,at));
        foreach(var mark in new[]{"2","3","4"})
        {
            var snapshot=(f.Snapshot() with{Selections=[f.Select(1,QuoteKind.Outright,"gas_out",mark)]}).WithKnowledge(Guid.NewGuid(),at);
            var trade=new Trade(Guid.NewGuid(),Guid.NewGuid(),[..components.Select(c=>new TradeInstrument(
                GasParkAndLoanValuation.ComponentBinding(first,c.Role),c.Instrument,c.Quantity))]);
            var cash=components.Single(c=>c.Role==GasParkAndLoanValuation.FeeRole);
            var cashBinding=GasParkAndLoanValuation.ComponentBinding(first,cash.Role);
            var state=new RecordedCashValuation(trade,cashBinding,[],RecordedCashValuation.Policy,snapshot.Knowledge!.ContextId,snapshot.Knowledge.KnownAt);
            var setup=new ValuationSetup(ValuationMeasure.PresentValue,ImmutableDictionary<Guid,FuturesMarketBinding>.Empty,
                new ExplicitDiscounting(ExactDecimal.Parse("0.95"),DiscountFactorSource.Explicit)){
                BindingStates=ImmutableDictionary<MeasureBinding,IBindingValuationState>.Empty.Add(new(trade.Id,cashBinding),state)};
            var result=RiskEngine.CalculateExact(RiskEngine.Prepare(f.Model(),snapshot,[ValuationPortfolio.FromTrades([trade],setup)]),[],RiskEngine.ExactNumericalPolicy);
            // Independent oracle: the exact same-mark principal pair cancels at
            // every scenario; the independent fee is -18 times 0.95 = -17.1.
            Equal(result.Groups.Single().BaseValues.Select(v=>v.Value).Aggregate((a,b)=>a.Add(b)),"-17.1");
        }
    }

    private static void Equal(ExactDecimal actual,string expected)
    {if(actual!=ExactDecimal.Parse(expected))throw new Exception($"Expected {expected}; got {actual}.");}
    private static void Equal(ExactMoney actual,string expected)
    {if(actual!=ExactMoney.Parse(expected,actual.Currency))throw new Exception($"Expected {expected}; got {actual.ToExactString()}.");}
    private static void Reject(string code,Action action)
    {try{action();}catch(MarketDataException error)when(error.Code==code){return;}throw new Exception("Expected "+code);}
}
