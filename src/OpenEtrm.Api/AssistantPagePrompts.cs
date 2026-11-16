using System.Text.Json;
using System.Text.Json.Serialization;
using Npgsql;
using OpenEtrm.MarketData;

namespace OpenEtrm.Api;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record SavePagePromptRequest([property:JsonRequired]Guid OperationId,[property:JsonRequired]string Page,
    [property:JsonRequired]int ExpectedVersion,[property:JsonRequired]string Instructions);

static class AssistantPagePrompts
{
    public static async Task<object> Directory(NpgsqlConnection connection,CancellationToken ct)=>new
    {
        pages=new[]{new{id="application",name="Application",kind="application"}}
            .Concat(PageReports.All.Select(page=>new{id=page,name=PageReports.Name(page),kind="page"}))
            .Concat(AgentTools.Tools.Select(tool=>new{id="tool:"+tool.Name,name=tool.Name,kind="tool"}))
            .Concat(new[]{new{id="provider_test:instructions",name="Instructions",kind="provider_test"},new{id="provider_test:question",name="Question",kind="provider_test"}}),
        configuration=await ModelProviders.Read(connection,"SELECT assistant.page_prompt_directory()::text",[],ct)
    };
    public static Task<JsonElement> Save(NpgsqlConnection connection,SavePagePromptRequest body,CancellationToken ct)=>
        body.OperationId!=Guid.Empty&&body.Instructions is not null&&(body.Page is "application" or "provider_test:instructions" or "provider_test:question"||PageReports.All.Contains(body.Page)||AgentTools.Tools.Any(tool=>body.Page=="tool:"+tool.Name))
            ?ModelProviders.Read(connection,"SELECT assistant.save_page_prompt($1,$2,$3,$4)::text",[body.OperationId,body.Page,body.ExpectedVersion,body.Instructions],ct)
            :throw new MarketDataException("page_prompt_input","Choose a prompt scope and supply the complete prompt revision.");
}
