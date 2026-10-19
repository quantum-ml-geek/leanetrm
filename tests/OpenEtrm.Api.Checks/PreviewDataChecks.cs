using System.Collections.Immutable;
using System.Globalization;
using System.Text.Json;
using OpenEtrm.Api;
using OpenEtrm.MarketData;

internal static class PreviewDataChecks
{
    public static void Run()
    {
        var count=0;
        void Check(string name,Action test){test();count++;Console.WriteLine("PASS preview data: "+name);}
        void Reject(string code,Action test)
        {try{test();}catch(MarketDataException error)when(error.Code==code){return;}throw new Exception("Expected "+code);}
        var fixture=Fixture(405);
        PreviewData Data(ImmutableArray<JsonElement>? observations=null,Dictionary<string,ImmutableArray<JsonElement>>? references=null,
            Dictionary<string,ImmutableArray<JsonElement>>? definitions=null)=>new(fixture.Manifest,definitions??fixture.Definitions,references??fixture.References,observations??fixture.Observations);
        var data=Data();
        Check("all independently keyed futures retain their exact prices and input identities",()=>
        {
            var result=data.Build(fixture.Frame,"future");
            if(data.FuturesSeries.Length!=405||result.Values.Length!=405||result.EvaluatedConstituents!=405)throw new Exception("Selected future coverage changed.");
            for(var i=0;i<405;i++)
            {
                var value=result.Values[i];var row=fixture.Observations[i];
                if(value.Request.Contract.Id!=fixture.Frame.CurveContracts["future"][i]||value.Price.Value!=row.Number("value")||
                    !value.Lineage.Select(key=>key.Id).SequenceEqual([row.Id("id")]))throw new Exception("A price or exact observation identity changed.");
            }
        });
        Check("input pins determine selection independently of loaded row order",()=>
        {
            var reversed=Data([..fixture.Observations.Reverse()]);
            var expected=data.Build(fixture.Frame,"future");var actual=reversed.Build(fixture.Frame,"future");
            if(!actual.Values.Select(v=>(v.Request,v.Price,v.Lineage.Single())).SequenceEqual(expected.Values.Select(v=>(v.Request,v.Price,v.Lineage.Single()))))
                throw new Exception("Loaded row order selected another price.");
        });
        Check("missing and duplicated exact observation pins remain errors",()=>
        {
            Reject("ambiguous_reference",()=>data.Observation(Guid.NewGuid()));
            Reject("ambiguous_reference",()=>Data([..fixture.Observations,fixture.Observations[0]]).Snapshot(fixture.Frame));
            Reject("ambiguous_reference",()=>Data(fixture.Observations.RemoveAt(0)).Snapshot(fixture.Frame));
        });
        Check("corrections are explicit and conflicting successors cannot be chosen",()=>
        {
            var original=fixture.Observations[0];var second=Change(original,"id",Guid.NewGuid());
            second=Change(Change(second,"corrects_id",original.Id("id")),"value","111.001");
            var third=Change(Change(Change(second,"id",Guid.NewGuid()),"corrects_id",second.Id("id")),"value","112.001");
            var corrected=Data([..fixture.Observations,second,third]);
            if(corrected.SelectPinned(fixture.Frame).ObservationIds[0]!=third.Id("id")||
                corrected.Build(fixture.Frame,"future").Values[0].Price.Value!=original.Number("value"))
                throw new Exception("An exact pin was silently replaced or its explicit successor was lost.");
            var branch=Change(second,"id",Guid.NewGuid());
            Reject("revision_conflict",()=>Data([..fixture.Observations,second,branch]).SelectPinned(fixture.Frame));
        });
        Check("required futures joins preserve missing and ambiguous reference errors",()=>
        {
            foreach(var table in new[]{"futures_series","futures_products","futures_product_terms","futures_milestones"})
            {
                var rows=fixture.References[table];
                Reject("ambiguous_reference",()=>Data(references:new(fixture.References){[table]=rows.RemoveAt(0)}));
                Reject("ambiguous_reference",()=>Data(references:new(fixture.References){[table]=[..rows,rows[0]]}));
            }
        });
        Check("duplicate typed definitions retain their domain error",()=>
        {
            Reject("duplicate_definition",()=>Data(definitions:new(fixture.Definitions){["contracts"]=[..fixture.Definitions["contracts"],fixture.Definitions["contracts"][0]]}));
            Reject("duplicate_definition",()=>Data(references:new(fixture.References){["quote_specifications"]=[..fixture.References["quote_specifications"],fixture.References["quote_specifications"][0]]}));
        });
        Check("different authorized reads never reuse each other's source values",()=>
        {
            var changed=fixture.Observations.SetItem(0,Change(fixture.Observations[0],"value","201.001"));
            if(Data(changed).Build(fixture.Frame,"future").Values[0].Price.Value.ToString()!="201.001"||
                data.Build(fixture.Frame,"future").Values[0].Price.Value!=fixture.Observations[0].Number("value"))
                throw new Exception("A different read shared selected data.");
        });
        Console.WriteLine(count+" preview data checks passed.");
    }

