using OpenEtrm.Api;
using OpenEtrm.MarketData;

internal static class SideEntryAndReadChecks
{
    internal static void Run()
    {
        var catalog=Guid.NewGuid();var instrument=Guid.NewGuid();var selectedCut=Guid.NewGuid();var at=DateTimeOffset.Parse("2032-01-15T16:00:00Z");var published=false;
        var projected=OperatingSideReadProjection.Run(()=>{
            AsyncReadVisibility.ReferenceVersion(catalog,instrument);AsyncReadVisibility.Instrument(catalog,instrument,selectedCut,at,2);
            return Task.FromResult("retained terms");
        },proof=>{
            if(proof.Instruments.Single() is not{Catalog:var actualCatalog,Id:var actualInstrument,Context:var actualCut,AsOf:var actualAt,Members:2}||
                actualCatalog!=catalog||actualInstrument!=instrument||actualCut!=selectedCut||actualAt!=at||proof.Versions.Single()!=(catalog,instrument))
                throw new Exception("The selected operating read must publish its exact touched source/program closure under the original cut.");
            published=true;return Task.CompletedTask;
        }).GetAwaiter().GetResult();
        if(!published||projected!="retained terms")throw new Exception("The selected operating projection must collect and require fresh source/program visibility before publishing readable terms.");
        var frame=Guid.NewGuid();var trade=Guid.NewGuid();var binding=Guid.NewGuid();var context=new FuturesReadRequest(frame,TradingBlotter.Convention,"retained",Guid.NewGuid());
        var request=new StructuredPowerTradeReadRequest(frame,trade,context,binding,2);
        var selected=request.Selection();
        if(!request.Selected||selected.TradeId!=trade||selected.BindingId!=binding||selected.Revision!=2||selected.InstrumentType!=OperatingPositions.Type||
            new StructuredPowerTradeReadRequest(frame,trade).Selected)
            throw new Exception("An exact operating Side read must carry the selected context and native trade/binding/revision independently of legacy explicit-current reads.");
        foreach(var invalid in new[]{request with{SnapshotId=Guid.NewGuid()},request with{Context=null},request with{BindingId=null},request with{Revision=null},
            request with{TradeId=Guid.Empty},request with{Revision=0},request with{Context=context with{Convention="other"}}})
        {
            try{invalid.Selection();}catch(MarketDataException error)when(error.Code=="position_request"){continue;}
            throw new Exception("A conflicting snapshot/context or incomplete exact operating target cannot silently fall back to current selection.");
        }
        foreach(var layout in EntrySideFieldGroups.Operating().Values.Append(EntrySideFieldGroups.Rec()))
        {
            if(layout.Fields.IsDefaultOrEmpty||layout.Groups.IsDefaultOrEmpty||layout.Groups.SelectMany(group=>group.Fields).Distinct().Count()!=layout.Fields.Length||
                !layout.Groups.SelectMany(group=>group.Fields).Order().SequenceEqual(layout.Fields.Order())||!layout.Groups.Any(group=>group.Kind=="side_terms"))
                throw new Exception("Current operating and certificate entry must explicitly partition every active form field into agreement or independent Side terms.");
        }
        var operating=EntrySideFieldGroups.Operating();
        if(operating.Count!=3||operating["solar"].Fields.Contains("fuelPrice")||operating["thermal"].Fields.Contains("chargePrice")||
            !operating["battery"].Fields.Contains("chargePrice")||!operating["thermal"].Fields.Contains("fuelPrice"))
            throw new Exception("The backend owns each selected operating kind's exact active Side fields without inert fuel/charging terms or a client condition law.");
        var failures=new List<Exception>();
        foreach(var check in new Action[]{()=>UnsupportedValuation(request),EmptySelectedScope})try{check();}catch(Exception error){failures.Add(error);}
        if(failures.Count>0)throw new AggregateException("Exact operating read boundaries failed.",failures);
    }
    static void UnsupportedValuation(StructuredPowerTradeReadRequest selected)
    {
        new StructuredPowerTradeReadRequest(selected.SnapshotId,selected.TradeId).RequireCurrentValuation();
        try{selected.RequireCurrentValuation();}
        catch(MarketDataException error)when(error.Code=="position_request"){return;}
        throw new Exception("The legacy valuation operation must refuse selected context/target fields rather than silently recapture current knowledge.");
    }
    static void EmptySelectedScope()
    {
        try{StructuredPowerBookingStore.RequireSelectedPosition([]);}
        catch(MarketDataException error)when(error.Code=="position_unavailable"){return;}
        throw new Exception("A selected operating contract outside visible book scope must return its structured unavailable refusal.");
    }
}
