/** Deterministic tenant-scoped branch routing; reservations remain atomic server RPCs. */
const rad=x=>x*Math.PI/180;
const pointInPolygon=(point,polygon)=>{let inside=false;for(let i=0,j=polygon.length-1;i<polygon.length;j=i++){const a=polygon[i],b=polygon[j];const intersects=((a.longitude>point.longitude)!==(b.longitude>point.longitude))&&(point.latitude<(b.latitude-a.latitude)*(point.longitude-a.longitude)/(b.longitude-a.longitude)+a.latitude);if(intersects)inside=!inside;}return inside;};\nconst distanceKm=(a,b)=>{const dLat=rad(b.latitude-a.latitude),dLon=rad(b.longitude-a.longitude),x=Math.sin(dLat/2)**2+Math.cos(rad(a.latitude))*Math.cos(rad(b.latitude))*Math.sin(dLon/2)**2;return 6371*2*Math.atan2(Math.sqrt(x),Math.sqrt(1-x));};
export function chooseOrderBranch({tenantId,latitude,longitude,branches,requestedBranchId,actorCanOverride=false}){
 if(!tenantId||!Number.isFinite(latitude)||!Number.isFinite(longitude))throw new Error("ORDER_ROUTING_LOCATION_INVALID");
 if(requestedBranchId&&!actorCanOverride)throw new Error("ORDER_ROUTING_OVERRIDE_FORBIDDEN");
 const candidates=(branches||[]).filter(b=>b.tenant_id===tenantId&&b.status==="active"&&b.accepts_orders!==false&&Number.isFinite(b.latitude)&&Number.isFinite(b.longitude)&&Number.isFinite(b.service_radius_km)&&b.service_radius_km>0).map(b=>({...b,distance_km:distanceKm({latitude,longitude},b)})).filter(b=>(Array.isArray(b.service_area_polygon)&&b.service_area_polygon.length>=3?pointInPolygon({latitude,longitude},b.service_area_polygon):b.distance_km<=b.service_radius_km)&&b.capacity_used<b.capacity_limit);
 if(requestedBranchId){const selected=candidates.find(b=>b.id===requestedBranchId);if(!selected)throw new Error("ORDER_ROUTING_OVERRIDE_NOT_ELIGIBLE");return Object.freeze({branch_id:selected.id,distance_km:selected.distance_km,reason:"authorized_manual_override"});}
 candidates.sort((a,b)=>a.distance_km-b.distance_km||((a.capacity_used/a.capacity_limit)-(b.capacity_used/b.capacity_limit))||a.id.localeCompare(b.id));
 if(!candidates.length)throw new Error("ORDER_ROUTING_NO_ELIGIBLE_BRANCH");
 const selected=candidates[0];return Object.freeze({branch_id:selected.id,distance_km:selected.distance_km,reason:"nearest_eligible_with_capacity"});
}