    private static JsonElement Row(object value)=>JsonSerializer.SerializeToElement(value);
    private static JsonElement Change(JsonElement row,string key,object? value)
    {var fields=JsonSerializer.Deserialize<Dictionary<string,JsonElement>>(row.GetRawText())!;fields[key]=Row(value!);return Row(fields);}
    private static (PreviewManifest Manifest,Dictionary<string,ImmutableArray<JsonElement>> Definitions,
        Dictionary<string,ImmutableArray<JsonElement>> References,ImmutableArray<JsonElement> Observations,InputFrame Frame) Fixture(int count)
    {
        var cat=Guid.NewGuid();var rev=Guid.NewGuid();var rcat=Guid.NewGuid();var rrev=Guid.NewGuid();
        var contract=Enumerable.Range(0,count).Select(_=>Guid.NewGuid()).ToArray();
        var series=Enumerable.Range(0,count).Select(_=>Guid.NewGuid()).ToArray();
        var at=DateTimeOffset.Parse("2040-01-10T00:00:00Z",CultureInfo.InvariantCulture);
        Dictionary<string,ImmutableArray<JsonElement>> definitions=new()
        {
            ["revisions"]=[Row(new{catalog_id=cat,id=rev,reference_catalog_id=rcat,reference_revision_id=rrev,state="sealed"})],
            ["contracts"]=[..contract.Select((id,i)=>Row(new{id,kind="future",delivery_from="2040-02-01",delivery_to="2040-03-01",expiry_at="2040-01-20T00:00:00Z",futures_series_code="synthetic_"+i}))],
            ["curves"]=[Row(new{code="future",quote_code="price",location_code="hub",profile_code="uniform",settlement_target_code="target",rule="direct",direct_role="daily_settlement",direct_source_code="synthetic"})],
            ["curve_members"]=[..contract.Select((id,i)=>Row(new{curve_code="future",contract_id=id,ordinal=i}))],
            ["series"]=[..series.Select((id,i)=>Row(new{id,contract_id=contract[i],quote_code="price",value_specification_code=(string?)null}))],
            ["curve_inputs"]=[],["constituent_mappings"]=[],["rate_curves"]=[],["rate_curve_points"]=[],["revision_periods"]=[]
        };
        Dictionary<string,ImmutableArray<JsonElement>> references=new()
        {
            ["quantity_specifications"]=[Row(new{code="quantity",commodity_code="gas",basis_code="energy",unit_code="mwh",dimension_code="energy"})],
            ["quote_specifications"]=[Row(new{code="price",kind="outright",currency_code="usd",quantity_code="quantity",multiplier="1",trading_tick="0.001",clearing_increment="0.001",minimum="0",maximum="1000"})],
            ["settlement_targets"]=[Row(new{code="target",kind="future_series",index_a_code=(string?)null,index_b_code=(string?)null})],
            ["futures_series"]=[..Enumerable.Range(0,count).Select(i=>Row(new{code="synthetic_"+i,product_code="product",delivery_from="2040-02-01",delivery_to="2040-03-01"}))],
            ["futures_products"]=[Row(new{code="product",commodity_code="gas",quote_currency_code="usd",quote_multiplier="1",outright_tick_size="0.001",location_code="hub",quote_unit_code="mwh",lot_unit_code="mwh",contract_size="40",lot_basis="fixed_total",settlement_method="cash"})],
            ["futures_milestones"]=[..Enumerable.Range(0,count).SelectMany(i=>new[]{
                Row(new{series_code="synthetic_"+i,milestone="first_trading",value_state="known",event_at="2040-01-01T00:00:00Z"}),
                Row(new{series_code="synthetic_"+i,milestone="last_trading",value_state="known",event_at="2040-01-20T00:00:00Z"})})],
            ["futures_product_terms"]=[Row(new{product_code="product",profile_code="uniform",index_code=(string?)null})],
            ["futures_lot_resolutions"]=[],["futures_basis_settlements"]=[],["value_specifications"]=[]
        };
        ImmutableArray<JsonElement> observations=[..series.Select((id,i)=>Row(new{id=Guid.NewGuid(),series_id=id,source_code="synthetic",role="daily_settlement",publication_state="final",observed_at="2040-01-09T00:00:00Z",value="100."+i.ToString("D3",CultureInfo.InvariantCulture),corrects_id=(Guid?)null}))];
        var frame=new InputFrame(Guid.NewGuid(),"Synthetic selected futures",at,[..observations.Select(row=>row.Id("id"))],
            ImmutableDictionary<string,ImmutableArray<Guid>>.Empty.Add("future",[..contract]));
        return(new("local-synthetic-preview",cat,rev,rcat,rrev,Guid.NewGuid(),Guid.NewGuid(),[],null),definitions,references,observations,frame);
    }
}
