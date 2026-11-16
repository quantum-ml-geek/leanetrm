using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Nodes;
using OpenEtrm.Api;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;

internal static class OperatingCompositionChecks
{
    internal static void Run()
    {
        var fixture=StructuredPowerChecks.Fixture();
        var at=DateTimeOffset.Parse("2040-01-31T00:00:00Z");
        var frame=new InputFrame(Guid.NewGuid(),"Synthetic side composition",at,new(2040,1,31),[],ImmutableDictionary<string,ImmutableArray<Guid>>.Empty);
        var saved=new StructuredPowerFacilityVersion(Guid.NewGuid(),1,"2040-02-01T00:00:00Z","2041-02-01T00:00:00Z",fixture.Terms);
        var request=new StructuredPowerPreviewRequest(frame.Id,saved.Id,1,new("2040-02-01",1),new("2040-02-01T00:00:00Z","0","0","0","0"),
            [new("10","0","1"),new("0","8.1","1")],null,[],null,[],null);
        object Payment(int days)=>new{frequency="monthly",rule="days_after_period_end",days,dayOfMonth=(int?)null,dayBasis="calendar_days",shortMonth=(string?)null,adjustment="unadjusted",calendar=(object?)null,implementation=PaymentRule.Implementation};
        object Side(string key,string source,string amount,string coefficient,int days,string quote="energy_price",string kind="payment")=>new{
            key,name="Synthetic "+key,quantitySource=source,coefficient,kind,
            price=new{mode="fixed",quoteCode=quote,fixedPrice=amount,curveCode=(string?)null,contractId=(Guid?)null},paymentRule=kind=="payment"?Payment(days):null};
        var json=JsonSerializer.SerializeToNode(request,new JsonSerializerOptions(JsonSerializerDefaults.Web))!.AsObject();
        json["composition"]=JsonSerializer.SerializeToNode(new{implementation="operating_side_composition_v2",perspective="resource_right_holder_v1",measure="remaining_operating_value_v1",currencyCode="usd",rightQuantityCode="right",discounting=false,
            sides=new[]{Side("output","discharging_energy","100","1",10),Side("charging","charging_energy","20","-1",20),Side("fee_a","grid_throughput","1","-1",25),Side("fee_b","grid_throughput","2","-1",30),Side("access","horizon_right","5","-1",15,"right_price")}});
        StructuredPowerPreparedPlan Prepare(JsonObject input)=>StructuredPowerPreview.Prepare(fixture.Data,frame,saved,at,input.Deserialize<StructuredPowerPreviewRequest>(new JsonSerializerOptions(JsonSerializerDefaults.Web))!);
        var prepared=Prepare(json);var valuation=prepared.Preview.Valuation!;
        var retained= json.Deserialize<StructuredPowerPreviewRequest>(new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
        retained=retained with{Composition=retained.Composition! with{CurrencyCode="unavailable_authoring_choice"}};
        var feasibility=StructuredPowerPreview.Calculate(fixture.Data,frame,saved,at,StructuredPowerBookingStore.PhysicalPlan(retained));
        if(feasibility.Valuation is not null||feasibility.Intervals.Length!=2)throw new Exception("Saved repricing must obtain physical evidence without reassembling authored financial Sides.");
        if(valuation.Value.ToExactString()!="550.7"||valuation.Sides.Length!=5)throw new Exception("Independent repeated fee sides must both contribute exactly once.");
        var members=prepared.Instrument!.Sides;
        if(members.Any(m=>m.Side is not FixedSide)||members[2].Side.GenerateSchedule().Rows[0].PaymentAt==members[3].Side.GenerateSchedule().Rows[0].PaymentAt)
            throw new Exception("Each concrete Side must retain its independent payment schedule.");
        var reordered=json.DeepClone().AsObject();var sides=reordered["composition"]!["sides"]!.AsArray();var first=sides[0]!.DeepClone();sides.RemoveAt(0);sides.Add(first);
        if(Prepare(reordered).Preview.Valuation!.Value!=valuation.Value)throw new Exception("Reordering independent memberships must preserve value.");
        void Reject(string code,Action<JsonObject> change)
        {
            var invalid=json.DeepClone().AsObject();change(invalid);
            try{Prepare(invalid);}catch(MarketDataException error)when(error.Code==code){return;}
            throw new Exception("Expected "+code);
        }
        Reject("operating_composition",v=>v["composition"]!["sides"]![1]!["key"]="output");
        Reject("operating_composition",v=>v["composition"]!["sides"]![0]!["coefficient"]="0");
        Reject("operating_composition",v=>v["composition"]!["sides"]![0]!["quantitySource"]="guaranteed_fuel");
        Reject("operating_composition",v=>v["composition"]!["sides"]![0]!["paymentRule"]=null);
        Reject("structured_power_price",v=>v["composition"]!["sides"]![0]!["price"]!["quoteCode"]="fuel_price");
        Reject("operating_composition",v=>v["composition"]!["sides"]=new JsonArray());
        var delivery=json.DeepClone().AsObject();delivery["composition"]!["sides"]![0]!["kind"]="delivery";delivery["composition"]!["sides"]![0]!["paymentRule"]=null;
        var delivered=Prepare(delivery).Instrument!.Sides[0].Side.GenerateSchedule().Rows[0];
        if(delivered.PaymentAt!=prepared.Grid[0].End)throw new Exception("Physical delivery is valued at the retained delivery boundary without a payment rule.");
        if(JsonSerializer.Serialize(request,new JsonSerializerOptions(JsonSerializerDefaults.Web)).Contains("composition"))throw new Exception("The optional composition extension must not rewrite retained v1 commands.");
        var thermal=saved with{Terms=fixture.Terms with{Kind="thermal",Battery=null,FuelQuantityCode="fuel",Thermal=new("0","10","100","100","10","10",0,0,0,3,"1.5","0","1")}};
        var thermalPlan=request with{BatteryState=null,BatteryDispatch=[],ThermalState=new("2040-02-01T00:00:00Z","offline",60,"0",0,"2","1","3","require_minimum_times_satisfied","thermal_exact_elapsed_quantity_v1"),ThermalDispatch=[new("online","10","10","2040-02-01T00:00:00Z")]};
        var thermalJson=JsonSerializer.SerializeToNode(thermalPlan,new JsonSerializerOptions(JsonSerializerDefaults.Web))!.AsObject();
        thermalJson["composition"]=json["composition"]!.DeepClone();
        thermalJson["composition"]!["sides"]=JsonSerializer.SerializeToNode(new[]{Side("energy","energy_output","100","1",10),Side("guarantee","guaranteed_fuel","10","-1",20,"fuel_price"),Side("consumption","consumption_fuel","1","-1",25,"fuel_price")});
        var thermalPrepared=StructuredPowerPreview.Prepare(fixture.Data,frame,thermal,at,thermalJson.Deserialize<StructuredPowerPreviewRequest>(new JsonSerializerOptions(JsonSerializerDefaults.Web))!);
        if(thermalPrepared.Preview.Valuation!.Value.ToExactString()!="744")throw new Exception("Guaranteed 24 and modeled 16 fuel units must retain distinct typed output identities under one thermal plan.");
        Console.WriteLine("PASS explicit operating Side composition, repeated sources, signs, independent dates, delivery and legacy command identity");
    }
}
