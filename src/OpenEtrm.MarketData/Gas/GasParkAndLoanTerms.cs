using OpenEtrm.MarketData.Trading;

namespace OpenEtrm.MarketData.Gas;

// The installed commercial profile selects each policy explicitly. Native
// admission additionally resolves this exact mark's point, quote and currency.
[EconomicDefinition("gas_park_and_loan_terms_v1")]
public sealed record GasParkAndLoanTerms
{
    public const string Version="physical_gas_park_loan_v1";
    public const string Park="park",Loan="loan",Customer="customer",Provider="provider";
    public const string EqualQuantity="same_quantity_partial_returns_v1";
    public const string ReturnsAfterAdvance="accepted_advance_then_returns_v1";
    public const string FeeAtAdvance="accepted_advance_v1";

    [IdentityField]public string Implementation{get;}
    [IdentityField]public string Service{get;}
    [IdentityField]public string Perspective{get;}
    [IdentityField]public string TitlePolicy{get;}
    [IdentityField]public string ReturnRule{get;}
    [IdentityField]public ReferenceKey Point{get;}
    [IdentityField]public ReferenceKey Quantity{get;}
    [IdentityField]public ReferenceKey Currency{get;}
    [IdentityField]public CurveRequest Mark{get;}
    [IdentityField]public DateTimeOffset AdvanceAt{get;}
    [IdentityField]public DateTimeOffset ReturnAt{get;}
    [IdentityField]public GasHoldingCarrying Carrying{get;}
    public Money FixedFee{get;}
    [IdentityField]public ExactDecimal FixedFeeAmount=>FixedFee.Amount;
    [IdentityField]public ExactDecimal FeeDirection{get;}
    [IdentityField]public DateTimeOffset? FeeDueAt{get;}
    [IdentityField]public string FeeRecognition=>FeeAtAdvance;
    [IdentityField]public string ReturnTiming{get;}

    // Direction is from the booked party's perspective. Service and perspective
    // are both explicit terms; neither is guessed from fee or quantity signs.
    public ExactDecimal AdvanceDirection=>ExactDecimal.Parse(
        Service==Loan&&Perspective==Customer||Service==Park&&Perspective==Provider?"1":"-1");
    public Money SignedFixedFee=>FixedFee.Scale(FeeDirection);

    public GasParkAndLoanTerms(string implementation,string service,string perspective,string titlePolicy,string returnRule,
        ReferenceKey point,ReferenceKey quantity,ReferenceKey currency,CurveRequest mark,DateTimeOffset advanceAt,DateTimeOffset returnAt,
        GasHoldingCarrying carrying,Money fixedFee,ExactDecimal feeDirection,DateTimeOffset? feeDueAt,string returnTiming)
    {
        foreach(var key in new[]{point,quantity,currency})Money.RequireKey(key);
        if(implementation!=Version||service is not(Park or Loan)||perspective is not(Customer or Provider)||
            titlePolicy!=GasCommodityLoan.TitleTransfer||returnRule!=EqualQuantity||returnTiming!=ReturnsAfterAdvance||
            point.Revision!=quantity.Revision||quantity.Revision!=currency.Revision||
            mark.Curve.Revision.CatalogId==Guid.Empty||mark.Curve.Revision.RevisionId==Guid.Empty||string.IsNullOrWhiteSpace(mark.Curve.Code)||
            mark.Contract.Id==Guid.Empty||mark.Contract.Revision!=mark.Curve.Revision||
            !TradingInstant.IsSupported(advanceAt)||!TradingInstant.IsSupported(returnAt)||returnAt<=advanceAt||
            carrying!=GasHoldingCarrying.Nominal||fixedFee is null||fixedFee.Currency!=currency||fixedFee.Amount.CompareTo(default)<0||
            feeDirection!=ExactDecimal.Parse("1")&&feeDirection!=ExactDecimal.Parse("-1")||
            (fixedFee.Amount==default)!=(feeDueAt is null)||feeDueAt is {} feeAt&&(!TradingInstant.IsSupported(feeAt)||feeAt<advanceAt))
            throw new MarketDataException("gas_park_loan_terms","Select the installed title-transfer profile, exact point, quantity, currency and mark, dated commitments, equal return and nominal principal. Its independent fixed fee is determined at accepted advance and due no earlier than the planned advance.");
        Implementation=implementation;Service=service;Perspective=perspective;TitlePolicy=titlePolicy;ReturnRule=returnRule;
        Point=point;Quantity=quantity;Currency=currency;Mark=mark;AdvanceAt=advanceAt;ReturnAt=returnAt;Carrying=carrying;
        FixedFee=fixedFee;FeeDirection=feeDirection;FeeDueAt=feeDueAt;ReturnTiming=returnTiming;
    }
}
