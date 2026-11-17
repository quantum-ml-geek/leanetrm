using System.Collections.Immutable;
using Npgsql;

namespace OpenEtrm.Api;

// The authorization a read's answer waits for, in one fresh identity transaction: the read's permissions and the
// sign-in, the read's own recheck of what it read, the permissions and sign-in again, then the publication itself.
// Nothing here is cached; an ordinary route and the response channel both disclose a result only through it.
internal static class ReadAuthority
{
    internal static Task Require(PreviewDatabase database,string profile,string? hostedDigest,ImmutableArray<string> permissions,
        CancellationToken ct,Func<NpgsqlConnection,CancellationToken,Task>? recheck=null,Func<CancellationToken,Task>? publish=null)=>
        database.WithIdentity(profile,null,async(connection,t)=>
        {
            async Task Rights()
            {
                foreach(var permission in permissions)
                    if(!await PreviewDatabase.HasPermission(connection,permission,t))throw new PreviewDeniedException();
                await database.RequireSignedIn(connection,t);
            }
            await Rights();
            if(recheck is not null)await recheck(connection,t);
            await Rights();
            if(publish is not null)await publish(t);
            return true;
        },ct,hostedDigest:hostedDigest);
}
