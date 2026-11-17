using System.Collections.Immutable;
using System.Security.Cryptography;
using System.Text.Json;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;
using OpenEtrm.Shared.Commands;

namespace OpenEtrm.Api;

internal static class PointTraderMarkInputSelection
{
    internal static string Fingerprint(InputFrame frame)
    {
        var parts=RequireFrame(frame);
        // Include ignored/private input fields explicitly. Display names are not
        // input provenance; dictionary enumeration and set order are not either.
        var content=new
        {
            policy="point_trader_mark_original_inputs_v1",frame.Id,frame.At,frame.BusinessDate,frame.ContextId,
            frame.OriginCloseId,frame.OriginInputId,frame.Close,frame.ResolvesLatestCorrection,frame.Source,frame.PpaBundle,
            observations=frame.ObservationIds.Order().ToArray(),frozen=frame.FrozenObservationIds.Order().ToArray(),
            members=Members(frame.CurveContracts),
            sources=parts.OrderBy(pair=>pair.Key).Select(pair=>new
            {
                revision=pair.Key,pair.Value.Source,observations=pair.Value.ObservationIds.Order().ToArray(),
                frozen=pair.Value.FrozenObservationIds.Order().ToArray(),members=Members(pair.Value.CurveContracts),
                roots=pair.Value.RootCurves.Order(StringComparer.Ordinal).ToArray()
            }).ToArray(),
            legacy=frame.SwapMarketSelections?.OrderBy(pair=>pair.Key)
                .Select(pair=>new{revision=pair.Key,observations=pair.Value.Order().ToArray()}).ToArray()
        };
        return Convert.ToHexStringLower(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(content)));
    }

    internal static InputFrame Edit(InputFrame original,Guid operation,CatalogueSource source,string curve,Guid contract,
        Guid observation,ImmutableArray<Guid> selectedPointPins)
    {
        var parts=RequireFrame(original);
        if(operation==Guid.Empty||!ValidSource(source)||string.IsNullOrWhiteSpace(curve)||contract==Guid.Empty||observation==Guid.Empty||
            selectedPointPins.IsDefault||selectedPointPins.Length>1||selectedPointPins.Any(id=>id==Guid.Empty))
            throw Invalid("Select one exact published point and explicitly identify its original selected pin, if any.");
        if(parts.Values.Any(part=>part.Source.DefinitionRevisionId!=source.DefinitionRevisionId&&part.RootCurves.Contains(curve,StringComparer.Ordinal)))
            throw Invalid("Another source already owns the selected root curve.");

        var existing=parts.GetValueOrDefault(source.DefinitionRevisionId);
        if(existing is not null&&existing.Source!=source)
            throw Invalid("The selected definition has different reference coordinates in the original input matrix.");
        if(existing is null&&!selectedPointPins.IsEmpty||existing is not null&&selectedPointPins.Any(id=>!existing.ObservationIds.Contains(id)))
            throw Invalid("The selected point pins do not belong to the original exact source part.");
        if(existing is not null&&selectedPointPins.Any(existing.FrozenObservationIds.Contains))
            throw Invalid("A frozen point cannot become a variable published input.");
        if(parts.Values.Any(part=>part.ObservationIds.Contains(observation))&&!selectedPointPins.Contains(observation))
            throw Invalid("The accepted observation is already selected outside the attested point.");

        var part=existing??new MarketSourceInputs(source,[],[],ImmutableDictionary<string,ImmutableArray<Guid>>.Empty,[]);
        var pins=selectedPointPins.IsEmpty?part.ObservationIds.Add(observation):part.ObservationIds.Replace(selectedPointPins[0],observation);
        var contracts=part.CurveContracts.ToImmutableDictionary(pair=>pair.Key,pair=>pair.Value,StringComparer.Ordinal);
        var members=contracts.GetValueOrDefault(curve,[]);
        var edited=part with
        {
            ObservationIds=pins,
            CurveContracts=contracts.SetItem(curve,members.Contains(contract)?members:members.Add(contract)),
            RootCurves=part.RootCurves.Contains(curve,StringComparer.Ordinal)?part.RootCurves:part.RootCurves.Add(curve)
        };
        var legacy=original.SwapMarketSelections;
        if(legacy?.ContainsKey(source.DefinitionRevisionId)==true)
            legacy=legacy.SetItem(source.DefinitionRevisionId,pins);
        var result=original with
        {
            Id=OperationIdentity.For("point_trader_mark_edited_inputs_v1",operation),Name="Edited market inputs",
            ContextId=null,OriginCloseId=null,OriginInputId=null,Close=null,ResolvesLatestCorrection=false,
            SourceInputs=parts.SetItem(source.DefinitionRevisionId,edited),SwapMarketSelections=legacy
        };
        if(original.Source==source)
            result=result with{ObservationIds=edited.ObservationIds,FrozenObservationIds=edited.FrozenObservationIds,CurveContracts=edited.CurveContracts};
        _=RequireFrame(result);
        return result;
    }

    private static ImmutableDictionary<Guid,MarketSourceInputs> RequireFrame(InputFrame frame)
    {
        if(frame is null||frame.Id==Guid.Empty||!TradingInstant.IsSupported(frame.At)||
            !ValidSource(frame.Source)||frame.SourceInputs is not {} parts||parts.Count is <1 or >256||
            frame.ContextId==Guid.Empty||frame.OriginCloseId==Guid.Empty||frame.OriginInputId==Guid.Empty||
            frame.Close is {} close&&(close.BusinessDate!=frame.BusinessDate||string.IsNullOrWhiteSpace(close.Session)||close.SessionVersion<1||close.ReplacedBy==Guid.Empty)||
            frame.PpaBundle is {} bundle&&!ValidSource(bundle))
            throw Invalid("The original selection requires its exact clock, certificate and complete explicit source matrix.");
        var allPins=new HashSet<Guid>();var roots=new HashSet<string>(StringComparer.Ordinal);
        foreach(var (revision,part) in parts)
        {
            if(part is null||!ValidSource(part.Source)||revision!=part.Source.DefinitionRevisionId||
                !ValidPins(part.ObservationIds)||!ValidPins(part.FrozenObservationIds)||part.FrozenObservationIds.Any(id=>!part.ObservationIds.Contains(id))||
                part.RootCurves.IsDefault||part.RootCurves.Any(string.IsNullOrWhiteSpace)||
                part.RootCurves.Distinct(StringComparer.Ordinal).Count()!=part.RootCurves.Length||!ValidMembers(part.CurveContracts)||
                part.RootCurves.Any(root=>!part.CurveContracts.Keys.Contains(root,StringComparer.Ordinal))||
                part.ObservationIds.Any(id=>!allPins.Add(id))||part.RootCurves.Any(root=>!roots.Add(root)))
                throw Invalid("Every input part requires exact source coordinates, distinct pins, explicit frozen uses, members and unambiguous roots.");
        }
        if(!parts.TryGetValue(frame.Source!.DefinitionRevisionId,out var primary)||primary.Source!=frame.Source||
            !ValidPins(frame.ObservationIds)||!ValidPins(frame.FrozenObservationIds)||!ValidMembers(frame.CurveContracts)||!primary.Matches(frame)||
            !primary.CurveContracts.Keys.ToHashSet(StringComparer.Ordinal).SetEquals(frame.CurveContracts.Keys))
            throw Invalid("The original primary projection differs from its exact source part.");
        if(frame.SwapMarketSelections is {} legacy&&legacy.Any(pair=>!parts.TryGetValue(pair.Key,out var part)||
            !ValidPins(pair.Value)||!pair.Value.ToHashSet().SetEquals(part.ObservationIds)))
            throw Invalid("A legacy pin projection differs from the complete exact source matrix.");
        return parts;
    }

    private static bool ValidSource(CatalogueSource? source)=>source is not null&&source.DefinitionRevisionId!=Guid.Empty&&
        source.ReferenceCatalogId!=Guid.Empty&&source.ReferenceRevisionId!=Guid.Empty;
    private static bool ValidPins(ImmutableArray<Guid> pins)=>!pins.IsDefault&&pins.All(id=>id!=Guid.Empty)&&pins.Distinct().Count()==pins.Length;
    private static bool ValidMembers(ImmutableDictionary<string,ImmutableArray<Guid>>? members)=>members is not null&&
        members.All(pair=>!string.IsNullOrWhiteSpace(pair.Key)&&ValidPins(pair.Value));
    private static object[] Members(ImmutableDictionary<string,ImmutableArray<Guid>> members)=>
        [..members.OrderBy(pair=>pair.Key,StringComparer.Ordinal).Select(pair=>(object)new{curve=pair.Key,contracts=pair.Value})];
    private static MarketDataException Invalid(string message)=>new("point_trader_mark_inputs",message);
}
