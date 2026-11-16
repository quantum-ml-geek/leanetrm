using System.Collections.Immutable;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Power;
using OpenEtrm.MarketData.Trading;
using OpenEtrm.Shared.Temporal;

namespace OpenEtrm.Api;

public static partial class StructuredPowerPreview
{
    static StructuredPowerValuationResult Value(PreviewData data,InputFrame frame,DateTimeOffset knownAt,Guid id,
        StructuredPowerResolvedTerms resolved,DeliveryInterval[] grid,IReadOnlyDictionary<string,OperatingOutputPort> ports,
        ImmutableArray<OperatingScenarioQuantityCell> cells,StructuredPowerValuationInput input)
    {
        if(input.Perspective!=RightHolderPerspective||input.Measure!=RemainingValueMeasure||input.EnergyPrice is null||input.PaymentRule is null)
            throw Error("structured_power_policy","Select the explicit right-holder perspective, remaining-value measure, energy price and payment rule.");
        if(input.Discounting)throw Error("structured_power_unavailable","Discounted operating previews require an admitted currency-rate operation; select explicitly undiscounted for this preview.");
        if(input.StartupPrice is not null||input.StartupQuoteCode is not null||input.StartupFeeBasis is not null)
            throw Error("structured_power_unavailable","Startup fees need an admitted start-count quote; the complete resource-right unit cannot be reused as a start.");
        Reference(data,"currencies",input.CurrencyCode);var currency=new ReferenceKey(data.ReferenceRevision,input.CurrencyCode);
        var right=Quantity(data,input.RightQuantityCode);
        if(right.Unit.Code!="resource_right"||!CompleteRightDimension(data,right.Dimension.Code)||right.Commodity!=resolved.Energy.Commodity)throw Error("structured_power_reference","Select an explicit compatible complete resource-right quantity for economic normalization.");
        var payment=OperatingPayment(input.PaymentRule);var unit=new Quantity(One,right.Key);
        var memberships=ImmutableArray.CreateBuilder<SideMembership>();var names=new Dictionary<Guid,string>();var quotes=new Dictionary<Guid,ReferenceKey>();
        QuoteSpecification Quote(string code,QuantitySpecification quantity)
        {
            var matches=data.QuoteRows(code).Take(2).ToArray();if(matches.Length!=1||matches[0].Key.Revision!=data.ReferenceRevision||matches[0].Kind!=QuoteKind.Outright||matches[0].Currency!=currency||matches[0].Quantity!=quantity.Key)
                throw Error("structured_power_price","Select an authorized outright quote in the exact native quantity and preview currency.");
            return matches[0];
        }
        void Add(string name,string portName,StructuredPowerPriceInput price,QuantitySpecification quantity,ExactDecimal sign,bool once=false)
        {
            if(price is null)throw Error("structured_power_price","Supply an explicit price for every valued side.");
            var quote=Quote(price.QuoteCode,quantity);CurveRequest? projection=null;FixedPriceTerm? fixedPrice=null;
            switch(price.Mode)
            {
                case "fixed" when price.FixedPrice is {} amount&&price.CurveCode is null&&price.ContractId is null:
                    fixedPrice=new FlatPrice(new(Decimal(amount),PriceUnit.FromQuote(quote)));break;
                case "selected_contract_flat_v1" when price.FixedPrice is null&&price.CurveCode is {} curve&&price.ContractId is {} contract:
                {
                    var requests=data.Requests(frame,curve);var selected=requests.Where(x=>x.Contract.Id==contract).Take(2).ToArray();
                    var definitions=data.Definitions["curves"].Where(x=>x.Text("code")==curve).Take(2).ToArray();
                    var contracts=data.ContractRows(contract).Take(2).ToArray();
                    if(selected.Length!=1||definitions.Length!=1||definitions[0].Text("quote_code")!=quote.Key.Code||contracts.Length!=1||
                        contracts[0].DeliveryFrom>grid[0].OperatingDate||contracts[0].DeliveryTo<=grid[^1].OperatingDate)
                        throw Error("structured_power_price","The explicitly selected price contract must be authorized and cover every operating date in this flat-contract model.");
                    projection=selected[0];break;
                }
                default:throw Error("structured_power_price","Select exactly one fixed price or an explicit selected-contract flat projection.");
            }
            var sideId=Identity(new{id,name});var selectedGrid=once?grid.Take(1):grid;
            var periods=selectedGrid.Select(interval=>
            {
                var month=new DateOnly(interval.OperatingDate.Year,interval.OperatingDate.Month,1);
                return new OperatingSidePeriod(interval,month,month.AddMonths(1),once?new(null,new(One,right.Key)):new(ports[portName],null),projection);
            }).ToImmutableArray();
            var terms=new OperatingSideTerms(unit,quote,payment,ComponentKind.Payment,periods,OperatingSideTerms.SupportedImplementation,
                new SideCalendarPolicy(CalendarBinding.NotApplicable(),CalendarBinding.NotApplicable(),CalendarBinding.NotApplicable(),SideCalendarPolicy.Implementation));
            Side side=fixedPrice is {} fixedTerm?new FixedSide(sideId,terms,fixedTerm):new FloatingSide(sideId,terms);
            memberships.Add(new(side,sign));names.Add(sideId,name);quotes.Add(sideId,quote.Key);
        }
        var kind=resolved.CanonicalTerms.Kind;
        Add(kind=="battery"?"discharging_energy":kind=="thermal"?"energy_output":"payment_energy",kind=="solar"?"payment":"energy",input.EnergyPrice,resolved.Energy,One);
        if(kind=="battery")
        {
            if(input.ChargingPrice is null||input.FuelPrice is not null||input.FuelQuantityBasis is not null)throw Error("structured_power_price","Battery valuation needs an explicit charging price and no fuel terms.");
            Add("charging_energy","charge",input.ChargingPrice,resolved.Energy,MinusOne);
        }
        else if(input.ChargingPrice is not null)throw Error("structured_power_price","A charging price belongs only to a battery preview.");
        if(kind=="thermal")
        {
            if(input.FuelPrice is null||input.FuelQuantityBasis is not("guaranteed" or "consumption"))throw Error("structured_power_price","Thermal valuation needs an explicit fuel price and guaranteed or consumption basis.");
            Add("fuel_input","fuel",input.FuelPrice,resolved.Fuel!,MinusOne);
        }
        else if(input.FuelPrice is not null||input.FuelQuantityBasis is not null)throw Error("structured_power_price","Fuel price and basis belong only to thermal previews.");
        if(input.VariablePrice is {} variable)
        {
            var expected=kind switch{"battery"=>"grid_charge_plus_discharge","thermal"=>"energy_output",_=>"payment_energy"};
            if(input.VariableQuantityBasis!=expected)throw Error("structured_power_policy","Select the implemented variable-fee quantity basis explicitly.");
            Add("variable_fee",kind=="battery"?"variable":kind=="solar"?"payment":"energy",new("fixed",input.EnergyPrice.QuoteCode,variable,null,null),resolved.Energy,MinusOne);
        }
        else if(input.VariableQuantityBasis is not null)throw Error("structured_power_policy","A variable-fee quantity basis requires an explicit variable price.");
        if(input.AccessPrice is {} access)
        {
            if(input.AccessQuoteCode is null||input.AccessFeeBasis!="preview_horizon_once_v1")throw Error("structured_power_policy","A horizon access fee requires its exact complete-right quote and explicit once-per-preview-horizon basis.");
            Add("access_fee","",new("fixed",input.AccessQuoteCode,access,null,null),right,MinusOne,true);
        }
        else if(input.AccessQuoteCode is not null||input.AccessFeeBasis is not null)throw Error("structured_power_policy","Access fee reference and basis require an explicit fee amount.");
        var instrument=new OperatingRightInstrument(id,resolved.Resource.Asset,unit,currency,memberships.ToImmutable());
        var dependencies=instrument.Dependencies;var snapshot=data.Snapshot(frame);
        if(frame.ContextId is {} contextId)snapshot=snapshot.WithKnowledge(contextId,knownAt);
        var discounting=new ExplicitDiscounting(One,DiscountFactorSource.Undiscounted);
        var context=dependencies.IsEmpty?new SideValuationContext(snapshot,discounting):new SideValuationContext(data.Model.Build(snapshot,dependencies),discounting);
        context=context.WithOperatingQuantities(OperatingQuantityInputs.Scenario(snapshot,cells,OperatingQuantityInputs.ScenarioImplementation));
        var value=instrument.PV(context);
        var sides=value.Sides.Select(contribution=>
        {
            var sideId=contribution.SideId;var evaluated=(OperatingSideValuation)contribution.Value;
            var rows=evaluated.Rows.Select(row=>new StructuredPowerSideRow(row.Interval!,row.ValueAt,row.Quantity,row.PriceComponents[0].Price,row.Amount,row.RequirePresentValue(),row.QuantityState,
                row.OperatingEvidence?.EvidenceId,row.OperatingEvidence?.KnownAt)).ToImmutableArray();
            return new StructuredPowerSideResult(sideId,names[sideId],contribution.Coefficient.ToString(),quotes[sideId],evaluated.PresentValue,contribution.Contribution,rows);
        }).ToImmutableArray();
        return new(input.Measure,input.Perspective,currency,unit,value.PresentValue,sides,value.NumericalPolicy);
    }
    private static PaymentRule OperatingPayment(PpaPaymentInput input)
    {
        if(input.Frequency!="monthly"||input.Rule!="days_after_period_end"||input.Days is not >=0 or >366||input.DayOfMonth is not null||
            input.DayBasis!="calendar_days"||input.ShortMonth is not null||input.Adjustment!="unadjusted"||input.Calendar is not null||
            input.Implementation!=PaymentRule.Implementation)
            throw Error("structured_power_payment","Select the supported explicit monthly calendar-day payment rule without holiday adjustment or an external calendar.");
        return new(PaymentFrequency.Monthly,PaymentDateRule.DaysAfterPeriodEnd,input.Days,null,PaymentDayBasis.CalendarDays,null,DateRoll.Unadjusted,null,input.Implementation);
    }

}
