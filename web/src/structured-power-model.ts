import {PendingCommand} from './pending-command.js';
export type StructuredPowerKind='battery'|'thermal'|'solar';
export type StructuredPowerPins={definitionCatalogId:string;definitionRevisionId:string;referenceCatalogId:string;referenceRevisionId:string};
export type OperatingField={key:string;label:string;type:'decimal'|'integer'|'choice';choices?:readonly [string,string][];optional?:boolean};
const decimal=(key:string,label:string):OperatingField=>({key,label,type:'decimal'});
const integer=(key:string,label:string):OperatingField=>({key,label,type:'integer'});
const choice=(key:string,label:string,choices:readonly [string,string][]):OperatingField=>({key,label,type:'choice',choices});
const fields:Record<StructuredPowerKind,readonly OperatingField[]>={
 battery:[decimal('maximumChargeMw','Maximum charging power (MW)'),decimal('maximumDischargeMw','Maximum discharging power (MW)'),decimal('minimumStoredMwh','Minimum usable stored energy (MWh)'),decimal('maximumStoredMwh','Maximum usable stored energy (MWh)'),
  decimal('chargeEfficiency','Charging efficiency (fraction)'),decimal('dischargeEfficiency','Discharging efficiency (fraction)'),
  choice('meterBoundary','Meter boundary',[['grid_side_ac','Grid side AC']]),choice('lossPolicy','Auxiliary and self-discharge policy',[['zero_auxiliary_and_self_discharge','Explicitly zero auxiliary and self-discharge']]),
  choice('capacityPolicy','Capacity policy',[['fixed','Fixed usable capacity']]),choice('simultaneousPolicy','Simultaneous charging and discharging',[['prohibited','Prohibited']]),choice('chargingOrigin','Charging origin',[['grid','Grid charging']]),
  choice('throughputPolicy','Cumulative grid throughput budget',[['uncapped','Explicitly uncapped'],['grid_charge_plus_discharge','Grid charge plus discharge budget']]),{...decimal('maximumThroughputMwh','Maximum cumulative grid throughput (MWh; only with budget)'),optional:true}],
 thermal:[decimal('minimumOutputMw','Minimum online output (MW)'),decimal('maximumOutputMw','Maximum output (MW)'),decimal('rampUpMwPerHour','Ramp-up limit (MW per hour)'),decimal('rampDownMwPerHour','Ramp-down limit (MW per hour)'),
  decimal('startupMaximumOutputMw','Maximum boundary-start output (MW)'),decimal('shutdownMaximumOutputMw','Maximum output before boundary stop (MW)'),integer('minimumUpMinutes','Minimum uptime (minutes)'),integer('minimumDownMinutes','Minimum downtime (minutes)'),integer('startupLeadMinutes','Startup instruction lead (minutes)'),integer('maximumStarts','Maximum starts in effective period'),
  decimal('consumptionHeatRate','Consumption fuel energy per output MWh'),decimal('consumptionNoLoadFuelPerHour','Consumption no-load fuel per elapsed hour'),decimal('consumptionStartupFuel','Consumption fuel per start')],
 solar:[choice('stage','Production measurement stage',[['generated','Generated'],['delivered','Delivered']])]
};
export const operatingParameterFields=(kind:StructuredPowerKind)=>fields[kind];
export const comingSoonFields=(kind:StructuredPowerKind):readonly string[]=>({
 battery:['Cycle and degradation model','Self-discharge and auxiliary load','Renewable charging attribution'],
 thermal:['Continuous startup and ramp trajectory','Alternative fuel selection','Startup-fee quote in a start-count unit'],
 solar:['Fixed-profile replacement and surplus valuation','Admitted metered and deemed evidence','Meter-evidence deadline and pending-actuals policy','Automatic certificate issuance']
}[kind]);

