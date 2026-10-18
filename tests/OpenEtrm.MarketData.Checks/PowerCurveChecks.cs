using System.Collections.Immutable;
using OpenEtrm.MarketData;

// Existing curve/amount capabilities only. Interval fixings and operator billing
// remain separate acceptance cases until their business operations exist.
internal static class PowerCurveChecks
{
    public static int Run()
    {
        var passed=0;
        void Check(string name,Action run){run();passed++;Console.WriteLine($"PASS power curve: {name}");}
        void Equal<T>(T actual,T expected)where T:notnull
        {if(!actual.Equals(expected))throw new Exception($"Expected {expected}; got {actual}.");}
        var f=new Fixture();var original=f.Snapshot();
        var direct=f.Direct("power_all_in",f.K(5),f.R("power_out"),SettlementKind.Index);
        var model=f.Model(f.Curves.Add(direct));
        var snapshot=original with {Selections=original.Selections.Add(f.Select(5,QuoteKind.Outright,"power_out","-5.125"))};
        var request=new CurveRequest(f.C("power_all_in"),f.K(5));
        Check("declared negative outright price stays negative without a floor",()=>{
            var build=model.Build(snapshot,[request]);
            Equal(build.Values[0].Price.Value.ToString(),"-5.125");Equal(build.EvaluatedConstituents,1);
        });
        Check("negative locational basis can make the derived power price negative",()=>{
            var changed=original with {Selections=original.Selections.Select(s=>s.Input.Series==f.S(5)
                ?s with {Observation=s.Observation with {Value=ExactDecimal.Parse("-40")}}:s).ToImmutableArray()};
            Equal(model.Build(changed,[new(f.C("local_power"),f.K(5))]).Values[0].Price.Value.ToString(),"-12.9");
        });
        Check("an outright power mark has no inferred gas exposure even when negative",()=>{
            var changed=snapshot with {Selections=snapshot.Selections.Select(s=>s.Input.Series==f.S(1)
                ?s with {Observation=s.Observation with {Value=ExactDecimal.Parse("3.1")}}:s).ToImmutableArray()};
            var result=model.Build(changed,[new(f.C("local_power"),f.K(5)),request]);
            Equal(result.Values[0].Price.Value.ToString(),"29.8");Equal(result.Values[1].Price.Value.ToString(),"-5.125");
        });
        Check("negative power price preserves exact signed monetary amounts",()=>{
            var quote=f.Quotes.Single(q=>q.Key==f.R("power_out"));
            var price=new UnitPrice(ExactDecimal.Parse("-5.125"),quote);
            Equal(price.Times(new Quantity(ExactDecimal.Parse("10"),f.R("power_quantity"))).Amount.ToString(),"-51.25");
            Equal(price.Times(new Quantity(ExactDecimal.Parse("-10"),f.R("power_quantity"))).Amount.ToString(),"51.25");
        });
        Console.WriteLine($"{passed} power curve checks passed.");return passed;
    }
}
