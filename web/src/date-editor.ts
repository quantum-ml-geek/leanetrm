import {displayDate,displayInstant,publicText,friendly} from './market-view.js';
import {renderRegularTable} from './regular-table.js';

type Calendar={name:string;from:string;to:string;weekendDays:number[];closedDates:string[]};
type Definition={name:string;symbol:string;firstMonth:string;lastMonth:string;anchor:string;day:number|null;shortMonth:string;adjustment:string;calendar:Calendar|null};
type CalendarRef={catalogId:string;revisionId:string;code:string};
export type LibraryCalendar={reference:CalendarRef;coverageFrom:string;coverageTo:string;weekendDays:string[];closedDates:string[];openDates:string[]};
type SavedDates={definition:Definition;dates:{month:string;unadjusted:string;date:string}[]};
type Version={id:string;version:number;generation:number;state:'draft'|'published';definition:Definition;selection:string;effectiveFrom:string;effectiveTo:string;publicationOrder:number|null;publishedAt:string|null;calendar:CalendarRef|null};
export type Context={effectiveOn:string;knownThrough:number|null;knownAt?:string;contextId?:string};
type Snapshot={context:Context;coverageFrom:string;certifiedThrough:string};
type Receipt={expression:string;date:string;source:{version?:number;name?:string;kind?:string;context?:Context}};
type ContractInput={label:string;start:string;end:string;lastTrading:string;cutoffUtc:string};
type Contract={label:string;start:string;end:string;lastTradingAt:string;startReference:Receipt;endReference:Receipt;lastTradingReference:Receipt;cutoffUtc:string};
type Candidate={code:string;name:string;context:Context;contracts:Contract[]};
type Choice={code:string;name:string};
type Library={knownThrough:number;versions:Version[];canEdit:boolean;canPublish:boolean;contractDefinitions:Candidate[];calendars:LibraryCalendar[];choices:{anchors:Choice[];shortMonths:Choice[];adjustments:Choice[];selections:Choice[]}};
type Api=<T>(path:string,body?:unknown)=>Promise<T>;

