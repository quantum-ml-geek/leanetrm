using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power;

internal static class PowerQuantityChecks
{
 public static int Run()
 {
  int passed=0;
  void Check(string label,Action action){action();passed++;Console.WriteLine("PASS power quantity: "+label);}
  void Equal(string actual,string expected){if(actual!=expected)throw new Exception($"Expected {expected}; got {actual}.");}
  void Reject(string code,Action action){try{action();}catch(MarketDataException e)when(e.Code==code){return;}throw new Exception("Expected "+code);}
  var r=new ReferenceRevision(Guid.NewGuid(),Guid.NewGuid());ReferenceKey R(string code)=>new(r,code);
  var energy=new QuantitySpecification(R("energy_quantity"),R("power_product"),R("delivered_energy"),R("megawatt_hour"),R("energy"));
  var power=new QuantitySpecification(R("power_quantity"),R("power_product"),R("delivery_rate"),R("megawatt"),R("power"));
  var clock=PowerClock.Capture(TimeZoneInfo.FindSystemTimeZoneById("America/New_York"));
  PowerQuantitySchedule Schedule(string value,PowerQuantityBasis basis,DateOnly from,DateOnly to,int minutes=60,TimeOfUse? mask=null,DateOnly[]? holidays=null,PowerAllocation? allocation=null)=>
   PowerQuantitySchedule.Compile(new(ExactDecimal.Parse(value),basis==PowerQuantityBasis.FlatPower?power.Key:energy.Key),
    basis,basis==PowerQuantityBasis.FlatPower?power:energy,energy,from,to,clock,mask??TimeOfUse.All(minutes),holidays??[],minutes,allocation);
  Check("flat MW follows 23, 24 and 25 actual hours",()=>{
   foreach(var (date,hours) in new[]{(new DateOnly(2027,3,14),"23"),(new DateOnly(2027,3,15),"24"),(new DateOnly(2026,11,1),"25")}){
    var s=Schedule("10",PowerQuantityBasis.FlatPower,date,date.AddDays(1));Equal(s.Total.ToQuantity().Amount.ToString(),hours=="23"?"230":hours=="24"?"240":"250");
    Equal(s.Hours.ToString(),hours);if(s.Clock.Fingerprint!=clock.Fingerprint)throw new Exception("Lost clock rule identity.");
   }
  });
  Check("total MWh is conserved over nonterminating interval allocations",()=>{
   var s=Schedule("1",PowerQuantityBasis.TotalEnergy,new(2027,3,14),new(2027,3,15),allocation:PowerAllocation.FlatRate);
   Equal(s.Intervals.Select(p=>p.Energy).Aggregate((a,b)=>a.Add(b)).ToQuantity().Amount.ToString(),"1");
   Equal(s.Intervals[0].Energy.Numerator,"1");Equal(s.Intervals[0].Energy.Denominator,"23");
   Reject("precision_loss",()=>s.Intervals[0].Energy.ToQuantity());
   Equal(s.Intervals[0].Energy.ToString(new(6,CashTieRule.ToEven,false,false),new(energy.Key,"MWh")),"0.043478 MWh");
  });
  Check("resolution changes preserve exact energy and cash with varying interval prices",()=>{
   foreach(var minutes in new[]{60,30,15,5}){
    var s=Schedule("1",PowerQuantityBasis.TotalEnergy,new(2027,3,14),new(2027,3,15),minutes,allocation:PowerAllocation.FlatRate);
    var total=s.Intervals.Select(p=>p.Energy.Times(new UnitPrice(ExactDecimal.Parse(p.Interval.Start.Hour==5?"23":"0"),new PriceUnit(R("usd"),energy.Key,ExactDecimal.Parse("1"))))).Aggregate((a,b)=>a.Add(b));
    Equal(total.ToMoney().Amount.ToString(),"1");
    Equal(s.Total.ToQuantity().Amount.ToString(),"1");
   }
  });
  Check("TOU and explicit holidays determine rate energy",()=>{
   var s=Schedule("2",PowerQuantityBasis.FlatPower,new(2026,11,1),new(2026,12,1),60,TimeOfUse.WeekdayBlock(60,7,23,false),[new(2026,11,26)]);
   Equal(s.Hours.ToString(),"320");Equal(s.Total.ToQuantity().Amount.ToString(),"640");
  });
  Check("negative and zero amounts retain sign and exact price units",()=>{
   var s=Schedule("-2",PowerQuantityBasis.TotalEnergy,new(2027,3,14),new(2027,3,15),allocation:PowerAllocation.FlatRate);
   Equal(s.Total.Times(new UnitPrice(ExactDecimal.Parse("3"),new PriceUnit(R("usd"),energy.Key,ExactDecimal.Parse("2")))).ToMoney().Amount.ToString(),"-12");
   Equal(Schedule("0",PowerQuantityBasis.FlatPower,new(2027,3,14),new(2027,3,15)).Total.ToQuantity().Amount.ToString(),"0");
   Reject("quantity_mismatch",()=>s.Total.Times(new UnitPrice(ExactDecimal.Parse("3"),new PriceUnit(R("usd"),power.Key,ExactDecimal.Parse("1")))));
  });
  Check("missing allocation, wrong units, empty masks and revision mismatches reject",()=>{
   Reject("power_quantity",()=>Schedule("1",PowerQuantityBasis.TotalEnergy,new(2027,3,14),new(2027,3,15)));
   Reject("power_quantity",()=>Schedule("1",PowerQuantityBasis.FlatPower,new(2027,3,14),new(2027,3,15),allocation:PowerAllocation.FlatRate));
   Reject("settlement_coverage",()=>Schedule("1",PowerQuantityBasis.FlatPower,new(2027,3,14),new(2027,3,15),mask:TimeOfUse.All(60).Complement()));
   Reject("power_quantity",()=>PowerQuantitySchedule.Compile(new(ExactDecimal.Parse("1"),power.Key),PowerQuantityBasis.TotalEnergy,power,energy,new(2027,3,14),new(2027,3,15),clock,TimeOfUse.All(60),[],60,PowerAllocation.FlatRate));
  });
  Check("every embedded quantity reference must belong to its exact definition revision",()=>{
   var foreign=new ReferenceRevision(Guid.NewGuid(),Guid.NewGuid());ReferenceKey Other(string code)=>new(foreign,code);
   foreach(var changed in new[]{new QuantitySpecification(power.Key,Other("power_product"),power.MeasurementBasis,power.Unit,power.Dimension),
    new(power.Key,power.Commodity,Other("delivery_rate"),power.Unit,power.Dimension),
    new(power.Key,power.Commodity,power.MeasurementBasis,Other("megawatt"),power.Dimension),
    new(power.Key,power.Commodity,power.MeasurementBasis,power.Unit,Other("power")),
    new(power.Key,power.Commodity,power.MeasurementBasis,power.Unit,new(r,""))})
    Reject("power_quantity",()=>PowerQuantitySchedule.Compile(new(ExactDecimal.Parse("1"),power.Key),PowerQuantityBasis.FlatPower,changed,energy,new(2027,3,14),new(2027,3,15),clock,TimeOfUse.All(60),[],60,null));
  });
  Check("typed settlement preserves exact varying-price cash and rejects another MWh basis",()=>{
   var s=Schedule("1",PowerQuantityBasis.TotalEnergy,new(2027,3,14),new(2027,3,15),allocation:PowerAllocation.FlatRate);
   var index=new PowerIndex(R("index"),R("usd"),energy.Unit,energy.Key,"Test","Intraday");
   var rows=s.Intervals.Select((p,n)=>new PowerFixing(p.Interval.Start,p.Interval.End,index,ExactDecimal.Parse(n==0?"1":"0"),null)).ToArray();
   var result=PowerSettlement.Calculate(s,rows,index,PowerSettlementPolicy.Preview);
   Equal(result.Summary.ExactAmountNumerator,"1");Equal(result.Summary.ExactAmountDenominator,"23");
   Equal(result.Cash.Amount.ToString(),"0.04");Equal(result.Energy.ToQuantity().Amount.ToString(),"1");
   var wrong=index with {EnergyQuantity=R("other_measurement_basis")};
   Reject("settlement_index",()=>PowerSettlement.Calculate(s,rows.Select(p=>p with {Index=wrong}).ToArray(),wrong,PowerSettlementPolicy.Preview));
   Reject("settlement_coverage",()=>PowerSettlement.Calculate(s,null!,index,PowerSettlementPolicy.Preview));
   Reject("power_quantity",()=>PowerSettlement.Calculate(null!,rows,index,PowerSettlementPolicy.Preview));
  });
  Check("cash aggregation defers rounding, cancels large terms and rejects final overflow",()=>{
   var s=Schedule("999999999999999999999999",PowerQuantityBasis.TotalEnergy,new(2027,3,15),new(2027,3,16),allocation:PowerAllocation.FlatRate);
   var index=new PowerIndex(R("index"),R("usd"),energy.Unit,energy.Key,"Test","Intraday");
   var rows=s.Intervals.Select((p,n)=>new PowerFixing(p.Interval.Start,p.Interval.End,index,ExactDecimal.Parse(n<12?"999999999999999999999999":"-999999999999999999999999"),null)).ToArray();
   Equal(PowerSettlement.Calculate(s,rows,index,PowerSettlementPolicy.Preview).Cash.Amount.ToString(),"0");
   Reject("numeric_range",()=>PowerSettlement.Calculate(s,rows.Select(p=>p with {Total=ExactDecimal.Parse("2")}).ToArray(),index,PowerSettlementPolicy.Preview));
  });
  return passed;
 }
}
