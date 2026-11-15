namespace OpenEtrm.MarketData.Trading;

// Contractual payments have UTC operating dates. Stored instants are calculation
// coordinates, not intraday deadlines or evidence of payment.
public static class PaymentDatePolicy
{
    public const string Implementation="utc_payment_day_v1";
    public static DateOnly Date(DateTimeOffset at)=>DateOnly.FromDateTime(at.UtcDateTime);
    public static bool IsDue(DateTimeOffset payment,DateTimeOffset at)=>Date(at)>=Date(payment);
    public static bool IsOverdue(DateTimeOffset payment,DateTimeOffset at)=>Date(at)>Date(payment);
    public static bool SameDay(DateTimeOffset payment,DateTimeOffset at)=>Date(at)==Date(payment);
    public static DateTimeOffset Start(DateOnly date)=>new(date.ToDateTime(TimeOnly.MinValue,DateTimeKind.Utc));
    public static DateTimeOffset OverdueBoundary(DateTimeOffset payment)=>Start(Date(payment).AddDays(1));
    public static void RequireCompletion(DateTimeOffset payment,DateTimeOffset completion)
    {
        if(Date(payment)<Date(completion))
            throw new MarketDataException("payment_before_completion","The adjusted payment date precedes required delivery completion or fixing.");
    }
}
