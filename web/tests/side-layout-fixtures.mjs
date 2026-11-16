const group=(id,label,kind,fields)=>({id,label,kind,fields});
const layout=groups=>({fields:groups.flatMap(group=>group.fields),groups});
export const savedSideGroups=(bindingId,roles)=>[{instrumentId:'synthetic-managed-definition',bindingId,label:'Retained contractual composition',sides:roles.map((roleLabel,slot)=>({slot,sideId:'synthetic-side-'+slot,label:roleLabel,roleLabel,directionLabel:'Explicit synthetic company direction',overviewSections:[{label:'Terms',values:[{label:'Definition','value':'Exact saved contractual terms'}]}]}))}];
export const recFieldLayout=layout([
 group('agreement','Agreement and parties','agreement',['calendar','discount','book','entity','party','tradeDate','convention']),
 group('delivery','Certificate delivery Side terms','side_terms',['assignment','deliveryFrom','deliveryTo','quantity','physical']),
 group('consideration','Consideration Side terms','side_terms',['consideration','mode','quote','price','contract','payment','days'])
]);
export const operatingFieldLayouts=Object.fromEntries(['battery','thermal','solar'].map(kind=>[kind,layout([
 group('valuation','Valuation agreement terms','agreement',['right','currency','perspective','measure','discounting','paymentDays','paymentPolicy']),
 group('energy',kind==='battery'?'Discharging energy Side terms':kind==='thermal'?'Energy output Side terms':'Payment energy Side terms','side_terms',['saleMode','saleContract','saleQuote','salePrice']),
 ...kind==='battery'?[group('charging','Charging energy Side terms','side_terms',['chargeMode','chargeContract','chargeQuote','chargePrice'])]:[],
 ...kind==='thermal'?[group('fuel','Fuel input Side terms','side_terms',['fuelMode','fuelContract','fuelQuote','fuelPrice','fuelBasis'])]:[],
 group('variable_fee','Optional variable fee terms','side_terms',['variablePrice','variableBasis']),
 group('access_fee','Optional access fee terms','side_terms',['accessQuote','accessPrice','accessBasis'])
])]));
