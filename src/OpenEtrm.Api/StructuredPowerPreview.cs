using System.Collections.Immutable;
using System.Globalization;
using System.Text.Json;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Power.Structured;

namespace OpenEtrm.Api;

public sealed record StructuredPowerResolvedTerms(StructuredPowerFacilityTerms CanonicalTerms,
    AssetVersionKey Resource,ReferenceKey Location,ReferenceKey Clock,PowerClock OperatingClock,
    QuantitySpecification? Power,QuantitySpecification Energy,QuantitySpecification? Fuel,
    BatteryResource? Battery,BatteryThroughputConstraint? Throughput,
    ThermalFacilityParameters? Thermal,QuantityStage? SolarStage);

// The caller supplies an authorized exact bundle and saved effective bounds.
// Reference codes are resolved solely inside that captured bundle.
public static partial class StructuredPowerPreview
{
    public const string FacilityImplementation="structured_power_facility_v1";
    public const int MaximumPreviewIntervals=1024;

    public static StructuredPowerResolvedTerms ResolveTerms(PreviewData data,StructuredPowerFacilityTerms terms,
        DateTimeOffset effectiveFrom,DateTimeOffset effectiveTo)
    {
        ArgumentNullException.ThrowIfNull(data);
        if(terms is null||terms.Implementation!=FacilityImplementation)throw Error("structured_power_policy","Select a supported explicit facility implementation.");
        if(terms.DefinitionCatalogId!=data.DefinitionRevision.CatalogId||terms.DefinitionRevisionId!=data.DefinitionRevision.RevisionId||
            terms.ReferenceCatalogId!=data.ReferenceRevision.CatalogId||terms.ReferenceRevisionId!=data.ReferenceRevision.RevisionId)
            throw Error("structured_power_pin","The facility must retain the exact authorized market and reference versions.");
        if(!Utc(effectiveFrom)||!Utc(effectiveTo)||effectiveFrom>=effectiveTo)
            throw Error("structured_power_time","Supply distinct ordered UTC effective bounds.");
        var location=Reference(data,"locations",terms.FacilityCode);
        var clock=Reference(data,"clock_rules",terms.ClockCode);
        if(location.OptionalText("clock_code") is {} locationClock&&locationClock!=terms.ClockCode)
            throw Error("structured_power_reference","The selected operating clock must match the retained facility location clock.");
        var operatingClock=PowerClock.FromRule(ReferenceClockJson.Read(clock),TimeZoneDatabase.Installed());
        if(terms.Kind=="solar"?terms.PowerQuantityCode is not null:terms.PowerQuantityCode is null)throw Union();
        var power=terms.PowerQuantityCode is {} powerCode?Quantity(data,powerCode):null;var energy=Quantity(data,terms.EnergyQuantityCode);
        if(energy.Unit.Code!="megawatt_hour"||energy.Dimension.Code!="energy"||power is {} selectedPower&&(selectedPower.Key==energy.Key||selectedPower.Unit.Code!="megawatt"||selectedPower.Dimension.Code!="power"||selectedPower.Commodity!=energy.Commodity))
            throw Error("structured_power_reference","Select distinct compatible MW/MWh quantities.");
        var asset=new AssetVersionKey(new(data.DefinitionRevision,terms.FacilityCode),effectiveFrom);
        var locationKey=new ReferenceKey(data.ReferenceRevision,terms.FacilityCode);var clockKey=new ReferenceKey(data.ReferenceRevision,terms.ClockCode);
        BatteryResource? battery=null;BatteryThroughputConstraint? throughput=null;ThermalFacilityParameters? thermal=null;QuantitySpecification? fuel=null;QuantityStage? stage=null;
        switch(terms.Kind)
        {
            case "battery":
            {
                if(terms.Battery is not {} b||terms.Thermal is not null||terms.Solar is not null||terms.FuelQuantityCode is not null)throw Union();
                if(b.MeterBoundary!="grid_side_ac"||b.LossPolicy!="zero_auxiliary_and_self_discharge"||b.CapacityPolicy!="fixed"||b.SimultaneousPolicy!="prohibited"||b.ChargingOrigin!="grid")
                    throw Error("structured_power_policy","Select the explicit supported AC boundary, losses, capacity, simultaneous-operation and charging-origin policies.");
                b=b with{MaximumChargeMw=Number(b.MaximumChargeMw),MaximumDischargeMw=Number(b.MaximumDischargeMw),MinimumStoredMwh=Number(b.MinimumStoredMwh),MaximumStoredMwh=Number(b.MaximumStoredMwh),
                    ChargeEfficiency=Number(b.ChargeEfficiency),DischargeEfficiency=Number(b.DischargeEfficiency),MaximumThroughputMwh=b.MaximumThroughputMwh is {} maximum?Number(maximum):null};
                throughput=b.ThroughputPolicy switch
                {
                    "uncapped" when b.MaximumThroughputMwh is null=>new(BatteryThroughputPolicy.Uncapped,null),
                    "grid_charge_plus_discharge" when b.MaximumThroughputMwh is {} cap&&Decimal(cap).CompareTo(default)>=0=>new(BatteryThroughputPolicy.GridChargePlusDischarge,new(Decimal(cap),energy.Key)),
                    _=>throw Error("structured_power_policy","Select an uncapped policy with no budget or a nonnegative cumulative grid charge-plus-discharge budget.")
                };
                battery=new(data.DefinitionRevision,terms.FacilityCode,locationKey,clockKey,operatingClock,terms.IntervalMinutes,power!,energy,
                    new(Q(b.MaximumChargeMw,power!),Q(b.MaximumDischargeMw,power!),Q(b.MinimumStoredMwh,energy),Q(b.MaximumStoredMwh,energy)),
                    new(Decimal(b.ChargeEfficiency),Decimal(b.DischargeEfficiency),BatteryMeterBoundary.GridSideAc,BatteryLossPolicy.ZeroAuxiliaryAndSelfDischarge,BatteryCapacityPolicy.Fixed,BatterySimultaneousPolicy.Prohibited));
                BatteryOperatingPlans.ValidateResource(battery);terms=terms with{Battery=b};break;
            }
            case "thermal":
            {
                if(terms.Thermal is not {} t||terms.Battery is not null||terms.Solar is not null||terms.FuelQuantityCode is null)throw Union();
                fuel=Quantity(data,terms.FuelQuantityCode);
                t=t with{MinimumOutputMw=Number(t.MinimumOutputMw),MaximumOutputMw=Number(t.MaximumOutputMw),RampUpMwPerHour=Number(t.RampUpMwPerHour),RampDownMwPerHour=Number(t.RampDownMwPerHour),
                    StartupMaximumOutputMw=Number(t.StartupMaximumOutputMw),ShutdownMaximumOutputMw=Number(t.ShutdownMaximumOutputMw),ConsumptionHeatRate=Number(t.ConsumptionHeatRate),
                    ConsumptionNoLoadFuelPerHour=Number(t.ConsumptionNoLoadFuelPerHour),ConsumptionStartupFuel=Number(t.ConsumptionStartupFuel)};
                thermal=new(asset,effectiveTo,clockKey,operatingClock,terms.IntervalMinutes,power!,energy,fuel,Q(t.MinimumOutputMw,power!),Q(t.MaximumOutputMw,power!),Decimal(t.RampUpMwPerHour),Decimal(t.RampDownMwPerHour),
                    Q(t.StartupMaximumOutputMw,power!),Q(t.ShutdownMaximumOutputMw,power!),Minutes(t.MinimumUpMinutes),Minutes(t.MinimumDownMinutes),Minutes(t.StartupLeadMinutes),t.MaximumStarts,
                    Fuel(t.ConsumptionHeatRate,t.ConsumptionNoLoadFuelPerHour,t.ConsumptionStartupFuel,fuel,energy),ThermalToll.Implementation);
                ThermalToll.ValidateResource(thermal);terms=terms with{Thermal=t};break;
            }
            case "solar":
            {
                if(terms.Solar is not {} s||terms.Battery is not null||terms.Thermal is not null||terms.FuelQuantityCode is not null)throw Union();
                stage=s.Stage switch{"generated"=>QuantityStage.Generated,"delivered"=>QuantityStage.Delivered,_=>throw Error("structured_power_policy","Select the explicit generated or delivered measurement stage.")};
                if(terms.IntervalMinutes is not(15 or 60))
                    throw Error("structured_power_policy","Select a supported solar interval.");
                break;
            }
            default:throw Union();
        }
        return new(terms,asset,locationKey,clockKey,operatingClock,power,energy,fuel,battery,throughput,thermal,stage);
    }

