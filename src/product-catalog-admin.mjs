/** D05-F01: tenant-scoped catalog master and branch publication. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("CATALOG_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("CATALOG_ADAPTER_REQUIRED",k);return d[k];};
export async function publishProductCatalog(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),actorId:req(input?.actorId,"actorId"),version:input.version,products:input.products,categories:input.categories??[],branchIds:input.branchIds??[]};
 if(!Number.isSafeInteger(payload.version)||payload.version<1||!Array.isArray(payload.products)||!payload.products.length)fail("CATALOG_PAYLOAD_INVALID","Catalog version and products are required");
 const skus=new Set();for(const p of payload.products){const sku=req(p.sku,"sku");if(skus.has(sku))fail("CATALOG_DUPLICATE_SKU","SKU must be unique in the catalog batch");skus.add(sku);req(p.name,"product name");}
 const result=await fn(deps,"publishProductCatalogAtomically")(payload);
 if(!result?.catalogVersion||result.catalogVersion!==payload.version||result.tenantId!==payload.tenantId||
  !Array.isArray(result.publishedBranches)||!Array.isArray(result.exceptions))fail("CATALOG_PUBLISH_FAILED","Catalog rollout result is incomplete");
 return Object.freeze(result);
}
