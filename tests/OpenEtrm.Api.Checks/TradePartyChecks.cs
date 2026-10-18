using System.Text.Json;
using OpenEtrm.Api;
using OpenEtrm.MarketData;

internal static class TradePartyChecks
{
    public static void Run()
    {
        var catalog = Guid.NewGuid();
        var row = new Dictionary<string, object?> {
            ["trade_date"] = "2040-12-18", ["legal_entity_id"] = Guid.NewGuid(), ["legal_entity_revision"] = 1,
            ["legal_entity_code"] = "entity_a", ["legal_entity_name"] = "Synthetic entity A",
            ["counterparty_id"] = Guid.NewGuid(), ["counterparty_revision"] = 2,
            ["counterparty_code"] = "party_a", ["counterparty_name"] = "Synthetic party A" };
        var terms = TradeParties.Read(catalog, JsonSerializer.SerializeToElement(row))!;
        if (terms.Counterparty.Key.Revision != 2 || terms.TradeDate != new DateOnly(2040, 12, 18)) throw new Exception("Lost exact booking terms.");
        foreach (var key in new[] { "legal_entity_code", "legal_entity_name", "counterparty_code", "counterparty_name" })
        {
            var missing = new Dictionary<string, object?>(row) { [key] = null };
            try { TradeParties.Read(catalog, JsonSerializer.SerializeToElement(missing)); }
            catch (MarketDataException e) when (e.Code == "trade_party") { continue; }
            throw new Exception("Unavailable joined party reference was accepted: " + key);
        }
        Console.WriteLine("PASS exact trade party read rejects unavailable joined versions rather than displaying null as a party name");
    }
}
