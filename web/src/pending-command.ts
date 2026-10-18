export type RequestCommand={operationId:string;path:string;body:Record<string,unknown>};

// Once sent, a command keeps its identity and economics through uncertain replies.
export class PendingCommand {
  command:RequestCommand|undefined;
  begin(path:string,body:Record<string,unknown>,newId:()=>string=()=>crypto.randomUUID()):RequestCommand{
    if(this.command){
      if(this.command.path!==path||JSON.stringify(this.command.body)!==JSON.stringify(body))throw Error('Review the outstanding request before changing its details. You can retry the original request or discard it after checking recent changes.');
      return this.command;
    }
    return this.command={operationId:newId(),path,body:structuredClone(body)};
  }
  clear(){this.command=undefined;}
}
