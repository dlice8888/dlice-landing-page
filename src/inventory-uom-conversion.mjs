/** Dimension-safe UOM conversion with immutable effective snapshots. */
export function convertInventoryQuantity({quantity,fromUom,toUom,conversions,at,precision=3}){
 if(!Number.isFinite(quantity)||quantity<0||!fromUom||!toUom||!Number.isFinite(Date.parse(at))||!Number.isInteger(precision)||precision<0||precision>9)throw new Error("INVENTORY_UOM_INPUT_INVALID");
 if(fromUom===toUom)return Object.freeze({quantity,from_uom:fromUom,to_uom:toUom,conversion_version:"identity"});
 const row=(conversions||[]).filter(x=>x.from_uom===fromUom&&x.to_uom===toUom&&x.status==="active"&&Date.parse(x.effective_from)<=Date.parse(at)&&(!x.effective_to||Date.parse(x.effective_to)>Date.parse(at))).sort((a,b)=>Date.parse(b.effective_from)-Date.parse(a.effective_from))[0];
 if(!row||!Number.isFinite(row.factor)||row.factor<=0||row.from_dimension!==row.to_dimension)throw new Error("INVENTORY_UOM_CONVERSION_NOT_FOUND");
 const scale=10**precision,result=Math.round(quantity*row.factor*scale)/scale;
 return Object.freeze({quantity:result,from_uom:fromUom,to_uom:toUom,conversion_version:row.version});
}
