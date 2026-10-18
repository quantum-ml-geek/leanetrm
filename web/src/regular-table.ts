import {publicText} from './market-view.js';

type Cell=string|HTMLElement;
type Filters={scope:string;query:string;columns:(string|null)[];expanded:boolean};
const filters=new Map<string,Filters>();
const clean=(value:string)=>publicText(value).toLocaleLowerCase('en').trim();
export function matchesTableRow(cells:string[],query:string,columns:(string|null)[]){
  const shown=cells.map(publicText),values=shown.map(clean),terms=clean(query).split(/\s+/).filter(Boolean);
  return terms.every(term=>values.some(value=>value.includes(term)))&&columns.every((term,i)=>term===null||shown[i]===term);
}
export const columnValues=(values:string[])=>[...new Set(values.map(publicText))];
export function clearTableFilters(){filters.clear();}

// Pure presentation over the already-authorized displayed values. This renderer
// is used only by ordinary tables; the connected worksheet has its own renderer.
export function renderRegularTable(host:HTMLElement,key:string,scope:string,headers:string[],rows:Cell[][],numeric:number[],isBusy:()=>boolean){
  let saved=filters.get(key);
  if(!saved||saved.scope!==scope||saved.columns.length!==headers.length){saved={scope,query:'',columns:headers.map(()=>null),expanded:false};filters.set(key,saved);}
  const state=saved;
  const current=()=>host.isConnected&&toolbar.isConnected&&toolbar.parentElement===host&&filters.get(key)===state&&!isBusy();
  const el=<K extends keyof HTMLElementTagNameMap>(tag:K,value?:string)=>{const n=document.createElement(tag);if(value!==undefined)n.textContent=publicText(value);return n;};
  const toolbar=el('div');toolbar.className='table-filters';
  const search=el('input');search.type='search';search.value=state.query;search.placeholder='Filter rows…';search.setAttribute('aria-label','Filter table rows');search.autocomplete='off';search.className='table-search';
  const columnToggle=el('button','Column filters');columnToggle.type='button';columnToggle.className='secondary column-filter-toggle';columnToggle.setAttribute('aria-expanded',String(state.expanded));
  const clear=el('button','Clear filters');clear.type='button';clear.className='text-button table-filter-clear';
  const count=el('span');count.className='table-row-count';count.setAttribute('aria-live','polite');
  toolbar.append(search,columnToggle,clear,count);
  const scroll=el('div');scroll.className='regular-table-scroll';const table=el('table'),thead=el('thead'),heading=el('tr'),columnRow=el('tr');columnRow.className='column-filter-row';columnRow.id='column-filters-'+key;columnToggle.setAttribute('aria-controls',columnRow.id);columnRow.hidden=!state.expanded;
  const inputs:HTMLSelectElement[]=[];
  headers.forEach((name,i)=>{const th=el('th',name);th.scope='col';if(numeric.includes(i))th.className='numeric';heading.append(th);const filter=el('th');
    if(name){const input=el('select'),all=el('option','All values');all.value='';input.append(all);
      const choices=columnValues(rows.map(r=>typeof r[i]==='string'?r[i] as string:r[i]?.textContent??''));
      choices.forEach((value,index)=>{const option=el('option',value===''?'(Blank)':value);option.value=String(index);input.append(option);});
      if(state.columns[i]!==null&&!choices.includes(state.columns[i]!))state.columns[i]=null;
      input.value=state.columns[i]===null?'':String(choices.indexOf(state.columns[i]!));input.setAttribute('aria-label','Filter '+name);
      input.onchange=()=>{if(!current())return;state.columns[i]=input.value===''?null:choices[input.selectedIndex-1];apply();};filter.append(input);inputs[i]=input;}columnRow.append(filter);});
  thead.append(heading,columnRow);table.append(thead);const tbody=el('tbody'),elements:HTMLTableRowElement[]=[],searchable:string[][]=[];
  rows.forEach(values=>{const tr=el('tr');values.forEach((value,i)=>{const td=el('td');if(typeof value==='string')td.textContent=publicText(value);else td.append(value);if(numeric.includes(i))td.className='numeric';tr.append(td);});tbody.append(tr);elements.push(tr);searchable.push(values.map((v,i)=>headers[i]?publicText(typeof v==='string'?v:v.textContent??''):''));});
  table.append(tbody);scroll.append(table);const empty=el('p');empty.className='table-filter-empty';empty.setAttribute('role','status');
  function apply(){let visible=0;for(let i=0;i<rows.length;i++){const match=matchesTableRow(searchable[i],state.query,state.columns);elements[i].hidden=!match;if(match)visible++;}
    count.textContent=`${visible} of ${rows.length} rows`;clear.hidden=!state.query&&!state.columns.some(v=>v!==null);empty.hidden=visible>0;
    empty.textContent=rows.length?'No rows match your filters.':'No details to show.';
  }
  search.oninput=()=>{if(!current())return;state.query=search.value;apply();};
  columnToggle.onclick=()=>{if(!current())return;state.expanded=!state.expanded;columnToggle.setAttribute('aria-expanded',String(state.expanded));columnRow.hidden=!state.expanded;if(state.expanded)inputs.find(Boolean)?.focus();};
  clear.onclick=()=>{if(!current())return;state.query='';state.columns=state.columns.map(()=>null);search.value='';inputs.forEach(input=>{if(input)input.value='';});apply();search.focus();};
  for(const control of [search,columnToggle,clear,...inputs.filter(Boolean)])control.disabled=isBusy();
  host.replaceChildren(toolbar,scroll,empty);apply();
}
