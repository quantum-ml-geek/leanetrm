using System.Collections.Immutable;
using OpenEtrm.MarketData;

namespace OpenEtrm.Api;

public sealed record EntryFieldLayout(ImmutableArray<string> Fields,ImmutableArray<TicketFieldGroup> Groups);

internal static class EntrySideFieldGroups
{
    static TicketFieldGroup Group(string id,string label,string kind,params string[] fields)=>new(id,label,kind,[..fields]);
    static EntryFieldLayout Layout(params TicketFieldGroup[] groups)
    {
        ImmutableArray<TicketFieldGroup> partition=[..groups];ImmutableArray<string> fields=[..groups.SelectMany(group=>group.Fields)];
        TicketDescriptions.RequireFieldGroups(fields,partition,message=>throw new MarketDataException("ticket_description",message));
        return new(fields,partition);
    }
    internal static EntryFieldLayout Rec()=>Layout(
        Group("agreement","Agreement and parties","agreement","calendar","discount","book","entity","party","tradeDate","convention"),
        Group("delivery","Certificate delivery Side terms","side_terms","assignment","deliveryFrom","deliveryTo","quantity","physical"),
        Group("consideration","Consideration Side terms","side_terms","consideration","mode","quote","price","contract","payment","days"));
    internal static ImmutableDictionary<string,EntryFieldLayout> Operating()=>new[]{"battery","thermal","solar"}.ToImmutableDictionary(kind=>kind,_=>Layout(
        Group("valuation","Valuation agreement terms","agreement","right","currency","perspective","measure","discounting"),
        Group("sides","Independent operating Side terms","side_terms","sideDefinitions")),StringComparer.Ordinal);
}
