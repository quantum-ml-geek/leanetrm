import type {VolSurfaceResult} from './vol-surface-view.js';

// The term structure of a stored surface: each expiry's fitted smile at the money. The level and slope are the fit's own
// stored parameters, shown as they are; an expiry that is not fitted has neither, and nothing is interpolated across it.

/** One expiry of the term structure: its fitted level (the smile at the money) and slope there, or why it has none. */
export type TermPoint={expiryAt:string;status:string;level:string|null;slope:string|null;points:number;rmsResidual:string|null};

/** One point per expiry, in the surface's order. */
export function termPoints(surface:VolSurfaceResult):TermPoint[]{
 return surface.expiries.map(expiry=>{
  const fitted=expiry.status==='fitted';
  if(fitted&&!expiry.parameters)throw Error('The surface fits an expiry without stating its parameters.');
  return {expiryAt:expiry.expiryAt,status:expiry.status,level:fitted?expiry.parameters!.a:null,slope:fitted?expiry.parameters!.b:null,points:expiry.points,rmsResidual:expiry.rmsResidual};
 });
}
