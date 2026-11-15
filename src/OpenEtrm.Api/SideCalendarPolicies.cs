using System.Text.Json.Serialization;
using System.Text.Json;
using System.Collections.Immutable;
using Npgsql;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record CalendarBindingInput([property:JsonRequired]bool Applicable,[property:JsonRequired]ReferenceKey? Calendar);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record SideCalendarPolicyInput([property:JsonRequired]string Implementation,
    [property:JsonRequired]CalendarBindingInput Delivery,[property:JsonRequired]CalendarBindingInput Observation,
    [property:JsonRequired]CalendarBindingInput Payment)
{
    [JsonIgnore]internal SideCalendarPolicy? Retained { get; init; }
}

public sealed record SideCalendarChoice(ReferenceKey Reference,string Code,DateOnly CoverageFrom,DateOnly CoverageTo,
        int WeekendMask,ImmutableArray<CalendarException> Exceptions,string DefinitionDigest,CalendarPublicationProof Publication);

internal static class SideCalendarPolicies
{
    internal static async Task<ImmutableArray<SideCalendarChoice>> Catalog(NpgsqlConnection connection,CancellationToken ct)
    {
        await using var command=ScheduleStore.Command(connection,"SELECT value::text FROM security.list_side_calendars() value");
        await using var reader=await command.ExecuteReaderAsync(ct);
        var choices=ImmutableArray.CreateBuilder<SideCalendarChoice>();
        while(await reader.ReadAsync(ct))
        {
            using var document=JsonDocument.Parse(reader.GetString(0));var row=document.RootElement;
            var key=row.GetProperty("reference");
            var calendar=Read(new(new(key.GetProperty("catalogId").GetGuid(),key.GetProperty("revisionId").GetGuid()),key.Text("code")),row);
            choices.Add(new(calendar.Key,calendar.Key.Code,calendar.From,calendar.To,calendar.WeekendMask,calendar.Exceptions,calendar.Digest,calendar.Publication!));
        }
        return choices.ToImmutable();
    }

