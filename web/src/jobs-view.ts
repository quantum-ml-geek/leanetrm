import {renderRegularTable} from './regular-table.js';
import {zonedInput} from './user-time.js';
import {JobRequest} from './job-requests.js';

type Job={id:string;name:string;operation:string;state:string;version:number;dueAt:string;expiresAt:string;intervalSeconds:number|null;timeZone:string;misfire:string;overlap:string;timeoutSeconds:number;maximumAttempts:number;profileId:string|null;profileVersion:number|null;profileName:string|null;canEdit:boolean;editReason:string|null;owner:string;mine:boolean;actions:string[];runs:{state:string;startedAt:string;attempt:number;observation:string|null;errorCode:string|null}[]};
type Node={clusterId:string;id:string;version:number;name:string;role:string;state:string;availability:string;cpuNano:number;memoryBytes:number;observedAt:string;stale:boolean;actions:string[]};
type Directory={page:number;total:number;jobs:Job[];profiles:{id:string;version:number;name:string}[];canCreate:boolean;manageAll:boolean;observedAt:string;infrastructure:{state:string;observedAt:string|null;nodes:Node[];commands:{id:string;nodeId:string;availability:string;state:string;errorCode:string|null;createdAt:string;canResolve:boolean}[]}};
export function setupJobs(options:{api:<T>(path:string,body?:unknown)=>Promise<T>;act:(work:()=>Promise<void>)=>Promise<void>;busy:()=>boolean;identity:()=>string;instant:(at:string)=>string;zone:()=>string}){
  const get=<T extends HTMLElement=HTMLElement>(id:string)=>document.getElementById(id) as T;
  const field=(id:string)=>get<HTMLInputElement|HTMLSelectElement>(id);
  const dueInput=zonedInput(get<HTMLInputElement>('job-due'),options.zone,options.api),expiryInput=zonedInput(get<HTMLInputElement>('job-expires'),options.zone,options.api);
  const pending=new JobRequest();
  let directory:Directory|undefined;
  let selected:Job|undefined,generation=0;
  const editorStatus=document.createElement('p');editorStatus.id='job-edit-status';editorStatus.className='field-help';editorStatus.setAttribute('role','status');get('job-editor-title').after(editorStatus);
  const key=()=>`openetrm.jobs.request.${options.identity()}`;
  function save(){try{if(pending.command)sessionStorage.setItem(key(),JSON.stringify(pending.command));else sessionStorage.removeItem(key());}catch{/* The in-memory request is retained. */}get('job-pending').hidden=!pending.command;}
  function closeEditor(){selected=undefined;get<HTMLFormElement>('job-create').reset();dueInput.clear();expiryInput.clear();editorStatus.textContent='';get('job-editor-title').textContent='New job';get('job-submit').textContent='Create job';get('job-submit').hidden=false;get('job-cancel-edit').hidden=true;get('job-create').hidden=!directory?.canCreate;fields();sync();}
  function clear(){directory=undefined;closeEditor();for(const id of ['jobs-table','job-runs','jobs-nodes','jobs-node-commands'])get(id).replaceChildren();get('jobs-page-count').textContent='';get<HTMLButtonElement>('jobs-previous').disabled=true;get<HTMLButtonElement>('jobs-next').disabled=true;get('jobs-infrastructure').textContent='Status unavailable.';}
  function openEditor(job:Job){
    if(options.busy()||!directory?.jobs.includes(job))return;
    selected=job;get('job-create').hidden=false;
    get('job-editor-title').textContent=job.canEdit?'Edit job':'Job details';get('job-submit').textContent='Save job';get('job-submit').hidden=!job.canEdit;get('job-cancel-edit').hidden=false;
    get('job-cancel-edit').textContent=job.canEdit?'Cancel edit':'Close details';
    editorStatus.textContent=`${job.owner} · ${job.state}. ${job.canEdit?'Changes apply to future runs. Ownership, operation and approved image remain fixed.':job.editReason??'These retained terms are read-only.'}`;
    field('job-name').value=job.name;field('job-operation').value=job.operation;dueInput.set(job.dueAt);expiryInput.set(job.expiresAt);
    field('job-frequency').value=job.intervalSeconds===null?'once':'interval';field('job-interval').value=job.intervalSeconds===null?'':String(job.intervalSeconds);
    field('job-timeout').value=String(job.timeoutSeconds);field('job-attempts').value=String(job.maximumAttempts);
    const profile=job.profileId===null?'':`${job.profileId}:${job.profileVersion}`;
    const profiles=get<HTMLSelectElement>('job-profile');if(profile&&![...profiles.options].some(p=>p.value===profile))profiles.add(new Option(job.profileName??'Retained approved image',profile));profiles.value=profile;
    fields();sync();get('job-editor-title').scrollIntoView({block:'nearest'});if(job.canEdit)field('job-name').focus();
  }
  async function send(){
    const command=pending.command,identity=options.identity();if(!command)return;
    const previouslyUncertain=pending.sending();save();
    try{await options.api(command.path,{...command.body,requestId:command.operationId});if(identity!==options.identity()||pending.command!==command)return;}
    catch(error){if(identity!==options.identity()||pending.command!==command)return;clear();const code=(error as {code?:string}).code;pending.failed(code,previouslyUncertain);save();throw error;}
    pending.clear();save();await load();
  }
  async function mutate(path:string,body:Record<string,unknown>){pending.begin(path,body);save();await send();}
  function button(label:string,job:Job,action:string){const b=document.createElement('button');b.type='button';b.className='secondary';b.textContent=label;b.onclick=()=>void options.act(()=>mutate('jobs/control',{id:job.id,action,expectedVersion:job.version}));return b;}
  function render(){
    if(!directory)return;
    get('job-create').hidden=!selected&&!directory.canCreate;
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
      const name=document.createElement('button');name.type='button';name.className='text-button';name.textContent=j.name;name.onclick=()=>openEditor(j);
      return[name,j.owner,labels[j.operation]??'Unsupported operation',j.state,options.instant(j.dueAt),options.instant(j.expiresAt),actions];
    }),[],options.busy);
    renderRegularTable(get('job-runs'),'job-runs',options.identity(),['Job','Started','Outcome','Attempt','Details'],directory.jobs.flatMap(j=>j.runs.map(r=>[j.name,options.instant(r.startedAt),r.state,String(r.attempt),r.observation==='unknown'?'Outcome unknown; intervention required':r.errorCode??r.observation??''])),[3],options.busy);
    const profiles=get<HTMLSelectElement>('job-profile'),profile=selected?.profileId?`${selected.profileId}:${selected.profileVersion}`:profiles.value;
    profiles.replaceChildren(new Option('Choose an approved image…',''),...directory.profiles.map(p=>new Option(p.name,`${p.id}:${p.version}`)));
    if(selected?.profileId&&![...profiles.options].some(p=>p.value===profile))profiles.add(new Option(selected.profileName??'Retained approved image',profile));
    profiles.value=[...profiles.options].some(p=>p.value===profile)?profile:'';
  }
  async function load(page=0){const request=++generation,identity=options.identity();clear();const result=await options.api<Directory>(`jobs?page=${page}`);if(request!==generation||identity!==options.identity())return;directory=result;render();sync();}
  function fields(){field('job-attempts').setAttribute('max',field('job-operation').value==='swarm_job'?'1':'3');get('job-interval-field').hidden=field('job-frequency').value!=='interval';get('job-profile-field').hidden=field('job-operation').value!=='swarm_job';}
  field('job-frequency').onchange=fields;field('job-operation').onchange=fields;
  get('jobs-refresh').onclick=()=>void options.act(()=>load());
  get('jobs-previous').onclick=()=>void options.act(()=>load(Math.max(0,(directory?.page??0)-1)));
  get('jobs-next').onclick=()=>void options.act(()=>load((directory?.page??0)+1));
  get('job-retry-request').onclick=()=>void options.act(send);
  get('job-discard-request').onclick=()=>{pending.clear();save();sync();};
  get('job-cancel-edit').onclick=()=>{if(!options.busy())closeEditor();};
  get<HTMLFormElement>('job-create').onsubmit=event=>{event.preventDefault();void options.act(async()=>{
    if(pending.command)throw Error('Reconcile the outstanding job request first.');
    if(selected&&!selected.canEdit)throw Error('This job is read-only. Refresh its current status.');
    const frequency=field('job-frequency').value;if(!['once','interval'].includes(frequency))throw Error('Choose a frequency.');
    const due=field('job-due').value,expires=field('job-expires').value;
    if(!due||!expires)throw Error('Supply due and expiry times in your display time zone.');
    const profile=directory?.profiles.find(p=>`${p.id}:${p.version}`===field('job-profile').value);
    const editing=selected,identity=options.identity(),request=generation;
    const target=editing?{id:editing.id,expectedVersion:editing.version}:{operation:field('job-operation').value,profileId:profile?.id??null,profileVersion:profile?.version??null};
    const terms={name:field('job-name').value,intervalSeconds:frequency==='once'?null:Number(field('job-interval').value),
      timeZone:editing?.timeZone??'UTC',misfire:editing?.misfire??'run_once',overlap:editing?.overlap??'forbid',
      timeoutSeconds:Number(field('job-timeout').value),maximumAttempts:Number(field('job-attempts').value)};
    const dueAt=await dueInput.instant(),expiresAt=await expiryInput.instant();
    if(identity!==options.identity()||request!==generation||selected!==editing)throw Error('The job selection changed. Refresh before saving.');
    await mutate(editing?'jobs/update':'jobs/create',{...terms,dueAt,expiresAt,...target});
  });};
  function sync(){get<HTMLButtonElement>('jobs-previous').disabled=options.busy()||!directory||directory.page===0;get<HTMLButtonElement>('jobs-next').disabled=options.busy()||!directory||(directory.page+1)*100>=directory.total;for(const input of get<HTMLFormElement>('job-create').querySelectorAll<HTMLInputElement|HTMLSelectElement|HTMLButtonElement>('input,select,button'))input.disabled=options.busy()||(input.id!=='job-cancel-edit'&&(!!pending.command||!!selected&&!selected.canEdit))||(!!selected&&['job-operation','job-profile'].includes(input.id));}
  return{load,sync,refresh(){dueInput.refresh();expiryInput.refresh();render();sync();},reset(){generation++;clear();pending.clear();try{const stored=sessionStorage.getItem(key());if(stored){const value=JSON.parse(stored);if(['jobs/create','jobs/update','jobs/control','infrastructure/availability','infrastructure/resolve'].includes(value.path)&&typeof value.operationId==='string'&&value.body&&typeof value.body==='object')pending.command={...value,uncertain:true};}}catch{/* Invalid browser state cannot grant authority. */}fields();get('job-pending').hidden=!pending.command;sync();}};
}
