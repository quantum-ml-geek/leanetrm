using System.Text.Json;
using OpenEtrm.Api;
using OpenEtrm.MarketData;

// An ordinary read captures under the session gate, executes without it and authorizes again under it before answering.
internal static class UngatedReadChecks
{
    static readonly TimeSpan Limit=TimeSpan.FromSeconds(5);
    static readonly ReadInput Input=AsyncReadContract.Decode(new(Guid.NewGuid(),Guid.NewGuid(),"curve.evaluate.v1",
        JsonSerializer.SerializeToElement(new{snapshotId=Guid.NewGuid(),curve="synthetic"})));
    static PreviewSession Session(HostedSignIn? signIn=null)=>new(new PreviewManifest("local-synthetic-preview",Guid.NewGuid(),Guid.NewGuid(),
        Guid.NewGuid(),Guid.NewGuid(),Guid.NewGuid(),Guid.NewGuid(),[],null,FuturesConvention:"contract_lot_execution_pnl_v2"),signIn){Profile="trader"};
    static ReadPlan Plan(Func<CancellationToken,Task<object>> work)=>new(Input,async ct=>new(await work(ct),(_,_)=>Task.CompletedTask));
    static Task Allowed(string profile,ReadPlan plan,ReadOutcome outcome,CancellationToken ct)=>Task.CompletedTask;
    static TaskCompletionSource Signal()=>new(TaskCreationOptions.RunContinuationsAsynchronously);
    static bool Free(PreviewSession session)
    {
        if(!session.Gate.Wait(0))return false;
        session.Gate.Release();return session.Reads.CurrentCount==PreviewSession.MaximumReads;
    }
    static async Task Refused<T>(Task<object> read,string message) where T:Exception
    {
        try{await read.WaitAsync(Limit);}
        catch(T){return;}
        throw new Exception(message);
    }

