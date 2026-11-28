/** D06-F03: tenant-safe warehouse, zone and bin hierarchy. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("WAREHOUSE_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("WAREHOUSE_ADAPTER_REQUIRED",k);return d[k];};
export async function createWarehouseLocation(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),branchId:req(input?.branchId,"branchId"),actorId:req(input?.actorId,"actorId"),
  warehouseId:req(input?.warehouseId,"warehouseId"),parentLocationId:input.parentLocationId??null,code:req(input?.code,"code"),
  name:req(input?.name,"name"),locationType:input.locationType,capacity:input.capacity??null};
 if(!["zone","bin"].includes(payload.locationType)||payload.code.length>40)fail("WAREHOUSE_LOCATION_INVALID","Location type or code invalid");
 if(payload.capacity!==null&&(!Number.isFinite(payload.capacity)||payload.capacity<0))fail("WAREHOUSE_CAPACITY_INVALID","Capacity must be non-negative");
 const result=await fn(deps,"createWarehouseLocationAtomically")(payload);
 if(!result?.locationId||result.tenantId!==payload.tenantId||result.branchId!==payload.branchId||result.locationType!==payload.locationType)
  fail("WAREHOUSE_LOCATION_CREATE_FAILED","Warehouse location was not persisted in tenant scope");
 return Object.freeze(result);
}