    internal static JsonElement Reference(PreviewData data,string table,string code)
    {
        if(string.IsNullOrWhiteSpace(code)||!data.References.TryGetValue(table,out var rows))throw ReferenceError();
        var matches=rows.Where(row=>row.Text("code")==code).Take(2).ToArray();if(matches.Length!=1)throw ReferenceError();return matches[0];
    }
    internal static QuantitySpecification Quantity(PreviewData data,string code)
    {
        var q=Reference(data,"quantity_specifications",code);var r=data.ReferenceRevision;
        Reference(data,"commodities",q.Text("commodity_code"));Reference(data,"measurement_bases",q.Text("basis_code"));Reference(data,"dimensions",q.Text("dimension_code"));
        var unit=Reference(data,"units",q.Text("unit_code"));if(unit.Text("dimension_code")!=q.Text("dimension_code"))throw ReferenceError();
        return new(new(r,code),new(r,q.Text("commodity_code")),new(r,q.Text("basis_code")),new(r,q.Text("unit_code")),new(r,q.Text("dimension_code")));
    }
    internal static ThermalFuelTerms Fuel(string heatRate,string noLoad,string startup,QuantitySpecification fuel,QuantitySpecification energy)=>
        new(new(Decimal(heatRate),fuel.Key,energy.Key,"contractual_quantity_factor_v1"),Q(noLoad,fuel),Q(startup,fuel));
    internal static Quantity Q(string value,QuantitySpecification spec)=>new(Decimal(value),spec.Key);
    internal static string Number(string value)=>Decimal(value).ToString();
    internal static ExactDecimal Decimal(string value)
    {
        if(value is null||value.Length>80)throw Error("structured_power_number","Supply a bounded exact decimal string.");
        try{return ExactDecimal.Parse(value);}catch(Exception e)when(e is FormatException or OverflowException or ArgumentException){throw Error("structured_power_number","Supply an exact decimal string within the supported precision.");}
    }
    internal static TimeSpan Minutes(int minutes)=>minutes>=0&&minutes<=525600?TimeSpan.FromMinutes(minutes):throw Error("structured_power_time","Explicit elapsed minutes must be between zero and one year.");
    internal static bool Utc(DateTimeOffset value)=>value.Offset==TimeSpan.Zero&&value.Ticks%10==0&&value.Year<9999;
    internal static MarketDataException Error(string code,string message)=>new(code,message);
    static MarketDataException Union()=>Error("structured_power_union","Supply exactly one matching thermal, battery or solar parameter record and fuel only for thermal.");
    static MarketDataException ReferenceError()=>Error("structured_power_reference","A selected exact reference is absent, ambiguous or incompatible in the authorized bundle.");
}
