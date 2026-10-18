using System.Text.Json;
using System.Text.Json.Serialization;
using OpenEtrm.MarketData;

namespace OpenEtrm.Api;

// Typed amounts keep their references; their decimal payload is always exact text.
public sealed class ExactDecimalJsonConverter : JsonConverter<ExactDecimal>
{
 public override ExactDecimal Read(ref Utf8JsonReader reader,Type typeToConvert,JsonSerializerOptions options)
 {
  if(reader.TokenType!=JsonTokenType.String)throw new JsonException("An exact decimal must use canonical decimal text.");
  return ExactDecimal.Parse(reader.GetString()!);
 }
 public override void Write(Utf8JsonWriter writer,ExactDecimal value,JsonSerializerOptions options)=>writer.WriteStringValue(value.ToString());
}
