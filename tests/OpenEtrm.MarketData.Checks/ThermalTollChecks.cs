using System.Collections.Immutable;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Power.Structured;

internal static class ThermalTollChecks
{
    internal static int Run()
    {
        var count=0;
        void Check(string name,Action action){action();count++;Console.WriteLine("PASS thermal toll: "+name);}
        Check("five MWh requires thirty-five fuel units and retains separate operating consumption",()=>
        {
            var f=new Fixture();var result=ThermalToll.Evaluate(f.Terms,f.Initial(),[f.Row(0,"5",true)]);
            Equal(result.Energy,"5");Equal(result.GuaranteedFuel,"35");Equal(result.ConsumptionFuel,"37.5");
            if(!result.Rows[0].Started||result.Rows[0].Stopped||result.StartsInPlan!=1||result.FinalState.StartsUsed!=1)
                throw new Exception("A boundary start must remain an explicit occurrence.");
        });
        Check("additive no-load and startup fuel apply once to the same output plan",()=>
        {
            var f=new Fixture();var terms=f.Terms with{GuaranteedFuel=f.Fuel("7","2","3"),ConsumptionFuel=f.Fuel("7.5","1","4")};
            var result=ThermalToll.Evaluate(terms,f.Initial(),[f.Row(0,"5",true),f.Row(1,"5",true)]);
            Equal(result.Energy,"10");Equal(result.GuaranteedFuel,"77");Equal(result.ConsumptionFuel,"81");
            Equal(result.Rows[0].GuaranteedFuel,"40");Equal(result.Rows[1].GuaranteedFuel,"37");
        });
        Check("quarter-hour output uses elapsed duration without early quantity rounding",()=>
        {
            var f=new Fixture(15);var result=ThermalToll.Evaluate(f.Terms,f.Initial(),[f.Row(0,"1",true)]);
            Equal(result.Energy,"0.25");Equal(result.GuaranteedFuel,"1.75");
        });
        Check("sub-decimal interval energy remains exact until a representable total",()=>
        {
            var f=new Fixture(15);var rows=Enumerable.Range(0,4).Select(n=>f.Row(n,"0.000000000000000001",true)).ToImmutableArray();
            var result=ThermalToll.Evaluate(f.Terms,f.Initial(),rows);
            if(result.Rows[0].Energy.Numerator!="1"||result.Rows[0].Energy.Denominator!="4000000000000000000")
                throw new Exception("A quarter of the smallest entered MW must not be rounded at the interval boundary.");
            Equal(result.Energy,"0.000000000000000001");
        });
        Check("explicit zero online output consumes no-load fuel but offline output consumes none",()=>
        {
            var f=new Fixture();var terms=f.Terms with{GuaranteedFuel=f.Fuel("7","2","3")};
            var result=ThermalToll.Evaluate(terms,f.Initial(),[f.Row(0,"0",true),f.Row(1,"0",false)]);
            Equal(result.Rows[0].GuaranteedFuel,"5");Equal(result.Rows[1].GuaranteedFuel,"0");
            if(!result.Rows[1].Stopped)throw new Exception("Shutdown must be explicit even at zero output.");
        });
        Check("availability and minimum stable output constrain each online interval",()=>
        {
            var f=new Fixture();Reject("thermal_output",()=>ThermalToll.Evaluate(f.Terms,f.Initial(),[f.Row(0,"5",true) with{Available=f.Mw("4")} ]));
            Reject("thermal_output",()=>ThermalToll.Evaluate(f.Terms with{MinimumOutput=f.Mw("3")},f.Initial(),[f.Row(0,"2",true)]));
            Reject("thermal_output",()=>ThermalToll.Evaluate(f.Terms,f.Initial(),[f.Row(0,"1",false)]));
        });
        Check("ordinary ramp budgets use elapsed hours and separate startup/shutdown limits",()=>
        {
            var f=new Fixture(15);var initial=f.Initial(ThermalCommitment.Online,"1",120);
            var terms=f.Terms with{RampUpMwPerHour=D("4"),RampDownMwPerHour=D("4")};
            ThermalToll.Evaluate(terms,initial,[f.Row(0,"2",true) with{StartupInstructionAt=null}]);
            Reject("thermal_ramp",()=>ThermalToll.Evaluate(terms,initial,[f.Row(0,"2.01",true) with{StartupInstructionAt=null}]));
            ThermalToll.Evaluate(terms,f.Initial(ThermalCommitment.Online,"5",120),[f.Row(0,"4",true) with{StartupInstructionAt=null}]);
            Reject("thermal_ramp",()=>ThermalToll.Evaluate(terms,f.Initial(ThermalCommitment.Online,"5",120),
                [f.Row(0,"3.99",true) with{StartupInstructionAt=null}]));
            Reject("thermal_start",()=>ThermalToll.Evaluate(f.Terms with{StartupMaximumOutput=f.Mw("4")},f.Initial(),[f.Row(0,"5",true)]));
            Reject("thermal_stop",()=>ThermalToll.Evaluate(f.Terms with{ShutdownMaximumOutput=f.Mw("4")},f.Initial(ThermalCommitment.Online,"5",120),[f.Row(0,"0",false)]));
        });
        Check("minimum up and down times survive the input boundary",()=>
        {
            var f=new Fixture();var terms=f.Terms with{MinimumUpTime=TimeSpan.FromHours(2),MinimumDownTime=TimeSpan.FromHours(2)};
            Reject("thermal_minimum_up",()=>ThermalToll.Evaluate(terms,f.Initial(ThermalCommitment.Online,"5",30),[f.Row(0,"0",false)]));
            Reject("thermal_minimum_down",()=>ThermalToll.Evaluate(terms,f.Initial(ThermalCommitment.Offline,"0",30),[f.Row(0,"5",true)]));
            ThermalToll.Evaluate(terms,f.Initial(ThermalCommitment.Online,"5",120),[f.Row(0,"5",true) with{StartupInstructionAt=null}]);
        });
        Check("minimum times also constrain transitions inside the horizon",()=>
        {
            var f=new Fixture();
            Reject("thermal_minimum_up",()=>ThermalToll.Evaluate(f.Terms with{MinimumUpTime=TimeSpan.FromHours(2)},f.Initial(),
                [f.Row(0,"5",true),f.Row(1,"0",false)]));
            Reject("thermal_minimum_down",()=>ThermalToll.Evaluate(f.Terms with{MinimumDownTime=TimeSpan.FromHours(2)},
                f.Initial(ThermalCommitment.Online,"5",120),[f.Row(0,"0",false),f.Row(1,"5",true) with{StartupInstructionAt=f.Intervals[1].Start}]));
        });
        Check("terminal policy refuses unpriced minimum-time continuation",()=>
        {
            var f=new Fixture();var terms=f.Terms with{MinimumUpTime=TimeSpan.FromHours(2)};
            Reject("thermal_terminal",()=>ThermalToll.Evaluate(terms,f.Initial(),[f.Row(0,"5",true)]));
            ThermalToll.Evaluate(terms,f.Initial(),[f.Row(0,"5",true),f.Row(1,"5",true)]);
            Reject("thermal_terminal",()=>ThermalToll.Evaluate(f.Terms with{MinimumDownTime=TimeSpan.FromHours(2)},
                f.Initial(ThermalCommitment.Online,"5",120),[f.Row(0,"0",false)]));
        });
        Check("start limit includes starts already consumed before this plan",()=>
        {
            var f=new Fixture();Reject("thermal_start_limit",()=>ThermalToll.Evaluate(f.Terms with{MaximumStarts=1},
                f.Initial() with{StartsUsed=1},[f.Row(0,"5",true)]));
            Reject("thermal_start_limit",()=>ThermalToll.Evaluate(f.Terms with{MaximumStarts=1},f.Initial(),
                [f.Row(0,"5",true),f.Row(1,"0",false),f.Row(2,"5",true) with{StartupInstructionAt=f.Intervals[2].Start}]));
        });
        Check("startup lead time requires an explicit timely instruction after downtime",()=>
        {
            var f=new Fixture();var terms=f.Terms with{StartupLeadTime=TimeSpan.FromMinutes(30),MinimumDownTime=TimeSpan.FromHours(1)};
            var row=f.Row(0,"5",true) with{StartupInstructionAt=f.From.AddMinutes(-30)};
            ThermalToll.Evaluate(terms,f.Initial(),[row]);
            Reject("thermal_start_notice",()=>ThermalToll.Evaluate(terms,f.Initial(),[row with{StartupInstructionAt=f.From.AddMinutes(-29)}]));
            Reject("thermal_start_notice",()=>ThermalToll.Evaluate(terms,f.Initial(),[row with{StartupInstructionAt=null}]));
            Reject("thermal_minimum_down",()=>ThermalToll.Evaluate(terms,f.Initial(ThermalCommitment.Offline,"0",60),[row]));
            ThermalToll.Evaluate(terms,f.Initial(ThermalCommitment.Offline,"0",90),[row]);
            Reject("thermal_minimum_down",()=>ThermalToll.Evaluate(terms,f.Initial(ThermalCommitment.Offline,"0",90),
                [row with{StartupInstructionAt=f.From.AddMinutes(-31)}]));
        });
        Check("native DST days integrate twenty-three and twenty-five distinct UTC hours",()=>
        {
            foreach(var (day,hours) in new[]{(new DateOnly(2031,3,9),23),(new DateOnly(2031,11,2),25)})
            {
                var f=new Fixture(60,day);var grid=PowerHours.Compile(day,day.AddDays(1),f.Terms.OperatingClock,TimeOfUse.All(60),[],60);
                var rows=grid.Select((h,n)=>new ThermalDispatchInterval(h.Delivery,ThermalCommitment.Online,f.Mw("1"),f.Mw("10"),n==0?h.Start:null)).ToImmutableArray();
                var result=ThermalToll.Evaluate(f.Terms,f.Initial(),rows);Equal(result.Energy,hours.ToString(System.Globalization.CultureInfo.InvariantCulture));
                if(result.Rows.Select(r=>r.Interval.Start).Distinct().Count()!=hours)throw new Exception("Repeated local hours must retain distinct UTC intervals.");
            }
        });
        Check("grid gaps overlaps ordering split cells and fabricated clock labels refuse",()=>
        {
            var f=new Fixture();Reject("thermal_grid",()=>ThermalToll.Evaluate(f.Terms,f.Initial(),[f.Row(0,"5",true),f.Row(2,"5",true)]));
            Reject("thermal_grid",()=>ThermalToll.Evaluate(f.Terms,f.Initial(),[f.Row(0,"5",true),f.Row(0,"5",true)]));
            Reject("thermal_grid",()=>ThermalToll.Evaluate(f.Terms,f.Initial(),[f.Row(0,"5",true) with{Interval=f.Intervals[0] with{End=f.From.AddMinutes(30)}}]));
            Reject("thermal_grid",()=>ThermalToll.Evaluate(f.Terms,f.Initial(),[f.Row(0,"5",true) with{Interval=f.Intervals[0] with{HourBeginning=17}}]));
            Reject("thermal_grid",()=>ThermalToll.Evaluate(f.Terms,f.Initial(),[f.Row(0,"5",true) with{Interval=f.Intervals[0] with{Start=f.From.ToOffset(TimeSpan.FromHours(-5))}}]));
            Reject("thermal_grid",()=>ThermalToll.Evaluate(f.Terms,f.Initial(),[]));
        });
        Check("exact references units implementation and policy cannot be silently replaced",()=>
        {
            var f=new Fixture();var rows=ImmutableArray.Create(f.Row(0,"5",true));
            Reject("thermal_implementation",()=>ThermalToll.Evaluate(f.Terms with{Implementation="unknown"},f.Initial(),rows));
            Reject("thermal_implementation",()=>ThermalToll.Evaluate(f.Terms with{NumericalPolicy="unknown"},f.Initial(),rows));
            Reject("thermal_policy",()=>ThermalToll.Evaluate(f.Terms with{TerminalPolicy=(ThermalTerminalPolicy)0},f.Initial(),rows));
            Reject("thermal_reference",()=>ThermalToll.Evaluate(f.Terms with{Clock=new(new(Guid.NewGuid(),Guid.NewGuid()),"clock")},f.Initial(),rows));
            Reject("thermal_units",()=>ThermalToll.Evaluate(f.Terms with{Energy=f.Terms.Energy with{Unit=f.Key("kilowatt_hour")}},f.Initial(),rows));
            Reject("thermal_units",()=>ThermalToll.Evaluate(f.Terms,f.Initial(),[rows[0] with{Output=new(D("5"),f.Terms.Fuel.Key)}]));
            Reject("thermal_fuel",()=>ThermalToll.Evaluate(f.Terms with{GuaranteedFuel=f.Fuel("7","-1","0")},f.Initial(),rows));
            Reject("thermal_initial_state",()=>ThermalToll.Evaluate(f.Terms,f.Initial() with{PreviousOutput=f.Mw("1")},rows));
        });
        Check("malformed constraints and missing consumed inputs refuse explicitly",()=>
        {
            var f=new Fixture();var rows=ImmutableArray.Create(f.Row(0,"5",true));
            Reject("thermal_definition",()=>ThermalToll.Evaluate(null!,f.Initial(),rows));
            Reject("thermal_definition",()=>ThermalToll.Evaluate(f.Terms,null!,rows));
            Reject("thermal_definition",()=>ThermalToll.Evaluate(f.Terms with{MaximumOutput=f.Mw("0")},f.Initial(),rows));
            Reject("thermal_definition",()=>ThermalToll.Evaluate(f.Terms with{MinimumUpTime=TimeSpan.FromMinutes(-1)},f.Initial(),rows));
            Reject("thermal_definition",()=>ThermalToll.Evaluate(f.Terms with{RampDownMwPerHour=D("-1")},f.Initial(),rows));
            Reject("thermal_fuel",()=>ThermalToll.Evaluate(f.Terms with{ConsumptionFuel=null!},f.Initial(),rows));
            Reject("thermal_output",()=>ThermalToll.Evaluate(f.Terms,f.Initial(),[rows[0] with{Available=f.Mw("11")}]));
            Reject("thermal_output",()=>ThermalToll.Evaluate(f.Terms,f.Initial(),[rows[0] with{Output=f.Mw("-1")}]));
            Reject("thermal_initial_state",()=>ThermalToll.Evaluate(f.Terms,f.Initial() with{ElapsedInState=TimeSpan.MaxValue},rows));
        });
        Check("same immutable terms and supplied plan reproduce every quantity and state",()=>
        {
            var f=new Fixture();var rows=ImmutableArray.Create(f.Row(0,"5",true),f.Row(1,"3",true),f.Row(2,"0",false));
            var a=ThermalToll.Evaluate(f.Terms,f.Initial(),rows);var b=ThermalToll.Evaluate(f.Terms,f.Initial(),rows);
            if(!a.Rows.SequenceEqual(b.Rows)||a.FinalState!=b.FinalState||a.Energy!=b.Energy||a.GuaranteedFuel!=b.GuaranteedFuel)
                throw new Exception("A pure supplied-plan replay changed its outputs.");
        });
        Check("static facility terms validate without fabricated operating state or dispatch",()=>
        {
            var f=new Fixture();ThermalToll.ValidateTerms(f.Terms);
            Reject("thermal_definition",()=>ThermalToll.ValidateTerms(f.Terms with{MaximumOutput=f.Mw("0")}));
            Reject("thermal_grid",()=>ThermalToll.ValidateTerms(f.Terms with{IntervalMinutes=30}));
        });
        Check("physical facility validation needs no guaranteed toll fuel or valuation policy",()=>
        {
            var f=new Fixture();ThermalToll.ValidateResource(f.Terms.Facility);
            Reject("thermal_definition",()=>ThermalToll.ValidateResource(f.Terms.Facility with{MaximumOutput=f.Mw("0")}));
            Reject("thermal_fuel",()=>ThermalToll.ValidateResource(f.Terms.Facility with{ConsumptionFuel=null!}));
        });
        Check("explicit MW and MWh specifications retain their dimension-specific measurement bases",()=>
        {
            var f=new Fixture();var terms=f.Terms with
            {
                Power=f.Terms.Power with{MeasurementBasis=f.Key("net_electric_power")},
                Energy=f.Terms.Energy with{MeasurementBasis=f.Key("net_electric_energy")}
            };
            var result=ThermalToll.Evaluate(terms,f.Initial(),[f.Row(0,"5",true)]);
            Equal(result.Energy,"5");Equal(result.GuaranteedFuel,"35");
            if(result.Terms.Power.MeasurementBasis==result.Terms.Energy.MeasurementBasis)
                throw new Exception("A dimension-specific reference basis must remain an explicit selected relationship.");
        });
        return count;
    }

