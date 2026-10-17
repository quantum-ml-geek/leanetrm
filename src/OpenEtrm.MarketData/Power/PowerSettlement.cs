using System.Globalization;
using System.Numerics;

namespace OpenEtrm.MarketData.Power;

public sealed record PowerIndex(ReferenceKey Definition,ReferenceKey Currency,ReferenceKey EnergyUnit,string PriceType,string Timing);
public sealed record LmpComponents(ExactDecimal Energy,ExactDecimal Congestion,ExactDecimal Loss);
public sealed record PowerFixing(DateTimeOffset Start,DateTimeOffset End,PowerIndex Index,ExactDecimal Total,LmpComponents? Components);
public sealed record PowerSettlementPolicy(string Implementation,int PriceScale,int AmountScale)
{
    public static PowerSettlementPolicy Preview { get; }=new("duration_weighted_flat_mw_to_even_v1",18,2);
    public void Validate()
    {
        if(this!=Preview)throw new MarketDataException("settlement_policy","Choose the supported explicit preview numerical policy.");
    }
}
public sealed record PowerSettlementResult(string Hours,string Energy,string AveragePrice,string Amount,
    string ExactAmountNumerator,string ExactAmountDenominator,PowerIndex Index,PowerSettlementPolicy Policy);

public static class PowerSettlement
{
    private static readonly BigInteger Scale=BigInteger.Pow(10,18);
    private static BigInteger Integer(ExactDecimal value)
    {
        var text=value.ToString();var parts=text.TrimStart('-').Split('.');
        var result=BigInteger.Parse(parts[0],CultureInfo.InvariantCulture)*Scale+
            BigInteger.Parse((parts.Length==2?parts[1]:"").PadRight(18,'0'),CultureInfo.InvariantCulture);
        return text.StartsWith('-')?-result:result;
    }
    private static string Rounded(BigInteger numerator,BigInteger denominator,int decimals)
    {
        var sign=numerator.Sign; numerator=BigInteger.Abs(numerator);
        var scale=BigInteger.Pow(10,decimals);
        var q=BigInteger.DivRem(numerator*scale,denominator,out var remainder);
        if(remainder*2>denominator || remainder*2==denominator&&!q.IsEven)q++;
        var whole=BigInteger.DivRem(q,scale,out var fraction);
        return ExactDecimal.Parse((sign<0&&q!=0?"-":"")+whole.ToString(CultureInfo.InvariantCulture)+
            (decimals==0?"":"."+fraction.ToString("D"+decimals,CultureInfo.InvariantCulture))).ToString();
    }
    private static Dictionary<DateTimeOffset,PowerFixing> Validate(PowerInterval[] periods,PowerFixing[] rows,PowerIndex index)
    {
        if(index is null)throw new MarketDataException("settlement_index","An exact index specification is required.");
        Money.RequireKey(index.Definition);Money.RequireKey(index.Currency);Money.RequireKey(index.EnergyUnit);
        if(new[]{index.PriceType,index.Timing}.Any(string.IsNullOrWhiteSpace) ||
            index.EnergyUnit.Code!="megawatt_hour" || index.Definition.Revision!=index.Currency.Revision || index.Currency.Revision!=index.EnergyUnit.Revision)
            throw new MarketDataException("settlement_index","Every index specification and classification is required.");
        if(periods.Length==0 || periods.Length>110000 || rows.Length!=periods.Length)
            throw new MarketDataException("settlement_coverage","Supply exactly one fixing per selected interval.");
        var result=new Dictionary<DateTimeOffset,PowerFixing>();
        foreach(var row in rows)
        {
            if(row.Index!=index)throw new MarketDataException("settlement_index","Fixings must share the exact selected index, units and classifications.");
            if(row.Start.Offset!=TimeSpan.Zero||row.End.Offset!=TimeSpan.Zero||row.End<=row.Start||!result.TryAdd(row.Start,row))
                throw new MarketDataException("settlement_coverage","Fixing intervals must be distinct, ordered UTC boundaries.");
            if(row.Components is {} c && c.Energy+c.Congestion+c.Loss!=row.Total)
                throw new MarketDataException("lmp_components","LMP components must sum exactly to the total.");
        }
        PowerInterval? previous=null;
        foreach(var period in periods.OrderBy(p=>p.Start))
        {
            if(period.Start.Offset!=TimeSpan.Zero||period.End.Offset!=TimeSpan.Zero||period.End<=period.Start||
                previous is {} prior&&prior.End>period.Start || !result.TryGetValue(period.Start,out var fixing)||fixing.End!=period.End)
                throw new MarketDataException("settlement_coverage","Fixings must cover the selected UTC intervals without overlap.");
            previous=period;
        }
        return result;
    }
    public static PowerSettlementResult Calculate(PowerInterval[] periods,PowerFixing[] rows,PowerIndex index,ExactDecimal flatMegawatts,PowerSettlementPolicy policy)
    {
        policy.Validate();var fixings=Validate(periods,rows,index);
        BigInteger duration=0,priceDuration=0;
        foreach(var p in periods)
        {
            var ticks=(p.End-p.Start).Ticks; duration+=ticks;priceDuration+=Integer(fixings[p.Start].Total)*ticks;
        }
        var hourTicks=new BigInteger(TimeSpan.TicksPerHour);
        var numerator=priceDuration*Integer(flatMegawatts); var denominator=Scale*Scale*hourTicks;
        var gcd=BigInteger.GreatestCommonDivisor(numerator,denominator);
        return new(Rounded(duration,hourTicks,18),Rounded(duration*Integer(flatMegawatts),Scale*hourTicks,18),
            Rounded(priceDuration,Scale*duration,policy.PriceScale),Rounded(numerator,denominator,policy.AmountScale),
            (numerator/gcd).ToString(CultureInfo.InvariantCulture),(denominator/gcd).ToString(CultureInfo.InvariantCulture),index,policy);
    }
    // Hour grouping uses actual UTC intervals, preserving the repeated local hour.
    // This is a diagnostic for an explicitly flat-within-hour quantity, not a
    // substitute for a contractually named published hourly index.
    public static Dictionary<DateTimeOffset,string> Hourly(PowerInterval[] periods,PowerFixing[] rows,PowerIndex index,PowerSettlementPolicy policy)
    {
        policy.Validate();var fixings=Validate(periods,rows,index);
        return periods.GroupBy(p=>new DateTimeOffset(p.Start.Year,p.Start.Month,p.Start.Day,p.Start.Hour,0,0,TimeSpan.Zero)).ToDictionary(g=>g.Key,g=>
        {
            if(g.Sum(p=>(p.End-p.Start).Ticks)!=TimeSpan.TicksPerHour ||g.Any(p=>p.Start<g.Key||p.End>g.Key.AddHours(1)))
                throw new MarketDataException("settlement_hour","Hourly diagnostics require full, aligned UTC hours.");
            BigInteger sum=0;foreach(var p in g)sum+=Integer(fixings[p.Start].Total)*(p.End-p.Start).Ticks;
            return Rounded(sum,Scale*TimeSpan.TicksPerHour,policy.PriceScale);
        });
    }
}
