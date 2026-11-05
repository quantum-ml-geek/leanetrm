// Exact presentation differences only. A structural change uses the grid's
// ordinary keyed reconciliation rather than pretending its rows are unchanged.
export function changedCells(beforeKeys:readonly string[],before:readonly (readonly string[])[],keys:readonly string[],rows:readonly (readonly string[])[]){
 if(beforeKeys.length!==keys.length||beforeKeys.some((key,n)=>key!==keys[n])||before.some((row,n)=>row.length!==rows[n]?.length))return null;
 return rows.flatMap((row,n)=>row.flatMap((value,column)=>value===before[n][column]?[]:[{row:n,column}]));
}
