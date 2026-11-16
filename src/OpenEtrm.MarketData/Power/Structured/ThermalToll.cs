using System.Collections.Immutable;

namespace OpenEtrm.MarketData.Power.Structured;

public enum ThermalCommitment { Offline=1, Online }
public enum ThermalTerminalPolicy { RequireMinimumTimesSatisfied=1 }

// All fuel quantities use the selected fuel-energy specification. The per-hour
// quantity is a rate with an explicit elapsed-hour integration convention.
public sealed record ThermalFuelTerms(QuantityFactor IncrementalHeatRate,Quantity NoLoadFuelPerHour,Quantity StartupFuel);

public sealed record ThermalFacilityParameters(AssetVersionKey Resource,DateTimeOffset EffectiveTo,
    ReferenceKey Clock,PowerClock OperatingClock,int IntervalMinutes,
    QuantitySpecification Power,QuantitySpecification Energy,QuantitySpecification Fuel,
    Quantity MinimumOutput,Quantity MaximumOutput,ExactDecimal RampUpMwPerHour,ExactDecimal RampDownMwPerHour,
    Quantity StartupMaximumOutput,Quantity ShutdownMaximumOutput,TimeSpan MinimumUpTime,TimeSpan MinimumDownTime,
    TimeSpan StartupLeadTime,int MaximumStarts,ThermalFuelTerms ConsumptionFuel,string Implementation);

public sealed record ThermalTollTerms(AssetVersionKey Resource,DateTimeOffset EffectiveTo,
    ReferenceKey Clock,PowerClock OperatingClock,int IntervalMinutes,
    QuantitySpecification Power,QuantitySpecification Energy,QuantitySpecification Fuel,
    Quantity MinimumOutput,Quantity MaximumOutput,ExactDecimal RampUpMwPerHour,ExactDecimal RampDownMwPerHour,
    Quantity StartupMaximumOutput,Quantity ShutdownMaximumOutput,TimeSpan MinimumUpTime,TimeSpan MinimumDownTime,
    TimeSpan StartupLeadTime,int MaximumStarts,ThermalFuelTerms GuaranteedFuel,ThermalFuelTerms ConsumptionFuel,
    ThermalTerminalPolicy TerminalPolicy,string Implementation,string NumericalPolicy)
{
    public ThermalTollTerms(ThermalFacilityParameters facility,ThermalFuelTerms guaranteedFuel,
        ThermalTerminalPolicy terminalPolicy,string numericalPolicy):this(facility.Resource,facility.EffectiveTo,
        facility.Clock,facility.OperatingClock,facility.IntervalMinutes,facility.Power,facility.Energy,facility.Fuel,
        facility.MinimumOutput,facility.MaximumOutput,facility.RampUpMwPerHour,facility.RampDownMwPerHour,
        facility.StartupMaximumOutput,facility.ShutdownMaximumOutput,facility.MinimumUpTime,facility.MinimumDownTime,
        facility.StartupLeadTime,facility.MaximumStarts,guaranteedFuel,facility.ConsumptionFuel,terminalPolicy,
        facility.Implementation,numericalPolicy){}

    public ThermalFacilityParameters Facility=>new(Resource,EffectiveTo,Clock,OperatingClock,IntervalMinutes,
        Power,Energy,Fuel,MinimumOutput,MaximumOutput,RampUpMwPerHour,RampDownMwPerHour,StartupMaximumOutput,
        ShutdownMaximumOutput,MinimumUpTime,MinimumDownTime,StartupLeadTime,MaximumStarts,ConsumptionFuel,Implementation);
}

public sealed record ThermalInitialState(DateTimeOffset At,ThermalCommitment Commitment,TimeSpan ElapsedInState,
    Quantity PreviousOutput,int StartsUsed);

public sealed record ThermalDispatchInterval(DeliveryInterval Interval,ThermalCommitment Commitment,
    Quantity Output,Quantity Available,DateTimeOffset? StartupInstructionAt);

