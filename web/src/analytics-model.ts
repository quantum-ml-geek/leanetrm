import {deliveryLabel,curveName} from './market-view.js';
/** Ordering and reshaping displayed values only; no pricing or aggregation. */
export function compareDecimalStrings(a:string,b:string):number{
  const parts=(value:string)=>{if(!/^-?\d+(\.\d+)?$/.test(value))throw Error('A numeric column requires exact decimal strings.');const [integer,fraction='']=value.replace(/^-/,'').split('.');const whole=integer.replace(/^0+(?=\d)/,'');const decimal=fraction.replace(/0+$/,'');return {negative:value.startsWith('-')&&(whole!=='0'||decimal!==''),whole,decimal};};
  const x=parts(a),y=parts(b);if(x.negative!==y.negative)return x.negative?-1:1;
  const sign=x.negative?-1:1;
  if(x.whole.length!==y.whole.length)return Math.sign(x.whole.length-y.whole.length)*sign;
  if(x.whole!==y.whole)return (x.whole<y.whole?-1:1)*sign;
  const length=Math.max(x.decimal.length,y.decimal.length),xf=x.decimal.padEnd(length,'0'),yf=y.decimal.padEnd(length,'0');return xf===yf?0:(xf<yf?-1:1)*sign;
}
export type PivotGroup=Record<string,unknown>;
export type MatrixColumn={key:string;title:string;numeric:boolean;measure?:string};
const labels:Record<string,string>={instrumentType:'Instrument type',presentValue:'PV',portfolio:'Portfolio',book:'Book',market:'Market',contract:'Contract',unit:'Units',currency:'Currency',tradeCount:'Trades',lots:'Lots',quantity:'Quantity',executionPnl:'Execution P&L'};
const canonical=(v:unknown):string=>JSON.stringify(v,(_key,value)=>value&&typeof value==='object'&&!Array.isArray(value)?Object.fromEntries(Object.entries(value).sort(([a],[b])=>a.localeCompare(b))):value);
function identity(group:PivotGroup,dimension:string){return dimension==='instrumentType'?group.instrumentType:dimension==='market'?group.market:group[dimension+'Id'];}
function label(group:PivotGroup,dimension:string){return dimension==='contract'?deliveryLabel(String(group.deliveryFrom),String(group.deliveryTo)):dimension==='market'?curveName(group.market):String(group[dimension]??'');}
export function pivotMatrix(groups:PivotGroup[],dimensions:string[],splitBy:string[],measures:string[]){
  if(!splitBy.length||!dimensions.some(d=>!splitBy.includes(d))||splitBy.some(d=>!dimensions.includes(d))||new Set(dimensions).size!==dimensions.length)throw Error('Choose separate row and column dimensions.');
  const rowsBy=dimensions.filter(d=>!splitBy.includes(d));
  const splits=new Map<string,{title:string;ids:unknown[];sortKey:string}>();
  for(const group of groups){const ids=splitBy.map(d=>identity(group,d));if(ids.some(v=>v===null||v===undefined))throw Error('A pivot dimension identity is missing.');splits.set(canonical(ids),{title:splitBy.map(d=>label(group,d)).join(' / '),ids,sortKey:canonical(splitBy.map(d=>d==='contract'?[group.deliveryFrom,group.deliveryTo]:label(group,d)))});}
  const ordered=[...splits.entries()].sort(([a,x],[b,y])=>x.sortKey.localeCompare(y.sortKey)||a.localeCompare(b));
  const columns:MatrixColumn[]=[...new Set([...rowsBy,...(groups.some(g=>g.instrumentType!==undefined)?['instrumentType']:[]),'unit','currency'])].map(key=>({key,title:labels[key],numeric:false}));
  for(const [key,split] of ordered)for(const measure of measures)columns.push({key:'pivot:'+canonical([key,measure]),title:split.title+' · '+labels[measure],numeric:true,measure});
  if(columns.length>128)throw Error('Choose fewer pivot columns; this view supports up to 128 columns.');
  const rows=new Map<string,Record<string,string|null>>(),filled=new Set<string>();
  for(const group of groups){
    if(!group.quantitySpecification||!group.currencyReference)throw Error('A pivot needs exact quantity and currency partitions.');
    const key=canonical([rowsBy.map(d=>identity(group,d)),group.instrumentType,group.quantitySpecification,group.currencyReference]);
    const split=canonical(splitBy.map(d=>identity(group,d)));const cell=canonical([key,split]);
    if(filled.has(cell))throw Error('Duplicate pivot cells cannot be combined in the browser.');filled.add(cell);
    let row=rows.get(key);if(!row){row=Object.fromEntries(columns.map(c=>[c.key,null]));for(const d of rowsBy)row[d]=label(group,d);if(group.instrumentType!==undefined)row.instrumentType=String(group.instrumentType);row.unit=String(group.unit);row.currency=String(group.currency);rows.set(key,row);}
    for(const measure of measures){const value=group[measure];if(value===undefined)throw Error('A selected pivot measure is missing.');row['pivot:'+canonical([split,measure])]=value===null?null:String(value);}
  }
  return {columns,rows:[...rows.values()]};
}
