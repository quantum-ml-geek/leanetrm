// Wire enums for implemented conventions. Reference identities and available
// choices are supplied by the backend catalog, never enumerated here.
export enum PaymentFrequency {Monthly='monthly'}
export enum PaymentDateRule {DaysAfterPeriodEnd='days_after_period_end',DayOfFollowingMonth='day_of_following_month'}
export enum PaymentDayBasis {CalendarDays='calendar_days',BusinessDays='business_days'}
export enum ShortMonth {Reject='reject',Clamp='clamp'}
export enum DateAdjustment {Unadjusted='unadjusted',Following='following',Preceding='preceding',ModifiedFollowing='modified_following'}
export enum Discounting {CurrencyDefault='currency_default',None='none'}
export type Choice<T extends string=string>={value:T;label:string};
export type PaymentOptions={frequencies:Choice<PaymentFrequency>[];rules:Choice<PaymentDateRule>[];dayBases:Choice<PaymentDayBasis>[];shortMonths:Choice<ShortMonth>[];adjustments:Choice<DateAdjustment>[];implementation:string};
export type PaymentInput={frequency:PaymentFrequency;rule:PaymentDateRule;days:number|null;dayOfMonth:number|null;dayBasis:PaymentDayBasis|null;shortMonth:ShortMonth|null;adjustment:DateAdjustment;calendar:string|null;implementation:string};
