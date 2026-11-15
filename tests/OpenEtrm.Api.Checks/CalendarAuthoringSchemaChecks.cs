using System.Reflection;
using System.Text.Json.Nodes;
using OpenEtrm.Api;

internal static class CalendarAuthoringSchemaChecks
{
    private static void Endpoint<T>(T body) { }
    private static JsonNode Shape<T>()=>AssistantOperations.Schema(typeof(CalendarAuthoringSchemaChecks)
        .GetMethod(nameof(Endpoint),BindingFlags.Static|BindingFlags.NonPublic)!.MakeGenericMethod(typeof(T)))["body"]!;
    private static void Required(JsonNode shape,params string[] names)
    {
        foreach(var name in names)
            if(shape["required"] is not JsonArray required||!required.Any(n=>n?.GetValue<string>()==name))
                throw new Exception("Agent authoring schema omits required field "+name);
    }
    internal static void Run()
    {
        Required(Shape<SideCalendarPolicyInput>(),"implementation","delivery","observation","payment");
        Required(Shape<CalendarBindingInput>(),"applicable","calendar");
        Required(Shape<SwapFixedInput>(),"calendarPolicy");Required(Shape<SwapFloatingInput>(),"calendarPolicy");
        Required(Shape<SwapScheduledSideInput>(),"calendarPolicy");Required(Shape<TicketSideDraft>(),"calendarPolicy");
        Required(Shape<PhysicalLngWriteRequest>(),"deliveryCalendarPolicy","considerationCalendarPolicy");
        Required(Shape<PhysicalCrudeWriteRequest>(),"deliveryCalendarPolicy","considerationCalendarPolicy");
        Required(Shape<CrudeSetupPreviewRequest>(),"calendarPolicy");
        Required(Shape<PhysicalGasTerms>(),"deliveryCalendarPolicy","considerationCalendarPolicy");
        var fee=Shape<PhysicalCrudeWriteRequest>()["properties"]!["feeCalendarPolicy"]!;
        if(fee["requiredWhen"]?.GetValue<string>()!="handlingFee is present")throw new Exception("An optional fee must describe its explicit policy applicability.");
        foreach(var shape in new[]{Shape<SwapPaymentInput>(),Shape<SwapObservationScheduleInput>(),Shape<SwapPowerScheduleInput>(),Shape<PpaHoursInput>(),Shape<PpaPaymentInput>()})
            if(shape["properties"]!["calendar"]!["type"]?.GetValue<string>()!="null")throw new Exception("Rule schemas cannot offer independent nested calendars.");
        var period=Shape<SwapScheduledPeriodInput>()["properties"]!["fixed"]!;
        if(period["properties"]!["calendarPolicy"]!["type"]?.GetValue<string>()!="null")throw new Exception("Periods must use their owning Side's policy.");
        Console.WriteLine("PASS agent calendar authoring: required purposes, explicit applicability, optional fee, and Side-owned nested rules");
    }
}
