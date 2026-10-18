import {displayDate,displayInstant,publicText} from './market-view.js';
import {renderRegularTable} from './regular-table.js';
import {zonedInput} from './user-time.js';

type Calendar={name:string;from:string;to:string;weekendDays:number[];closedDates:string[]};
type Definition={name:string;symbol:string;firstMonth:string;lastMonth:string;anchor:string;day:number|null;shortMonth:string;adjustment:string;calendar:Calendar};
type SavedDates={definition:Definition;dates:{month:string;unadjusted:string;date:string}[]};
type Version={id:string;version:number;generation:number;state:'draft'|'published';definition:Definition;selection:string;effectiveFrom:string;effectiveTo:string;publicationOrder:number|null;publishedAt:string|null};
export type Context={effectiveOn:string;knownThrough:number|null;knownAt?:string;contextId?:string};
type Snapshot={context:Context;coverageFrom:string;certifiedThrough:string};
type Receipt={expression:string;date:string;source:{version?:number;name?:string;kind?:string;context?:Context}};
type ContractInput={label:string;start:string;end:string;lastTrading:string;cutoffUtc:string};
type Contract={label:string;start:string;end:string;lastTradingAt:string;startReference:Receipt;endReference:Receipt;lastTradingReference:Receipt;cutoffUtc:string};
type Candidate={code:string;name:string;context:Context;contracts:Contract[]};
type Library={knownThrough:number;versions:Version[];canEdit:boolean;canPublish:boolean;contractDefinitions:Candidate[]};
type Api=<T>(path:string,body?:unknown)=>Promise<T>;

