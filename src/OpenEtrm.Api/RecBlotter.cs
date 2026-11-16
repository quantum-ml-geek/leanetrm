using System.Collections.Immutable;
using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;
using Npgsql;
using OpenEtrm.MarketData;

namespace OpenEtrm.Api;

// The report uses the portfolio's retained executor and exact market groups.
// A source or lifecycle failure occurs before this product yields any rows.
internal static class RecBlotter
{
 internal static async Task<RecRun> Run(NpgsqlConnection connection,PreviewDatabase database,InputFrame frame,
  ImmutableArray<Guid> books,ImmutableArray<Guid> portfolios,CancellationToken ct,TradePositionSelection? position=null)=>
  new(connection,database,frame,await RecPositions.Read(connection,database.Manifest,books,portfolios,ct,position));
 internal sealed class RecRun(NpgsqlConnection connection,PreviewDatabase database,InputFrame frame,ImmutableArray<RecPosition> positions):IBlotterProductRun
 {
  public int Positions=>positions.Length;
  public async IAsyncEnumerable<ImmutableArray<JsonObject>> Units([EnumeratorCancellation]CancellationToken ct)
  {
   if(positions.IsEmpty)yield break;
   var values=await RecPortfolio.Values(connection,database,frame,positions,ct);
   if(values.Count!=positions.Length||!positions.Select(p=>p.Binding).ToHashSet().SetEquals(values.Keys))
    throw new MarketDataException("rec_portfolio","Every held certificate instrument must have exactly one complete retained value.");
   foreach(var position in positions)
   {
    var row=position.Holding();row["presentValue"]=values[position.Binding].ToExactString();
    yield return [row];
   }
  }
 }
}
