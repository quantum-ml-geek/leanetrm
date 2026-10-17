namespace OpenEtrm.MarketData;

public enum CashTieRule { ToEven = 1, AwayFromZero }
public enum CashRoundingStage { Cashflow = 1, PaymentTotal }
public sealed record CashRoundingConvention(
    ReferenceKey Key, ReferenceKey Currency, ExactDecimal Increment,
    CashTieRule TieRule, CashRoundingStage Stage);

public sealed record Money
{
    public ExactDecimal Amount { get; }
    public ReferenceKey Currency { get; }
    public Money(ExactDecimal amount, ReferenceKey currency)
    {
        RequireKey(currency); Amount = amount; Currency = currency;
    }
    internal static void RequireKey(ReferenceKey key)
    {
        if (key.Revision.CatalogId == Guid.Empty || key.Revision.RevisionId == Guid.Empty || string.IsNullOrWhiteSpace(key.Code))
            throw new MarketDataException("missing_reference", "Exact reference identity is required.");
    }
    private void Same(Money other)
    {
        if (Currency != other.Currency)
            throw new MarketDataException("currency_mismatch", "Money arithmetic requires the exact same currency reference.");
    }
    public Money Add(Money other) { Same(other); return new(Amount + other.Amount, Currency); }
    public Money Subtract(Money other) { Same(other); return new(Amount - other.Amount, Currency); }
    public Money Scale(ExactDecimal scalar) => new(Amount * scalar, Currency);
    public Money Round(CashRoundingConvention convention, CashRoundingStage stage)
    {
        RequireKey(convention.Key);
        if (convention.Key.Revision != Currency.Revision || convention.Currency != Currency ||
            convention.Stage != stage || !Enum.IsDefined(stage))
            throw new MarketDataException("rounding_policy", "Currency, reference revision and requested rounding stage must match.");
        return new(Amount.RoundToIncrement(convention.Increment, convention.TieRule), Currency);
    }
}

public sealed record Quantity
{
    public ExactDecimal Amount { get; }
    public ReferenceKey Specification { get; }
    public Quantity(ExactDecimal amount, ReferenceKey specification)
    {
        Money.RequireKey(specification); Amount = amount; Specification = specification;
    }
    public Quantity Add(Quantity other)
    {
        if (Specification != other.Specification)
            throw new MarketDataException("quantity_mismatch", "Quantity arithmetic requires the exact same unit/commodity/basis specification.");
        return new(Amount + other.Amount, Specification);
    }
}

public sealed record UnitPrice
{
    public ExactDecimal Value { get; }
    public QuoteSpecification Specification { get; }
    public UnitPrice(ExactDecimal value, QuoteSpecification specification)
    {
        Money.RequireKey(specification.Key); Money.RequireKey(specification.Currency); Money.RequireKey(specification.Quantity);
        if (specification.Key.Revision != specification.Currency.Revision ||
            specification.Key.Revision != specification.Quantity.Revision || specification.Multiplier.CompareTo(default) <= 0 ||
            value.CompareTo(specification.Minimum) < 0 || value.CompareTo(specification.Maximum) > 0)
            throw new MarketDataException("quote_specification", "Price requires coherent references, explicit domain and positive quote multiplier.");
        Value = value; Specification = specification;
    }
    public Money Times(Quantity quantity)
    {
        if (Specification.Quantity != quantity.Specification)
            throw new MarketDataException("quantity_mismatch", "Price denominator and quantity specification must match exactly.");
        return new(Value * Specification.Multiplier * quantity.Amount, Specification.Currency);
    }
}