export function parseSuppliedPlan(kind:StructuredPowerKind,text:string):Record<string,string|null>[] {
 const columns={battery:['chargeMw','dischargeMw','availablePowerFraction'],thermal:['commitment','outputMw','availableMw','startupInstructionAt'],solar:['productionMwh','requiredDeliveryMwh']}[kind];
 const rows=text.split(/\r?\n/).filter(line=>line.trim());
 if(!rows.length)throw Error('Enter at least one supplied plan row.');
 if(rows.length>1024)throw Error('Use at most 1,024 supplied plan rows.');
 return rows.map((line,index)=>{
  const values=line.split(',').map(value=>value.trim());
  if(values.length!==columns.length)throw Error(`Row ${index+1} needs ${columns.length} columns.`);
  return Object.fromEntries(columns.map((key,n)=>[key,values[n]===''&&['startupInstructionAt','requiredDeliveryMwh'].includes(key)?null:values[n]]));
 });
}
export type FacilityCommon={facilityCode:string;clockCode:string;intervalMinutes:number;powerQuantityCode:string|null;energyQuantityCode:string;fuelQuantityCode:string|null};
export type StructuredPowerTerms=StructuredPowerPins&FacilityCommon&{kind:StructuredPowerKind;battery:Record<string,unknown>|null;thermal:Record<string,unknown>|null;solar:Record<string,unknown>|null;implementation:string};
export type StructuredPowerVersion={id:string;version:number;effectiveFrom:string;effectiveTo:string;terms:StructuredPowerTerms};
export function facilityTerms(pins:StructuredPowerPins,kind:StructuredPowerKind,common:FacilityCommon,parameters:Record<string,unknown>):StructuredPowerTerms {
 return {...pins,...common,kind,battery:kind==='battery'?parameters:null,thermal:kind==='thermal'?parameters:null,solar:kind==='solar'?parameters:null,implementation:'structured_power_facility_v1'};
}
export function structuredPreviewRequest(input:{snapshotId:string;facilityId:string;facilityVersion:number;kind:StructuredPowerKind;operatingDate:string;firstInterval:number;state:Record<string,unknown>;plan:string;valuation:unknown;composition?:unknown}) {
 const rows=parseSuppliedPlan(input.kind,input.plan);
 return {snapshotId:input.snapshotId,facilityId:input.facilityId,facilityVersion:input.facilityVersion,grid:{operatingDate:input.operatingDate,firstInterval:input.firstInterval},
  batteryState:input.kind==='battery'?input.state:null,batteryDispatch:input.kind==='battery'?rows:[],
  thermalState:input.kind==='thermal'?input.state:null,thermalDispatch:input.kind==='thermal'?rows:[],
  solarRight:input.kind==='solar'?input.state:null,solarDispatch:input.kind==='solar'?rows:[],valuation:input.valuation,...(input.composition===undefined?{}:{composition:input.composition})};
}

// Local recovery state grants no write authority. Each original profile keeps
// its own exact unknown command, even when another profile is selected.
export class StructuredPowerPendingStore {
 private readonly requests=new Map<string,PendingCommand>();
 constructor(private readonly storage:Pick<Storage,'getItem'|'setItem'|'removeItem'>){}
 select(identity:string):PendingCommand {
  const retained=this.requests.get(identity);if(retained)return retained;
  const pending=new PendingCommand(code=>!!code&&!['request_failed','response_unknown'].includes(code)&&!code.endsWith('_outcome_unknown'));
  if(identity)try{const raw=JSON.parse(this.storage.getItem(this.key(identity))??'null');if(raw?.path==='physical/power-facilities/save'&&typeof raw.operationId==='string'&&raw.operationId&&raw.body&&typeof raw.body==='object'&&!Array.isArray(raw.body))pending.command=raw;}catch{/* Unreadable local recovery data grants no authority. */}
  this.requests.set(identity,pending);return pending;
 }
 save(identity:string,pending:PendingCommand){if(!identity)return;try{if(pending.command)this.storage.setItem(this.key(identity),JSON.stringify(pending.command));else this.storage.removeItem(this.key(identity));}catch{/* The exact command remains in memory for this identity. */}}
 private key(identity:string){return `openetrm.physical-power.request.${identity}`;}
}

export type OperatingPriceContract={curveCode:string;contractId:string;quoteCode:string;quantityCode:string;currencyCode:string;deliveryFrom:string;deliveryTo:string;label:string;definitionRevisionId:string};
export function operatingPrice(mode:string,quoteCode:string,fixedPrice:string,selected:Pick<OperatingPriceContract,'curveCode'|'contractId'|'quoteCode'>|null){
 if(mode==='fixed')return {mode,quoteCode,fixedPrice,curveCode:null,contractId:null};
 if(mode==='selected_contract_flat_v1'){
  if(!selected)throw Error('Select an exact market contract for this side.');
  return {mode,quoteCode:selected.quoteCode,fixedPrice:null,curveCode:selected.curveCode,contractId:selected.contractId};
 }
 throw Error('Choose an explicit side price mode.');
}