public sealed record ThermalOperatingRow(DeliveryInterval Interval,ThermalCommitment Commitment,
    Quantity Output,Quantity Available,bool Started,bool Stopped,DateTimeOffset? StartupInstructionAt,
    ExactQuantity Energy,ExactQuantity GuaranteedFuel,ExactQuantity ConsumptionFuel,TimeSpan ElapsedInStateAtEnd);

public sealed record ThermalTollResult(ThermalTollTerms Terms,ThermalInitialState InitialState,
    ImmutableArray<ThermalOperatingRow> Rows,ThermalInitialState FinalState,int StartsInPlan,
    ExactQuantity Energy,ExactQuantity GuaranteedFuel,ExactQuantity ConsumptionFuel);

public static class ThermalToll
{
    public const string Implementation="thermal_supplied_interval_plan_v1";
    public const string NumericalPolicy="thermal_exact_elapsed_quantity_v1";
    public const int MaximumIntervals=35_136;



    // This version validates interval-average targets. Ordinary ramp budgets
    // compare consecutive targets over the current interval's elapsed duration;
    // startup/shutdown use their separately declared boundary limits. It does
    // not certify a continuous ramp trajectory or model partially started units.
    public static ThermalTollResult Evaluate(ThermalTollTerms terms,ThermalInitialState initial,
        ImmutableArray<ThermalDispatchInterval> dispatch)
    {
        Validate(terms,initial,dispatch);
        var rows=ImmutableArray.CreateBuilder<ThermalOperatingRow>(dispatch.Length);
        var state=initial.Commitment;
        var stateFrom=initial.At-initial.ElapsedInState;
        var previous=initial.PreviousOutput;
        var starts=initial.StartsUsed;
        var energy=Zero(terms.Energy.Key);
        var guaranteed=Zero(terms.Fuel.Key);
        var consumed=Zero(terms.Fuel.Key);
        foreach(var input in dispatch)
        {
            var online=input.Commitment==ThermalCommitment.Online;
            var started=online&&state==ThermalCommitment.Offline;
            var stopped=!online&&state==ThermalCommitment.Online;
            var elapsed=input.Interval.End-input.Interval.Start;
            if(started)
            {
                if(input.Interval.Start-stateFrom<terms.MinimumDownTime)
                    throw Error("thermal_minimum_down","A start cannot interrupt the retained minimum downtime.");
                if(input.StartupInstructionAt is not {} issued||!Utc(issued)||issued>input.Interval.Start||
                    input.Interval.Start-issued<terms.StartupLeadTime)
                    throw Error("thermal_start_notice","Every start requires an explicit UTC instruction satisfying its lead time.");
                if(issued<stateFrom||issued-stateFrom<terms.MinimumDownTime)
                    throw Error("thermal_minimum_down","The startup instruction must follow the retained minimum downtime.");
                if(starts>=terms.MaximumStarts)
                    throw Error("thermal_start_limit","This plan exceeds the start limit after retained earlier starts.");
                if(input.Output.Amount.CompareTo(terms.StartupMaximumOutput.Amount)>0)
                    throw Error("thermal_start","The online target exceeds the declared startup output limit.");
                starts++;
            }
            else if(input.StartupInstructionAt is not null)
                throw Error("thermal_start_notice","A startup instruction is permitted only on a boundary start.");
            if(stopped)
            {
                if(input.Interval.Start-stateFrom<terms.MinimumUpTime)
                    throw Error("thermal_minimum_up","A shutdown cannot interrupt the retained minimum uptime.");
                if(previous.Amount.CompareTo(terms.ShutdownMaximumOutput.Amount)>0)
                    throw Error("thermal_stop","The previous online target exceeds the declared shutdown output limit.");
            }
            if(started||stopped)stateFrom=input.Interval.Start;
            if(online)
            {
                if(input.Output.Amount.CompareTo(terms.MinimumOutput.Amount)<0||input.Output.Amount.CompareTo(input.Available.Amount)>0)
                    throw Error("thermal_output","Every online target must satisfy minimum output and explicitly available capacity.");
                if(!started)
                {
                    var change=input.Output.Amount.ScaledValue-previous.Amount.ScaledValue;
                    var limit=change.Sign>=0?terms.RampUpMwPerHour:terms.RampDownMwPerHour;
                    if(System.Numerics.BigInteger.Abs(change)*TimeSpan.TicksPerHour>limit.ScaledValue*elapsed.Ticks)
                        throw Error("thermal_ramp","The target change exceeds its declared elapsed-time ramp budget.");
                }
            }
            else if(input.Output.Amount!=default)
                throw Error("thermal_output","An offline interval cannot have nonzero output.");

            var intervalEnergy=ExactQuantity.FromQuantity(new(input.Output.Amount,terms.Energy.Key))
                .ScaleFraction(elapsed.Ticks,TimeSpan.TicksPerHour);
            var intervalGuaranteed=Fuel(terms.GuaranteedFuel,intervalEnergy,elapsed,online,started,terms.Fuel.Key);
            var intervalConsumed=Fuel(terms.ConsumptionFuel,intervalEnergy,elapsed,online,started,terms.Fuel.Key);
            rows.Add(new(input.Interval,input.Commitment,input.Output,input.Available,started,stopped,input.StartupInstructionAt,
                intervalEnergy,intervalGuaranteed,intervalConsumed,input.Interval.End-stateFrom));
            energy=energy.Add(intervalEnergy);
            guaranteed=guaranteed.Add(intervalGuaranteed);
            consumed=consumed.Add(intervalConsumed);
            state=input.Commitment;
            previous=input.Output;
        }
        var end=dispatch[^1].Interval.End;
        var minimum=state==ThermalCommitment.Online?terms.MinimumUpTime:terms.MinimumDownTime;
        if(end-stateFrom<minimum)
            throw Error("thermal_terminal","The horizon leaves minimum-time obligations outstanding under the selected strict terminal policy.");
        return new(terms,initial,rows.MoveToImmutable(),new(end,state,end-stateFrom,previous,starts),starts-initial.StartsUsed,
            energy,guaranteed,consumed);
    }

