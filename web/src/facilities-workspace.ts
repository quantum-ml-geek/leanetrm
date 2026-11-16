import {setupFacilityQuantities} from './facility-quantities-view.js';
import {setupFacilityOperations} from './facility-operations-view.js';
import {setupTabs} from './side-panel.js';

type Section='quantities'|'definitions'|'activity';
type Options=Parameters<typeof setupFacilityQuantities>[0]&{permission:(name:string)=>boolean};

/** One Facilities entry keeps physical asset work and contract allocations
 * distinct. Only the chosen view reads; each native operation keeps its rights. */
export function setupFacilities(o:Options){
 const root=document.getElementById('facilities-page')!,quantitiesHost=document.createElement('div'),operationsHost=document.createElement('div'),navigation=document.createElement('div'),content=document.createElement('div');
 quantitiesHost.id='facility-quantities-workspace';operationsHost.id='facility-operations-workspace';navigation.id='facilities-workspace-tabs';navigation.className='side-panel-tabs page-tabs';content.id='facilities-workspace-content';
 quantitiesHost.append(...root.childNodes);content.append(quantitiesHost,operationsHost);root.append(navigation,content);
 let section:Section='quantities',operations:ReturnType<typeof setupFacilityOperations>|undefined;
 const quantities=setupFacilityQuantities({...o,busy:()=>o.busy()||!!operations?.unconfirmed()});
 operations=setupFacilityOperations(operationsHost,{...o,busy:()=>o.busy()||quantities.unconfirmed(),openAllocations:async id=>{if(!await operations!.leave())return;section='quantities';show();await quantities.load(id,false);o.changed();}});
 const active=()=>section==='quantities'?quantities:operations!;
 const tabs=setupTabs(navigation,[['definitions','Facility definitions'],['activity','Physical activity'],['quantities','Quantities & allocations']],{label:'Facilities workspace',panel:content,selected:section,select:next=>{
  tabs.mark(section);if(next===section||o.busy())return;
  void o.act(async()=>{if(!await active().leave())return;section=next as Section;show();await active().load();o.changed();});
 }});
 for(const id of ['definitions','activity','quantities'])navigation.querySelector<HTMLButtonElement>('#'+navigation.id+'-'+id)!.dataset.facilitiesView=id;
 function show(){tabs.mark(section);quantitiesHost.hidden=section!=='quantities';operationsHost.hidden=section==='quantities';if(section!=='quantities')operations!.show(section);}
 show();
 return{
  async load(ledgerId?:string,rememberSelection=true){operations!.sync();if(ledgerId!==undefined){section='quantities';show();await quantities.load(ledgerId,rememberSelection);}else{if(operations!.unconfirmed()){section=operations!.recoverySection();show();}await active().load();}},
  sync(){quantities.sync();operations!.sync();for(const button of navigation.querySelectorAll<HTMLButtonElement>('button'))button.disabled=o.busy();},
  section:()=>section,selected:()=>section==='quantities'?quantities.selected():null,
  edited:()=>quantities.edited()||operations!.edited(),leave:()=>active().leave(),refresh:()=>active().refresh(),
  reset(){quantities.reset();operations!.reset();section='quantities';show();},
 };
}
