using System.Globalization;
using System.Numerics;
using OpenEtrm.MarketData;

namespace OpenEtrm.Rates;

public static class DiscountInterpolation
{
    public const string Policy = "log_discount_geometric_root_to_even_18_v1";
    public const int MaximumPillarDays = 3660;
    private static readonly BigInteger Scale = BigInteger.Pow(10, 18);

    // exp((1-w)log(a)+w log(b)) is the positive d-th root of
    // a^(d-n)*b^n when w=n/d. Work in integer scaled factors: no floating point
    // logarithm, intermediate rounding or platform math-library dependency.
    public static ExactDecimal Factor(DateOnly left, ExactDecimal leftFactor,
        DateOnly right, ExactDecimal rightFactor, DateOnly payment, string policy)
    {
        var days = right.DayNumber - left.DayNumber;
        if (policy != Policy || days <= 0 || days > MaximumPillarDays || payment < left || payment > right ||
            left.Year is < 1901 or > 2199 || right.Year is < 1901 or > 2199 ||
            leftFactor.CompareTo(default) <= 0 || rightFactor.CompareTo(default) <= 0)
            throw new MarketDataException("discount_interpolation", "Use positive factors, ordered covered dates within the supported pillar span, and the explicit log-discount interpolation policy.");
        if (payment == left) return leftFactor;
        if (payment == right) return rightFactor;
        var n = payment.DayNumber - left.DayNumber;
        var gcd = (int)BigInteger.GreatestCommonDivisor(n, days);
        n /= gcd; days /= gcd;
        var a = Scaled(leftFactor); var b = Scaled(rightFactor);
        if (a == b) return leftFactor;
        var power = BigInteger.Pow(a, days - n) * BigInteger.Pow(b, n);
        var low = BigInteger.Min(a, b); var high = BigInteger.Max(a, b);
        // The root lies between the two positive endpoint factors. The search
        // and exact half-integer comparison also handle genuine rounding ties.
        while (high - low > BigInteger.One)
        {
            var middle = (low + high) / 2;
            if (BigInteger.Pow(middle, days) <= power) low = middle;
            else high = middle;
        }
        var comparison = (power << days).CompareTo(BigInteger.Pow(2 * low + 1, days));
        if (comparison > 0 || comparison == 0 && !low.IsEven) low++;
        var whole = BigInteger.DivRem(low, Scale, out var fraction);
        return ExactDecimal.Parse(whole.ToString(CultureInfo.InvariantCulture) + "." + fraction.ToString("D18", CultureInfo.InvariantCulture));
    }

    private static BigInteger Scaled(ExactDecimal value)
    {
        var parts = value.ToString().Split('.');
        return BigInteger.Parse(parts[0] + (parts.Length == 2 ? parts[1] : "").PadRight(18, '0'), CultureInfo.InvariantCulture);
    }
}
