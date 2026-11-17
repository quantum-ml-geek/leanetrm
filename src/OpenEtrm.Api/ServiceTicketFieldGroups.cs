namespace OpenEtrm.Api;

// These are presentation partitions of existing fields, not new contract terms.
internal static class ServiceTicketFieldGroups
{
    internal const string Agreement="agreement",Principal="principal",Custody="custody",Rights="rights",Fee="fee";
    static TicketFieldGroup Group(TicketDescription description,string id,string label,string kind,params string[] fields)=>
        new(id,label,kind,[..fields.Where(fieldId=>description.TradeFields.Any(field=>field.Id==fieldId))]);
    static TicketDescription Describe(TicketDescription description,params TicketFieldGroup[] groups)=>
        TicketDescriptions.Validate(description with{FieldGroups=[..groups],SideGroupsRequired=true});

    internal static TicketDescription ParkLoan(TicketDescription d,bool selected)=>Describe(d,
        Group(d,Agreement,"Agreement and parties","agreement","profile","service_kind","perspective","book","legal_entity","counterparty"),
        Group(d,Principal,selected?"Principal Side terms":"Principal exchange terms",selected?"side_terms":"agreement",
            "owned_account","claim_account","principal_quantity","advance_at","return_at","title_policy","return_policy","return_timing","carrying"),
        Group(d,Fee,"Independent fee terms","independent_instrument_terms","fixed_fee_amount","fee_rate_amount","fee_basis","fee_time_basis",
            "fee_start_policy","fee_end_policy","fee_overdue_policy","fee_projection_policy","fee_unadvanced_policy","fee_determination_policy",
            "fee_accrual_through_at","fee_rounding_increment","fee_rounding_tie_rule","fee_rounding_stage","fee_due_at","fee_direction"));

    internal static TicketDescription ParkCustody(TicketDescription d)=>Describe(d,
        Group(d,Agreement,"Agreement and parties","agreement","profile","service_kind","perspective","reference_bundle","currency","book","legal_entity","counterparty"),
        Group(d,Custody,"Custody performance terms","agreement","point","quantity_specification","owned_account","custody_quantity","park_at","return_at",
            "title_policy","return_policy","return_timing","return_order","use_policy","loss_policy","physical_policy","plan_policy"),
        Group(d,Fee,"Independent fee terms","independent_instrument_terms","fixed_fee_amount","fee_due_at","fee_recognition","fee_direction"));

    internal static TicketDescription Transport(TicketDescription d)=>Describe(d,
        Group(d,Agreement,"Agreement and parties","agreement","profile","business_key","perspective","evidence","book","legal_entity","counterparty"),
        Group(d,Rights,"Rights Side terms","side_terms","entitlement","capacity_version","valuation_definition","valuation_reference_bundle","package_quantity",
            "currency","rights_valuation_policy","expiry_policy"),
        Group(d,Fee,"Independent fee terms","independent_instrument_terms","fee_profile","fixed_fee_amount","fee_direction","fee_due_at"));
}
