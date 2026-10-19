import {PendingCommand} from './pending-command.js';

const knownRejections=new Set(['job_conflict','job_input','job_transition','job_limit','access_denied','request_format','request_token','definition_rejected','infrastructure_conflict','infrastructure_input','infrastructure_busy']);

export class JobRequest extends PendingCommand {
  sending(){
    const previouslyUncertain=this.command?.uncertain===true;
    if(this.command)this.command.uncertain=true;
    return previouslyUncertain;
  }
  failed(code:string|undefined,previouslyUncertain=this.command?.uncertain===true){
    if(!this.command)return;
    // A denied retry says nothing about the preceding uncertain transaction.
    if(code&&knownRejections.has(code)&&!previouslyUncertain)this.clear();
    else this.command.uncertain=true;
  }
}
