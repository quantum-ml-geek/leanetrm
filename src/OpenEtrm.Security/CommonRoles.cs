using System.Collections.Immutable;

namespace OpenEtrm.Security;

// Permission templates only: no automatic principal assignment or global scope.
public sealed record RoleTemplate(string Code, ImmutableHashSet<Permission> Permissions);
public static class CommonRoles
{
    private static RoleTemplate Template(string code, params Permission[] permissions) => new(code, permissions.ToImmutableHashSet());
    public static ImmutableArray<RoleTemplate> Templates { get; } =
    [
        Template("viewer", Permission.ReadMarketData),
        Template("trader", Permission.ReadMarketData, Permission.BookTrade, Permission.AmendTrade, Permission.CreateDelegations),
        Template("risk_analyst", Permission.ReadMarketData, Permission.RunValuation, Permission.RunScenario, Permission.CreateDelegations),
        Template("market_data_editor", Permission.ReadMarketData, Permission.WriteMarketDefinitions, Permission.ImportObservations,
            Permission.WriteReferenceData, Permission.CreateDelegations),
        Template("market_data_approver", Permission.ReadMarketData, Permission.SealMarketDefinitions, Permission.SealReferenceData,
            Permission.ApproveMarketData, Permission.PublishMarketData),
        Template("access_administrator", Permission.ManageIdentities, Permission.ManageAccess, Permission.CreateDelegations)
    ];
}
