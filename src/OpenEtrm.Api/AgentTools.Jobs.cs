using System.Collections.Immutable;
using System.Text.Json.Nodes;
using Npgsql;
using NpgsqlTypes;

namespace OpenEtrm.Api;

// Jobs & Infrastructure (docs/devops-assistant.md §2–§3, D239): the jobs the turn's delegator owns, with each job's runs,
// audit actions and command receipts, read in the agent's request context under ReadJobs alone. The database decides
// whose jobs they are, so another person's job reads like an unknown one, a job manager's included.
public sealed partial class AgentTools
{
    static AgentTool JobTool=>Tool("read_jobs",
        $$$"""
        {"type":"object","properties":{"view":{"type":"string","enum":["jobs","history"]},
         "job":{"type":["string","null"],"pattern":"{{{Uuid}}}"},
         "page":{"type":["integer","null"],"minimum":0,"maximum":10000},
         "before":{"type":["integer","null"],"minimum":1}},
         "required":["view","job","page","before"],"additionalProperties":false}
        """,["ReadJobs"]);

    static ImmutableArray<ReadAccess> JobAccess(PreviewManifest _)=>[new("job_access",null,"ReadJobs")];

    static ToolCall ParseJobs(ToolInput members)
    {
        members.Exactly("view","job","page","before");
        if(members.Choice("view","jobs","history")=="jobs")
        {
            members.Null("job","before");
            return new(Operations["jobs.list_v1"],new JobListArguments((int)members.Whole("page",0,10000)));
        }
        members.Null("page");
        return new(Operations["jobs.history_v1"],new JobHistoryArguments(members.Id("job"),members.OptionalWhole("before",1,long.MaxValue)));
    }

    static async Task<ToolResult> Jobs(NpgsqlConnection connection,JobListArguments list,CancellationToken ct)
    {
        var result=await JobRead(connection,"SELECT automation.owned_jobs($1)::text",ct,new NpgsqlParameter{Value=list.Page,NpgsqlDbType=NpgsqlDbType.Integer});
        return new(result,result["jobs"]!.AsArray().Count,false);
    }

    static async Task<ToolResult> JobHistory(NpgsqlConnection connection,JobHistoryArguments job,CancellationToken ct)
    {
        var result=await JobRead(connection,"SELECT automation.owned_job_history($1,$2)::text",ct,
            new NpgsqlParameter{Value=job.Job,NpgsqlDbType=NpgsqlDbType.Uuid},
            new NpgsqlParameter{Value=(object?)job.Before??DBNull.Value,NpgsqlDbType=NpgsqlDbType.Bigint});
        return new(result,1+new[]{"runs","audit","commands"}.Sum(name=>result[name]!.AsArray().Count),false);
    }

    static async Task<JsonObject> JobRead(NpgsqlConnection connection,string sql,CancellationToken ct,params NpgsqlParameter[] parameters)
    {
        await using var command=new NpgsqlCommand(sql,connection);
        command.Parameters.AddRange(parameters);
        return JsonNode.Parse((string)(await command.ExecuteScalarAsync(ct))!)!.AsObject();
    }
}
