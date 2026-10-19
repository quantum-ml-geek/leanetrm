using System.Collections.Immutable;
using System.Security.Cryptography;
using System.Text;
using Npgsql;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.CustomCurves;

namespace OpenEtrm.Api;

// This qualified transformation has no database-reading capability: its complete
// data input is the supplied panel. Changing this body requires a new version.
public static class RegisteredCurveSql
{
    public const string Code="sql_mean_dates_v1";
    public const string Sql="""
SELECT position,sum(coefficient::numeric)::text,count(*)::integer
FROM unnest($1::integer[],$2::text[]) AS supplied_panel(position,coefficient)
GROUP BY position ORDER BY position
""";
    public static string Sha256=>Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(Sql)));
    public static object[] Catalog=>[new{code=Code,name="Historical mean · SQL",implementation=Code,sha256=Sha256,sql=Sql,
        description="Average the supplied historical samples for each tenor. All dates, units and dependencies come from the graph.",
        inputContract="raw_sample_position_scaled_integer_v1",outputContract="position_sum_and_count_v1"}];
    public static async Task<ImmutableArray<RecipeSqlSum>> Execute(NpgsqlConnection connection,string code,ImmutableArray<RecipeSqlValue> values,CancellationToken ct)
    {
        if(code!=Code||values.IsDefaultOrEmpty||values.Length>50000)throw new MarketDataException("recipe_transform","Choose the qualified SQL transformation and a bounded nonempty panel.");
        await using var command=ScheduleStore.Command(connection,Sql,values.Select(v=>v.Position).ToArray(),values.Select(v=>v.Coefficient).ToArray());
        var result=ImmutableArray.CreateBuilder<RecipeSqlSum>();
        await using var reader=await command.ExecuteReaderAsync(ct);
        while(await reader.ReadAsync(ct))result.Add(new(reader.GetInt32(0),reader.GetString(1),reader.GetInt32(2)));
        return result.ToImmutable();
    }
}