export function calendarFromFields(fields:{name:string;from:string;to:string;weekends:string;closures:string}):Calendar{
  if(!['0,6','5,6','none'].includes(fields.weekends))throw Error('Choose closed weekdays explicitly.');
  const closedDates=fields.closures.trim()?fields.closures.trim().split(/\s+/):[];
  if(closedDates.some(d=>!/^\d{4}-\d{2}-\d{2}$/.test(d)))throw Error('Enter each closed date as YYYY-MM-DD.');
  return {name:fields.name,from:fields.from,to:fields.to,weekendDays:fields.weekends==='none'?[]:fields.weekends.split(',').map(Number),closedDates};
}
export function contractExampleRows(symbol:string,count:number,cutoffUtc:string):ContractInput[]{
  if(!Number.isInteger(count)||count<1||count>119)throw Error('Choose a schedule with at least two dates.');
  return Array.from({length:count},(_,i)=>({label:`Contract ${i+1}`,start:`${symbol}[${i}]`,end:`${symbol}[${i+1}]`,lastTrading:`${symbol}[${i}] - 3bd`,cutoffUtc}));
}
export function setupDateEditor(run:(work:()=>Promise<void>)=>Promise<void>,api:Api,isBusy:()=>boolean,zone:()=>string,onContextChanged:()=>void=()=>{}){
  const get=<T extends HTMLElement=HTMLElement>(id:string)=>document.getElementById(id) as T;
  const input=(id:string)=>get<HTMLInputElement|HTMLSelectElement|HTMLTextAreaElement>(id);
  const value=(id:string)=>input(id).value;
  const set=(id:string,text:string)=>{input(id).value=text;};
  const el=<K extends keyof HTMLElementTagNameMap>(tag:K,text?:string)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=publicText(text);return n;};
  const form=get<HTMLFormElement>('dates-form'),curveForm=get<HTMLFormElement>('curve-dates-form');
  const empty=():Library=>({knownThrough:0,versions:[],canEdit:false,canPublish:false,contractDefinitions:[]});
  let library=empty(),selected:Version|undefined,shownDates:SavedDates|undefined,shownCurve:Candidate|undefined;
  let pinnedContext:Context|undefined,exactKnownAt:string|undefined;
  const knownInput=zonedInput(get<HTMLInputElement>('date-context-view'),zone,api);
  const clearDates=()=>{shownDates=undefined;get('dates-result').hidden=true;};
  const clearCurve=()=>{shownCurve=undefined;get('curve-dates-result').hidden=true;};
  const clearExpression=()=>{get('date-expression-result').hidden=true;};
  for(const event of ['input','change']){
    form.addEventListener(event,clearDates);curveForm.addEventListener(event,clearCurve);get('date-expression-form').addEventListener(event,clearExpression);
    get('date-context').addEventListener(event,()=>{pinnedContext=undefined;clearCurve();clearExpression();});
    get('date-context-view').addEventListener(event,()=>{exactKnownAt=undefined;});
  }
  function setContext(context:Context){onContextChanged();pinnedContext=context;exactKnownAt=context.knownAt;set('date-context-on',context.effectiveOn);if(context.knownAt)knownInput.set(context.knownAt);else knownInput.clear();}
  async function context():Promise<Context>{
    if(!value('date-context-on')||!value('date-context-view'))throw Error('Choose the business date and knowledge time in your display time zone first.');
    if(pinnedContext)return pinnedContext;
    const snapshot=await api<Snapshot>('date-schedules/context',{effectiveOn:value('date-context-on'),knownAt:exactKnownAt??await knownInput.instant(),mode:'at'});
    setContext(snapshot.context);return snapshot.context;
  }
  async function currentKnowledge(){
    if(!value('date-context-on'))throw Error('Choose a context date before capturing current knowledge.');
    const snapshot=await api<Snapshot>('date-schedules/context',{effectiveOn:value('date-context-on'),knownAt:null,mode:'current'});
    setContext(snapshot.context);clearCurve();clearExpression();
  }
  function definition():Definition{
    return {name:value('dates-name'),symbol:value('dates-symbol'),firstMonth:value('dates-first'),lastMonth:value('dates-last'),anchor:value('dates-anchor'),day:value('dates-day')?Number(value('dates-day')):null,shortMonth:value('dates-short'),adjustment:value('dates-adjustment'),calendar:calendarFromFields({name:value('dates-calendar-name'),from:value('dates-calendar-from'),to:value('dates-calendar-to'),weekends:value('dates-weekends'),closures:value('dates-closures')})};
  }
  function versionLabel(){
    (input('dates-symbol') as HTMLInputElement).readOnly=!!selected;
    get('dates-version').textContent=selected?`${selected.definition.symbol} · version ${selected.version} · ${selected.state}${selected.state==='published'?' · saving edits creates a new draft':''}`:'New schedule';
    get('dates-publish').hidden=!library.canPublish||selected?.state!=='draft';get('dates-keep').hidden=!library.canEdit;
  }
  function fill(d:Definition){
    for(const [id,text] of Object.entries({'dates-name':d.name,'dates-symbol':d.symbol,'dates-first':d.firstMonth,'dates-last':d.lastMonth,'dates-anchor':d.anchor,'dates-day':d.day===null?'':String(d.day),'dates-short':d.shortMonth,'dates-adjustment':d.adjustment,'dates-calendar-name':d.calendar.name,'dates-calendar-from':d.calendar.from,'dates-calendar-to':d.calendar.to,'dates-weekends':d.calendar.weekendDays.length?d.calendar.weekendDays.join(','):'none','dates-closures':d.calendar.closedDates.join('\n')}))set(id,text);
    clearDates();versionLabel();
  }
  function open(version:Version){
    selected=version;fill(version.definition);set('dates-selection',version.selection);set('dates-effective-from',version.effectiveFrom);set('dates-effective-to',version.effectiveTo);versionLabel();
  }
  function showDates(result:SavedDates){
    shownDates=result;get('dates-result-title').textContent=publicText(`${result.definition.symbol} · ${result.dates.length} dates`);
    renderRegularTable(get('dates-table'),'date-occurrences',JSON.stringify(result),['Index','Month','Anchor date','Adjusted date'],result.dates.map((d,i)=>[String(i),d.month.slice(0,7),displayDate(d.unadjusted),displayDate(d.date)]),[],isBusy);get('dates-result').hidden=false;
  }
  function options(id:string,choices:{value:string;name:string}[],placeholder:string){
    const prior=value(id),first=el('option',placeholder);first.value='';get(id).replaceChildren(first,...choices.map(c=>{const o=el('option',c.name);o.value=c.value;return o;}));set(id,choices.some(c=>c.value===prior)?prior:'');
  }
  function list(){
    const host=get('dates-saved');host.replaceChildren();if(!library.versions.length)host.textContent='No schedules saved yet.';
    for(const version of library.versions){
      const row=el('div');row.className='shortcut-saved-row';const use=el('button',version.state==='draft'?'Open draft':'View / create next draft');use.type='button';use.className='secondary';use.onclick=()=>{if(!isBusy())open(version);};
      row.append(el('span',`${version.definition.name} · ${version.definition.symbol} · v${version.version} · ${version.state}`),use);host.append(row);
    }
    const drafts=get('curve-dates-saved');drafts.replaceChildren();if(!library.contractDefinitions.length)drafts.textContent='No candidates kept in this demo user’s session.';
    for(const candidate of library.contractDefinitions){const row=el('div');row.className='shortcut-saved-row';const use=el('button','View candidate');use.type='button';use.className='secondary';use.onclick=()=>{if(!isBusy()){fillCurve(candidate);showCurve(candidate);}};row.append(el('span',`${candidate.name} · ${candidate.contracts.length} contracts`),use);drafts.append(row);}
  }
  async function load(){
    library=await api<Library>('date-schedules');
    options('curve-dates-schedule',[...new Set(library.versions.filter(v=>v.state==='published').map(v=>v.definition.symbol))].map(symbol=>({value:symbol,name:symbol})),'Choose a published schedule…');
    // The opened form owns its base generation. Refreshing lists must not advance it.
    list();versionLabel();
  }
  form.onsubmit=e=>{e.preventDefault();void run(async()=>{clearDates();showDates(await api<SavedDates>('schedules/dates/preview',definition()));});};
  get('dates-keep').onclick=()=>{if(isBusy()||!form.reportValidity())return;void run(async()=>{
    clearDates();const saved=await api<Version>('date-schedules/save',{id:selected?.id??null,version:selected?.version??null,generation:selected?.generation??null,expectedState:selected?.state??null,definition:definition(),selection:value('dates-selection'),effectiveFrom:value('dates-effective-from'),effectiveTo:value('dates-effective-to')});
    selected=saved;await load();open(saved);
  });};
  get('dates-publish').onclick=()=>void run(async()=>{
    if(!selected||selected.state!=='draft')throw Error('Open a saved draft first.');
    // Publish the retained draft, never unsaved form edits.
    if(JSON.stringify(definition())!==JSON.stringify(selected.definition)||value('dates-selection')!==selected.selection||value('dates-effective-from')!==selected.effectiveFrom||value('dates-effective-to')!==selected.effectiveTo)throw Error('Save your changes before publishing.');
    const published=await api<Version>('date-schedules/publish',{id:selected.id,version:selected.version,generation:selected.generation});selected=published;await load();open(published);
  });
  get('dates-new').onclick=()=>{if(!isBusy()){selected=undefined;form.reset();clearDates();versionLabel();}};
  get('dates-example').onclick=()=>void run(async()=>{selected=undefined;
    fill({name:'Monthly dates',symbol:'oe.ng',firstMonth:'2021-01',lastMonth:'2021-04',anchor:'day',day:1,shortMonth:'reject',adjustment:'unadjusted',calendar:{name:'Synthetic weekdays',from:'2020-12-01',to:'2021-06-01',weekendDays:[0,6],closedDates:['2021-01-01']}});
    set('dates-selection','context_month');set('dates-effective-from','2021-01-01');set('dates-effective-to','2021-05-01');set('date-context-on','2021-01-15');set('date-expression','oe.ng[0] - 3bd');await currentKnowledge();
  });
  get('date-context-latest').onclick=()=>void run(async()=>{await load();await currentKnowledge();});
  get<HTMLFormElement>('date-expression-form').onsubmit=e=>{e.preventDefault();void run(async()=>{
    clearExpression();const receipt=await api<Receipt>('date-schedules/resolve',{expression:value('date-expression'),context:await context()});
    get('date-expression-result').textContent=publicText(`${receipt.expression} → ${displayDate(receipt.date)}${receipt.source.version?` · ${receipt.source.name} v${receipt.source.version}`:' · literal date'}`);get('date-expression-result').hidden=false;
  });};
  const fields=['label','start','end','lastTrading','cutoffUtc'] as const;
  function addRow(d?:ContractInput){
    if(get('curve-dates-rows').children.length>=120)throw Error('At most 120 contracts in this example.');
    const row=el('tr');for(const field of fields){const td=el('td'),n=el('input');n.required=true;n.value=d?.[field]??'';n.maxLength=field==='label'?80:100;n.setAttribute('aria-label',field);if(field==='cutoffUtc'){n.type='time';n.step='60';}n.dataset.field=field;td.append(n);row.append(td);}
    const td=el('td'),remove=el('button','Remove');remove.type='button';remove.className='text-button';remove.onclick=()=>{if(!isBusy()){row.remove();clearCurve();}};td.append(remove);row.append(td);get('curve-dates-rows').append(row);
  }
  const rows=():ContractInput[]=>Array.from(get('curve-dates-rows').children,row=>Object.fromEntries(Array.from(row.querySelectorAll<HTMLInputElement>('input[data-field]'),n=>[n.dataset.field!,n.value])) as ContractInput);
  async function candidate(){return {code:value('curve-dates-code'),name:value('curve-dates-name'),context:await context(),contracts:rows()};}
  function fillCurve(c:Candidate){set('curve-dates-code',c.code);set('curve-dates-name',c.name);setContext(c.context);get('curve-dates-rows').replaceChildren();for(const row of c.contracts)addRow({label:row.label,start:row.startReference.expression,end:row.endReference.expression,lastTrading:row.lastTradingReference.expression,cutoffUtc:row.cutoffUtc});clearCurve();clearExpression();}
  function showCurve(c:Candidate){
    shownCurve=c;get('curve-dates-result-title').textContent=publicText(`${c.name} · ${c.contracts.length} contracts`);get('curve-dates-spec').textContent=`Context ${displayDate(c.context.effectiveOn)} · known ${c.context.knownAt?displayInstant(c.context.knownAt,zone()):'from a retained publication prefix'} · end dates excluded`;
    const source=(r:Receipt)=>r.source.version?`v${r.source.version}`:'Literal';
    renderRegularTable(get('curve-dates-table'),'curve-date-contracts',JSON.stringify(c),['Contract','Start reference','Start','Source','End reference','End','Last trading reference',`Last trading · ${zone()}`,'Source'],c.contracts.map(row=>[row.label,row.startReference.expression,displayDate(row.start),source(row.startReference),row.endReference.expression,displayDate(row.end),row.lastTradingReference.expression,displayInstant(row.lastTradingAt,zone()),source(row.lastTradingReference)]),[],isBusy);get('curve-dates-result').hidden=false;
  }
  get('curve-dates-add').onclick=()=>void run(async()=>{addRow();clearCurve();});
  get('curve-dates-example').onclick=()=>void run(async()=>{const symbol=value('curve-dates-schedule');if(!symbol)throw Error('Choose a published schedule first.');get('curve-dates-rows').replaceChildren();contractExampleRows(symbol,2,'15:30').forEach(addRow);set('curve-dates-name','Scheduled contract example');set('curve-dates-code','scheduled_contracts');clearCurve();});
  curveForm.onsubmit=e=>{e.preventDefault();void run(async()=>{clearCurve();showCurve(await api<Candidate>('date-schedules/contracts/preview',await candidate()));});};
  get('curve-dates-keep').onclick=()=>{if(isBusy()||!curveForm.reportValidity())return;void run(async()=>{clearCurve();const result=await api<Candidate>('date-schedules/contracts/save',await candidate());await load();showCurve(result);});};
  return {load,context,setContext,clearContext(){pinnedContext=undefined;exactKnownAt=undefined;set('date-context-on','');knownInput.clear();},refresh(){knownInput.refresh();if(shownDates)showDates(shownDates);if(shownCurve)showCurve(shownCurve);},reset(){library=empty();selected=undefined;form.reset();curveForm.reset();get<HTMLFormElement>('date-expression-form').reset();set('date-context-on','');set('date-context-view','');pinnedContext=undefined;exactKnownAt=undefined;knownInput.clear();options('curve-dates-schedule',[],'Choose a published schedule…');clearDates();clearCurve();clearExpression();get('curve-dates-rows').replaceChildren();get('dates-table').replaceChildren();get('curve-dates-table').replaceChildren();list();versionLabel();}};
}
