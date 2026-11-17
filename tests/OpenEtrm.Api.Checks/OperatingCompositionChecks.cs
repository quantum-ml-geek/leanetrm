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
        var references=fixture.Data.References.ToDictionary(pair=>pair.Key,pair=>pair.Value);
        var alternate=JsonNode.Parse(references["quote_specifications"].Single(row=>row.GetProperty("code").GetString()=="energy_price").GetRawText())!.AsObject();
        alternate["code"]="synthetic_alternate_energy_price";
        references["quote_specifications"]=references["quote_specifications"].Add(JsonSerializer.SerializeToElement(alternate));
        fixture=fixture with{Data=new(fixture.Manifest,fixture.Data.Definitions,references,[])};
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
        var legacyLabels=json.DeepClone().AsObject();var legacyNames=new[]{"discharging_energy","charging_energy","variable_fee","variable_fee","access_fee"};
        for(var slot=0;slot<legacyNames.Length;slot++)legacyLabels["composition"]!["sides"]![slot]!["name"]=legacyNames[slot];
        RetainedPresentation(Prepare(legacyLabels),legacyLabels,Prepare,profileChecks:true);
        RetainedPresentation(prepared,json,Prepare);
        var repeatedLabels=json.DeepClone().AsObject();
        repeatedLabels["composition"]!["sides"]![2]!["name"]="Synthetic repeated fee";
        repeatedLabels["composition"]!["sides"]![3]!["name"]="Synthetic repeated fee";
        repeatedLabels["composition"]!["sides"]![0]!["coefficient"]="-1";
        repeatedLabels["composition"]!["sides"]![1]!["coefficient"]="1";
        RetainedPresentation(Prepare(repeatedLabels),repeatedLabels,Prepare);
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
        var deliveredPlan=Prepare(delivery);RetainedPresentation(deliveredPlan,delivery,Prepare);
        var delivered=deliveredPlan.Instrument!.Sides[0].Side.GenerateSchedule().Rows[0];
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
    private static void RetainedPresentation(StructuredPowerPreparedPlan prepared,JsonObject request,Func<JsonObject,StructuredPowerPreparedPlan> prepare,bool profileChecks=false)
    {
        var instrument=prepared.Instrument!;
        var options=new JsonSerializerOptions(JsonSerializerDefaults.Web);
        var declarations=request["composition"]!["sides"]!.AsArray();
        var programs=instrument.Sides.Select((member,slot)=>{
            var program=BookedSideProgram.Compile(ScheduleDefinitionCompiler.Generate(member.Side,operatingInputs:prepared.Quantities));
            return new RetainedSideProgram(slot,member.Side.Id,Guid.NewGuid(),program.Identity,program);
        }).ToImmutableArray();
        var head=JsonSerializer.SerializeToNode(new{instrument_id=instrument.Id,catalog_id=prepared.Resolved.CanonicalTerms.DefinitionCatalogId,
            definition_revision_id=prepared.Resolved.CanonicalTerms.DefinitionRevisionId,request=new{plan=request},members=programs.Select(program=>new{
            slot=program.Slot,sideId=program.SideId,name=declarations[program.Slot]!["name"]!.GetValue<string>(),coefficient=declarations[program.Slot]!["coefficient"]!.GetValue<string>()})},options)!.AsObject();
        var physical=JsonSerializer.SerializeToElement(new{kind="battery",facility_code=prepared.Resolved.CanonicalTerms.FacilityCode,reference_catalog_id=instrument.Currency.Revision.CatalogId,
            reference_revision_id=instrument.Currency.Revision.RevisionId,quantity_code=instrument.UnitQuantity.Specification.Code,currency_code=instrument.Currency.Code});
        OperatingPosition Position(JsonObject value)=>new(JsonSerializer.SerializeToElement(value),JsonSerializer.SerializeToElement(new{}),physical);
        var group=RetainedInstrumentSidePresentation.Operating(Position(head),programs);
        if(group.BindingId!=instrument.Id||group.Sides.Length!=declarations.Count||!group.Sides.Select(side=>side.SideId).SequenceEqual(programs.Select(program=>program.SideId)))
            throw new Exception("The saved v2 operating view must retain every exact ordered program and native binding.");
        for(var slot=0;slot<declarations.Count;slot++)
        {
            var declaration=declarations[slot]!;var side=group.Sides[slot];var delivery=declaration["kind"]!.GetValue<string>()=="delivery";
            var positive=declaration["coefficient"]!.GetValue<string>()=="1";
            var values=side.OverviewSections.SelectMany(section=>section.Values).ToArray();
            bool Shows(string label,string value)=>values.Any(term=>term.Label==label&&term.Value==value);
            if(side.Label!=declaration["name"]!.GetValue<string>()||side.RoleLabel!=(delivery?"Operating-right delivery":"Operating-right payment")||
                side.DirectionLabel!=(positive?delivery?"Company receives delivery":"Company receives proceeds":delivery?"Company delivers":"Company pays")||
                !Shows("Quantity source",declaration["quantitySource"]!.GetValue<string>())||!Shows("Price policy",declaration["price"]!["mode"]!.GetValue<string>())||
                !Shows("Quote",declaration["price"]!["quoteCode"]!.GetValue<string>())||!Shows("Fixed price",declaration["price"]!["fixedPrice"]!.GetValue<string>())||
                !Shows("Quote quantity",declaration["quantitySource"]!.GetValue<string>()=="horizon_right"?"right":"energy")||!Shows("Quote multiplier","1")||
                !delivery&&(!Shows("Payment rule",declaration["paymentRule"]!["rule"]!.GetValue<string>())||!Shows("Payment days after delivery month",declaration["paymentRule"]!["days"]!.ToJsonString())))
                throw new Exception("Saved v2 Side names, explicit signs, delivery/payment roles and quantity sources must come from their exact retained declaration, not legacy slot names.");
        }
        var equivalent=head.DeepClone().AsObject();var original=declarations[0]!["price"]!["fixedPrice"]!.GetValue<string>();
        equivalent["request"]!["plan"]!["composition"]!["sides"]![0]!["price"]!["fixedPrice"]=original.Contains('.')?original+"0":original+".0000";
        _=prepare(equivalent["request"]!["plan"]!.AsObject());
        _=RetainedInstrumentSidePresentation.Operating(Position(equivalent),programs);
        if(profileChecks)
        {
            var legacy=request.DeepClone().AsObject();legacy.Remove("composition");
            legacy["valuation"]=JsonSerializer.SerializeToNode(new StructuredPowerValuationInput(
                "resource_right_holder_v1","remaining_operating_value_v1","usd","right",false,
                new("monthly","days_after_period_end",18,null,"calendar_days",null,"unadjusted",null,PaymentRule.Implementation),
                new("fixed","energy_price","100",null,null),new("fixed","energy_price","20",null,null),null,null,null,null,null,null,null,null,null,null),options);
            var old=prepare(legacy);var oldPrograms=old.Instrument!.Sides.Select((member,slot)=>{
                var program=BookedSideProgram.Compile(ScheduleDefinitionCompiler.Generate(member.Side,operatingInputs:old.Quantities));
                return new RetainedSideProgram(slot,member.Side.Id,Guid.NewGuid(),program.Identity,program);
            }).ToImmutableArray();
            var oldHead=head.DeepClone().AsObject();oldHead["instrument_id"]=old.Instrument.Id;
            oldHead["request"]!["plan"]=legacy.DeepClone();
            oldHead["members"]=JsonSerializer.SerializeToNode(oldPrograms.Select(program=>new{slot=program.Slot,sideId=program.SideId,
                name=old.SideNames[program.SideId],coefficient=old.Instrument.Sides[program.Slot].Coefficient.ToString()}),options);
            var oldGroup=RetainedInstrumentSidePresentation.Operating(Position(oldHead),oldPrograms);
            if(oldGroup.Sides.Length!=2||oldGroup.Sides[0].RoleLabel!="Operating-right discharging energy")
                throw new Exception("A real v1 request with explicit financial valuation must preserve its retained Side mapping.");
            var admitted=new List<string>();
            foreach(var (label,mutate) in new (string,Action<JsonObject>)[]{
                ("perspective",value=>value["request"]!["plan"]!["composition"]!["perspective"]="unsupported_perspective"),
                ("measure",value=>value["request"]!["plan"]!["composition"]!["measure"]="unsupported_measure"),
                ("discounting",value=>value["request"]!["plan"]!["composition"]!["discounting"]=true),
                ("missing financial form",value=>value["request"]!["plan"]!.AsObject().Remove("composition")),
                ("both financial forms",value=>value["request"]!["plan"]!["valuation"]=legacy["valuation"]!.DeepClone()),
                ("missing valuation member",value=>value["request"]!["plan"]!.AsObject().Remove("valuation")),
                ("null composition",value=>value["request"]!["plan"]!["composition"]=null),
                ("incomplete legacy valuation",value=>{var plan=value["request"]!["plan"]!.AsObject();plan.Remove("composition");plan["valuation"]=new JsonObject();}),
                ("missing request",value=>value.Remove("request"))})
            {
                var invalid=head.DeepClone().AsObject();mutate(invalid);
                try{RetainedInstrumentSidePresentation.Operating(Position(invalid),programs);}
                catch(MarketDataException error)when(error.Code=="instrument_side_presentation"){continue;}
                admitted.Add(label);
            }
            if(admitted.Count>0)throw new Exception("Saved operating profiles or financial forms were not qualified: "+string.Join(", ",admitted));
        }
        foreach(var mutate in new Action<JsonObject>[] {
            value=>value["members"]![0]!["coefficient"]=declarations[0]!["coefficient"]!.GetValue<string>()=="1"?"-1":"1",
            value=>value["members"]![0]!["name"]="Different retained label",
            value=>value["members"]![0]!["sideId"]=Guid.NewGuid().ToString(),
            value=>value["request"]!["plan"]!["composition"]!.AsObject().Remove("implementation"),
            value=>value["request"]!["plan"]!["composition"]!["implementation"]="unsupported_composition",
            value=>{
                var side=value["request"]!["plan"]!["composition"]!["sides"]![0]!;
                var delivery=declarations[0]!["kind"]!.GetValue<string>()=="delivery";
                side["kind"]=delivery?"payment":"delivery";
                side["paymentRule"]=delivery?declarations[1]!["paymentRule"]!.DeepClone():null;
            }})
        {
            var invalid=head.DeepClone().AsObject();mutate(invalid);
            try{RetainedInstrumentSidePresentation.Operating(Position(invalid),programs);}
            catch(MarketDataException error)when(error.Code=="instrument_side_presentation"){continue;}
            throw new Exception("A v2 Side summary cannot relabel a mismatched native member, sign or retained delivery/payment program.");
        }
        var paymentSlot=Enumerable.Range(0,declarations.Count).First(slot=>declarations[slot]!["kind"]!.GetValue<string>()=="payment");
        var unproved=new List<string>();
        foreach(var (label,mutate) in new (string,Action<JsonObject>)[] {
            ("quantity source",plan=>plan["composition"]!["sides"]![0]!["quantitySource"]="charging_energy"),
            ("exact quote",plan=>plan["composition"]!["sides"]![0]!["price"]!["quoteCode"]="synthetic_alternate_energy_price"),
            ("fixed price",plan=>plan["composition"]!["sides"]![0]!["price"]!["fixedPrice"]="101"),
            ("payment days",plan=>plan["composition"]!["sides"]![paymentSlot]!["paymentRule"]!["days"]=declarations[paymentSlot]!["paymentRule"]!["days"]!.GetValue<int>()+1)})
        {
            var invalid=head.DeepClone().AsObject();var plan=invalid["request"]!["plan"]!.AsObject();mutate(plan);
            _=prepare(plan); // Each changed declaration is itself a valid supported v2 contract.
            try{RetainedInstrumentSidePresentation.Operating(Position(invalid),programs);}
            catch(MarketDataException error)when(error.Code=="instrument_side_presentation"){continue;}
            unproved.Add(label);
        }
        if(unproved.Count>0)throw new Exception("Saved v2 terms disagree with their sealed executable program: "+string.Join(", ",unproved));
    }
}
