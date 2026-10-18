using Microsoft.AspNetCore.Antiforgery;
namespace OpenEtrm.Api;
public sealed record PreviewScope(string Name);
// Cookie material may be shared by the host; request tokens cannot cross examples.
public sealed class PreviewAntiforgeryScope : IAntiforgeryAdditionalDataProvider
{
 public string GetAdditionalData(HttpContext context)=>context.GetEndpoint()?.Metadata.GetMetadata<PreviewScope>()?.Name??"host";
 public bool ValidateAdditionalData(HttpContext context,string additionalData)=>additionalData==GetAdditionalData(context);
}