    // Consumption is calculated from supplied operating coefficients. It is not
    // a metered actual or a finality assertion; evidence selection belongs to the
    // authorized consumer that supplies this immutable plan.
    private static ExactQuantity Fuel(ThermalFuelTerms model,ExactQuantity energy,TimeSpan elapsed,
        bool online,bool started,ReferenceKey fuel)
    {
        if(!online)return Zero(fuel);
        var incremental=new ExactQuantity(energy.NumeratorValue*model.IncrementalHeatRate.Value.ScaledValue,
            energy.DenominatorValue*ExactDecimal.WorkingScale,fuel);
        var noLoad=ExactQuantity.FromQuantity(model.NoLoadFuelPerHour).ScaleFraction(elapsed.Ticks,TimeSpan.TicksPerHour);
        return incremental.Add(noLoad).Add(started?ExactQuantity.FromQuantity(model.StartupFuel):Zero(fuel));
    }

    public static void ValidateTerms(ThermalTollTerms terms)
    {
        if(terms is null)throw Error("thermal_definition","Supply explicit thermal terms.");
        ValidateResource(terms.Facility);
        if(terms.NumericalPolicy!=NumericalPolicy)
            throw Error("thermal_implementation","Select the supported exact thermal numerical policy.");
        if(terms.TerminalPolicy!=ThermalTerminalPolicy.RequireMinimumTimesSatisfied)
            throw Error("thermal_policy","Select the explicit minimum-times-satisfied terminal policy.");
        FuelTerms(terms.GuaranteedFuel,terms.Facility);
    }

