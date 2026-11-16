using System.Collections.Immutable;
using OpenEtrm.Api;
using OpenEtrm.MarketData;

internal static class PointTraderMarkInputSelectionChecks
{
    internal static void Run()
    {
        var primary=new CatalogueSource(Id(1),Id(11),Id(12));var target=new CatalogueSource(Id(2),Id(21),Id(22));
        var rates=new CatalogueSource(Id(3),Id(31),Id(32));var native=Id(100);var rate=Id(101);var other=Id(102);
        var primaryPart=new MarketSourceInputs(primary,[native,rate],[rate],Members(("synthetic_primary",Id(201)),("synthetic_rate",Id(202))),["synthetic_primary","synthetic_rate"]);
        var independent=new MarketSourceInputs(rates,[other],[other],Members(("synthetic_independent",Id(203))),["synthetic_independent"]);
        var frame=new InputFrame(Id(300),"Synthetic original inputs",DateTimeOffset.Parse("2020-12-19T23:00:00Z"),new(2020,12,20),
            primaryPart.ObservationIds,primaryPart.CurveContracts,Id(301),primaryPart.FrozenObservationIds)
        {
            Source=primary,SourceInputs=ImmutableDictionary<Guid,MarketSourceInputs>.Empty.Add(primary.DefinitionRevisionId,primaryPart).Add(rates.DefinitionRevisionId,independent),
            OriginCloseId=Id(302),OriginInputId=Id(303),Close=new("synthetic_close",1,new(2020,12,20),null),ResolvesLatestCorrection=true
        };
        var fingerprint=PointTraderMarkInputSelection.Fingerprint(frame);var accepted=Id(400);var operation=Id(401);var contract=Id(204);
        var edited=PointTraderMarkInputSelection.Edit(frame,operation,target,"synthetic_rights",contract,accepted,[]);
        if(edited.Source!=primary||edited.At!=frame.At||edited.BusinessDate!=frame.BusinessDate||edited.ContextId is not null||
            edited.OriginCloseId is not null||edited.OriginInputId is not null||edited.Close is not null||edited.ResolvesLatestCorrection||
            edited.Id==frame.Id||edited.SourceInputs?.Count!=3||!primaryPart.Matches(edited)||!independent.Matches(edited.SourceInputs[rates.DefinitionRevisionId]))
            throw new Exception("First-point insertion must preserve the complete independent input matrix and date while clearing old certification claims.");
        var added=edited.SourceInputs[target.DefinitionRevisionId];
        if(added.Source!=target||!added.ObservationIds.SequenceEqual([accepted])||!added.FrozenObservationIds.IsEmpty||
            !added.CurveContracts["synthetic_rights"].SequenceEqual([contract])||!added.RootCurves.SequenceEqual(["synthetic_rights"]))
            throw new Exception("An absent target source gets only the explicitly published point and member, without invented rate inputs.");
        if(edited.Id!=OpenEtrm.Shared.Commands.OperationIdentity.For("point_trader_mark_edited_inputs_v1",operation))
            throw new Exception("An edited selection must use the retained operation's declared technical identity.");
        if(PointTraderMarkInputSelection.Fingerprint(frame)!=fingerprint||
            PointTraderMarkInputSelection.Edit(frame,operation,target,"synthetic_rights",contract,accepted,[]).Id!=edited.Id)
            throw new Exception("Editing must preserve the original snapshot and give exact recovery one stable selection identity.");
        var old=Id(410);var unrelated=Id(411);var replacement=Id(412);
        var part=new MarketSourceInputs(target,[old,unrelated],[unrelated],Members(("synthetic_rights",contract),("synthetic_other",Id(205))),["synthetic_rights","synthetic_other"]);
        var original=frame with{SourceInputs=frame.SourceInputs!.Add(target.DefinitionRevisionId,part),
            SwapMarketSelections=ImmutableDictionary<Guid,ImmutableArray<Guid>>.Empty.Add(target.DefinitionRevisionId,part.ObservationIds)
                .Add(rates.DefinitionRevisionId,independent.ObservationIds)};
        var corrected=PointTraderMarkInputSelection.Edit(original,Id(413),target,"synthetic_rights",contract,replacement,[old]);
        var changed=corrected.SourceInputs![target.DefinitionRevisionId];
        if(changed.ObservationIds.Contains(old)||!changed.ObservationIds.Contains(replacement)||!changed.ObservationIds.Contains(unrelated)||
            !changed.FrozenObservationIds.SequenceEqual([unrelated])||!changed.CurveContracts["synthetic_other"].SequenceEqual([Id(205)])||
            !corrected.SwapMarketSelections![target.DefinitionRevisionId].ToHashSet().SetEquals(changed.ObservationIds)||
            !corrected.SwapMarketSelections[rates.DefinitionRevisionId].SequenceEqual(independent.ObservationIds))
            throw new Exception("Point replacement uses the original selected pin, independently of a native predecessor, and preserves unrelated frozen inputs.");
        var unchanged=PointTraderMarkInputSelection.Edit(original,Id(416),target,"synthetic_rights",contract,old,[old]);
        if(!unchanged.SourceInputs![target.DefinitionRevisionId].Matches(part)||unchanged.Id==original.Id||unchanged.ContextId is not null)
            throw new Exception("Acknowledging an already selected unfrozen point keeps that exact input while creating only an explicit working selection.");
        Reject(()=>PointTraderMarkInputSelection.Edit(original,Id(414),target,"synthetic_rights",contract,replacement,[old,unrelated]));
        Reject(()=>PointTraderMarkInputSelection.Edit(original,Id(414),target,"synthetic_rights",contract,replacement,[Id(999)]));
        Reject(()=>PointTraderMarkInputSelection.Edit(original,Id(414),target,"synthetic_rights",contract,old,[]));
        Reject(()=>PointTraderMarkInputSelection.Edit(original,Id(414),target,"synthetic_rights",contract,replacement,default));
        Reject(()=>PointTraderMarkInputSelection.Edit(original,Guid.Empty,target,"synthetic_rights",contract,replacement,[old]));
        Reject(()=>PointTraderMarkInputSelection.Edit(original with{SwapMarketSelections=original.SwapMarketSelections!.SetItem(target.DefinitionRevisionId,[unrelated])},
            Id(414),target,"synthetic_rights",contract,replacement,[old]));
        Reject(()=>PointTraderMarkInputSelection.Edit(original with{SourceInputs=original.SourceInputs!.SetItem(target.DefinitionRevisionId,part with{FrozenObservationIds=[old,unrelated]})},
            Id(414),target,"synthetic_rights",contract,replacement,[old]));
        Reject(()=>PointTraderMarkInputSelection.Edit(frame with{SourceInputs=null},Id(414),target,"synthetic_rights",contract,replacement,[]));
        var wrongOwner=target with{ReferenceRevisionId=Id(999)};
        Reject(()=>PointTraderMarkInputSelection.Edit(original,Id(414),wrongOwner,"synthetic_rights",contract,replacement,[old]));
        var conflict=primaryPart with{RootCurves=[..primaryPart.RootCurves,"synthetic_rights"],
            CurveContracts=primaryPart.CurveContracts.Add("synthetic_rights",[Id(206)])};
        Reject(()=>PointTraderMarkInputSelection.Edit(frame with{CurveContracts=conflict.CurveContracts,
            SourceInputs=frame.SourceInputs!.SetItem(primary.DefinitionRevisionId,conflict)},Id(414),target,"synthetic_rights",contract,replacement,[]));
        var missingPrimary=primaryPart with{ObservationIds=[rate]};
        var unpriced=frame with{ObservationIds=[rate],SourceInputs=frame.SourceInputs!.SetItem(primary.DefinitionRevisionId,missingPrimary)};
        var priced=PointTraderMarkInputSelection.Edit(unpriced,Id(415),primary,"synthetic_primary",Id(201),accepted,[]);
        if(!priced.ObservationIds.ToHashSet().SetEquals(new[]{rate,accepted})||!priced.SourceInputs![primary.DefinitionRevisionId].Matches(priced)||
            !priced.FrozenObservationIds.SequenceEqual([rate]))
            throw new Exception("A first primary-source value must update both the root and its exact matrix part, preserving the independent rate pin.");
        if(PointTraderMarkInputSelection.Fingerprint(frame with{Name="Synthetic renamed view"})!=fingerprint||
            PointTraderMarkInputSelection.Fingerprint(frame with{ContextId=Id(999)})==fingerprint)
            throw new Exception("Input provenance distinguishes exact certificates while display-only names do not change a source matrix.");
        Fingerprints(frame,primaryPart,independent);
        Console.WriteLine("PASS published-point input selection: missing first pin/source, exact replacement, independent/frozen preservation, stable replay and conflicting-source refusal");
    }
    static void Fingerprints(InputFrame frame,MarketSourceInputs primary,MarketSourceInputs independent)
    {
        var expected=PointTraderMarkInputSelection.Fingerprint(frame);
        if(expected.Length!=64||expected.Any(c=>!(c is >= '0' and <= '9' or >= 'a' and <= 'f')))
            throw new Exception("An original-input attestation must be a complete lowercase SHA256 fingerprint.");
        void Changed(string field,InputFrame selected)
        {
            if(PointTraderMarkInputSelection.Fingerprint(selected)==expected)
                throw new Exception($"The original-input fingerprint omitted {field}.");
        }
        Changed("snapshot identity",frame with{Id=Id(700)});
        Changed("valuation instant",frame with{At=frame.At.AddTicks(10)});
        Changed("explicit business date",frame with{BusinessDate=frame.BusinessDate.AddDays(1),Close=frame.Close! with{BusinessDate=frame.BusinessDate.AddDays(1)}});
        Changed("origin close",frame with{OriginCloseId=Id(701)});
        Changed("origin input",frame with{OriginInputId=Id(702)});
        Changed("close session",frame with{Close=frame.Close! with{Session="synthetic_other_close"}});
        Changed("close version",frame with{Close=frame.Close! with{SessionVersion=2}});
        Changed("close replacement",frame with{Close=frame.Close! with{ReplacedBy=Id(703)}});
        Changed("correction policy",frame with{ResolvesLatestCorrection=false});
        Changed("legacy source projection",frame with{PpaBundle=independent.Source});
        Changed("legacy selected pins",frame with{SwapMarketSelections=ImmutableDictionary<Guid,ImmutableArray<Guid>>.Empty.Add(independent.Source.DefinitionRevisionId,independent.ObservationIds)});
        Changed("independent frozen use",frame with{SourceInputs=frame.SourceInputs!.SetItem(independent.Source.DefinitionRevisionId,independent with{FrozenObservationIds=[]})});
        Changed("independent roots",frame with{SourceInputs=frame.SourceInputs!.SetItem(independent.Source.DefinitionRevisionId,independent with{RootCurves=[]})});
        Changed("independent reference pins",frame with{SourceInputs=frame.SourceInputs!.SetItem(independent.Source.DefinitionRevisionId,
            independent with{Source=independent.Source with{ReferenceRevisionId=Id(704)}})});
        var extra=primary with{ObservationIds=primary.ObservationIds.Add(Id(705))};
        Changed("primary selected observations",frame with{ObservationIds=extra.ObservationIds,SourceInputs=frame.SourceInputs!.SetItem(primary.Source.DefinitionRevisionId,extra)});
        extra=primary with{FrozenObservationIds=[]};
        Changed("primary frozen use",frame with{FrozenObservationIds=[],SourceInputs=frame.SourceInputs!.SetItem(primary.Source.DefinitionRevisionId,extra)});
        extra=primary with{CurveContracts=primary.CurveContracts.SetItem("synthetic_primary",[Id(201),Id(706)])};
        var ordered=frame with{CurveContracts=extra.CurveContracts,SourceInputs=frame.SourceInputs!.SetItem(primary.Source.DefinitionRevisionId,extra)};
        Changed("ordered member selection",ordered);
        var reversed=extra with{CurveContracts=extra.CurveContracts.SetItem("synthetic_primary",[Id(706),Id(201)])};
        if(PointTraderMarkInputSelection.Fingerprint(ordered)==PointTraderMarkInputSelection.Fingerprint(ordered with
            {CurveContracts=reversed.CurveContracts,SourceInputs=ordered.SourceInputs!.SetItem(primary.Source.DefinitionRevisionId,reversed)}))
            throw new Exception("Ordered contract membership is part of the original input selection.");
        var reordered=primary with{ObservationIds=[..primary.ObservationIds.Reverse()],RootCurves=[..primary.RootCurves.Reverse()],
            CurveContracts=primary.CurveContracts.Reverse().ToImmutableDictionary(pair=>pair.Key,pair=>pair.Value,StringComparer.Ordinal)};
        var same=frame with{ObservationIds=reordered.ObservationIds,CurveContracts=reordered.CurveContracts,
            SourceInputs=ImmutableDictionary<Guid,MarketSourceInputs>.Empty.Add(independent.Source.DefinitionRevisionId,independent).Add(primary.Source.DefinitionRevisionId,reordered)};
        if(PointTraderMarkInputSelection.Fingerprint(same)!=expected)
            throw new Exception("Set ordering and source dictionary enumeration must not change the same complete input attestation.");
        Reject(()=>PointTraderMarkInputSelection.Fingerprint(frame with{SourceInputs=null}));
        Reject(()=>PointTraderMarkInputSelection.Fingerprint(frame with{ObservationIds=[]}));
        Reject(()=>PointTraderMarkInputSelection.Fingerprint(frame with{CurveContracts=ImmutableDictionary.Create<string,ImmutableArray<Guid>>(StringComparer.OrdinalIgnoreCase)
            .Add("SYNTHETIC_PRIMARY",[Id(201)]).Add("synthetic_rate",[Id(202)])}));
        Reject(()=>PointTraderMarkInputSelection.Fingerprint(frame with{SourceInputs=frame.SourceInputs!.SetItem(primary.Source.DefinitionRevisionId,primary with{FrozenObservationIds=[Id(999)]})}));
        Reject(()=>PointTraderMarkInputSelection.Fingerprint(frame with{SwapMarketSelections=ImmutableDictionary<Guid,ImmutableArray<Guid>>.Empty.Add(Id(999),[])}));
    }
    static ImmutableDictionary<string,ImmutableArray<Guid>> Members(params(string Curve,Guid Contract)[] members)=>
        members.ToImmutableDictionary(p=>p.Curve,p=>ImmutableArray.Create(p.Contract),StringComparer.Ordinal);
    static Guid Id(int number)=>Guid.Parse($"00000000-0000-4000-8000-{number:000000000000}");
    static void Reject(Action action)
    {
        try{action();throw new Exception("An unproven point-input edit was accepted.");}
        catch(MarketDataException error)when(error.Code=="point_trader_mark_inputs"){}
    }
}
