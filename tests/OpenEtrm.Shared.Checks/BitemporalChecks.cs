using OpenEtrm.Shared.Temporal;

internal static class BitemporalChecks
{
    public static int Run()
    {
        var from=new DateOnly(2021,1,1);var to=new DateOnly(2021,4,1);
        var known=new DateTimeOffset(2026,10,17,12,0,0,TimeSpan.Zero);
        var range=new BitemporalRange(from,to,known,known.AddHours(1));
        if(!range.Contains(from,known)||range.Contains(to,known)||range.Contains(from,known.AddHours(1))||range.Contains(from.AddDays(-1),known))throw new Exception("Temporal boundaries are not half-open.");
        void Reject(Action work){try{work();}catch(TemporalException e)when(e.Code=="temporal_interval"){return;}throw new Exception("Expected explicit interval rejection.");}
        Reject(()=>new BitemporalRange(to,from,known,known.AddHours(1)));
        Reject(()=>new BitemporalRange(from,to,known.AddHours(1),known));
        Reject(()=>new BitemporalRange(from,to,known.ToOffset(TimeSpan.FromHours(1)),known.AddHours(1)));
        Console.WriteLine("4 bitemporal interval checks passed.");return 4;
    }
}
