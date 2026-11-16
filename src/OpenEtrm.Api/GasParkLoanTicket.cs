using System.Collections.Immutable;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using OpenEtrm.MarketData;
using OpenEtrm.MarketData.Gas;
using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.Api;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record GasParkLoanBooking(Guid OperationId,Guid SnapshotId,Guid ContextId,Guid DefinitionRevisionId,
    string Convention,string KnowledgeMode,string Profile,Guid BookId,Guid LegalEntityId,int LegalEntityRevision,
    Guid CounterpartyId,int CounterpartyRevision,Guid OwnedAccountId,[property:JsonRequired]Guid? ClaimAccountId,
    string ServiceKind,string Perspective,string Quantity,DateTimeOffset AdvanceAt,DateTimeOffset ReturnAt,
    string TitlePolicy,string ReturnPolicy,string ReturnTiming,string Carrying,string FixedFeeAmount,string FeeDirection,
    [property:JsonRequired]DateTimeOffset? FeeDueAt);

public static class GasParkLoanTicket
{
    public const string Product="physical_gas_park_loan";
    public const string Measure="scheduled_plan_present_value_v1";
    public const string NoAccount="none";
    static TicketField Field(string id,string label,string meaning,string type="choice",string? choices=null,params string[] depends)=>
        new(id,label,meaning,type,null,"editable",true,null,type=="choice"?choices??id:null,[..depends],null,null,null);
    public static TicketDescription Description{get;}=TicketDescriptions.Validate(new(Product,1,"flow",
    [
        Field("profile","Contract profile","The installed title-transfer agreement and its qualified financial behavior."),
        Field("service_kind","Service","The commercial service being booked."),
        Field("perspective","Our perspective","Our customer or provider role under the selected service."),
        Field("owned_account","Inventory account","Exact title account defining point, quantity specification, currency and mark.",depends:["book","legal_entity","counterparty"]),
        Field("claim_account","Return claim account","An exact compatible operator account for a principal giver; explicitly not applicable for a receiver.",depends:["owned_account","service_kind","perspective","counterparty"]),
        Field("principal_quantity","Principal quantity","Absolute quantity advanced and owed back in the selected account's exact basis.","decimal"),
        Field("advance_at","Advance time","Earliest accepted title-transfer advance under this profile.","datetime"),
        Field("return_at","Return due","Due time for the principal; passing it does not settle the obligation.","datetime"),
        Field("title_policy","Title treatment","Explicit ownership treatment at accepted advance."),
        Field("return_policy","Return quantity rule","Equal quantity at the same point and basis, with partial returns."),
        Field("return_timing","Return timing","Returns follow the accepted advance; late performance remains recorded."),
        Field("carrying","Principal carrying","Explicit nominal carrying under the one-exact-mark profile."),
        Field("fixed_fee_amount","Fixed fee","Absolute fee independent of principal quantity. Fee cash is determined on accepted advance; payment before that event is not supported.","decimal"),
        Field("fee_direction","Fee direction","Whether our party pays or receives the independently stated fee."),
        Field("fee_due_at","Fee due","Due no earlier than planned advance, or explicitly not applicable when the fee is zero.","datetime") with{AllowNotApplicable=true},
        Field("book","Book","The book owning the agreement.",choices:"books"),
        Field("legal_entity","Legal entity","Our exact legal entity revision.",choices:"legal_entities"),
        Field("counterparty","Counterparty","The other exact legal party revision.",choices:"counterparties")
    ],[],[],[new("principal","Principal","quantity","quantity",[]),new("present_value","Remaining plan PV",null,"money",[])],["term"],[],["new","booked"]));

    public static ImmutableArray<TicketChoice>? StaticChoices(string field)=>field switch
    {
        "profile"=>[new(GasParkAndLoanTerms.Version,"Title transfer; fixed fee determined on advance")],
        "service_kind"=>[new("park","Park"),new("loan","Loan")],
        "perspective"=>[new("customer","Customer"),new("provider","Provider")],
        "title_policy"=>[new(GasCommodityLoan.TitleTransfer,"Transfer title on accepted advance")],
        "return_policy"=>[new(GasParkAndLoanTerms.EqualQuantity,"Equal quantity at the same point and basis")],
        "return_timing"=>[new(GasParkAndLoanTerms.ReturnsAfterAdvance,"After accepted advance; overdue principal remains owed")],
        "carrying"=>[new("nominal_mark_v1","Nominal principal at the exact saved mark")],
        "fee_direction"=>[new("pay","Pay"),new("receive","Receive")],
        _=>null
    };

