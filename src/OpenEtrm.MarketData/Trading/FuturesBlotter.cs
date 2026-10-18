using System.Collections.Immutable;

namespace OpenEtrm.MarketData.Trading;

public enum BlotterDimension { Portfolio=1, Book, Market, Contract }
public enum BlotterMeasure { TradeCount=1, Lots, Quantity, ExecutionPnl }
public sealed record FuturesBlotterEntry(Guid PortfolioId,FuturesHolding Holding);
public sealed record FuturesBlotterKey(Guid? PortfolioId,Guid? BookId,CurveKey? Market,ContractKey? Contract,
    ReferenceKey Quantity,ReferenceKey Currency);
public sealed record FuturesBlotterGroup(FuturesBlotterKey Key,int? TradeCount,ExactDecimal? Lots,Quantity? Quantity,Money? ExecutionPnl);

public static class FuturesBlotter
{
    public const string Implementation="futures_blotter_totals_v1";
    public static void Validate(ImmutableArray<BlotterDimension> dimensions,ImmutableArray<BlotterMeasure> measures,string implementation)
    {
        if(implementation!=Implementation || dimensions.IsDefaultOrEmpty || measures.IsDefaultOrEmpty ||
            dimensions.Any(d=>!Enum.IsDefined(d)) || measures.Any(m=>!Enum.IsDefined(m)) ||
            dimensions.Distinct().Count()!=dimensions.Length || measures.Distinct().Count()!=measures.Length ||
            measures.Contains(BlotterMeasure.Lots)&&!dimensions.Contains(BlotterDimension.Contract))
            throw new MarketDataException("blotter_view","Choose unique supported dimensions and measures; lot totals require dated-contract grouping.");
    }
    public static ImmutableArray<FuturesBlotterGroup> Pivot(ImmutableArray<FuturesBlotterEntry> entries,
        ImmutableArray<BlotterDimension> dimensions,ImmutableArray<BlotterMeasure> measures,string implementation)
    {
        Validate(dimensions,measures,implementation);
        if(entries.IsDefault || entries.Length>256 || entries.Any(e=>e.PortfolioId==Guid.Empty) ||
            entries.Select(e=>(e.Holding.TradeId,e.Holding.BindingId)).Distinct().Count()!=entries.Length ||
            entries.GroupBy(e=>e.Holding.BookId).Any(g=>g.Select(e=>e.PortfolioId).Distinct().Count()!=1))
            throw new MarketDataException("blotter_view","Use distinct authorized trade bindings with exact portfolio/book relationships.");
        // Canonical contribution ordering also makes bounded intermediate overflow deterministic.
        return entries.OrderBy(e=>e.Holding.TradeId).ThenBy(e=>e.Holding.BindingId).GroupBy(e=>new FuturesBlotterKey(
            dimensions.Contains(BlotterDimension.Portfolio)?e.PortfolioId:null,
            dimensions.Contains(BlotterDimension.Book)?e.Holding.BookId:null,
            dimensions.Contains(BlotterDimension.Market)?e.Holding.Market:null,
            dimensions.Contains(BlotterDimension.Contract)?e.Holding.Contract:null,
            e.Holding.Quantity.Specification,e.Holding.ExecutionPnl.Currency)).Select(g=>new FuturesBlotterGroup(g.Key,
                measures.Contains(BlotterMeasure.TradeCount)?g.Select(e=>e.Holding.TradeId).Distinct().Count():null,
                measures.Contains(BlotterMeasure.Lots)?g.Select(e=>e.Holding.Lots).Aggregate((a,b)=>a+b):null,
                measures.Contains(BlotterMeasure.Quantity)?g.Select(e=>e.Holding.Quantity).Aggregate((a,b)=>a.Add(b)):null,
                measures.Contains(BlotterMeasure.ExecutionPnl)?g.Select(e=>e.Holding.ExecutionPnl).Aggregate((a,b)=>a.Add(b)):null)).ToImmutableArray();
    }
}
