using System.Collections.Immutable;
using OpenEtrm.Api;
using OpenEtrm.MarketData;

internal static class GasParkLoanTicketChecks
{
    static readonly Guid Id=Guid.Parse("00000000-0000-0000-0000-000000000101");
    static TicketDraft Draft()=>new(GasParkLoanTicket.Product,1,new Dictionary<string,string>{
        ["book"]=Id.ToString(),["legal_entity"]=$"{Id}@1",["counterparty"]=$"{Id}@2",
        ["profile"]="physical_gas_park_loan_v1",["service_kind"]="loan",["perspective"]="customer",
        ["owned_account"]=Id.ToString(),["claim_account"]="none",["principal_quantity"]="720",
        ["advance_at"]="2027-01-05T09:00:00Z",["return_at"]="2027-01-20T09:00:00Z",
        ["title_policy"]="fungible_gas_title_transfer_return_v1",["return_policy"]="same_quantity_partial_returns_v1",
        ["return_timing"]="accepted_advance_then_returns_v1",["carrying"]="nominal_mark_v1",
        ["fixed_fee_amount"]="12.50",["fee_direction"]="receive",["fee_due_at"]="2027-01-22T09:00:00Z"
    }.ToImmutableDictionary(),[]);
    static GasParkLoanBooking Map(TicketDraft draft)=>GasParkLoanTicket.Request(draft,Id,Id,"current",Id,Id);
    public static void Run()
    {
        void Check(bool ok,string message){if(!ok)throw new Exception(message);}
        void Reject(TicketDraft draft,string field)
        {
            try{Map(draft);}catch(TicketFieldException e)when(e.Field==field){return;}
            throw new Exception($"Expected explicit field refusal: {field}");
        }
        var d=Draft();
        Check(GasParkLoanTicket.Description.Product=="physical_gas_park_loan"&&GasParkLoanTicket.Description.Sides.IsEmpty,"A separate profile must use managed terms without a pretend physical Side composer.");
        var mapped=Map(d);
        Check(mapped.Quantity=="720"&&mapped.FixedFeeAmount=="12.5"&&mapped.FeeDirection=="receive","Absolute fixed fee must not be scaled by principal or direction inferred from commercial role.");
        Check(mapped.ClaimAccountId is null,"Explicit none retains no provider claim account.");
        Reject(d with{Trade=d.Trade.Remove("profile")},"profile");
        Reject(d with{Trade=d.Trade.Remove("carrying")},"carrying");
        Reject(d with{Trade=d.Trade.Remove("fee_direction")},"fee_direction");
        Reject(d with{Trade=d.Trade.SetItem("fixed_fee_amount","-12.5")},"fixed_fee_amount");
        Reject(d with{Trade=d.Trade.SetItem("advance_at","2027-01-05T09:00:00")},"advance_at");
        Reject(d with{Trade=d.Trade.SetItem("return_at","2027-01-04T09:00:00Z")},"return_at");
        Reject(d with{Trade=d.Trade.SetItem("perspective","provider")},"claim_account");
        Reject(d with{Trade=d.Trade.SetItem("claim_account",Id.ToString())},"claim_account");
        Reject(d with{Trade=d.Trade.SetItem("fee_due_at","none")},"fee_due_at");
        Reject(d with{Trade=d.Trade.SetItem("fee_due_at","2027-01-05T08:59:59.999999Z")},"fee_due_at");
        var zero=Map(d with{Trade=d.Trade.SetItem("fixed_fee_amount","0").SetItem("fee_due_at","none").SetItem("fee_direction","pay")});
        Check(zero.FeeDueAt is null&&zero.FeeDirection=="pay","Zero fee preserves the explicit direction and not-applicable date.");
        Reject(d with{Trade=d.Trade.SetItem("inferred_price","3")},"inferred_price");
        Console.WriteLine("PASS Park and Loan explicit ticket terms and independent fixed fee");
    }
}
