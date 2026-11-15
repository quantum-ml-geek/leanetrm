using System.Collections.Immutable;
using System.Text.Json.Serialization;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;
using OpenEtrm.Shared.Temporal;

namespace OpenEtrm.Api;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record SwapObservationQuantityInput(string From,string To,QuantityInput Quantity);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record SwapObservationScheduleInput(string Implementation,
    [property:JsonRequired]ReferenceKey? Calendar,[property:JsonRequired]ImmutableArray<SwapObservationQuantityInput>? Quantities);

public sealed partial class SwapStore
{
    public const string ObservationScheduleImplementation="side_observation_schedule_v1";

    private static FloatingAveraging StoredAveraging(string value)=>value switch
    {
        "monthly_index_price"=>FloatingAveraging.MonthlyIndexPrice,
        "calendar_day_arithmetic"=>FloatingAveraging.CalendarDayArithmetic,
        _=>SwapObservationCompatibility.Parse("daily",value)
    };

    private static (SwapObservationCalendar? Calendar,ImmutableArray<FloatingObservation> Quantities) ObservationTerms(
        PreviewData data,SwapFloatingInput input,FloatingAveraging averaging,SideCalendarPolicy policy)
    {
        var mode=SwapObservationCompatibility.Mode(averaging);
        var required=mode.RequiresObservationCalendar||mode.RequiresQuantityWeights;
        if(required!=(input.ObservationSchedule is not null))
            throw Error("swap_averaging","Supply the explicit observation schedule only for a calendar-based or quantity-weighted convention.");
        if(input.ObservationSchedule is not {} schedule)return(null,[]);
        if(schedule.Implementation!=ObservationScheduleImplementation||
            schedule.Calendar is not null||
            mode.RequiresQuantityWeights!=(schedule.Quantities is not null)||input.FirstFixingAt is not null)
            throw Error("swap_averaging","The observation schedule must match its explicit convention and implementation.");
        var binding=policy.For(CalendarPurpose.Observation);
        var calendar=mode.RequiresObservationCalendar?new SwapObservationCalendar(binding.Key,binding.BusinessDays):null;
        if(schedule.Quantities is not {} entries)return(calendar,[]);
        if(entries.IsDefaultOrEmpty||entries.Length>FloatingSide.MaximumDeliveryDays||entries.Any(row=>row is null||row.Quantity is null))
            throw Error("swap_averaging","Supply one positive typed quantity for every required observation interval.");
        return(calendar,entries.Select(row=>new FloatingObservation(Date(row.From),Date(row.To),
            new Quantity(ExactDecimal.Parse(Required(row.Quantity.Value)),row.Quantity.Specification))).ToImmutableArray());
    }

    private static object? ObservationInspection(ScheduleRowValue payment)
    {
        if(payment.Plan.Averaging is not {} averaging)return null;
        var mode=SwapObservationCompatibility.Mode(averaging);
        return new
        {
            implementation="side_observation_schedule_inspection_v1",mode.ResetFrequency,mode.AveragingMethod,averaging=averaging.ToString(),
            denominator=payment.ObservationWeightTotal.ToString(),deliveryFrom=Date(payment.Plan.DeliveryFrom),deliveryTo=Date(payment.Plan.DeliveryTo),
            mappingRule=payment.Plan.Applications[0].MappingRule,calendar=payment.Plan.Calendar?.Key,
            observations=payment.Resets.Select((reset,n)=>new
            {
                ordinal=n,from=Date(reset.Price.Term.ContractObservation?.From??reset.Price.Term.Lookup!.Contract.DeliveryFrom),to=Date(reset.Price.Term.ContractObservation?.To??reset.Price.Term.Lookup!.Contract.DeliveryTo),
                isGuard=(reset.Price.Term.ContractObservation?.From??reset.Price.Term.Lookup!.Contract.DeliveryFrom)<payment.Plan.DeliveryFrom||(reset.Price.Term.ContractObservation?.To??reset.Price.Term.Lookup!.Contract.DeliveryTo)>payment.Plan.DeliveryTo,
                averagingQuantity=reset.Price.Term.Lookup?.AveragingQuantity,weight=reset.Price.Term.Weight.ToString(),
                price=ExactPrice(reset.Price.ExactPrice),exactPrice=new{reset.Price.ExactPrice.Numerator,reset.Price.ExactPrice.Denominator},
                cashContribution=Exact(reset.CashContribution),fixingState=reset.Price.State.ToString(),
                expectedPublication=reset.Price.Term.Lookup?.Fixing?.FixingAt,fixing=reset.Price.Term.Lookup?.Fixing,lookup=reset.Price.Term.Lookup,contractObservation=reset.Price.Term.ContractObservation,lineage=reset.Price.Lineage
            }).ToArray(),
            applications=payment.Applications.Select(value=>new
            {
                paymentOrdinal=value.Application.Payment.Ordinal,targetFrom=Date(value.Application.TargetFrom),targetTo=Date(value.Application.TargetTo),
                observationOrdinal=value.Application.PriceOrdinal,weight=value.Application.Weight.ToString(),value.Application.MappingRule,
                price=ExactPrice(value.Price.ExactPrice),exactPrice=new{value.Price.ExactPrice.Numerator,value.Price.ExactPrice.Denominator},
                cashContribution=Exact(value.CashContribution),fixingState=value.Price.State.ToString(),
                expectedPublication=value.Price.Term.Lookup?.Fixing?.FixingAt,fixing=value.Price.Term.Lookup?.Fixing,lookup=value.Price.Term.Lookup,contractObservation=value.Price.Term.ContractObservation,lineage=value.Price.Lineage
            }).ToArray()
        };
    }

}