    public static GasParkLoanBooking Request(TicketDraft draft,Guid snapshot,Guid context,string knowledgeMode,Guid operation,Guid definition)
    {
        if(draft is null||draft.Product!=Product||draft.Version!=1||draft.Trade is null||draft.Sides.IsDefault||!draft.Sides.IsEmpty)
            throw Invalid("profile","Supply the installed Park and Loan ticket and its explicit agreement terms.");
        var v=draft.Trade;
        foreach(var pair in v)
        {
            if(!Description.TradeFields.Any(f=>f.Id==pair.Key))throw Invalid(pair.Key,"This agreement has no such editable field.");
            if(string.IsNullOrWhiteSpace(pair.Value))throw Invalid(pair.Key,"Select an explicit value.");
        }
        foreach(var field in Description.TradeFields)
        {
            if(!v.ContainsKey(field.Id))throw Invalid(field.Id,$"Select {field.Label.ToLowerInvariant()} explicitly.");
            if(StaticChoices(field.Id) is {} choices&&!choices.Any(c=>c.Value==v[field.Id]))
                throw Invalid(field.Id,$"Select a supported {field.Label.ToLowerInvariant()}.");
        }
        if(snapshot==Guid.Empty||context==Guid.Empty||definition==Guid.Empty||knowledgeMode!="current")
            throw Invalid("profile","Book or preview under an explicit current certified source context.");
        var (entity,entityRevision)=Party("legal_entity");var (party,partyRevision)=Party("counterparty");
        var quantity=Number("principal_quantity");
        if(quantity.CompareTo(default)<=0)throw Invalid("principal_quantity","Principal must be positive in the selected exact quantity basis.");
        var fee=Number("fixed_fee_amount");
        if(fee.CompareTo(default)<0)throw Invalid("fixed_fee_amount","Enter the absolute fee and select its direction separately.");
        var advance=Instant("advance_at");var due=Instant("return_at");
        if(due<=advance)throw Invalid("return_at","Return due must follow the advance time.");
        var receiver=v["service_kind"]=="loan"&&v["perspective"]=="customer"||v["service_kind"]=="park"&&v["perspective"]=="provider";
        Guid? claim=v["claim_account"]==NoAccount?null:Id("claim_account");
        if(receiver!=(claim is null))throw Invalid("claim_account",receiver?"Select Not applicable for a principal receiver.":"A principal giver requires an exact return claim account.");
        DateTimeOffset? feeDue=v["fee_due_at"]=="none"?null:Instant("fee_due_at");
        if((fee==default)!=(feeDue is null))throw Invalid("fee_due_at","Select a due time for a nonzero fee, or Not applicable for a zero fee.");
        if(feeDue is {} feeAt&&feeAt<advance)throw Invalid("fee_due_at","This profile determines fee cash on accepted advance; choose a due time no earlier than planned advance.");
        return new(operation,snapshot,context,definition,PhysicalGasStore.Convention,knowledgeMode,v["profile"],Id("book"),entity,entityRevision,party,partyRevision,
            Id("owned_account"),claim,v["service_kind"],v["perspective"],quantity.ToString(),advance,due,v["title_policy"],v["return_policy"],v["return_timing"],v["carrying"],
            (v["fee_direction"]=="pay"?-fee:fee).ToString(),v["fee_direction"],feeDue);
        Guid Id(string field)=>Guid.TryParse(v[field],out var id)&&id!=Guid.Empty?id:throw Invalid(field,"Select an exact identity.");
        (Guid,int) Party(string field)
        {
            var parts=v[field].Split('@');
            return parts.Length==2&&Guid.TryParse(parts[0],out var id)&&id!=Guid.Empty&&int.TryParse(parts[1],NumberStyles.None,CultureInfo.InvariantCulture,out var revision)&&revision>0?
                (id,revision):throw Invalid(field,"Select an exact party and revision.");
        }
        ExactDecimal Number(string field)
        {
            try{return ExactDecimal.Parse(v[field]);}
            catch(MarketDataException e){throw Invalid(field,e.Message);}
        }
        DateTimeOffset Instant(string field)
        {
            try{return TradingInstant.Parse(v[field],"gas_park_loan_input");}
            catch(MarketDataException e){throw Invalid(field,e.Message);}
        }
    }

    public static TicketDraft Reopen(JsonElement read)
    {
        var t=read.GetProperty("terms");var fee=ExactDecimal.Parse(t.Text("fixedFeeAmount"));
        var values=new Dictionary<string,string>{
            ["book"]=read.Id("bookId").ToString(),["legal_entity"]=$"{read.Id("legalEntityId")}@{read.GetProperty("legalEntityRevision").GetInt32()}",
            ["counterparty"]=$"{read.Id("counterpartyId")}@{read.GetProperty("counterpartyRevision").GetInt32()}",
            ["profile"]=GasParkAndLoanTerms.Version,["service_kind"]=t.Text("serviceKind"),["perspective"]=t.Text("perspective"),
            ["owned_account"]=read.Id("ownedAccountId").ToString(),["claim_account"]=read.OptionalId("claimAccountId")?.ToString()??NoAccount,
            ["principal_quantity"]=read.Text("quantity"),["advance_at"]=t.Text("advanceAt"),["return_at"]=t.Text("returnAt"),
            ["title_policy"]=t.Text("titlePolicy"),["return_policy"]=t.Text("returnPolicy"),["return_timing"]=t.Text("returnTiming"),["carrying"]=t.Text("carrying"),
            ["fixed_fee_amount"]=(fee.CompareTo(default)<0?-fee:fee).ToString(),["fee_direction"]=t.Text("feeDirection"),
            ["fee_due_at"]=t.OptionalText("feeDueAt")??"none"
        };
        return new(Product,1,values.ToImmutableDictionary(),[]);
    }
    public static TicketFieldException Invalid(string field,string message)=>new("gas_park_loan_input",message,null,field);
}
