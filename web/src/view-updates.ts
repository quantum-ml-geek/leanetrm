// Retain equal read-only presentation nodes. Callers with button properties
// rebind those properties explicitly; this does not copy hidden event listeners.
export function replaceChangedChildren(host:HTMLElement,next:readonly Node[],buttons=false){
 next.forEach((node,index)=>{
  const old=host.childNodes[index];
  if(old===node)return;
  if(old?.isEqualNode(node)){
   if(buttons&&old instanceof HTMLElement&&node instanceof HTMLElement){
    const from=[...(node instanceof HTMLButtonElement?[node]:[]),...node.querySelectorAll<HTMLButtonElement>('button')];
    const to=[...(old instanceof HTMLButtonElement?[old]:[]),...old.querySelectorAll<HTMLButtonElement>('button')];
    to.forEach((button,n)=>button.onclick=from[n].onclick);
   }
   return;
  }
  if(node.parentNode===host)host.insertBefore(node,old??null);
  else if(old)old.replaceWith(node);else host.append(node);
 });
 while(host.childNodes.length>next.length)host.lastChild!.remove();
}