    public static void ValidateResource(ThermalFacilityParameters resource)
    {
        if(resource is null)throw Error("thermal_definition","Supply explicit thermal facility parameters.");
        if(resource.Implementation!=Implementation)
            throw Error("thermal_implementation","Select the supported thermal implementation.");
        if(resource.Power is null||resource.Energy is null||resource.Fuel is null||resource.OperatingClock is null||resource.Resource is null||resource.Resource.Asset is null)
            throw Error("thermal_reference","Supply exact resource, clock and quantity definitions.");
        var reference=resource.Power.Key.Revision;
        if(reference.CatalogId==Guid.Empty||reference.RevisionId==Guid.Empty||
            resource.Resource.Asset.Revision.CatalogId==Guid.Empty||resource.Resource.Asset.Revision.RevisionId==Guid.Empty||
            string.IsNullOrWhiteSpace(resource.Resource.Asset.Code)||!Utc(resource.Resource.From)||!Utc(resource.EffectiveTo)||
            resource.Resource.From>=resource.EffectiveTo||!Reference(resource.Clock,reference)||
            new[]{resource.Power,resource.Energy,resource.Fuel}.Any(spec=>new[]{spec.Key,spec.Commodity,spec.MeasurementBasis,spec.Unit,spec.Dimension}.Any(key=>!Reference(key,reference))))
            throw Error("thermal_reference","Every resource, clock and quantity relationship must retain an exact valid version.");
        if(resource.Power.Unit.Code!="megawatt"||resource.Power.Dimension.Code!="power"||
            resource.Energy.Unit.Code!="megawatt_hour"||resource.Energy.Dimension.Code!="energy"||resource.Fuel.Dimension.Code!="energy"||
            resource.Power.Commodity!=resource.Energy.Commodity||
            resource.Fuel.Commodity==resource.Energy.Commodity||resource.Fuel.Key==resource.Energy.Key)
            throw Error("thermal_units","This version requires explicit compatible MW/MWh and a distinct selected fuel-energy commodity.");
        foreach(var value in new[]{resource.MinimumOutput,resource.MaximumOutput,resource.StartupMaximumOutput,resource.ShutdownMaximumOutput})
            Power(value,resource.Power.Key,"thermal_definition");
        if(resource.MaximumOutput.Amount.CompareTo(default)<=0||resource.MinimumOutput.Amount.CompareTo(resource.MaximumOutput.Amount)>0||
            resource.StartupMaximumOutput.Amount.CompareTo(resource.MaximumOutput.Amount)>0||resource.ShutdownMaximumOutput.Amount.CompareTo(resource.MaximumOutput.Amount)>0||
            resource.RampUpMwPerHour.CompareTo(default)<0||resource.RampDownMwPerHour.CompareTo(default)<0||
            !Duration(resource.MinimumUpTime)||!Duration(resource.MinimumDownTime)||!Duration(resource.StartupLeadTime)||resource.MaximumStarts<0)
            throw Error("thermal_definition","Supply coherent explicit output, ramp, timing and start constraints.");
        FuelTerms(resource.ConsumptionFuel,resource);
        if(resource.IntervalMinutes is not(15 or 60))
            throw Error("thermal_grid","Select a supported native 15- or 60-minute grid.");
    }

