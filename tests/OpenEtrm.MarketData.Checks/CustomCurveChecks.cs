using System.Collections.Immutable;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.CustomCurves;
using OpenEtrm.MarketData.Risk;

internal static class CustomCurveChecks
{
    public static void Run()
    {
        var revision=new DefinitionRevision(Guid.NewGuid(),Guid.NewGuid());var reference=new ReferenceRevision(Guid.NewGuid(),Guid.NewGuid());
        var unit=new PriceUnit(new(reference,"usd"),new(reference,"gas_quantity"),ExactDecimal.Parse("1"));
        var curve=new CurveKey(revision,"gas");
        var a=new ContractKey(revision,Guid.NewGuid());var b=new ContractKey(revision,Guid.NewGuid());
        DateTimeOffset At(int day,int hour=16)=>new(2026,1,day,hour,0,0,TimeSpan.Zero);
        RecipeNode Node(string id,string kind,(string,string)[]? parameters=null,(string,string)[]? ports=null)=>new(id,kind,
            (parameters??[]).ToImmutableDictionary(x=>x.Item1,x=>x.Item2),(ports??[]).ToImmutableDictionary(x=>x.Item1,x=>x.Item2));
        var definition=new RecipeDefinition("ng_average","Synthetic rolling average",[
            Node("source","source",[("curve","gas")]),
            Node("select","select",[("mode","positions"),("first","1"),("count","1"),("binding","each_sample")],[("source","source")]),
            Node("dates","dates",[("mode","previous_publications")]),
            Node("sample","sample",ports:[("selection","select"),("dates","dates")]),
            Node("mean","mean",[("axis","dates")],[("values","sample")]),
            Node("out","output",ports:[("values","mean")])],"out");
        var contracts=ImmutableArray.Create(new RecipeContract(new(a,ContractKind.Future,new(2026,2,1),new(2026,3,1),At(28,12),null),At(1)),
            new RecipeContract(new(b,ContractKind.Future,new(2026,3,1),new(2026,4,1),new(2026,2,28,12,0,0,TimeSpan.Zero),null),At(1)));
        var samples=ImmutableArray.CreateBuilder<RecipeSample>();
        for(var i=0;i<3;i++)foreach(var (key,value) in new[]{(a,new[]{"3.0","3.1","3.2"}[i]),(b,new[]{"3.6","3.8","4.0"}[i])})
            samples.Add(new(new(2026,1,26+i),At(26+i),key,new(ExactDecimal.Parse(value),unit),[new(revision.CatalogId,Guid.NewGuid())],[],true));
        var source=new RecipeSource(curve,unit,contracts,samples.ToImmutable());
        var inputs=new RecipeInputs(new(2026,1,28),At(28),ImmutableDictionary<string,RecipeSource>.Empty.Add("source",source),
            ImmutableDictionary<string,ImmutableArray<DateOnly>>.Empty.Add("dates",[new(2026,1,26),new(2026,1,27),new(2026,1,28)]));
        void Equal(string label,string actual,string expected){if(actual!=expected)throw new Exception($"{label}: expected {expected}, got {actual}");}
        void Reject(string label,Action action){try{action();}catch(MarketDataException){return;}throw new Exception(label+" was accepted.");}
        var result=RecipeEngine.Evaluate(definition,inputs);
        Equal("Exact historical prompt numerator",result.Points.Single().Price.Numerator,"101");
        Equal("Exact historical prompt denominator",result.Points.Single().Price.Denominator,"30");
        if(result.Inputs.Length!=3||result.Factors.Length!=0)throw new Exception("Historical samples must stay distinct frozen observations.");
        var locked=definition with{Nodes=definition.Nodes.Select(n=>n.Id=="select"?n with{Parameters=n.Parameters.SetItem("binding","context")}:n).ToImmutableArray()};
        Equal("Locked current-contract numerator",RecipeEngine.Evaluate(locked,inputs).Points.Single().Price.Numerator,"19");
        Equal("Locked current-contract denominator",RecipeEngine.Evaluate(locked,inputs).Points.Single().Price.Denominator,"5");
        var missing=source with{Samples=source.Samples.Where(s=>!(s.Contract==a&&s.Date==new DateOnly(2026,1,27))).ToImmutableArray()};
        Reject("Missing required historical prompt",()=>RecipeEngine.Evaluate(definition,inputs with{Sources=inputs.Sources.SetItem("source",missing)}));
        Reject("Repeated source sample",()=>RecipeEngine.Evaluate(definition,inputs with{Sources=inputs.Sources.SetItem("source",source with{Samples=source.Samples.Add(source.Samples[0])})}));
        Reject("A graph cycle",()=>RecipeEngine.Validate(definition with{Nodes=definition.Nodes.SetItem(0,Node("source","source",ports:[("cycle","out")]))}));
        Reject("Date passed as source",()=>RecipeEngine.Validate(definition with{Nodes=definition.Nodes.SetItem(1,definition.Nodes[1] with{Inputs=definition.Nodes[1].Inputs.SetItem("source","dates")})}));
        Reject("Duplicate contract",()=>RecipeEngine.Evaluate(definition,inputs with{Sources=inputs.Sources.SetItem("source",source with{Contracts=source.Contracts.Add(source.Contracts[0])})}));
        Reject("Future publication",()=>RecipeEngine.Evaluate(definition,inputs with{Sources=inputs.Sources.SetItem("source",source with{Samples=source.Samples.SetItem(0,source.Samples[0] with{At=At(29)})})}));
        Reject("Incorrect quote unit",()=>RecipeEngine.Evaluate(definition,inputs with{Sources=inputs.Sources.SetItem("source",source with{Unit=new(unit.Currency,unit.Quantity,ExactDecimal.Parse("100"))})}));
        using(var cancelled=new CancellationTokenSource())
        {cancelled.Cancel();try{RecipeEngine.Evaluate(definition,inputs,cancelled.Token);throw new Exception("Expected cancellation");}catch(OperationCanceledException){}}

        // Four remaining daily delivery forwards, all priced at the SAME context
        // instant. The month-end window includes today and the weekend.
        var days=Enumerable.Range(28,4).Select(d=>new DateOnly(2026,1,d)).ToImmutableArray();
        var dailyContracts=days.Select(d=>new RecipeContract(new(new(revision,Guid.NewGuid()),ContractKind.Forward,d,d.AddDays(1),new(2026,2,1,0,0,0,TimeSpan.Zero),null),At(1))).ToImmutableArray();
        var dailySamples=dailyContracts.Select((c,i)=>
        {
            var observation=new ObservationKey(revision.CatalogId,Guid.NewGuid());var value=ExactDecimal.Parse(((i+1)*10).ToString(System.Globalization.CultureInfo.InvariantCulture));
            var factor=new QuoteFactor(new(new(revision,Guid.NewGuid()),InputUse.Variable),new(reference,"quote"),unit,c.Contract.Key,observation,new(reference,"source"),ObservationRole.TraderMark,value,[curve],ExactDecimal.Parse("0.001"));
            return new RecipeSample(inputs.ContextDate,inputs.ValuationAt,c.Contract.Key,new(value,unit),[observation],[factor],false);
        }).ToImmutableArray();
        var balmo=definition with{Code="ng_balmo",Nodes=definition.Nodes.Select(n=>n.Id switch
        {
            "select"=>n with{Parameters=n.Parameters.SetItem("mode","daily_delivery").SetItem("binding","context").Remove("first").Remove("count")},
            "dates"=>n with{Parameters=n.Parameters.SetItem("mode","balance_month")},
            "mean"=>n with{Parameters=n.Parameters.SetItem("axis","contracts")},_=>n
        }).ToImmutableArray()};
        var dailySource=source with{Contracts=dailyContracts,Samples=dailySamples};
        var dailyInputs=inputs with{Sources=inputs.Sources.SetItem("source",dailySource),Dates=inputs.Dates.SetItem("dates",days)};
        var remaining=RecipeEngine.Evaluate(balmo,dailyInputs);
        Equal("BALMO includes all four days",remaining.Points.Single().Price.Numerator,"25");
        if(remaining.Inputs.Length!=4||remaining.Factors.Length!=4)throw new Exception("BALMO must retain four projected factors at one sampling instant.");
        var up=dailySource with{Samples=dailySamples.Select(s=>s with{Price=new(s.Price.Value+ExactDecimal.Parse("1"),unit),Factors=s.Factors.Select(f=>f with{BaseValue=f.BaseValue+ExactDecimal.Parse("1")}).ToImmutableArray()}).ToImmutableArray()};
        Equal("Shared parallel shock of all daily forwards",RecipeEngine.Evaluate(balmo,dailyInputs with{Sources=dailyInputs.Sources.SetItem("source",up)}).Points.Single().Price.Numerator,"26");
        var oneUp=dailySource with{Samples=dailySamples.SetItem(0,up.Samples[0])};
        var oneShock=RecipeEngine.Evaluate(balmo,dailyInputs with{Sources=dailyInputs.Sources.SetItem("source",oneUp)}).Points.Single().Price;
        Equal("One daily factor shock numerator",oneShock.Numerator,"101");Equal("One daily factor shock denominator",oneShock.Denominator,"4");
        Reject("Missing weekend daily forward",()=>RecipeEngine.Evaluate(balmo,dailyInputs with{Sources=dailyInputs.Sources.SetItem("source",dailySource with{Samples=dailySamples.RemoveAt(2)})}));
        Reject("Daily forwards at different sampling times",()=>RecipeEngine.Evaluate(balmo,dailyInputs with{Sources=dailyInputs.Sources.SetItem("source",dailySource with{Samples=dailySamples.SetItem(0,dailySamples[0] with{At=At(28,15)})})}));
        Reject("Live source without factors",()=>RecipeEngine.Evaluate(balmo,dailyInputs with{Sources=dailyInputs.Sources.SetItem("source",dailySource with{Samples=dailySamples.SetItem(0,dailySamples[0] with{Factors=[]})})}));
        var past=source.Samples[0];var pastFactor=dailySamples[0].Factors[0] with{Contract=past.Contract,Observation=past.Observations[0],BaseValue=past.Price.Value};
        Reject("Historical fixing declared as a live factor",()=>RecipeEngine.Evaluate(definition,inputs with{Sources=inputs.Sources.SetItem("source",source with{Samples=source.Samples.SetItem(0,past with{Fixed=false,Factors=[pastFactor]})})}));
        Reject("Historical date relabelled with later price",()=>RecipeEngine.Evaluate(definition,inputs with{Sources=inputs.Sources.SetItem("source",source with{Samples=source.Samples.SetItem(0,source.Samples[0] with{At=At(28)})})}));
        Reject("Silently ignored financial parameter",()=>RecipeEngine.Validate(definition with{Nodes=definition.Nodes.Select(n=>n.Kind=="mean"?n with{Parameters=n.Parameters.Add("weights","hours")}:n).ToImmutableArray()}));
        var monthEnd=dailyInputs with{ContextDate=new(2026,1,31),ValuationAt=At(31),Dates=dailyInputs.Dates.SetItem("dates",[new(2026,1,31)]),
            Sources=dailyInputs.Sources.SetItem("source",dailySource with{Samples=dailySamples.Select(s=>s with{Date=new(2026,1,31),At=At(31)}).ToImmutableArray()})};
        Equal("Month-end retains one daily forward",RecipeEngine.Evaluate(balmo,monthEnd).Points.Single().Price.Numerator,"40");
        var formula=RecipeFormula.Format(definition);
        var compiled=RecipeFormula.Compile(formula,definition.Code,definition.Name);
        Equal("Formula graph preserves exact result",RecipeEngine.Evaluate(compiled,inputs).Points.Single().Price.Numerator,"101");
        Reject("Formula cannot invoke arbitrary code",()=>RecipeFormula.Compile("out = system(command=\"anything\")",definition.Code,definition.Name));
        Reject("Repeated formula argument",()=>RecipeFormula.Compile("out = source(curve=\"a\",curve=\"b\")",definition.Code,definition.Name));
        var sqlMean=definition with{Nodes=definition.Nodes.Select(n=>n.Id=="mean"?n with{Kind="sql_transform",Parameters=ImmutableDictionary<string,string>.Empty.Add("sqlTransformCode","sql_mean_dates_v1")}:n).ToImmutableArray()};
        Reject("Unregistered SQL executor",()=>RecipeEngine.Evaluate(sqlMean,inputs));
        RecipeSqlExecutor executor=(code,values,ct)=>
        {
            if(code!="sql_mean_dates_v1")throw new Exception("Unexpected transformation");
            return Task.FromResult(values.GroupBy(v=>v.Position).Select(g=>new RecipeSqlSum(g.Key,
                g.Aggregate(System.Numerics.BigInteger.Zero,(total,v)=>total+System.Numerics.BigInteger.Parse(v.Coefficient,System.Globalization.CultureInfo.InvariantCulture)).ToString(System.Globalization.CultureInfo.InvariantCulture),g.Count())).ToImmutableArray());
        };
        var sqlResult=RecipeEngine.EvaluateAsync(sqlMean,inputs,executor).GetAwaiter().GetResult();
        Equal("Registered SQL mean retains exact value",sqlResult.Points.Single().Price.Numerator,"101");
        Equal("Registered SQL mean retains exact divisor",sqlResult.Points.Single().Price.Denominator,"30");
        var hundredUnit=new PriceUnit(unit.Currency,unit.Quantity,ExactDecimal.Parse("100"));
        var signedSource=source with{Unit=hundredUnit,Samples=source.Samples.Select(s=>s with
        {
            Price=new(ExactDecimal.Parse(s.Contract==a&&s.Date.Day==26?"-3":s.Contract==b&&s.Date.Day==28?"1.5":"0"),hundredUnit)
        }).ToImmutableArray()};
        var signed=RecipeEngine.EvaluateAsync(sqlMean,inputs with{Sources=inputs.Sources.SetItem("source",signedSource)},executor).GetAwaiter().GetResult().Points.Single().Price;
        Equal("Signed samples with zero numerator",signed.Numerator,"-1");Equal("Signed samples with zero denominator",signed.Denominator,"2");
        if(signed.Unit!=hundredUnit)throw new Exception("SQL means must retain the nonunit quote multiplier.");
        Reject("Registered transform cannot omit a required sample",()=>RecipeEngine.EvaluateAsync(sqlMean,inputs,(_,_,_)=>Task.FromResult(ImmutableArray.Create(new RecipeSqlSum(1,"1",1)))).GetAwaiter().GetResult());
        Console.WriteLine("PASS custom curves: exact rolling/locked means, inclusive BALMO, live scenarios, unit and lineage checks, strict gaps, cancellation and typed formula graph");
    }
}
