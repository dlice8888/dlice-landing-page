/** Dimension-safe UOM conversion chains with immutable effective snapshots. */
export function convertInventoryQuantity({quantity,fromUom,toUom,conversions,at,precision=3}){
 if(!Number.isFinite(quantity)||quantity<0||!fromUom||!toUom||!Number.isFinite(Date.parse(at))||!Number.isInteger(precision)||precision<0||precision>9)throw new Error("INVENTORY_UOM_INPUT_INVALID");
 if(fromUom===toUom)return Object.freeze({quantity,from_uom:fromUom,to_uom:toUom,conversion_version:"identity"});
 const active=(conversions||[]).filter(x=>x.status==="active"&&Date.parse(x.effective_from)<=Date.parse(at)&&(!x.effective_to||Date.parse(x.effective_to)>Date.parse(at)));
 const graph=new Map();
 for(const row of active){
  if(!row.from_uom||!row.to_uom||!Number.isFinite(row.factor)||row.factor<=0||!row.from_dimension||row.from_dimension!==row.to_dimension)throw new Error("INVENTORY_UOM_CONVERSION_INVALID");
  const edges=graph.get(row.from_uom)||[];edges.push({to:row.to_uom,factor:row.factor,version:row.version||"unversioned"});graph.set(row.from_uom,edges);
 }
 const visiting=new Set(),visited=new Set();
 const detectCycle=node=>{
  if(visiting.has(node))throw new Error("INVENTORY_UOM_CONVERSION_CYCLE");
  if(visited.has(node))return;
  visiting.add(node);for(const edge of graph.get(node)||[])detectCycle(edge.to);visiting.delete(node);visited.add(node);
 };
 for(const node of graph.keys())detectCycle(node);
 const paths=[];
 const walk=(node,factor,versions,path)=>{
  if(node===toUom){paths.push({factor,versions,path});return;}
  for(const edge of graph.get(node)||[])if(!path.includes(edge.to))walk(edge.to,factor*edge.factor,[...versions,edge.version],[...path,edge.to]);
 };
 walk(fromUom,1,[],[fromUom]);
 if(!paths.length)throw new Error("INVENTORY_UOM_CONVERSION_NOT_FOUND");
 const shortest=Math.min(...paths.map(p=>p.path.length));
 const best=paths.filter(p=>p.path.length===shortest);
 if(best.some(p=>Math.abs(p.factor-best[0].factor)>1e-9))throw new Error("INVENTORY_UOM_AMBIGUOUS_PATH");
 const scale=10**precision,result=Math.round(quantity*best[0].factor*scale)/scale;
 return Object.freeze({quantity:result,from_uom:fromUom,to_uom:toUom,conversion_version:best[0].versions.join("+"),conversion_path:Object.freeze(best[0].path)});
}
