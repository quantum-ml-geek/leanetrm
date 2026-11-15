using OpenEtrm.Api;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Trading;

internal static class AsyncReadVisibilityChecks
{
    internal static async Task Run()
    {
        var one=Guid.NewGuid();var two=Guid.NewGuid();var nested=Guid.NewGuid();var revision=Guid.NewGuid();
        var started=0;var together=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        async Task<AsyncReadVisibilityProof> Worker(Guid own)
        {
            using var visibility=new AsyncReadVisibility();AsyncReadVisibility.ReferenceCatalog(own);
            using(var child=new AsyncReadVisibility()){AsyncReadVisibility.ReferenceCatalog(nested);if(child.Seal().Catalogs.Single()!=nested)throw new Exception("Nested visibility belongs to its own operation.");}
            AsyncReadVisibility.ReferenceVersion(own,revision);
            if(Interlocked.Increment(ref started)==2)together.SetResult();await together.Task;
            return visibility.Seal();
        }
        var proofs=await Task.WhenAll(Task.Run(()=>Worker(one)),Task.Run(()=>Worker(two)));
        if(proofs[0].Versions.Single().Catalog!=one||proofs[1].Versions.Single().Catalog!=two||proofs.Any(p=>p.Catalogs.Contains(nested)))
            throw new Exception("Concurrent workers must never inherit another read's source authority evidence.");
        using(var visibility=new AsyncReadVisibility())
        {
            AsyncReadVisibility.ReferenceCatalog(one);var sealedProof=visibility.Seal();AsyncReadVisibility.ReferenceCatalog(two);
            if(sealedProof.Catalogs.Length!=1||sealedProof.Catalogs[0]!=one)throw new Exception("Publication evidence must be immutable after capture.");
        }
        using(var empty=new AsyncReadVisibility())if(!empty.Seal().Catalogs.IsEmpty)throw new Exception("Disposing a worker must restore and clear ambient visibility.");
        using(var visibility=new AsyncReadVisibility())
        {
            var key=new ReferenceKey(new(one,revision),"synthetic_calendar");var publication=new CalendarPublicationProof(two,7,DateTimeOffset.Parse("2020-01-01T00:00:00Z"));
            AsyncReadVisibility.Calendar(key,publication);AsyncReadVisibility.Calendar(key,publication);
            var captured=visibility.Seal().Calendars.Single();
            if(captured.Reference!=key||captured.Publication!=publication)throw new Exception("Calendar authority must retain its exact independent publication source, without a general reference-version substitute.");
            var at=DateTimeOffset.Parse("2020-01-01T00:00:00Z");
            AsyncReadVisibility.Instrument(one,two,nested,at,3);
            var instrument=visibility.Seal().Instruments.Single();
            if(instrument.Catalog!=one||instrument.Id!=two||instrument.Context!=nested||instrument.AsOf!=at||instrument.Members!=3)
                throw new Exception("Retained schedule source authority must be rechecked at the exact instrument context and complete original membership set.");
        }
    }
}
