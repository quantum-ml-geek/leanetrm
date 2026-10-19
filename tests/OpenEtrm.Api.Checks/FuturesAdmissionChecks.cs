using System.Collections.Immutable;
using System.Text.Json;
using OpenEtrm.Api;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;
using OpenEtrm.MarketData.Power;

internal static class FuturesAdmissionChecks
{
    private static JsonElement Row(object value)=>JsonSerializer.SerializeToElement(value);
    public static void Run()
    {
        var count=0;
        void Check(string name,Action test){test();count++;Console.WriteLine("PASS futures admission: "+name);}
        void Reject(string code,Action test)
        {try{test();}catch(MarketDataException error)when(error.Code==code){return;}throw new Exception("Expected "+code);}
        var fixture=Fixture();
        var references=fixture.References;
        PreviewData Data(Dictionary<string,ImmutableArray<JsonElement>>? selected=null,Dictionary<string,ImmutableArray<JsonElement>>? definitions=null)
            =>new(fixture.Manifest,definitions??fixture.Definitions,selected??references,[]);
        FuturesMarketBinding Bind(PreviewData selected)=>FuturesStore.Binding(selected,"gas_curve",selected.Contracts.Single().Key.Id,Guid.NewGuid(),FuturesMarketBinding.GeneralImplementation);
        var data=Data();var expected=DateTimeOffset.Parse("2040-01-02T00:00:00Z");
        Check("date-only facts load without fabricating source time",()=>
        {
            if(data.FuturesSeries.Single().FirstTradingAt is not null||references["futures_milestones"][0].OptionalText("event_at") is not null)
                throw new Exception("A source event timestamp was invented.");
            if(Bind(data).EligibleFrom!=expected)throw new Exception("Explicit approved eligibility changed.");
            var sequence=SchedulePreview.Compile(data,new("gas_curve",expected.AddDays(-1),expected.AddDays(18),expected.AddDays(1)));
            if(sequence.Entries.Single().EligibleFrom!=expected)throw new Exception("Date sequence lost its explicit eligibility.");
        });
        JsonElement With(JsonElement row,string key,object? value)
        {var copy=JsonSerializer.Deserialize<Dictionary<string,JsonElement>>(row.GetRawText())!;copy[key]=Row(value!);return Row(copy);}
        Dictionary<string,ImmutableArray<JsonElement>> Change(string table,params JsonElement[] rows)=>new(references){[table]=[..rows]};
        var admission=references["futures_execution_admissions"].Single();
        var first=references["futures_milestones"][0];
        Check("missing and duplicate approvals fail instead of choosing eligibility",()=>
        {
            Reject("futures_admission",()=>Bind(Data(Change("futures_execution_admissions"))));
            Reject("futures_admission",()=>Bind(Data(Change("futures_execution_admissions",admission,admission))));
        });
        foreach(var (key,value) in new (string,object?)[]{("eligible_from","2040-01-01T00:00:00Z"),("eligibility_offset_seconds","60"),
                    ("eligibility_tzdb_version","unqualified"),("eligibility_rule","unknown"),("usage_policy","unknown"),("execution_venue","block"),
                    ("qualification_source_code","missing"),("implementation",FuturesMarketBinding.Implementation)})
            Check("rejects conflicting retained "+key,()=>Reject("futures_admission",()=>Bind(Data(Change("futures_execution_admissions",With(admission,key,value))))));
        Check("unknown source dates and unsupported clocks do not receive defaults",()=>
        {
            Reject("futures_admission",()=>Bind(Data(Change("futures_milestones",With(first,"value_state","unknown"),references["futures_milestones"][1]))));
            Reject("futures_admission",()=>Bind(Data(Change("clock_rules",With(references["clock_rules"][0],"fixed_offset_seconds","3600")))));
            Reject("futures_admission",()=>Bind(Data(Change("clock_rules"))));
        });
        foreach(var (source,key,value) in new (int,string,object?)[]{(0,"content_sha256",null),(1,"content_sha256",null),
                    (0,"content_sha256",new string('A',64)),(0,"locator","unqualified:mark"),(0,"kind","manual_entry"),(1,"kind","synthetic")})
            Check("rejects missing or contradictory source evidence "+source+"/"+key,()=>
            {
                var changed=references["sources"].ToArray();changed[source]=With(changed[source],key,value);
                Reject("futures_admission",()=>Bind(Data(Change("sources",changed))));
            });
        Check("generated marks require the exact candidate contract policy",()=>
        {
            var definitions=new Dictionary<string,ImmutableArray<JsonElement>>(fixture.Definitions)
                {["curves"]=[With(fixture.Definitions["curves"][0],"direct_role","daily_settlement")]};
            Reject("futures_admission",()=>Bind(Data(definitions:definitions)));
            Reject("futures_admission",()=>FuturesStore.Binding(data,"gas_curve",data.Contracts.Single().Key.Id,Guid.NewGuid(),FuturesMarketBinding.Implementation));
            Reject("futures_admission",()=>Bind(Data(Change("futures_products",With(references["futures_products"][0],"definition_state","placeholder")))));
            var synthetic=Change("futures_products",With(references["futures_products"][0],"definition_state","synthetic"));
            synthetic["futures_series"]=[With(references["futures_series"][0],"definition_state","synthetic")];
            Reject("futures_admission",()=>Bind(Data(synthetic,definitions)));
        });
        Check("precise source events stay precise and do not become approval dates",()=>
        {
            const string instant="2040-01-01T15:30:00Z";
            var precise=Change("futures_milestones",With(first,"event_at",instant),references["futures_milestones"][1]);
            precise["futures_execution_admissions"]=[With(With(With(admission,"eligibility_rule",FuturesAdmission.ExactFirst),"eligible_from",instant),"eligibility_offset_seconds",null)];
            if(Bind(Data(precise)).EligibleFrom!=DateTimeOffset.Parse(instant))throw new Exception("Exact source event changed.");
            precise["futures_execution_admissions"]=[With(precise["futures_execution_admissions"][0],"eligible_from","2040-01-02T00:00:00Z")];
            Reject("futures_admission",()=>Bind(Data(precise)));
            precise["futures_execution_admissions"]=[];
            precise["futures_products"]=[With(references["futures_products"][0],"definition_state","synthetic")];
            precise["futures_series"]=[With(references["futures_series"][0],"definition_state","synthetic")];
            var definitions=new Dictionary<string,ImmutableArray<JsonElement>>(fixture.Definitions)
                {["curves"]=[With(fixture.Definitions["curves"][0],"direct_role","daily_settlement")]};
            if(Bind(Data(precise,definitions)).EligibleFrom!=DateTimeOffset.Parse(instant))throw new Exception("Legacy synthetic event changed.");
        });
        foreach(var (date,instant,offset) in new[]{("2026-03-07","2026-03-08T05:00:00Z","-18000"),("2026-03-08","2026-03-09T04:00:00Z","-14400"),
                    ("2026-10-31","2026-11-01T04:00:00Z","-14400"),("2026-11-01","2026-11-02T05:00:00Z","-18000")})
            Check("qualified next-date boundary observes installed DST: "+date,()=>
            {
                var version=TimeZoneDatabase.Installed().Version();
                var selected=Change("futures_milestones",With(With(first,"business_date",date),"clock_code","eastern"),references["futures_milestones"][1]);
                selected["clock_rules"]=[Row(new{code="eastern",kind="iana",fixed_offset_seconds=(string?)null,iana_zone="America/New_York",tzdb_version=version})];
                selected["futures_execution_admissions"]=[With(With(With(admission,"eligible_from",instant),"eligibility_offset_seconds",offset),"eligibility_tzdb_version",version)];
                if(new FuturesAdmission(selected).EligibleFrom("gas_feb")!=DateTimeOffset.Parse(instant))throw new Exception("DST boundary changed.");
                selected["futures_execution_admissions"]=[With(selected["futures_execution_admissions"][0],"eligibility_offset_seconds",offset=="-18000"?"-14400":"-18000")];
                Reject("futures_admission",()=>new FuturesAdmission(selected).EligibleFrom("gas_feb"));
            });
        Check("pinned clock rejects missing and repeated local midnight",()=>
        {
            var rule=TimeZoneInfo.AdjustmentRule.CreateAdjustmentRule(new(2040,1,1),new(2040,12,31),TimeSpan.FromHours(1),
                TimeZoneInfo.TransitionTime.CreateFixedDateRule(new(1,1,1,0,0,0),3,1),TimeZoneInfo.TransitionTime.CreateFixedDateRule(new(1,1,1,1,0,0),11,1));
            var clock=PowerClock.Capture(TimeZoneInfo.CreateCustomTimeZone("synthetic_midnight",TimeSpan.Zero,"Synthetic clock","Synthetic standard","Synthetic daylight",[rule]));
            Reject("clock_rule",()=>clock.StartOfDay(new(2040,3,1)));
            Reject("clock_rule",()=>clock.StartOfDay(new(2040,11,1)));
        });
        Console.WriteLine(count+" futures admission checks passed.");
    }

