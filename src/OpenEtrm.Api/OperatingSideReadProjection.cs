namespace OpenEtrm.Api;

internal static class OperatingSideReadProjection
{
    internal static async Task<T> Run<T>(Func<Task<T>> read,Func<AsyncReadVisibilityProof,Task> publish)
    {
        using var visibility=new AsyncReadVisibility();
        var result=await read();await publish(visibility.Seal());return result;
    }
}