    private static void Validate(ThermalTollTerms terms,ThermalInitialState initial,ImmutableArray<ThermalDispatchInterval> dispatch)
    {
        ValidateTerms(terms);
        if(initial is null)throw Error("thermal_definition","Supply an explicit initial operating state.");
        Power(initial.PreviousOutput,terms.Power.Key,"thermal_initial_state");
        if(!Utc(initial.At)||initial.At<terms.Resource.From||initial.At>=terms.EffectiveTo||!Enum.IsDefined(initial.Commitment)||
            !Duration(initial.ElapsedInState)||initial.ElapsedInState>initial.At-DateTimeOffset.MinValue||
            initial.StartsUsed<0||initial.StartsUsed>terms.MaximumStarts||
            initial.PreviousOutput.Amount.CompareTo(terms.MaximumOutput.Amount)>0||
            initial.Commitment==ThermalCommitment.Offline&&initial.PreviousOutput.Amount!=default||
            initial.Commitment==ThermalCommitment.Online&&initial.PreviousOutput.Amount.CompareTo(terms.MinimumOutput.Amount)<0)
            throw Error("thermal_initial_state","Retain an explicit valid boundary state, elapsed time, previous output and used starts.");
        if(dispatch.IsDefaultOrEmpty||dispatch.Length>MaximumIntervals)
            throw Error("thermal_grid","Supply a bounded nonempty native 15- or 60-minute grid.");

        var days=new Dictionary<DateOnly,Dictionary<DateTimeOffset,DeliveryInterval>>();
        var previous=initial.At;
        foreach(var row in dispatch)
        {
            if(row is null||row.Interval is null||!Utc(row.Interval.Start)||!Utc(row.Interval.End)||row.Interval.Start!=previous||
                row.Interval.End-row.Interval.Start!=TimeSpan.FromMinutes(terms.IntervalMinutes)||row.Interval.End>terms.EffectiveTo||
                row.Interval.OperatingDate.Year>=9999||!Enum.IsDefined(row.Commitment))
                throw Error("thermal_grid","Every supplied interval must be ordered, contiguous, native and within the selected resource version.");
            if(!days.TryGetValue(row.Interval.OperatingDate,out var native))
            {
                native=PowerHours.Compile(row.Interval.OperatingDate,row.Interval.OperatingDate.AddDays(1),terms.OperatingClock,
                    TimeOfUse.All(terms.IntervalMinutes),[],terms.IntervalMinutes).ToDictionary(hour=>hour.Start,hour=>hour.Delivery);
                days.Add(row.Interval.OperatingDate,native);
            }
            if(!native.TryGetValue(row.Interval.Start,out var expected)||expected!=row.Interval)
                throw Error("thermal_grid","Each interval must retain the exact selected clock's native boundaries and repeated-hour labels.");
            Power(row.Output,terms.Power.Key,"thermal_output");Power(row.Available,terms.Power.Key,"thermal_output");
            if(row.Available.Amount.CompareTo(terms.MaximumOutput.Amount)>0)
                throw Error("thermal_output","Declared availability cannot exceed the selected resource's maximum output.");
            previous=row.Interval.End;
        }
    }

    private static void FuelTerms(ThermalFuelTerms model,ThermalFacilityParameters terms)
    {
        if(model is null||model.IncrementalHeatRate is null||model.NoLoadFuelPerHour is null||model.StartupFuel is null||
            model.IncrementalHeatRate.NumeratorQuantity!=terms.Fuel.Key||model.IncrementalHeatRate.DenominatorQuantity!=terms.Energy.Key||
            model.NoLoadFuelPerHour.Specification!=terms.Fuel.Key||model.StartupFuel.Specification!=terms.Fuel.Key||
            model.NoLoadFuelPerHour.Amount.CompareTo(default)<0||model.StartupFuel.Amount.CompareTo(default)<0)
            throw Error("thermal_fuel","Fuel coefficients require a selected fuel-per-MWh factor and explicit nonnegative same-unit no-load/start quantities.");
    }

    private static void Power(Quantity value,ReferenceKey specification,string code)
    {
        if(value is null||value.Specification!=specification)
            throw Error("thermal_units","Power quantities must use the exact selected MW specification.");
        if(value.Amount.CompareTo(default)<0)throw Error(code,"Power quantities must be explicitly nonnegative.");
    }
    private static bool Reference(ReferenceKey key,ReferenceRevision revision)=>key.Revision==revision&&!string.IsNullOrWhiteSpace(key.Code);
    private static bool Utc(DateTimeOffset at)=>at.Offset==TimeSpan.Zero&&at.Ticks%10==0&&at.Year<9999;
    private static bool Duration(TimeSpan value)=>value>=TimeSpan.Zero&&value.Ticks%10==0;
    private static ExactQuantity Zero(ReferenceKey unit)=>ExactQuantity.FromQuantity(new(default,unit));
    private static MarketDataException Error(string code,string message)=>new(code,message);
}