    private static CalendarDefinition Read(ReferenceKey reference,JsonElement row)
    {
        var proof=row.GetProperty("publication");
        return new(reference,DateWorkspace.Date(row.Text("coverageFrom")),DateWorkspace.Date(row.Text("coverageTo")),row.GetProperty("weekendMask").GetInt32(),
            [..row.GetProperty("exceptions").EnumerateArray().Select(day=>new CalendarException(DateWorkspace.Date(day.Text("date")),day.GetProperty("open").GetBoolean()))],
            CalendarDefinition.Implementation,new(proof.GetProperty("CatalogId").GetGuid(),proof.GetProperty("EventOrder").GetInt32(),proof.GetProperty("KnownFrom").GetDateTimeOffset()));
    }
    // The narrow exact reader captures a certified publication proof independently
    // of the pricing reference revision. General reference visibility is unchanged.
    internal static Task<PreviewData> Prepare(NpgsqlConnection connection,PreviewData data,IEnumerable<SideCalendarPolicyInput?> policies,CancellationToken ct)
    {
        var references=policies.Where(p=>p is not null&&p.Retained is null).SelectMany(p=>new[]{p!.Delivery,p.Observation,p.Payment})
            .Where(b=>b?.Calendar is not null).Select(b=>b.Calendar!.Value).Distinct().ToArray();
        return PrepareReferences(connection,data,references,ct);
    }
    internal static async Task<PreviewData> PrepareReferences(NpgsqlConnection connection,PreviewData data,IEnumerable<ReferenceKey> references,CancellationToken ct)
    {
        var resolved=data.CapturedCalendars.ToBuilder();
        foreach(var reference in references.Distinct())
        {
            await using var query=ScheduleStore.Command(connection,"SELECT security.read_side_calendar($1,$2,$3)::text",
                reference.Revision.CatalogId,reference.Revision.RevisionId,reference.Code);
            if(await query.ExecuteScalarAsync(ct) is not string text)
                throw new MarketDataException("calendar_reference","An exact selected calendar is unavailable under this operation's authority and historical context.");
            using var document=JsonDocument.Parse(text);
            resolved[reference]=Read(reference,document.RootElement);
        }
        return data.WithCalendars(resolved.ToImmutable());
    }
    internal static IEnumerable<SideCalendarPolicyInput?> Inputs(SwapWriteRequest input)=>input.Scheduled is {} scheduled?
        [scheduled.First?.CalendarPolicy,scheduled.Second?.CalendarPolicy]:[input.Fixed?.CalendarPolicy,input.Floating?.CalendarPolicy,input.FirstFloating?.CalendarPolicy];
    internal static SideCalendarPolicy Resolve(PreviewData data,SideCalendarPolicyInput? input)
    {
        if(input is null)throw new MarketDataException("side_calendar_policy","Select explicit versioned calendar bindings for this Side.");
        if(input.Retained is {} retained){RequireInput(input,retained);return retained;}
        CalendarBinding Binding(CalendarBindingInput value)
        {
            if(value is null||value.Applicable!=(value.Calendar is not null))
                throw new MarketDataException("side_calendar_policy","Select one exact calendar for each applicable purpose; mark every other purpose not applicable.");
            return value.Calendar is {} key?CalendarBinding.Owned(CalendarDefinitions.From(data,key)):CalendarBinding.NotApplicable();
        }
        return new(Binding(input.Delivery),Binding(input.Observation),Binding(input.Payment),input.Implementation);
    }
    private static void RequireInput(SideCalendarPolicyInput input,SideCalendarPolicy retained)
    {
        bool Matches(CalendarBindingInput supplied,CalendarBinding original)=>supplied is not null&&supplied.Applicable==original.Applicable&&supplied.Calendar==original.Calendar?.Key;
        if(input.Implementation!=SideCalendarPolicy.Implementation||!Matches(input.Delivery,retained.Delivery)||
            !Matches(input.Observation,retained.Observation)||!Matches(input.Payment,retained.Payment))
            throw new MarketDataException("side_calendar_conflict","Authoring terms must agree with the exact retained Side calendar policy.");
    }
    // Call only with an identity supplied by a verified, authorized retained
    // program/publication. Reconstruction never selects another publication proof.
    internal static SideCalendarPolicyInput FromRetained(string economicIdentity,SideCalendarPolicyInput? authored=null)
    {
        try
        {
            using var document=JsonDocument.Parse(economicIdentity);var saved=document.RootElement.GetProperty("CalendarPolicy");
            CalendarBinding Read(string purpose)
            {
                var binding=saved.GetProperty(purpose);
                if(!binding.GetProperty("Applicable").GetBoolean())return CalendarBinding.NotApplicable();
                var definition=binding.GetProperty("Calendar");var key=definition.GetProperty("Key");
                if(key.GetArrayLength()!=3||key[0].GetString()!="reference"||key[1].GetArrayLength()!=3||key[1][0].GetString()!="reference_revision")throw Invalid();
                var proof=binding.GetProperty("Publication");
                var calendar=new CalendarDefinition(new(new(key[1][1].GetGuid(),key[1][2].GetGuid()),key[2].GetString()!),
                    DateWorkspace.Date(definition.Text("From")),DateWorkspace.Date(definition.Text("To")),definition.GetProperty("WeekendMask").GetInt32(),
                    [..definition.GetProperty("Exceptions").EnumerateArray().Select(e=>new CalendarException(DateWorkspace.Date(e.Text("Date")),e.GetProperty("Open").GetBoolean()))],
                    definition.Text("contract"),new(proof.GetProperty("CatalogId").GetGuid(),proof.GetProperty("EventOrder").GetInt32(),proof.GetProperty("KnownFrom").GetDateTimeOffset()));
                return CalendarBinding.Owned(calendar);
            }
            var retained=new SideCalendarPolicy(Read("Delivery"),Read("Observation"),Read("Payment"),saved.Text("contract"));
            if(DefinitionIdentity.For(retained).Canonical!=saved.GetRawText())throw Invalid();
            if(authored is not null)RequireInput(authored,retained);
            CalendarBindingInput Input(CalendarBinding binding)=>new(binding.Applicable,binding.Calendar?.Key);
            return new(SideCalendarPolicy.Implementation,Input(retained.Delivery),Input(retained.Observation),Input(retained.Payment)){Retained=retained};
        }
        catch(Exception error)when(error is JsonException or KeyNotFoundException or InvalidOperationException or FormatException or IndexOutOfRangeException)
        {throw Invalid();}
        static MarketDataException Invalid()=>new("side_calendar_policy","The retained program has no complete, consistent captured calendar policy and publication evidence.");
    }
    internal static PpaTermsInput Retain(PpaTermsInput input,Func<SideSlot,string> identity)
    {
        var members=input.Memberships.Select(member=>
        {
            var captured=identity(new(PpaCompiler.Role(member.Role),member.Ordinal));
            return member with{Side=member.Side with{CalendarPolicy=FromRetained(captured,member.Side.CalendarPolicy)}};
        }).ToArray();
        var clocks=input.Memberships.Select(member=>
        {
            try
            {
                using var document=JsonDocument.Parse(identity(new(PpaCompiler.Role(member.Role),member.Ordinal)));
                var root=document.RootElement;
                var terms=root.TryGetProperty("IntervalDefinition",out var interval)?interval:root.GetProperty("Terms");
                var schedule=terms.GetProperty("Schedule");
                return OpenEtrm.MarketData.Power.PowerClock.Restore(schedule.Text("ClockRules"),schedule.Text("ClockFingerprint"));
            }
            catch(Exception error)when(error is JsonException or KeyNotFoundException or InvalidOperationException or FormatException)
            {throw new MarketDataException("clock_rule","Every retained instrument member requires complete captured clock evidence.");}
        }).ToArray();
        if(clocks.Length==0||clocks.Any(clock=>clock.Rules!=clocks[0].Rules))
            throw new MarketDataException("clock_rule","Every retained instrument member must agree on its captured delivery clock.");
        return input with{Memberships=members,RetainedClock=clocks[0]};
    }
    internal static SwapWriteRequest Retain(SwapWriteRequest input,Func<int,string> identity)
    {
        if(input.Scheduled is {} scheduled)return input with{Scheduled=scheduled with
        {
            First=scheduled.First with{CalendarPolicy=FromRetained(identity(0),scheduled.First.CalendarPolicy),RetainedPowerQuantity=ScheduledPowerParameters.FromRetained(identity(0))},
            Second=scheduled.Second with{CalendarPolicy=FromRetained(identity(1),scheduled.Second.CalendarPolicy),RetainedPowerQuantity=ScheduledPowerParameters.FromRetained(identity(1))}
        }};
        return input with
        {
            Fixed=input.Fixed is {} fixedSide?fixedSide with{CalendarPolicy=FromRetained(identity(0),fixedSide.CalendarPolicy)}:null,
            FirstFloating=input.FirstFloating is {} first?first with{CalendarPolicy=FromRetained(identity(0),first.CalendarPolicy)}:null,
            Floating=input.Floating is {} second?second with{CalendarPolicy=FromRetained(identity(1),second.CalendarPolicy)}:null
        };
    }

}
