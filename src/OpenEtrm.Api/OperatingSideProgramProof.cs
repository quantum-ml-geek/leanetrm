using System.Numerics;
using System.Text.Json;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

// The v2 summary describes the accepted program, independently of current
// prices. Read only the supported canonical operating terms and instructions;
// never generate another schedule to justify a retained description.
internal static class OperatingSideProgramProof
{
    internal static PriceUnit Require(OperatingPosition position,StructuredPowerOperatingSideInput side,BookedSideProgram program)
    {
        try
        {
            using var document=JsonDocument.Parse(program.Document.EconomicIdentity);
            var economic=document.RootElement;var fixedPrice=side.Price.Mode=="fixed";
            if(fixedPrice?side.Price.FixedPrice is null||side.Price.CurveCode is not null||side.Price.ContractId is not null:
                side.Price.Mode!="selected_contract_flat_v1"||side.Price.FixedPrice is not null||side.Price.CurveCode is null||side.Price.ContractId is null)throw Invalid();
            if(program.Document.Family!="operating"||economic.GetProperty("contract").GetString()!=(fixedPrice?"FixedSide_operating_v1":"FloatingSide_operating_v1"))throw Invalid();
            var terms=economic.GetProperty("OperatingDefinition");var delivery=side.Kind=="delivery";
            if(terms.GetProperty("contract").GetString()!="operating_side_terms_v1"||
                terms.GetProperty("Implementation").GetString()!=OperatingSideTerms.SupportedImplementation||
                terms.GetProperty("Kind").GetInt32()!=(int)(delivery?ComponentKind.Delivery:ComponentKind.Payment))throw Invalid();
            var normalized=terms.GetProperty("UnitQuantity");RequireArray(normalized,"quantity",3);
            if(ExactDecimal.Parse(normalized[1].GetString()!)!=ExactDecimal.Parse("1")||Reference(normalized[2])!=position.Quantity)throw Invalid();
            var definition=new DefinitionRevision(position.Head.Id("catalog_id"),position.Definition);
            var quote=terms.GetProperty("Quote");RequireArray(quote,"quote",10);
            if(Reference(quote[1])!=new ReferenceKey(position.Reference,side.Price.QuoteCode)||quote[2].GetInt32()!=(int)QuoteKind.Outright||
                Reference(quote[3])!=position.Currency)throw Invalid();
            var quantity=Reference(quote[4]);var unit=new PriceUnit(position.Currency,quantity,ExactDecimal.Parse(quote[5].GetString()!));
            if(quantity.Revision!=position.Reference)throw Invalid();
            var periods=terms.GetProperty("Periods").EnumerateArray().ToArray();
            var guards=program.Document.Instructions.Where(row=>row.Output.Operation=="output_guard").ToArray();
            if(periods.Length is <1 or >StructuredPowerPreview.MaximumPreviewIntervals||periods.Length!=guards.Length)throw Invalid();
            foreach(var period in periods)
            {
                if(period.GetProperty("contract").GetString()!="operating_side_period_v1")throw Invalid();
                var source=period.GetProperty("Quantity");
                if(source.GetProperty("contract").GetString()!="operating_quantity_term_v1")throw Invalid();
                if(side.QuantitySource=="horizon_right")
                {
                    var literal=source.GetProperty("Literal");RequireArray(literal,"quantity",3);
                    if(source.GetProperty("Port").ValueKind!=JsonValueKind.Null||ExactDecimal.Parse(literal[1].GetString()!)!=ExactDecimal.Parse("1")||
                        Reference(literal[2])!=position.Quantity||quantity!=position.Quantity)throw Invalid();
                }
                else
                {
                    var port=source.GetProperty("Port");
                    if(source.GetProperty("Literal").ValueKind!=JsonValueKind.Null||port.GetProperty("contract").GetString()!="operating_output_port_v1"||
                        port.GetProperty("Kind").GetInt32()!=(int)Output(side.QuantitySource)||Reference(port.GetProperty("Quantity"))!=quantity)throw Invalid();
                    var plan=port.GetProperty("Plan");var resource=port.GetProperty("Resource");RequireArray(resource,"asset",3);
                    if(plan.GetProperty("contract").GetString()!="operating_plan_reference_v1"||plan.GetProperty("Id").GetGuid()!=position.Binding||
                        plan.GetProperty("Version").GetInt32()!=1||Definition(plan.GetProperty("Definitions"))!=definition||
                        Definition(resource[1])!=definition||resource[2].GetString()!=position.Physical.Text("facility_code"))throw Invalid();
                }
            }
            var payment=terms.GetProperty("Payment");
            if(delivery)
            {
                if(payment.ValueKind!=JsonValueKind.Null||guards.Any(row=>row.Output.Parameters.GetValueOrDefault("paymentRule")!="not_applicable_delivery_v1"))throw Invalid();
            }
            else
            {
                var rule=StructuredPowerPreview.OperatingPayment(side.PaymentRule!);
                var expected=JsonSerializer.SerializeToElement(new object?[]{"payment_rule",PaymentRule.Implementation,(int)rule.Frequency,(int)rule.Rule,
                    rule.Days,rule.DayOfMonth,(int?)rule.DayBasis,(int?)rule.ShortMonthPolicy,(int)rule.Adjustment,null});
                if(!JsonElement.DeepEquals(payment,expected)||guards.Any(row=>row.Output.Parameters.GetValueOrDefault("paymentRule")!=payment.GetRawText()))throw Invalid();
            }
            var prices=program.Document.Instructions.Where(row=>row.Output.Operation is "constant_price" or "operating_contract_price").ToArray();
            if(prices.Length==0)throw Invalid();
            foreach(var price in prices)
            {
                if(price.Output.Unit!=unit.Quantity||price.Output.Currency!=unit.Currency||price.Output.QuoteMultiplier is not {} multiplier||ExactDecimal.Parse(multiplier)!=unit.Multiplier)throw Invalid();
                if(fixedPrice)
                {
                    var expected=ExactDecimal.Parse(side.Price.FixedPrice!).Power(1);
                    var numerator=BigInteger.Parse(price.Output.Parameters["numerator"],System.Globalization.CultureInfo.InvariantCulture);
                    var denominator=BigInteger.Parse(price.Output.Parameters["denominator"],System.Globalization.CultureInfo.InvariantCulture);
                    if(price.Output.Operation!="constant_price"||denominator<=0||numerator*expected.Denominator!=expected.Numerator*denominator)throw Invalid();
                }
                else if(side.Price.Mode!="selected_contract_flat_v1"||price.Output.Operation!="operating_contract_price"||price.Bindings.Length!=2||
                    price.Bindings.Count(binding=>binding.Kind=="quote"&&binding.Reference==Reference(quote[1]))!=1||
                    price.Bindings.Count(binding=>binding.Kind=="contract_price"&&binding.Market is {} market&&
                        market.Curve.Revision==definition&&market.Contract.Revision==definition&&market.Curve.Code==side.Price.CurveCode&&market.Contract.Id==side.Price.ContractId)!=1)throw Invalid();
            }
            return unit;
        }
        catch(Exception error)when(error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException or MarketDataException)
        {throw Invalid();}
    }