    private static ExactDecimal D(string text)=>ExactDecimal.Parse(text);
    private static void Equal(ExactQuantity value,string expected)
    {if(value.ToQuantity().Amount!=D(expected))throw new Exception($"Expected {expected}; received {value.Numerator}/{value.Denominator}.");}
    private static void Reject(string code,Action action)
    {try{action();}catch(MarketDataException e)when(e.Code==code){return;}throw new Exception("Expected "+code);}

    private sealed class Fixture
    {
        private readonly ReferenceRevision reference=new(Guid.NewGuid(),Guid.NewGuid());
        internal ThermalTollTerms Terms { get; }
        internal ImmutableArray<DeliveryInterval> Intervals { get; }
        internal DateTimeOffset From=>Intervals[0].Start;
        internal ReferenceKey Key(string code)=>new(reference,code);
        internal Quantity Mw(string value)=>new(D(value),Terms.Power.Key);
        internal ThermalFuelTerms Fuel(string heatRate,string noLoad,string start)=>new(
            new(D(heatRate),Terms.Fuel.Key,Terms.Energy.Key,QuantityFactor.Implementation),new(D(noLoad),Terms.Fuel.Key),new(D(start),Terms.Fuel.Key));
        internal Fixture(int minutes=60,DateOnly? date=null)
        {
            var day=date??new DateOnly(2031,1,15);var clock=PowerClock.Capture(TimeZoneInfo.FindSystemTimeZoneById("America/New_York"));
            Intervals=[..PowerHours.Compile(day,day.AddDays(1),clock,TimeOfUse.All(minutes),[],minutes).Select(h=>h.Delivery)];
            var power=new QuantitySpecification(Key("thermal_mw"),Key("power"),Key("net_electricity"),Key("megawatt"),Key("power"));
            var energy=new QuantitySpecification(Key("thermal_mwh"),Key("power"),Key("net_electricity"),Key("megawatt_hour"),Key("energy"));
            var fuel=new QuantitySpecification(Key("thermal_fuel"),Key("gas"),Key("declared_fuel_energy"),Key("mmbtu"),Key("energy"));
            ThermalFuelTerms Coefficients(string value)=>new(new(D(value),fuel.Key,energy.Key,QuantityFactor.Implementation),new(D("0"),fuel.Key),new(D("0"),fuel.Key));
            Terms=new(new(new(new(Guid.NewGuid(),Guid.NewGuid()),"synthetic_thermal"),From.AddDays(-1)),From.AddDays(3),
                Key("thermal_clock"),clock,minutes,power,energy,fuel,new(D("0"),power.Key),new(D("10"),power.Key),D("100"),D("100"),
                new(D("10"),power.Key),new(D("10"),power.Key),TimeSpan.Zero,TimeSpan.Zero,TimeSpan.Zero,10,
                Coefficients("7"),Coefficients("7.5"),ThermalTerminalPolicy.RequireMinimumTimesSatisfied,ThermalToll.Implementation,ThermalToll.NumericalPolicy);
        }
        internal ThermalInitialState Initial(ThermalCommitment commitment=ThermalCommitment.Offline,string output="0",int elapsedMinutes=120)=>
            new(From,commitment,TimeSpan.FromMinutes(elapsedMinutes),Mw(output),0);
        internal ThermalDispatchInterval Row(int index,string output,bool online)=>new(Intervals[index],
            online?ThermalCommitment.Online:ThermalCommitment.Offline,Mw(output),Mw("10"),online&&(index==0)?Intervals[index].Start:null);
    }
}
