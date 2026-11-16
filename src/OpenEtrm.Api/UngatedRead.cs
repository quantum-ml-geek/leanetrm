namespace OpenEtrm.Api;

// An ordinary read of a registered definition. The session gate covers only the capture of the session's selection
// and the authorization before the answer; the read's own database work holds neither the gate nor another request back.
internal static class UngatedRead
{
    internal static async Task<object> Run(PreviewSession session,Func<PreviewSession,ReadPlan> capture,
        Func<string,ReadPlan,ReadOutcome,CancellationToken,Task> authorize,CancellationToken ct)
    {
        await session.Reads.WaitAsync(ct);
        try
        {
            string profile;ReadPlan plan;
            await session.Gate.WaitAsync(ct);
            try
            {
                profile=session.Profile??throw new PreviewDeniedException();
                plan=capture(session);
            }
            finally{session.Gate.Release();}
            var outcome=await plan.Execute(ct);
            await session.Gate.WaitAsync(ct);
            try
            {
                // The capture is immutable; only the person the answer goes to can have changed since.
                if(DateTimeOffset.UtcNow>=session.Ends||session.Profile!=profile)throw new PreviewDeniedException();
                await authorize(profile,plan,outcome,ct);
                return outcome.Value;
            }
            finally{session.Gate.Release();}
        }
        finally{session.Reads.Release();}
    }
}