    static OperatingOutputKind Output(string source)=>source switch
    {
        "energy_output"=>OperatingOutputKind.EnergyOutput,"discharging_energy"=>OperatingOutputKind.DischargingEnergy,
        "charging_energy"=>OperatingOutputKind.ChargingEnergy,"grid_throughput" or "payment_energy"=>OperatingOutputKind.PaymentEnergy,
        "guaranteed_fuel"=>OperatingOutputKind.GuaranteedFuelInput,"consumption_fuel"=>OperatingOutputKind.ConsumptionFuelInput,_=>throw Invalid()
    };
    static ReferenceKey Reference(JsonElement value)
    {
        RequireArray(value,"reference",3);var revision=value[1];RequireArray(revision,"reference_revision",3);
        return new(new(revision[1].GetGuid(),revision[2].GetGuid()),value[2].GetString()!);
    }
    static DefinitionRevision Definition(JsonElement value)
    {RequireArray(value,"definition_revision",3);return new(value[1].GetGuid(),value[2].GetGuid());}
    static void RequireArray(JsonElement value,string tag,int length)
    {if(value.ValueKind!=JsonValueKind.Array||value.GetArrayLength()!=length||value[0].GetString()!=tag)throw Invalid();}
    static MarketDataException Invalid()=>new("instrument_side_presentation","Retain the exact operating source, quote, price and payment policy sealed in every Side program.");
}
