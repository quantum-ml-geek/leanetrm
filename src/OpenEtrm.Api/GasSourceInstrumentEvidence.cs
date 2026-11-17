using System.Text.Json;
using System.Text.Json.Serialization;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Gas;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

// Retained source receipts describe exact admitted definitions. Materialization
// continues to read the native owner, terms and certificate under authority.
internal sealed class TimedCashSourceEvidenceConverter : JsonConverter<TimedCashPayment>
{
    public override TimedCashPayment Read(ref Utf8JsonReader reader,Type type,JsonSerializerOptions options)=>
        throw new MarketDataException("gas_source_evidence","Materialize cash from its exact authorized native source.");
    public override void Write(Utf8JsonWriter writer,TimedCashPayment value,JsonSerializerOptions options)=>
        JsonSerializer.Serialize(writer,new{implementation="timed_cash_source_definition_v1",value.Id,value.PaymentCurrency,
            value.PaymentAt,timing="instant",economicDefinition=value.EconomicIdentity,modelVersion=CashPaymentInstrument.ModelVersion},options);
}

internal sealed class GasHoldingSourceEvidenceConverter : JsonConverter<GasCommodityHoldingInstrument>
{
    public override GasCommodityHoldingInstrument Read(ref Utf8JsonReader reader,Type type,JsonSerializerOptions options)=>
        throw new MarketDataException("gas_source_evidence","Materialize a gas holding from its exact authorized native source.");
    public override void Write(Utf8JsonWriter writer,GasCommodityHoldingInstrument value,JsonSerializerOptions options)=>
        JsonSerializer.Serialize(writer,new{implementation="gas_holding_source_definition_v1",value.Id,value.Mark,
            value.QuantitySpecification,value.PaymentCurrency,value.ReturnAt,carrying=value.Carrying.ToString(),
            economicDefinition=value.EconomicIdentity,modelVersion=GasCommodityHoldingSide.ModelVersion},options);
}
