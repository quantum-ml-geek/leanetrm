using System.Text.Json.Serialization;

namespace OpenEtrm.Api;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record RecForwardTermsInput(
    [property:JsonRequired]Guid DefinitionRevisionId,
    [property:JsonRequired]string AssignmentCode,
    [property:JsonRequired]string ProductCode,
    [property:JsonRequired]string VintageFrom,
    [property:JsonRequired]string VintageTo,
    [property:JsonRequired]string DeliveryFrom,
    [property:JsonRequired]string DeliveryTo,
    [property:JsonRequired]string Quantity,
    [property:JsonRequired]string PhysicalDirection,
    [property:JsonRequired]string ConsiderationDirection,
    [property:JsonRequired]StructuredPowerPriceInput Consideration,
    [property:JsonRequired]PpaPaymentInput PaymentRule,
    [property:JsonRequired]SideCalendarPolicyInput CalendarPolicy,
    [property:JsonRequired]bool Discounting);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record RecForwardCatalogRequest([property:JsonRequired]FuturesReadRequest Context);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record RecForwardPreviewRequest([property:JsonRequired]FuturesReadRequest Context,
    [property:JsonRequired]RecForwardTermsInput Terms);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record RecForwardBookRequest([property:JsonRequired]FuturesReadRequest Context,
    [property:JsonRequired]Guid OperationId,[property:JsonRequired]Guid TradeId,[property:JsonRequired]string OwnerId,
    [property:JsonRequired]Guid BookId,[property:JsonRequired]string TradeDate,
    [property:JsonRequired]Guid LegalEntityId,[property:JsonRequired]int LegalEntityRevision,
    [property:JsonRequired]Guid CounterpartyId,[property:JsonRequired]int CounterpartyRevision,
    [property:JsonRequired]RecForwardTermsInput Terms);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record RecForwardReadRequest([property:JsonRequired]FuturesReadRequest Context,
    [property:JsonRequired]Guid TradeId,[property:JsonRequired]int Revision);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record RecForwardStatusRequest([property:JsonRequired]Guid OperationId,
    [property:JsonRequired]string OwnerId);