    internal static async Task Run()
    {
        await ExecutesOutsideTheGate();
        await ThirdReadWaits();
        await ChangedProfileRefuses();
        await EndedSignInRefuses();
        await FailuresRelease();
        await CancelledWaitDoesNotCapture();
        await MissingProfileRefuses();
        Console.WriteLine("PASS ungated reads: gate released while executing, publication authorized under the gate, two per session, profile and sign-in fences, release on failure and cancellation");
    }
    static async Task ExecutesOutsideTheGate()
    {
        var session=Session();var entered=Signal();var release=Signal();var value=new{value="synthetic"};
        var capturedUnderGate=false;var authorizedUnderGate=false;var authorized=0;var order=new List<string>();
        var read=UngatedRead.Run(session,captured=>
        {
            capturedUnderGate=ReferenceEquals(captured,session)&&session.Gate.CurrentCount==0;
            return Plan(async ct=>{order.Add("execute");entered.SetResult();await release.Task.WaitAsync(ct);return value;});
        },(profile,plan,outcome,ct)=>
        {
            authorized++;order.Add("authorize");
            authorizedUnderGate=session.Gate.CurrentCount==0&&profile=="trader"&&ReferenceEquals(plan.Input,Input)&&ReferenceEquals(outcome.Value,value);
            return Task.CompletedTask;
        },CancellationToken.None);
        await entered.Task.WaitAsync(Limit);
        if(!session.Gate.Wait(0))throw new Exception("An executing read must not hold the session gate.");
        session.Gate.Release();release.SetResult();
        if(!ReferenceEquals(await read.WaitAsync(Limit),value)||!capturedUnderGate)throw new Exception("A read must capture under the session gate and return its plan's value.");
        if(authorized!=1||!authorizedUnderGate||string.Join(',',order)!="execute,authorize")throw new Exception("Publication must authorize once under the session gate.");
        if(!Free(session))throw new Exception("A completed read must release its gate and slot.");
    }
    static async Task ThirdReadWaits()
    {
        var session=Session();var captures=0;var executing=0;var both=Signal();
        var releases=new[]{Signal(),Signal(),Signal()};
        Task<object> Start(int number)=>UngatedRead.Run(session,_=>
        {
            Interlocked.Increment(ref captures);
            return Plan(async ct=>{if(Interlocked.Increment(ref executing)==PreviewSession.MaximumReads)both.SetResult();await releases[number].Task.WaitAsync(ct);return number;});
        },Allowed,CancellationToken.None);
        var first=Start(0);var second=Start(1);await both.Task.WaitAsync(Limit);
        var third=Start(2);await Task.Delay(100);
        if(captures!=2||third.IsCompleted)throw new Exception("A third read must wait for a slot.");
        releases[0].SetResult();await first.WaitAsync(Limit);
        releases[2].SetResult();releases[1].SetResult();
        await second.WaitAsync(Limit);
        if((int)await third.WaitAsync(Limit)!=2||captures!=3||!Free(session))throw new Exception("A third read must wait for a slot, then complete.");
    }
    static async Task ChangedProfileRefuses()
    {
        var session=Session();var entered=Signal();var release=Signal();var authorized=false;
        var read=UngatedRead.Run(session,_=>Plan(async ct=>{entered.SetResult();await release.Task.WaitAsync(ct);return new{};}),
            (_,_,_,_)=>{authorized=true;return Task.CompletedTask;},CancellationToken.None);
        await entered.Task.WaitAsync(Limit);
        await session.Gate.WaitAsync();session.Profile="risk";session.Gate.Release();release.SetResult();
        await Refused<PreviewDeniedException>(read,"A read must not answer after its profile changed.");
        if(authorized||!Free(session))throw new Exception("A read must not answer after its profile changed.");
    }
    static async Task EndedSignInRefuses()
    {
        var session=Session(new("synthetic",DateTimeOffset.UtcNow.AddMilliseconds(150)));var authorized=false;
        var read=UngatedRead.Run(session,_=>Plan(async ct=>{await Task.Delay(400,ct);return new{};}),
            (_,_,_,_)=>{authorized=true;return Task.CompletedTask;},CancellationToken.None);
        await Refused<PreviewDeniedException>(read,"A read must not answer after its sign-in ended.");
        if(authorized||!Free(session))throw new Exception("A read must not answer after its sign-in ended.");
    }
    static async Task FailuresRelease()
    {
        const string message="A failed read must release its gate and slot.";
        var session=Session();
        await Refused<InvalidOperationException>(UngatedRead.Run(session,_=>throw new InvalidOperationException("capture"),Allowed,CancellationToken.None),message);
        if(!Free(session))throw new Exception(message);
        await Refused<InvalidOperationException>(UngatedRead.Run(session,_=>Plan(_=>throw new InvalidOperationException("execute")),Allowed,CancellationToken.None),message);
        if(!Free(session))throw new Exception(message);
        await Refused<InvalidOperationException>(UngatedRead.Run(session,_=>Plan(_=>Task.FromResult<object>(new{})),
            (_,_,_,_)=>throw new InvalidOperationException("authorize"),CancellationToken.None),message);
        if(!Free(session))throw new Exception(message);
    }
    static async Task CancelledWaitDoesNotCapture()
    {
        var session=Session();var captures=0;var executing=0;var both=Signal();var release=Signal();
        Task<object> Start(CancellationToken ct)=>UngatedRead.Run(session,_=>
        {
            Interlocked.Increment(ref captures);
            return Plan(async token=>{if(Interlocked.Increment(ref executing)==PreviewSession.MaximumReads)both.SetResult();await release.Task.WaitAsync(token);return new{};});
        },Allowed,ct);
        var first=Start(CancellationToken.None);var second=Start(CancellationToken.None);await both.Task.WaitAsync(Limit);
        using var cancelled=new CancellationTokenSource();cancelled.Cancel();
        await Refused<OperationCanceledException>(Start(cancelled.Token),"A cancelled wait must not capture.");
        if(captures!=2)throw new Exception("A cancelled wait must not capture.");
        release.SetResult();await Task.WhenAll(first,second).WaitAsync(Limit);
        if(!Free(session))throw new Exception("A cancelled wait must leave the slots to the reads that hold them.");
    }
    static async Task MissingProfileRefuses()
    {
        var session=Session();session.Profile=null;var captured=false;
        await Refused<PreviewDeniedException>(UngatedRead.Run(session,_=>{captured=true;return Plan(_=>Task.FromResult<object>(new{}));},Allowed,CancellationToken.None),
            "A session without a profile cannot read.");
        if(captured||!Free(session))throw new Exception("A session without a profile cannot read.");
    }
}
