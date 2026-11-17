using System.Collections.Immutable;
using System.Text.Json.Serialization;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

public sealed record InstrumentSideValue(string Label,string Value,
    [property:JsonIgnore(Condition=JsonIgnoreCondition.WhenWritingNull)]string? Kind=null);
public sealed record InstrumentSideSection(string Label,ImmutableArray<InstrumentSideValue> Values);
public sealed record InstrumentSideMember(int Slot,Guid SideId,string Label,string RoleLabel,string DirectionLabel,ImmutableArray<InstrumentSideSection> OverviewSections);
public sealed record InstrumentSideGroup(Guid InstrumentId,Guid? BindingId,string Label,ImmutableArray<InstrumentSideMember> Sides,
    [property:JsonIgnore(Condition=JsonIgnoreCondition.WhenWritingNull)]string? FieldGroupId=null);
internal sealed record InstrumentSideLabels(int Slot,string Label,string RoleLabel,string DirectionLabel,ImmutableArray<InstrumentSideSection> OverviewSections);

internal static class InstrumentSidePresentation
{
    internal static InstrumentSideGroup Describe(SidedInstrument instrument,Guid? bindingId,string label,ImmutableArray<InstrumentSideLabels> members,string? fieldGroupId=null)
    {
        if(instrument is null)throw Invalid();
        return Define(instrument.Id,instrument.Sides,bindingId,label,members,fieldGroupId);
    }
    internal static InstrumentSideGroup Define(Guid instrumentId,ImmutableArray<SideMembership> memberships,Guid? bindingId,string label,
        ImmutableArray<InstrumentSideLabels> members,string? fieldGroupId=null)
    {
        if(memberships.IsDefaultOrEmpty||memberships.Any(member=>member is null))throw Invalid();
        return DefineSides(instrumentId,[..memberships.Select(member=>member.Side)],bindingId,label,members,fieldGroupId);
    }
    internal static InstrumentSideGroup DefineSides(Guid instrumentId,ImmutableArray<Side> definitions,Guid? bindingId,string label,
        ImmutableArray<InstrumentSideLabels> members,string? fieldGroupId=null)
    {
        static bool Text(string? value)=>!string.IsNullOrWhiteSpace(value);
        if(instrumentId==Guid.Empty||definitions.IsDefaultOrEmpty||definitions.Any(side=>side is null||side.Id==Guid.Empty)||
            bindingId==Guid.Empty||!Text(label)||fieldGroupId is not null&&!Text(fieldGroupId)||members.IsDefaultOrEmpty||
            members.Length!=definitions.Length||members.Select(member=>member.Slot).Distinct().Count()!=members.Length)
            throw Invalid();
        var sides=ImmutableArray.CreateBuilder<InstrumentSideMember>(members.Length);
        foreach(var member in members.OrderBy(member=>member.Slot))
        {
            if(member.Slot<0||member.Slot>=definitions.Length||!Text(member.Label)||!Text(member.RoleLabel)||!Text(member.DirectionLabel)||member.OverviewSections.IsDefaultOrEmpty)
                throw Invalid();
            foreach(var section in member.OverviewSections)
            {
                if(!Text(section.Label)||section.Values.IsDefaultOrEmpty)throw Invalid();
                foreach(var value in section.Values)
                {
                    if(!Text(value.Label)||value.Value is null||value.Kind is not (null or "instant"))throw Invalid();
                    if(value.Kind=="instant")_ = TradingInstant.Parse(value.Value,"instrument_side_presentation");
                }
            }
            var side=definitions[member.Slot];
            sides.Add(new(member.Slot,side.Id,member.Label,member.RoleLabel,member.DirectionLabel,member.OverviewSections));
        }
        return new(instrumentId,bindingId,label,sides.ToImmutable(),fieldGroupId);
    }
    internal static void RequireMappings(TicketDescription description,ImmutableArray<InstrumentSideGroup> groups)
    {
        TicketDescriptions.Validate(description);
        var fields=description.FieldGroups is {} declared?declared.Select(group=>group.Id).ToHashSet(StringComparer.Ordinal):new HashSet<string>(StringComparer.Ordinal);
        if(groups.IsDefault||groups.Any(group=>group is null||group.FieldGroupId is {} id&&!fields.Contains(id)))throw Invalid();
    }
    static MarketDataException Invalid()=>new("instrument_side_presentation","Describe every actual Side membership and its explicit role, company direction and terms.");
}
