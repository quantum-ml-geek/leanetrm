/** Publish startup readiness once, after the initial reads and two rendered frames. */
export function workspaceReadyMarker(ready:()=>boolean,frame:(callback:FrameRequestCallback)=>unknown,mark:()=>void){
 let scheduled=false,marked=false;
 return ()=>{
  if(marked||scheduled||!ready())return;
  scheduled=true;
  frame(()=>frame(()=>{
   scheduled=false;
   if(!marked&&ready()){marked=true;mark();}
  }));
 };
}
