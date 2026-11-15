using System.Collections.Immutable;
using System.Text.Json.Nodes;

namespace OpenEtrm.Api;

internal static class AsyncReadJobs
{
    // RiskJobs owns these exact projections: List is an array, the archive has
    // items, and a direct read is one receipt. Pagination never authorizes an old page.
    internal static ImmutableArray<Guid> Ids(object value)=>value switch
    {
        JsonArray list=>[..list.Select(Id).Distinct()],
        JsonObject archive when archive["items"] is JsonArray items=>[..items.Select(Id).Distinct()],
        JsonObject receipt=>[Id(receipt)],
        _=>throw new InvalidOperationException("The retained risk read has no supported receipt projection.")
    };
    static Guid Id(JsonNode? node)=>node?["id"]?.GetValue<Guid>() is {} id&&id!=Guid.Empty?id:
        throw new InvalidOperationException("A retained risk receipt must identify its exact job.");
}
