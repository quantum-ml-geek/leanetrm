using System.Collections.Immutable;

namespace OpenEtrm.MarketData.Trading;

public static class OperatingContractScheduleSource
{
    public const string Operation="operating_contract_price";
    public const string Selection="selected_contract_flat_v1";
    public const string DeliveryLifecycle="future_operating_delivery_v1";
}

public static partial class ScheduleDefinitionCompiler
{
    private sealed partial class Builder
    {
        public void Operating(OperatingSideSchedule schedule,OperatingQuantityInputs? quantities)
        {
            if(selection!=ScheduleLifecycleSelection.FutureDelivery)
                throw new MarketDataException("physical_lifecycle_unsupported","Operating schedules require the explicit future supplied-plan profile.");
            foreach(var plan in schedule.Periods)
            {
                var operation=plan.Operating!;var period=operation.Period;var key="operating/"+plan.Ordinal;
                var amount=period.Quantity.Literal is {} literal?ExactQuantity.FromQuantity(literal):
                    quantities?.Resolve(period.Quantity.Port!,period.Interval).Quantity??
                    throw new MarketDataException("operating_inputs","Retaining a source-based operating Side requires its complete admitted plan quantities.");
                var quantity=Quantity(key+"/quantity",amount,plan);
                roots.Add(new(key+"/quantity",quantity,"schedule_quantity"));
                int price;
                if(operation.FixedPrice is {} fixedPrice)price=Price(key+"/price",fixedPrice.At(period.Interval.OperatingDate),plan);
                else
                {
                    var unit=PriceUnit.FromQuote(operation.Quote);
                    price=Row(key+"/price","source",OperatingContractScheduleSource.Operation,"price",plan,unit.Quantity,unit.Currency,
                        unit.Multiplier.ToString(),P(("selection",OperatingContractScheduleSource.Selection)));
                    Binding(price,"market","contract_price",market:period.Projection!.Value);
                    Binding(price,"quote","quote",reference:operation.Quote.Key);
                }
                var cash=Money(key+"/amount",quantity,price,plan);
                var discount=Row(key+"/discount","source","discount","factor",plan,parameters:P(("policy","context_required_v1")));
                var pv=Row(key+"/discounted","intermediate","pv","money",plan,currency:plan.Currency);
                Edge(pv,"amount",cash);Edge(pv,"discount",discount);
                var delivery=operation.Kind==ComponentKind.Delivery;
                var guard=Row(key+"/value","root","output_guard","money",plan,currency:plan.Currency,
                    parameters:P(("measure","present_value_v1"),("lifecycle",delivery?OperatingContractScheduleSource.DeliveryLifecycle:"undue_payment_v1"),
                        ("pricePolicy","selected_context_v1"),("averaging","none"),("firstFixingAt","none"),
                        ("paymentRule",delivery?"not_applicable_delivery_v1":PaymentIdentity(operation.Rule)),
                        ("unadjustedPayment",operation.GeneratedDate?.Unadjusted.ToString("yyyy-MM-dd",System.Globalization.CultureInfo.InvariantCulture)??"none")),
                    occurrence:Digest(new{Kind=delivery?"operating_delivery_v1":"operating_payment_v1",period.Interval,plan.PaymentAt,Rule=PaymentIdentity(operation.Rule)}),
                    digest:Digest(new{period.Interval,plan.Currency,Quantity=Closure(cash)}));
                Edge(guard,"amount",cash);Edge(guard,"discounted",pv);contributions.Add(guard);
                roots.Add(new(key+(delivery?"/delivery-value":"/cash"),cash,delivery?"physical_value":"contractual_amount"));
                roots.Add(new(key+"/pv",guard,"contribution_pv"));
                inputs.Clear();sources.Clear();termsHashes.Clear();
            }
        }
    }
}
