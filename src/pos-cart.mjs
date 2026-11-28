/** Server-authoritative cart pricing contract. Client-supplied prices are never read. */
const integer=(v,n)=>{if(!Number.isSafeInteger(v)||v<0)throw new TypeError(n+"_invalid");return v;};
export function buildValidatedCart({ requestedItems, catalogItems, branchId, availableStockByProduct }) {
  if(!Array.isArray(requestedItems)||requestedItems.length===0)throw new Error("cart_empty");
  const catalog=new Map((catalogItems||[]).map(p=>[p.id,p]));
  const seen=new Set();
  const items=requestedItems.map((requested)=>{
    if(!requested?.productId||seen.has(requested.productId))throw new Error("cart_duplicate_or_invalid_product");
    seen.add(requested.productId);
    const product=catalog.get(requested.productId);
    if(!product||product.is_active!==true)throw new Error("product_unavailable");
    if(!product.allowed_branch_ids?.includes(branchId))throw new Error("product_branch_forbidden");
    if(!Number.isInteger(requested.quantity)||requested.quantity<1||requested.quantity>100)throw new Error("quantity_invalid");
    const stock=availableStockByProduct?.[product.id];
    if(Number.isInteger(stock)&&requested.quantity>stock)throw new Error("insufficient_available_stock");
    const unit=integer(product.unit_price_idr,"server_price");
    const modifierOptions=new Map((product.modifiers||[]).filter(m=>m.is_active).map(m=>[m.id,m]));
    const selected=(requested.modifierIds||[]).map(id=>{
      const modifier=modifierOptions.get(id);
      if(!modifier)throw new Error("modifier_unavailable");
      return Object.freeze({id:modifier.id,name:modifier.name,price_idr:integer(modifier.price_idr||0,"modifier_price")});
    });
    for(const group of product.required_modifier_groups||[]) {
      if(!selected.some(m=>(group.option_ids||[]).includes(m.id)))throw new Error("required_modifier_missing");
    }
    const modifierTotal=selected.reduce((s,m)=>s+m.price_idr,0);
    const lineTotal=(unit+modifierTotal)*requested.quantity;
    if(!Number.isSafeInteger(lineTotal))throw new RangeError("cart_total_out_of_range");
    return Object.freeze({product_id:product.id,product_name_snapshot:product.name,quantity:requested.quantity,unit_price_idr:unit,modifier_snapshot:selected,line_total_idr:lineTotal,note:typeof requested.note==="string"?requested.note.trim().slice(0,300):""});
  });
  return Object.freeze({branch_id:branchId,items:Object.freeze(items),subtotal_idr:items.reduce((s,i)=>s+i.line_total_idr,0)});
}
