using System.Collections.Immutable;
using OpenEtrm.MarketData;

// Prices across an explicitly configured early-source expiry. This does not
// implement fixing aggregation, payments or futures variation-margin accounting.
internal static class ExpiryTransitionChecks
{
    public static int Run()
    {
        var passed=0;
        void Check(string name,Action run){run();passed++;Console.WriteLine($"PASS expiry transition: {name}");}
        void Equal<T>(T actual,T expected) where T:notnull
        {if(!actual.Equals(expected))throw new Exception($"Expected {expected}; got {actual}.");}
        void Reject(string code,Action run)
        {try{run();}catch(MarketDataException e)when(e.Code==code){return;}throw new Exception($"Expected {code}.");}
        var f=new Fixture();var original=f.Snapshot();
        var curves=f.Curves.Select(c=>c.Key==f.C("base_forward")?c with {
            Inputs=c.Inputs.SetItem(0,c.Inputs[0] with {ExpiryRule=SourceExpiryRule.FreezeFinalFuture})}:c).ToImmutableArray();
        var model=f.Model(curves);var output=new CurveRequest(f.C("local_power"),f.K(5));
        var expiry=f.Contracts.Single(c=>c.Key==f.K(1)).Expiry;
        var dependentExpiry=f.Contracts.Single(c=>c.Key==f.K(5)).Expiry;
        var final=f.Select(1,QuoteKind.Outright,"gas_out","3.2") with {Input=new(f.S(1),InputUse.FrozenFact)};
        final=final with {Observation=final.Observation with {Role=ObservationRole.FinalContractSettlement,ObservedAt=expiry}};
        MarketSnapshot At(DateTimeOffset instant,bool includeFinal=true)=>original with {
            ValuationAt=instant,MarketCutoff=instant,Selections=includeFinal?original.Selections.Add(final):original.Selections};
        string Price(MarketSnapshot snapshot)=>model.Build(snapshot,[output]).Values[0].Value.ToString();

        Check("source is live immediately before expiry and fixed exactly at expiry",()=>{
            Equal(Price(At(expiry.AddSeconds(-1),false)),"29.1");
            var built=model.Build(At(expiry),[output]);
            Equal(built.Values[0].Value.ToString(),"30.5");
            Equal(built.Evaluations.Single(e=>e.Result.Request.Curve==f.C("future")).Use,InputUse.FrozenFact);
        });
        Check("final evidence never implicitly changes a require-live policy",()=>
            Reject("source_expired",()=>f.Model().Build(At(expiry),[output])));
        Check("missing final fails at the exact boundary without a live-price fallback",()=>
            Reject("missing_observation",()=>Price(At(expiry,false))));
        Check("ordinary daily settlement is not the final contract settlement",()=>{
            var daily=final with {Observation=final.Observation with {Role=ObservationRole.DailySettlement}};
            Reject("frozen_fact",()=>Price(At(expiry) with {Selections=original.Selections.Add(daily)}));
        });
        Check("preliminary and premature final settlements are rejected",()=>{
            var preliminary=final with {Observation=final.Observation with {State=PublicationState.Preliminary}};
            Reject("frozen_fact",()=>Price(At(expiry) with {Selections=original.Selections.Add(preliminary)}));
            var premature=final with {Observation=final.Observation with {ObservedAt=expiry.AddSeconds(-1)}};
            Reject("frozen_fact",()=>Price(At(expiry) with {Selections=original.Selections.Add(premature)}));
        });
        Check("final observation after the market cutoff cannot enter the price",()=>{
            var later=final with {Observation=final.Observation with {ObservedAt=expiry.AddSeconds(1)}};
            Reject("observation_cutoff",()=>Price(At(expiry) with {Selections=original.Selections.Add(later)}));
        });
        Check("dependent remains priceable through its own later live interval",()=>{
            Equal(Price(At(dependentExpiry.AddSeconds(-1))),"30.5");
            Reject("source_expired",()=>Price(At(dependentExpiry)));
        });
        Check("stale live source changes do not move the explicitly fixed dependency",()=>{
            var snapshot=At(expiry);var changed=snapshot with {Selections=snapshot.Selections.Select(s=>
                s.Input==new InputKey(f.S(1),InputUse.Variable)?s with {Observation=s.Observation with {Value=ExactDecimal.Parse("900")}}:s).ToImmutableArray()};
            Equal(Price(changed),"30.5");Equal(Price(snapshot),"30.5");
            Equal(original.Selections[0].Observation.Value.ToString(),"3");
        });
        Console.WriteLine($"{passed} expiry transition checks passed.");return passed;
    }
}
