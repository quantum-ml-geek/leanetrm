using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.MarketData.Gas;

public sealed record GasParkAndLoanPrincipalPlan(Quantity RemainingAdvance,Quantity OutstandingReturn,Quantity OverdueReturn,
    Quantity SignedReturnHolding,Money FixedFee);

// Pure arithmetic over resolved accepted quantities. This does not accept title,
// establish available stock, pay a fee or resolve a native revision history.
public static class GasParkAndLoanPrincipal
{
    public static GasParkAndLoanPrincipalPlan Plan(GasParkAndLoanTerms terms,Quantity committed,Quantity advanced,Quantity returned,DateTimeOffset at)
    {
        if(terms is null||committed is null||advanced is null||returned is null||
            committed.Specification!=terms.Quantity||advanced.Specification!=terms.Quantity||returned.Specification!=terms.Quantity||
            committed.Amount.CompareTo(default)<=0||advanced.Amount!=default&&advanced.Amount!=committed.Amount||
            returned.Amount.CompareTo(default)<0||returned.Amount.CompareTo(advanced.Amount)>0||!TradingInstant.IsSupported(at)||
            advanced.Amount!=default&&at<terms.AdvanceAt||returned.Amount!=default&&at<=terms.AdvanceAt)
            throw new MarketDataException("gas_park_loan_principal","Supply one explicit committed quantity, its single full accepted advance and conserved partial returns at the selected business instant.");
        var outstanding=advanced.Amount-returned.Amount;
        return new(new(committed.Amount-advanced.Amount,terms.Quantity),new(outstanding,terms.Quantity),
            new(at>=terms.ReturnAt?outstanding:default,terms.Quantity),new(-terms.AdvanceDirection*outstanding,terms.Quantity),terms.SignedFixedFee);
    }

    public static GasParkAndLoanPrincipalPlan Advance(GasParkAndLoanTerms terms,Quantity committed,Quantity advanced,Quantity performance,DateTimeOffset at)
    {
        if(terms is null||committed is null||advanced is null||performance is null||!TradingInstant.IsSupported(at)||at<terms.AdvanceAt||at>=terms.ReturnAt||
            performance.Specification!=terms.Quantity||advanced.Amount!=default||performance.Amount!=committed.Amount)
            throw new MarketDataException("gas_park_loan_advance","The installed profile accepts one full committed advance from its advance instant until strictly before its return due instant.");
        _=Plan(terms,committed,advanced,new(default,terms.Quantity),at);
        return Plan(terms,committed,performance,new(default,terms.Quantity),at);
    }

    public static GasParkAndLoanPrincipalPlan Return(GasParkAndLoanTerms terms,Quantity committed,Quantity advanced,Quantity returned,
        DateTimeOffset acceptedAdvanceAt,Quantity performance,DateTimeOffset at)
    {
        if(terms is null||performance is null||!TradingInstant.IsSupported(acceptedAdvanceAt)||acceptedAdvanceAt<terms.AdvanceAt||
            !TradingInstant.IsSupported(at)||at<=acceptedAdvanceAt||performance.Specification!=terms.Quantity||performance.Amount.CompareTo(default)<=0)
            throw new MarketDataException("gas_park_loan_return","A positive return must follow this agreement's accepted advance; late performance leaves the due-date history intact.");
        _=Plan(terms,committed,advanced,returned,at);
        return Plan(terms,committed,advanced,returned.Add(performance),at);
    }
}