    private static (PreviewManifest Manifest,Dictionary<string,ImmutableArray<JsonElement>> Definitions,
        Dictionary<string,ImmutableArray<JsonElement>> References) Fixture()
    {
        var catalog=Guid.NewGuid();var revision=Guid.NewGuid();var reference=Guid.NewGuid();var referenceRevision=Guid.NewGuid();
        var contract=Guid.NewGuid();var series=Guid.NewGuid();
        var manifest=new PreviewManifest("local-synthetic-preview",catalog,revision,reference,referenceRevision,Guid.NewGuid(),Guid.NewGuid(),[],null,
            FuturesConvention:FuturesMarketBinding.GeneralImplementation);
        Dictionary<string,ImmutableArray<JsonElement>> definitions=new()
        {
            ["revisions"]=[Row(new{catalog_id=catalog,id=revision,reference_catalog_id=reference,reference_revision_id=referenceRevision,state="sealed"})],
            ["contracts"]=[Row(new{id=contract,kind="future",delivery_from="2040-02-01",delivery_to="2040-03-01",expiry_at="2040-01-20T00:00:00Z",futures_series_code="gas_feb"})],
            ["curves"]=[Row(new{code="gas_curve",name="Synthetic gas",commodity_code="gas",quote_code="gas_price",location_code="hub",profile_code="uniform",settlement_target_code="gas_target",rule="direct",direct_role="trader_mark",direct_source_code="generated"})],
            ["curve_members"]=[Row(new{curve_code="gas_curve",contract_id=contract,ordinal=0})],
            ["curve_inputs"]=[],["constituent_mappings"]=[],
            ["series"]=[Row(new{id=series,contract_id=contract,quote_code="gas_price",value_specification_code=(string?)null})],
            ["rate_curves"]=[],["rate_curve_points"]=[],["revision_periods"]=[]
        };
        Dictionary<string,ImmutableArray<JsonElement>> references=new()
        {
            ["quantity_specifications"]=[Row(new{code="gas_quantity",commodity_code="gas",basis_code="energy",unit_code="mwh",dimension_code="energy"})],
            ["quote_specifications"]=[Row(new{code="gas_price",kind="outright",currency_code="usd",quantity_code="gas_quantity",multiplier="1",trading_tick="0.01",clearing_increment="0.001",minimum="-100",maximum="1000"})],
            ["settlement_targets"]=[Row(new{code="gas_target",kind="future_series",index_a_code=(string?)null,index_b_code=(string?)null})],
            ["futures_series"]=[Row(new{code="gas_feb",product_code="gas",definition_state="candidate",delivery_from="2040-02-01",delivery_to="2040-03-01"})],
            ["futures_products"]=[Row(new{code="gas",definition_state="candidate",commodity_code="gas",quote_currency_code="usd",quote_multiplier="1",outright_tick_size="0.01",location_code="hub",quote_unit_code="mwh",lot_unit_code="mwh",contract_size="40",lot_basis="fixed_total",settlement_method="cash"})],
            ["futures_milestones"]=[Row(new{series_code="gas_feb",milestone="first_trading",value_state="known",business_date="2040-01-01",event_at=(string?)null,clock_code="utc"}),Row(new{series_code="gas_feb",milestone="last_trading",value_state="known",business_date="2040-01-20",event_at="2040-01-20T00:00:00Z",clock_code="utc"})],
            ["futures_product_terms"]=[Row(new{product_code="gas",profile_code="uniform",index_code=(string?)null})],
            ["futures_lot_resolutions"]=[],["futures_basis_settlements"]=[],["value_specifications"]=[],
            ["futures_execution_admissions"]=[Row(new{catalog_id=reference,revision_id=referenceRevision,series_code="gas_feb",implementation=FuturesMarketBinding.GeneralImplementation,usage_policy="generated_prices_sample_trades_v1",execution_venue="central_limit_order_book",qualification_source_code="qualification",source_catalog_id=reference,source_revision_id=Guid.NewGuid(),source_series_code="gas_feb",eligible_from="2040-01-02T00:00:00Z",eligibility_rule="after_source_first_trade_date_v1",eligibility_offset_seconds="0",eligibility_tzdb_version=(string?)null})],
            ["sources"]=[Row(new{code="generated",kind="synthetic",locator="generated:pilot-close-v1/synthetic",content_sha256=new string('a',64)}),Row(new{code="qualification",kind="manual_entry",locator="operator:synthetic-qualification",content_sha256=new string('b',64)})],
            ["clock_rules"]=[Row(new{code="utc",kind="fixed_offset",fixed_offset_seconds="0",iana_zone=(string?)null,tzdb_version=(string?)null})]
        };
        return(manifest,definitions,references);
    }
}
