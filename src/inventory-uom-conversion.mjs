/** D06-F04: effective-dated unit conversion with dimension and precision checks. */
const fail=(code,message)=>{throw Object.assign(new Error(message),{code});};
const req=(v,k)=>{if(typeof v!=="string"||!v.trim())fail("INVENTORY_UOM_INPUT_REQUIRED",k);return v.trim();};
const fn=(d,k)=>{if(typeof d?.[k]!=="function")fail("INVENTORY_UOM_ADAPTER_REQUIRED",k);return d[k];};
export async function convertInventoryQuantity(input,deps){
 const payload={tenantId:req(input?.tenantId,"tenantId"),inventoryItemId:req(input?.inventoryItemId,"inventoryItemId"),
  quantity:input.quantity,fromUnit:req(input?.fromUnit,"fromUnit"),toUnit:req(input?.toUnit,"toUnit"),effectiveDate:req(input?.effectiveDate,"effectiveDate")};
 if(!Number.isFinite(payload.quantity)||payload.quantity<0)fail("INVENTORY_UOM_QUANTITY_INVALID","Quantity must be non-negative");
 const result=await fn(deps,"convertInventoryQuantityReadOnly")(payload);
 if(!result||result.tenantId!==payload.tenantId||result.inventoryItemId!==payload.inventoryItemId||
  !Number.isFinite(result.convertedQuantity)||result.convertedQuantity<0||!Number.isFinite(result.factor)||result.factor<=0||
  result.fromUnit!==payload.fromUnit||result.toUnit!==payload.toUnit)fail("INVENTORY_UOM_CONVERSION_INVALID","UOM conversion result invalid");
 return Object.freeze(result);
}
