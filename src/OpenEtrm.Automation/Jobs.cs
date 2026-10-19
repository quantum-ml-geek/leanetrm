using System.Text.Json;
using System.Text.Json.Serialization;
using Npgsql;
using NpgsqlTypes;

namespace OpenEtrm.Automation;

public sealed class AutomationException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record JobCreate(Guid RequestId, string Name, string Operation, DateTimeOffset DueAt,
    DateTimeOffset ExpiresAt, [property: JsonRequired] int? IntervalSeconds, string TimeZone, string Misfire, string Overlap,
    int TimeoutSeconds, int MaximumAttempts, [property: JsonRequired] Guid? ProfileId, [property: JsonRequired] int? ProfileVersion)
{
    public void Validate()
    {
        if (RequestId == Guid.Empty || string.IsNullOrWhiteSpace(Name) || Name.Length > 80 ||
            Operation is not ("worker_check" or "swarm_job") || DueAt.Offset != TimeSpan.Zero ||
            ExpiresAt.Offset != TimeSpan.Zero || DueAt == default || ExpiresAt <= DueAt ||
            IntervalSeconds is < 60 or > 31536000 || TimeZone != "UTC" || Misfire != "run_once" ||
            Overlap != "forbid" || TimeoutSeconds is < 1 or > 3600 || MaximumAttempts is < 1 or > 3 ||
            (Operation == "worker_check" ? ProfileId is not null || ProfileVersion is not null :
                ProfileId is null || ProfileId == Guid.Empty || ProfileVersion is null or < 1))
            throw new AutomationException("job_input", "Supply a complete supported job contract, explicit UTC times and execution limits.");
    }
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record JobControl(Guid RequestId, Guid Id, string Action, int ExpectedVersion)
{
    public void Validate()
    {
        if (RequestId == Guid.Empty || Id == Guid.Empty || ExpectedVersion < 1 || Action is not ("pause" or "resume" or "cancel" or "run_again"))
            throw new AutomationException("job_input", "Choose an available action on the current job version.");
    }
}

public static class ScheduleTiming
{
    public static DateTimeOffset? Next(DateTimeOffset due, int? intervalSeconds, DateTimeOffset observed)
    {
        if (intervalSeconds is null) return null;
        if (intervalSeconds is < 60 or > 31536000 || observed < due)
            throw new AutomationException("job_input", "The recurrence must have an explicit supported interval and observation time.");
        var interval = checked((long)intervalSeconds.Value * TimeSpan.TicksPerSecond);
        var periods = checked((observed.UtcTicks - due.UtcTicks) / interval + 1);
        return due.AddTicks(checked(periods * interval));
    }
}

public static class JobOperations
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    public static async Task<JsonElement> List(NpgsqlConnection connection, CancellationToken ct, int page = 0)
    {
        if (page is < 0 or > 10000) throw new AutomationException("job_input", "Choose an available job page.");
        var jobs = await Read(connection, "SELECT automation.job_list($1::integer)::text", page.ToString(System.Globalization.CultureInfo.InvariantCulture), ct);
        var infrastructure = await Read(connection, "SELECT automation.infrastructure_directory()::text", null, ct);
        var result = System.Text.Json.Nodes.JsonNode.Parse(jobs.GetRawText())!.AsObject();
        result["infrastructure"] = System.Text.Json.Nodes.JsonNode.Parse(infrastructure.GetRawText());
        return JsonSerializer.SerializeToElement(result);
    }
    public static Task<JsonElement> NodeAction(NpgsqlConnection connection, NodeCommand request, CancellationToken ct)
    {
        request.Validate();
        return Read(connection, "SELECT automation.request_node_command($1::jsonb)::text", JsonSerializer.Serialize(request, Json), ct);
    }
    public static Task<JsonElement> ResolveNode(NpgsqlConnection connection, NodeResolution request, CancellationToken ct)
    {
        request.Validate();
        return Read(connection, "SELECT automation.resolve_node_command($1::jsonb)::text", JsonSerializer.Serialize(request, Json), ct);
    }

    public static Task<JsonElement> Create(NpgsqlConnection connection, JobCreate request, CancellationToken ct)
    {
        request.Validate();
        return Read(connection, "SELECT automation.create_job($1::jsonb)::text", JsonSerializer.Serialize(request, Json), ct);
    }

    public static Task<JsonElement> Control(NpgsqlConnection connection, JobControl request, CancellationToken ct)
    {
        request.Validate();
        return Read(connection, "SELECT automation.control_job($1::jsonb)::text", JsonSerializer.Serialize(request, Json), ct);
    }

    private static async Task<JsonElement> Read(NpgsqlConnection connection, string sql, string? request, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(sql, connection);
        if (request is not null) command.Parameters.AddWithValue(request);
        var result = (string?)await command.ExecuteScalarAsync(ct) ?? throw new AutomationException("job_outcome", "The job outcome was not returned.");
        using var document = JsonDocument.Parse(result);
        return document.RootElement.Clone();
    }
}

public sealed record JobClaim(Guid Id, Guid JobId, string Operation, long Fence, Guid WorkerId,
    DateTimeOffset LeaseUntil, DateTimeOffset DeadlineAt, DateTimeOffset DueAt, int? IntervalSeconds,
    JsonElement? Profile, string? ServiceId = null, bool LaunchPrepared = false, bool MustStop = false);

public sealed class JobWorkerStore(NpgsqlDataSource source)
{
    public async Task<JobClaim?> Claim(Guid workerId, int leaseSeconds, CancellationToken ct)
    {
        await using var command = source.CreateCommand("SELECT automation.claim_next($1,$2)::text");
        command.Parameters.AddWithValue(workerId); command.Parameters.AddWithValue(leaseSeconds);
        var value = await command.ExecuteScalarAsync(ct);
        return value is string json ? JsonSerializer.Deserialize<JobClaim>(json, new JsonSerializerOptions(JsonSerializerDefaults.Web))
            ?? throw new AutomationException("job_protocol", "The worker claim is incomplete.") : null;
    }

    public async Task Finish(JobClaim claim, bool succeeded, string? error, CancellationToken ct)
    {
        // Recomputing the next due instant never repeats the executed work.
        for (var retry = 0; ; retry++)
        {
            await using var connection = await source.OpenConnectionAsync(ct);
            await using var clock = new NpgsqlCommand("SELECT clock_timestamp()", connection);
            var observed = new DateTimeOffset((DateTime)(await clock.ExecuteScalarAsync(ct))!);
            var next = ScheduleTiming.Next(claim.DueAt, claim.IntervalSeconds, observed);
            await using var command = new NpgsqlCommand("SELECT automation.finish_run($1,$2,$3,$4,$5,$6)", connection);
            command.Parameters.AddWithValue(claim.Id); command.Parameters.AddWithValue(claim.Fence);
            command.Parameters.AddWithValue(claim.WorkerId); command.Parameters.AddWithValue(succeeded);
            command.Parameters.Add(new NpgsqlParameter { NpgsqlDbType = NpgsqlDbType.Text, Value = (object?)error ?? DBNull.Value });
            command.Parameters.Add(new NpgsqlParameter { NpgsqlDbType = NpgsqlDbType.TimestampTz, Value = (object?)next ?? DBNull.Value });
            try { await command.ExecuteNonQueryAsync(ct); return; }
            catch (PostgresException e) when (e.MessageText == "job_clock" && retry < 2) { }
        }
    }
}
