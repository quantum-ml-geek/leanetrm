using System.Text.Json;
using OpenEtrm.Api;

internal static class AsyncReadChecks
{
    internal static async Task Run()
    {
        var channelId=Guid.NewGuid();var snapshot=Guid.NewGuid();
        var request=new AsyncReadRequest(channelId,Guid.NewGuid(),"curve.evaluate.v1",JsonSerializer.SerializeToElement(new{snapshotId=snapshot,curve="synthetic",includeWorkspace=true}));
        AsyncReadPlan Plan(AsyncReadRequest selected,Func<CancellationToken,Task<object>> work)=>new(AsyncReadContract.Decode(selected),async ct=>new(await work(ct),(_,_)=>Task.CompletedTask));
        await using var channel=new AsyncReadChannel(channelId,CancellationToken.None);
        Refused("async_channel_not_ready",()=>channel.Submit(request,Plan(request,_=>Task.FromResult<object>(new {}))));
        channel.Connect();
        var both=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);var release=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);var calls=0;
        async Task<object> Work(CancellationToken ct){if(Interlocked.Increment(ref calls)==2)both.SetResult();await release.Task.WaitAsync(ct);return new{value="synthetic"};}
        channel.Submit(request,Plan(request,Work));
        var reordered=request with{Body=JsonSerializer.SerializeToElement(new{curve="synthetic",includeWorkspace=true,snapshotId=snapshot})};
        channel.Submit(reordered,Plan(reordered,Work));
        var conflict=request with{Body=JsonSerializer.SerializeToElement(new{snapshotId=snapshot,curve="different",includeWorkspace=true})};
        Refused("async_request_conflict",()=>channel.Submit(conflict,Plan(conflict,Work)));
        var second=request with{RequestId=Guid.NewGuid()};channel.Submit(second,Plan(second,Work));
        await both.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var third=request with{RequestId=Guid.NewGuid()};Refused("async_busy",()=>channel.Submit(third,Plan(third,Work)));
        release.SetResult();using var timeout=new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var a=await channel.Read(timeout.Token);var b=await channel.Read(timeout.Token);
        if(calls!=2||a.Request.RequestId==b.Request.RequestId||a.State!="completed"||b.State!="completed")throw new Exception("Independent reads must complete once with exact request identities.");
        channel.Submit(request,Plan(request,Work));if(calls!=2)throw new Exception("A completed retry must not repeat work.");
        var entered=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);var cancelled=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);var drain=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        channel.Submit(third,Plan(third,async ct=>{entered.SetResult();try{await Task.Delay(Timeout.Infinite,ct);}catch(OperationCanceledException){cancelled.SetResult();await drain.Task;throw;}return new {};}));
        await entered.Task;var firstDisposal=channel.DisposeAsync().AsTask();await cancelled.Task;
        var secondDisposal=channel.DisposeAsync().AsTask();if(secondDisposal.IsCompleted){drain.SetResult();await firstDisposal;throw new Exception("All replacement and disconnect callers must await the same worker drain.");}
        drain.SetResult();await Task.WhenAll(firstDisposal,secondDisposal);
        if(!channel.Stopping.IsCancellationRequested)throw new Exception("Retired channels retain a safe cancelled lifetime token.");
        Refused("async_channel_unavailable",()=>channel.Submit(request,Plan(request,Work)));
        await AsyncReadVisibilityChecks.Run();
        Console.WriteLine("PASS async reads: concurrency, normalized retries, conflicts, bounds, exact correlation, shared cancellation drain and visibility isolation");
    }
    static void Refused(string code,Action action){try{action();}catch(AsyncReadException error)when(error.Code==code){return;}throw new Exception("Expected async refusal "+code);}
}
