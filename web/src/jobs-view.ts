import {renderRegularTable} from './regular-table.js';
import {zonedInput} from './user-time.js';
import {JobRequest} from './job-requests.js';

type Job={id:string;name:string;operation:string;state:string;version:number;dueAt:string;expiresAt:string;owner:string;mine:boolean;actions:string[];runs:{state:string;startedAt:string;attempt:number;observation:string|null;errorCode:string|null}[]};
type Node={clusterId:string;id:string;version:number;name:string;role:string;state:string;availability:string;cpuNano:number;memoryBytes:number;observedAt:string;stale:boolean;actions:string[]};
type Directory={page:number;total:number;jobs:Job[];profiles:{id:string;version:number;name:string}[];canCreate:boolean;manageAll:boolean;observedAt:string;infrastructure:{state:string;observedAt:string|null;nodes:Node[];commands:{id:string;nodeId:string;availability:string;state:string;errorCode:string|null;createdAt:string;canResolve:boolean}[]}};
export function setupJobs(options:{api:<T>(path:string,body?:unknown)=>Promise<T>;act:(work:()=>Promise<void>)=>Promise<void>;busy:()=>boolean;identity:()=>string;instant:(at:string)=>string;zone:()=>string}){
  const get=<T extends HTMLElement=HTMLElement>(id:string)=>document.getElementById(id) as T;
  const field=(id:string)=>get<HTMLInputElement|HTMLSelectElement>(id);
  const dueInput=zonedInput(get<HTMLInputElement>('job-due'),options.zone,options.api),expiryInput=zonedInput(get<HTMLInputElement>('job-expires'),options.zone,options.api);
  const pending=new JobRequest();
  let directory:Directory|undefined;
  const key=()=>`openetrm.jobs.request.${options.identity()}`;
  function save(){try{if(pending.command)sessionStorage.setItem(key(),JSON.stringify(pending.command));else sessionStorage.removeItem(key());}catch{/* The in-memory request is retained. */}get('job-pending').hidden=!pending.command;}
  function clear(){directory=undefined;for(const id of ['jobs-table','job-runs','jobs-nodes','jobs-node-commands'])get(id).replaceChildren();get('job-create').hidden=true;get('jobs-page-count').textContent='';get<HTMLButtonElement>('jobs-previous').disabled=true;get<HTMLButtonElement>('jobs-next').disabled=true;get('jobs-infrastructure').textContent='Status unavailable.';}
  async function send(){
    const command=pending.command;if(!command)return;
    const previouslyUncertain=pending.sending();save();
    try{await options.api(command.path,{...command.body,requestId:command.operationId});pending.clear();save();await load();}
    catch(error){clear();const code=(error as {code?:string}).code;pending.failed(code,previouslyUncertain);save();throw error;}
  }
  async function mutate(path:string,body:Record<string,unknown>){pending.begin(path,body);save();await send();}
  function button(label:string,job:Job,action:string){const b=document.createElement('button');b.type='button';b.className='secondary';b.textContent=label;b.onclick=()=>void options.act(()=>mutate('jobs/control',{id:job.id,action,expectedVersion:job.version}));return b;}
  function render(){
    if(!directory)return;
    get('job-create').hidden=!directory.canCreate;
    get('jobs-page-count').textContent=`Showing ${directory.jobs.length} of ${directory.total} jobs — page ${directory.page+1}.`;
    get<HTMLButtonElement>('jobs-previous').disabled=directory.page===0;get<HTMLButtonElement>('jobs-next').disabled=(directory.page+1)*100>=directory.total;
    get('jobs-scope').textContent=directory.manageAll?'You can manage all jobs in your authorized scope.':'Your jobs and schedules.';
    get('jobs-infrastructure').textContent=directory.infrastructure.state==='not_configured'?'Swarm is not configured for this workspace.':directory.infrastructure.observedAt?`Latest node snapshot ${options.instant(directory.infrastructure.observedAt)}.`:'No node observation is available.';
    renderRegularTable(get('jobs-nodes'),'jobs-nodes',options.identity(),['Node','Role','Health','Availability','CPUs','Memory (MiB)','Observed','Actions'],directory.infrastructure.nodes.map(n=>{
      const actions=document.createElement('div');const labels:Record<string,string>={pause:'Pause scheduling',active:'Resume scheduling',drain:'Drain idle node'};
      for(const a of n.actions){if(!labels[a])continue;const b=document.createElement('button');b.type='button';b.className='secondary';b.textContent=labels[a];b.onclick=()=>void options.act(()=>mutate('infrastructure/availability',{clusterId:n.clusterId,nodeId:n.id,expectedVersion:n.version,availability:a}));actions.append(b);}
      return[n.name,n.role,n.stale?'Stale observation':n.state,n.availability,String(n.cpuNano/1e9),String(n.memoryBytes/1048576),options.instant(n.observedAt),actions];
    }),[4,5],options.busy);
    renderRegularTable(get('jobs-node-commands'),'jobs-node-commands',options.identity(),['Node','Requested availability','Outcome','Details','Requested','Reconciliation'],(directory.infrastructure.commands??[]).map(c=>{const node=directory!.infrastructure.nodes.find(n=>n.id===c.nodeId);const action=document.createElement('div');if(c.canResolve&&node&&!node.stale){const b=document.createElement('button');b.type='button';b.textContent='Keep observed state and reconcile';b.onclick=()=>void options.act(()=>mutate('infrastructure/resolve',{id:c.id,expectedVersion:node.version}));action.append(b);}return[node?.name??'Unavailable node',c.availability,c.state,c.errorCode??'',options.instant(c.createdAt),action];}),[],options.busy);
    const labels:Record<string,string>={worker_check:'Worker readiness check',swarm_job:'Approved container job'};
    renderRegularTable(get('jobs-table'),'jobs',options.identity(),['Job','Owner','Operation','State','Next due','Expires','Actions'],directory.jobs.map(j=>{
      const actions=document.createElement('div');
      for(const a of j.actions){const labels:Record<string,string>={pause:'Pause',resume:'Resume',cancel:'Cancel',run_again:'Run again'};if(labels[a])actions.append(button(labels[a],j,a));}
      return[j.name,j.owner,labels[j.operation]??'Unsupported operation',j.state,options.instant(j.dueAt),options.instant(j.expiresAt),actions];
    }),[],options.busy);
    renderRegularTable(get('job-runs'),'job-runs',options.identity(),['Job','Started','Outcome','Attempt','Details'],directory.jobs.flatMap(j=>j.runs.map(r=>[j.name,options.instant(r.startedAt),r.state,String(r.attempt),r.observation==='unknown'?'Outcome unknown; intervention required':r.errorCode??r.observation??''])),[3],options.busy);
    field('job-profile').replaceChildren(new Option('Choose an approved image…',''),...directory.profiles.map(p=>new Option(p.name,`${p.id}:${p.version}`)));
  }
  async function load(page=0){clear();directory=await options.api<Directory>(`jobs?page=${page}`);render();}
  function fields(){field('job-attempts').setAttribute('max',field('job-operation').value==='swarm_job'?'1':'3');get('job-interval-field').hidden=field('job-frequency').value!=='interval';get('job-profile-field').hidden=field('job-operation').value!=='swarm_job';}
  field('job-frequency').onchange=fields;field('job-operation').onchange=fields;
  get('jobs-refresh').onclick=()=>void options.act(()=>load());
  get('jobs-previous').onclick=()=>void options.act(()=>load(Math.max(0,(directory?.page??0)-1)));
  get('jobs-next').onclick=()=>void options.act(()=>load((directory?.page??0)+1));
  get('job-retry-request').onclick=()=>void options.act(send);
  get('job-discard-request').onclick=()=>{pending.clear();save();};
  get<HTMLFormElement>('job-create').onsubmit=event=>{event.preventDefault();void options.act(async()=>{
    if(pending.command)throw Error('Reconcile the outstanding job request first.');
    const frequency=field('job-frequency').value;if(!['once','interval'].includes(frequency))throw Error('Choose a frequency.');
    const due=field('job-due').value,expires=field('job-expires').value;
    if(!due||!expires)throw Error('Supply due and expiry times in your display time zone.');
    const profile=directory?.profiles.find(p=>`${p.id}:${p.version}`===field('job-profile').value);
    await mutate('jobs/create',{name:field('job-name').value,operation:field('job-operation').value,dueAt:await dueInput.instant(),expiresAt:await expiryInput.instant(),
      intervalSeconds:frequency==='once'?null:Number(field('job-interval').value),timeZone:'UTC',misfire:'run_once',overlap:'forbid',
      timeoutSeconds:Number(field('job-timeout').value),maximumAttempts:Number(field('job-attempts').value),profileId:profile?.id??null,profileVersion:profile?.version??null});
  });};
  function sync(){get<HTMLButtonElement>('jobs-previous').disabled=options.busy()||!directory||directory.page===0;get<HTMLButtonElement>('jobs-next').disabled=options.busy()||!directory||(directory.page+1)*100>=directory.total;}
  return{load,sync,refresh(){dueInput.refresh();expiryInput.refresh();render();},reset(){dueInput.clear();expiryInput.clear();clear();pending.clear();try{const stored=sessionStorage.getItem(key());if(stored){const value=JSON.parse(stored);if(['jobs/create','jobs/control','infrastructure/availability','infrastructure/resolve'].includes(value.path)&&typeof value.operationId==='string'&&value.body&&typeof value.body==='object')pending.command={...value,uncertain:true};}}catch{/* Invalid browser state cannot grant authority. */}get<HTMLFormElement>('job-create').reset();fields();get('job-pending').hidden=!pending.command;}};
}
