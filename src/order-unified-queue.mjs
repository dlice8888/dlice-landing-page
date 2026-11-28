/** Unified POS/online queue projection. Source orders remain authoritative. */
const req=(v,n)=>{if(typeof v!=="string"||!v.trim())throw new Error("ORDER_QUEUE_"+n+"_REQUIRED");return v.trim();};
export function buildUnifiedOrderQueue({posOrders=[],onlineOrders=[],tenantId,allowedBranchIds=[],filters={},now=new Date().toISOString()}){
 const tenant=req(tenantId,"TENANT"),branches=new Set(allowedBranchIds);if(!branches.size)throw new Error("ORDER_QUEUE_SCOPE_REQUIRED");
 const rows=[...posOrders.map(x=>({...x,channel:"pos"})),...onlineOrders.map(x=>({...x,channel:"online"}))];
 const byId=new Map(),external=new Map();
 for(const row of rows){
  if(row.tenant_id!==tenant||!branches.has(row.branch_id))continue;
  req(row.id,"ID");req(row.created_at,"CREATED_AT");
  const time=Date.parse(row.created_at);if(!Number.isFinite(time)||time>Date.parse(now))throw new Error("ORDER_QUEUE_TIMESTAMP_INVALID");
  if(row.external_order_id){const key=row.channel+":"+row.external_order_id;const prior=external.get(key);if(prior&&prior!==row.id)throw new Error("ORDER_QUEUE_EXTERNAL_ID_COLLISION");external.set(key,row.id);}
  const prior=byId.get(row.id);
  if(prior){if(prior.tenant_id!==row.tenant_id||prior.branch_id!==row.branch_id)throw new Error("ORDER_QUEUE_CANONICAL_SCOPE_MISMATCH");if((prior.order_status&&row.order_status&&prior.order_status!==row.order_status)||(prior.payment_status&&row.payment_status&&prior.payment_status!==row.payment_status)||(prior.fulfillment_status&&row.fulfillment_status&&prior.fulfillment_status!==row.fulfillment_status))throw new Error("ORDER_QUEUE_SOURCE_STATUS_MISMATCH");prior.channels=[...new Set([...prior.channels,row.channel])];continue;}
  byId.set(row.id,{id:row.id,tenant_id:tenant,branch_id:row.branch_id,channels:[row.channel],created_at:row.created_at,order_status:row.order_status,payment_status:row.payment_status,fulfillment_status:row.fulfillment_status,external_order_id:row.external_order_id||null,customer_reference:row.customer_reference||null});
 }
 return [...byId.values()].filter(x=>(!filters.branchId||x.branch_id===filters.branchId)&&(!filters.channel||x.channels.includes(filters.channel))&&(!filters.orderStatus||x.order_status===filters.orderStatus)).sort((a,b)=>Date.parse(a.created_at)-Date.parse(b.created_at)||a.id.localeCompare(b.id)).map(Object.freeze);
}
