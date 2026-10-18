using System.Text.Json;
using OpenEtrm.Api;
using OpenEtrm.MarketData;

internal static class AmountJsonChecks
{
 public static void Run()
 {
  var options=new JsonSerializerOptions(JsonSerializerDefaults.Web);options.Converters.Add(new ExactDecimalJsonConverter());
  var revision=new ReferenceRevision(Guid.NewGuid(),Guid.NewGuid());var key=new ReferenceKey(revision,"energy_quantity");
  var amount=new Quantity(ExactDecimal.Parse("12345678901234567890.123456789012345678"),key);
  var json=JsonSerializer.SerializeToElement(amount,options);
  if(json.GetProperty("amount").GetString()!=amount.Amount.ToString() || json.GetProperty("specification").GetProperty("code").GetString()!=key.Code)
   throw new Exception("The amount wire contract lost exact digits or its quantity specification.");
  if(JsonSerializer.Deserialize<ExactDecimal>("\"1.25\"",options)!=ExactDecimal.Parse("1.25"))throw new Exception("Lost decimal input.");
  try{JsonSerializer.Deserialize<ExactDecimal>("1.25",options);throw new Exception("Accepted an untyped JSON number.");}catch(JsonException){}
  Console.WriteLine("PASS typed amounts retain exact canonical decimals and exact unit references in JSON");
 }
}