// Presentation of the served reference calendar; weekday names and dates come from the API.
export function calendarSummary(c:LibraryCalendar){
  const plural=(n:number,word:string)=>`${n} ${word}${n===1?'':'s'}`,last=new Date(c.coverageTo+'T00:00:00Z');last.setUTCDate(last.getUTCDate()-1);
  const parts=[c.weekendDays.length?`Closed ${c.weekendDays.join(' and ')}`:'No weekly closures'];
  if(c.closedDates.length)parts.push(plural(c.closedDates.length,'closed date'));
  if(c.openDates.length)parts.push(plural(c.openDates.length,'opened date'));
  parts.push(`covers ${displayDate(c.coverageFrom)} – ${displayDate(last.toISOString().slice(0,10))}`);
  return parts.join(' · ');
}
// A calendar is chosen by its exact reference version, never by code alone.
export const calendarKey=(c:CalendarRef)=>[c.catalogId,c.revisionId,c.code].join('|');
export function visibleVersions<T extends {state:string}>(versions:T[],author:boolean){return author?versions:versions.filter(v=>v.state==='published');}
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
  const empty=():Library=>({knownThrough:0,versions:[],canEdit:false,canPublish:false,contractDefinitions:[],calendars:[],choices:{anchors:[],shortMonths:[],adjustments:[],selections:[]}});
  let library=empty(),selected:Version|undefined,shownDates:SavedDates|undefined,shownCurve:Candidate|undefined;
  let pinnedContext:Context|undefined,exactKnownAt:string|undefined;
  const clearDates=()=>{shownDates=undefined;get('dates-result').hidden=true;};
  const clearCurve=()=>{shownCurve=undefined;get('curve-dates-result').hidden=true;};
  const clearExpression=()=>{get('date-expression-result').hidden=true;};
  for(const event of ['input','change']){
    form.addEventListener(event,clearDates);curveForm.addEventListener(event,clearCurve);get('date-expression-form').addEventListener(event,clearExpression);
    get('date-context').addEventListener(event,()=>{pinnedContext=undefined;clearCurve();clearExpression();});
    get('date-context-view').addEventListener(event,()=>{exactKnownAt=undefined;});
  }
  function setContext(context:Context){onContextChanged();pinnedContext=context;exactKnownAt=context.knownAt;set('date-context-on',context.effectiveOn);set('date-context-view',context.knownAt?.slice(0,16)??'');}
  async function context():Promise<Context>{
    if(!value('date-context-on')||!value('date-context-view'))throw Error('Choose the context date and UTC knowledge time first.');
    if(pinnedContext)return pinnedContext;
    const snapshot=await api<Snapshot>('date-schedules/context',{effectiveOn:value('date-context-on'),knownAt:exactKnownAt??new Date(value('date-context-view')+'Z').toISOString(),mode:'at'});
    setContext(snapshot.context);return snapshot.context;
  }
  async function currentKnowledge(){
    if(!value('date-context-on'))throw Error('Choose a context date before capturing current knowledge.');
    const snapshot=await api<Snapshot>('date-schedules/context',{effectiveOn:value('date-context-on'),knownAt:null,mode:'current'});
    setContext(snapshot.context);clearCurve();clearExpression();
  }
  function definition():Definition{
    return {name:value('dates-name'),symbol:value('dates-symbol'),firstMonth:value('dates-first'),lastMonth:value('dates-last'),anchor:value('dates-anchor'),day:value('dates-day')?Number(value('dates-day')):null,shortMonth:value('dates-short'),adjustment:value('dates-adjustment'),calendar:null};
  }
  // The chosen calendar is one exact reference version served by the API; it is never assumed.
  function calendarChoice():LibraryCalendar{
    const found=library.calendars.find(c=>calendarKey(c.reference)===value('dates-calendar'));
    if(!found)throw Error('Choose a business calendar.');return found;
  }
  function calendarNote(){
    const found=library.calendars.find(c=>calendarKey(c.reference)===value('dates-calendar'));
    get('dates-calendar-summary').textContent=found?calendarSummary(found):selected&&!selected.calendar?'This earlier version used a typed calendar. Choose a reference calendar to save a new draft.':'';
  }
  function versionLabel(){
    (input('dates-symbol') as HTMLInputElement).readOnly=!!selected;
    get('dates-editor').hidden=!library.canEdit&&!library.canPublish;
    get('dates-version').textContent=selected?`${selected.definition.symbol} · version ${selected.version} · ${selected.state}${selected.state==='published'?' · saving edits creates a new draft':''}`:'New schedule';
    get('dates-publish').hidden=!library.canPublish||selected?.state!=='draft';get('dates-keep').hidden=!library.canEdit;
  }
  function fill(d:Definition){
    for(const [id,text] of Object.entries({'dates-name':d.name,'dates-symbol':d.symbol,'dates-first':d.firstMonth,'dates-last':d.lastMonth,'dates-anchor':d.anchor,'dates-day':d.day===null?'':String(d.day),'dates-short':d.shortMonth,'dates-adjustment':d.adjustment}))set(id,text);
    clearDates();versionLabel();calendarNote();
  }
  function open(version:Version){
    selected=version;set('dates-calendar',version.calendar?calendarKey(version.calendar):'');fill(version.definition);set('dates-selection',version.selection);set('dates-effective-from',version.effectiveFrom);set('dates-effective-to',version.effectiveTo);versionLabel();
  }
  function showDates(result:SavedDates){
    shownDates=result;get('dates-result-title').textContent=publicText(`${result.definition.symbol} · ${result.dates.length} dates`);
    renderRegularTable(get('dates-table'),'date-occurrences',JSON.stringify(result),['Index','Month','Anchor date','Adjusted date'],result.dates.map((d,i)=>[String(i),d.month.slice(0,7),displayDate(d.unadjusted),displayDate(d.date)]),[],isBusy);get('dates-result').hidden=false;
  }
  function options(id:string,choices:{value:string;name:string}[],placeholder:string){
    const prior=value(id),first=el('option',placeholder);first.value='';get(id).replaceChildren(first,...choices.map(c=>{const o=el('option',c.name);o.value=c.value;return o;}));set(id,choices.some(c=>c.value===prior)?prior:'');
  }
  function list(){
    const author=library.canEdit||library.canPublish,shown=visibleVersions(library.versions,author);
    const host=get('dates-saved');host.replaceChildren();if(!shown.length)host.textContent=author?'No schedules saved yet.':'No schedules have been published yet.';
    for(const version of shown){
      const row=el('div');row.className='shortcut-saved-row';const actions=el('div');actions.className='schedule-actions';
      const view=el('button','View dates');view.type='button';view.className='secondary';view.onclick=()=>void run(async()=>{clearDates();showDates(await previewVersion(version));});actions.append(view);
      if(author){const use=el('button',version.state==='draft'?'Open draft':'Open');use.type='button';use.className='secondary';use.onclick=()=>{if(!isBusy())open(version);};actions.append(use);}
      const label=el('div');label.append(el('strong',`${version.definition.name} · ${version.definition.symbol}`),el('span',`Version ${version.version} · ${version.state} · ${version.calendar?friendly(version.calendar.code)+' calendar':'typed calendar'}`));
      row.append(label,actions);host.append(row);
    }
    const drafts=get('curve-dates-saved');drafts.replaceChildren();if(!library.contractDefinitions.length)drafts.textContent='No candidates kept in this demo user’s session.';
    for(const candidate of library.contractDefinitions){const row=el('div');row.className='shortcut-saved-row';const use=el('button','View candidate');use.type='button';use.className='secondary';use.onclick=()=>{if(!isBusy()){fillCurve(candidate);showCurve(candidate);}};row.append(el('span',`${candidate.name} · ${candidate.contracts.length} contracts`),use);drafts.append(row);}
  }
  async function load(){
    library=await api<Library>('date-schedules');
    // Rule choices are served by the backend that validates them.
    for(const [id,list] of [['dates-anchor',library.choices.anchors],['dates-short',library.choices.shortMonths],['dates-adjustment',library.choices.adjustments],['dates-selection',library.choices.selections]] as const)
      options(id,list.map(c=>({value:c.code,name:c.name})),'Choose…');
    const calendarValue=value('dates-calendar'),placeholder=el('option','Choose a calendar…');placeholder.value='';
    get('dates-calendar').replaceChildren(placeholder,...library.calendars.map(c=>{const o=el('option',friendly(c.reference.code));o.value=calendarKey(c.reference);return o;}));
    set('dates-calendar',library.calendars.some(c=>calendarKey(c.reference)===calendarValue)?calendarValue:'');calendarNote();
    options('curve-dates-schedule',[...new Set(library.versions.filter(v=>v.state==='published').map(v=>v.definition.symbol))].map(symbol=>({value:symbol,name:symbol})),'Choose a published schedule…');
    // The opened form owns its base generation. Refreshing lists must not advance it.
    list();versionLabel();
  }
  // Published typed-calendar (v1) versions are compiled by the retained inline engine.
  const previewVersion=(v:Version)=>v.calendar?api<SavedDates>('date-schedules/preview',{definition:v.definition,calendar:v.calendar}):api<SavedDates>('schedules/dates/preview',v.definition);
  form.onsubmit=e=>{e.preventDefault();void run(async()=>{clearDates();showDates(await api<SavedDates>('date-schedules/preview',{definition:definition(),calendar:calendarChoice().reference}));});};
  get('dates-calendar').addEventListener('change',calendarNote);
  get('dates-keep').onclick=()=>{if(isBusy()||!form.reportValidity())return;void run(async()=>{
    clearDates();const saved=await api<Version>('date-schedules/save',{id:selected?.id??null,version:selected?.version??null,generation:selected?.generation??null,expectedState:selected?.state??null,definition:definition(),calendar:calendarChoice().reference,selection:value('dates-selection'),effectiveFrom:value('dates-effective-from'),effectiveTo:value('dates-effective-to')});
    selected=saved;await load();open(saved);
  });};
  get('dates-publish').onclick=()=>void run(async()=>{
    if(!selected||selected.state!=='draft')throw Error('Open a saved draft first.');
    // Publish the retained draft, never unsaved form edits.
    if(JSON.stringify(definition())!==JSON.stringify(selected.definition)||value('dates-calendar')!==(selected.calendar?calendarKey(selected.calendar):'')||value('dates-selection')!==selected.selection||value('dates-effective-from')!==selected.effectiveFrom||value('dates-effective-to')!==selected.effectiveTo)throw Error('Save your changes before publishing.');
    const published=await api<Version>('date-schedules/publish',{id:selected.id,version:selected.version,generation:selected.generation});selected=published;await load();open(published);
  });
  get('dates-new').onclick=()=>{if(!isBusy()){selected=undefined;form.reset();clearDates();versionLabel();calendarNote();}};
  get('dates-example').onclick=()=>void run(async()=>{selected=undefined;
    // Example terms only; the business calendar stays an explicit choice.
    fill({name:'Monthly dates',symbol:'oe.ng',firstMonth:'2021-01',lastMonth:'2021-04',anchor:'day',day:1,shortMonth:'reject',adjustment:'unadjusted',calendar:null});
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
    renderRegularTable(get('curve-dates-table'),'curve-date-contracts',JSON.stringify(c),['Contract','Start reference','Start','Source','End reference','End','Last trading reference','Last trading · UTC','Source'],c.contracts.map(row=>[row.label,row.startReference.expression,displayDate(row.start),source(row.startReference),row.endReference.expression,displayDate(row.end),row.lastTradingReference.expression,displayInstant(row.lastTradingAt,'UTC'),source(row.lastTradingReference)]),[],isBusy);get('curve-dates-result').hidden=false;
  }
  get('curve-dates-add').onclick=()=>void run(async()=>{addRow();clearCurve();});
  get('curve-dates-example').onclick=()=>void run(async()=>{const symbol=value('curve-dates-schedule');if(!symbol)throw Error('Choose a published schedule first.');get('curve-dates-rows').replaceChildren();contractExampleRows(symbol,2,'15:30').forEach(addRow);set('curve-dates-name','Scheduled contract example');set('curve-dates-code','scheduled_contracts');clearCurve();});
  curveForm.onsubmit=e=>{e.preventDefault();void run(async()=>{clearCurve();showCurve(await api<Candidate>('date-schedules/contracts/preview',await candidate()));});};
  get('curve-dates-keep').onclick=()=>{if(isBusy()||!curveForm.reportValidity())return;void run(async()=>{clearCurve();const result=await api<Candidate>('date-schedules/contracts/save',await candidate());await load();showCurve(result);});};
  return {load,context,setContext,clearContext(){pinnedContext=undefined;exactKnownAt=undefined;set('date-context-on','');set('date-context-view','');},refresh(){if(shownDates)showDates(shownDates);if(shownCurve)showCurve(shownCurve);},reset(){library=empty();selected=undefined;form.reset();curveForm.reset();get<HTMLFormElement>('date-expression-form').reset();set('date-context-on','');set('date-context-view','');pinnedContext=undefined;exactKnownAt=undefined;options('curve-dates-schedule',[],'Choose a published schedule…');clearDates();clearCurve();clearExpression();get('curve-dates-rows').replaceChildren();get('dates-table').replaceChildren();get('curve-dates-table').replaceChildren();list();versionLabel();}};
}
