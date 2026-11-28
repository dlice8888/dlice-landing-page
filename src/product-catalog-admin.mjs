/** Central catalog change validation and branch publication contract. */
export function validateProductCatalogChange({product,existingSkus=[],actor,scope,operation="upsert"}){
 if(!actor?.user_id||!scope?.tenant_id||product?.tenant_id!==scope.tenant_id)throw new Error("CATALOG_TENANT_SCOPE_FORBIDDEN");
 if(!["hq_catalog_admin","platform_owner"].includes(actor.role))throw new Error("CATALOG_MASTER_WRITE_FORBIDDEN");
 if(typeof product.sku!=="string"||!product.sku.trim()||typeof product.name!=="string"||!product.name.trim())throw new Error("CATALOG_PRODUCT_REQUIRED");
 if(existingSkus.some(x=>x.tenant_id===scope.tenant_id&&x.sku.toLowerCase()===product.sku.toLowerCase()&&x.id!==product.id))throw new Error("CATALOG_SKU_DUPLICATE");
 if(operation==="activate"&&actor.user_id===product.created_by&&product.separation_of_duties===true)throw new Error("CATALOG_SELF_APPROVAL_FORBIDDEN");
 return Object.freeze({tenant_id:scope.tenant_id,product_id:product.id||null,sku:product.sku.trim(),operation,actor_user_id:actor.user_id,audit_required:true});
}
export function resolvePublishedCatalog({products,branchId,now}){
 const instant=Date.parse(now);if(!branchId||!Number.isFinite(instant))throw new Error("CATALOG_RESOLUTION_CONTEXT_INVALID");
 return (products||[]).filter(p=>p.is_active===true&&(!p.branch_ids||p.branch_ids.includes(branchId))&&Date.parse(p.effective_from)<=instant&&(!p.effective_to||Date.parse(p.effective_to)>instant)).map(p=>Object.freeze({product_id:p.id,sku:p.sku,name:p.name,version:p.version,price_idr:p.price_idr}));
}
