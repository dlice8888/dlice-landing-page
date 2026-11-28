/**
 * D01-F02 Executive live sales monitor.
 *
 * This module deliberately treats payment as the sales-recognition event and
 * settlement as a separate reconciliation dimension. The adapter must resolve
 * authorized tenant/branch scope from the authenticated server session.
 */
const fail=(code,message)=>{const e=new Error(message);e.code=code;throw e;};
const required=(v,name)=>{if(typeof v!=="string"||!v.trim())fail("EXEC_SALES_INPUT_REQUIRED",name);return v.trim();};
const fn=(d,n)=>{if(typeof d?.[n]!=="function")fail("EXEC_SALES_ADAPTER_REQUIRED",n);return d[n];};
const money=(v,name)=>{if(!Number.isSafeInteger(v)||v<0)fail("EXEC_SALES_INVALID_AMOUNT",name);return v;};
const dateKey=(instant,timeZone)=>{
 const parts=new Intl.DateTimeFormat("en-CA",{timeZone,year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(instant);
 const get=k=>parts.find(p=>p.type===k)?.value;
 return `${get("year")}-${get("month")}-${get("day")}`;
};
const periodStart=(businessDate,period)=>{
 const d=new Date(`${businessDate}T00:00:00Z`);
 if(period==="day")return businessDate;
 if(period==="week"){const day=d.getUTCDay()||7;d.setUTCDate(d.getUTCDate()-day+1);}
 else if(period==="month")d.setUTCDate(1);
 else fail("EXEC_SALES_PERIOD_INVALID","period must be day, week, or month");
 return d.toISOString().slice(0,10);
};
const sum=(xs,fn)=>xs.reduce((n,x)=>{const v=fn(x),r=n+v;if(!Number.isSafeInteger(r))fail("EXEC_SALES_TOTAL_OVERFLOW","sales total overflow");return r;},0);

/**
 * Required transaction adapters:
 * authorizeExecutiveRead(tx,{actorId,tenantId,branchIds}),
 * resolveAuthorizedBranches(tx,scope), loadPaidSales(tx,scope),
 * loadProcessedRefunds(tx,scope), loadSettlementFacts(tx,scope),
 * appendAudit(tx,event).
 * Never accept client-provided role, tenant membership, or branch membership.
 */
export async function getExecutiveSalesMonitor(input,deps){
 const actorId=required(input?.actorId,"actorId"),tenantId=required(input?.tenantId,"tenantId");
 const period=input?.period??"day";
 if(!["day","week","month"].includes(period))fail("EXEC_SALES_PERIOD_INVALID","Unsupported period");
 const requestedDate=required(input?.businessDate,"businessDate");
 if(!/^\d{4}-\d{2}-\d{2}$/.test(requestedDate)||Number.isNaN(Date.parse(requestedDate)))fail("EXEC_SALES_DATE_INVALID","businessDate must be YYYY-MM-DD");
 const requestedBranches=input?.branchIds??[];
 if(!Array.isArray(requestedBranches)||requestedBranches.some(x=>typeof x!=="string"))fail("EXEC_SALES_BRANCH_FILTER_INVALID","branchIds must be strings");
 const scope=Object.freeze({actorId,tenantId,requestedDate,period,requestedBranches});
 return fn(deps,"withTenantTransaction")(scope,async tx=>{
  await fn(deps,"authorizeExecutiveRead")(tx,scope);
  const branches=await fn(deps,"resolveAuthorizedBranches")(tx,scope);
  if(!Array.isArray(branches)||branches.length===0)fail("EXEC_SALES_NO_AUTHORIZED_BRANCH","No authorized branches in scope");
  const branchMap=new Map();
  for(const b of branches){
   if(b.tenantId!==tenantId||!b.id||!b.timezone)fail("EXEC_SALES_BRANCH_SCOPE_MISMATCH","Branch scope must be server-resolved and tenant-bound");
   try{new Intl.DateTimeFormat("en",{timeZone:b.timezone});}catch{fail("EXEC_SALES_TIMEZONE_INVALID",b.timezone);}
   if(branchMap.has(b.id))fail("EXEC_SALES_DUPLICATE_BRANCH","Duplicate branch in authorized scope");
   branchMap.set(b.id,b);
  }
  const allowedIds=[...branchMap.keys()];
  const [sales,refunds,settlements]=await Promise.all([
   fn(deps,"loadPaidSales")(tx,{...scope,branchIds:allowedIds}),
   fn(deps,"loadProcessedRefunds")(tx,{...scope,branchIds:allowedIds}),
   fn(deps,"loadSettlementFacts")(tx,{...scope,branchIds:allowedIds})
  ]);
  if(!Array.isArray(sales)||!Array.isArray(refunds)||!Array.isArray(settlements))fail("EXEC_SALES_SOURCE_INVALID","All source adapters must return arrays");
  const saleById=new Map(),accepted=[];
  for(const sale of sales){
   const branch=branchMap.get(sale.branchId);
   if(!branch||sale.tenantId!==tenantId)fail("EXEC_SALES_SOURCE_SCOPE_MISMATCH","Sale outside authorized scope");
   if(!sale.id||saleById.has(sale.id))fail("EXEC_SALES_DUPLICATE_SALE","Duplicate sale source row");
   if(sale.paymentStatus!=="paid"||!sale.paidAt)continue;
   const paidAt=new Date(sale.paidAt);
   if(Number.isNaN(paidAt.valueOf()))fail("EXEC_SALES_PAYMENT_TIME_INVALID",sale.id);
   const businessDate=dateKey(paidAt,branch.timezone);
   if(businessDate>requestedDate)continue;
   const gross=money(sale.subtotalIdr,"subtotalIdr"),discount=money(sale.discountIdr??0,"discountIdr"),total=money(sale.totalIdr,"totalIdr");
   if(gross-discount!==total)fail("EXEC_SALES_SOURCE_TOTAL_MISMATCH",sale.id);
   const row={...sale,businessDate,grossIdr:gross,discountIdr:discount,netBeforeRefundIdr:total};
   saleById.set(sale.id,row);accepted.push(row);
  }
  const refundBySale=new Map();
  for(const refund of refunds){
   if(refund.tenantId!==tenantId||!branchMap.has(refund.branchId))fail("EXEC_SALES_REFUND_SCOPE_MISMATCH","Refund outside authorized scope");
   if(refund.status!=="processed")continue;
   if(!saleById.has(refund.saleId))continue;
   const amount=money(refund.amountIdr,"refund.amountIdr");
   refundBySale.set(refund.saleId,(refundBySale.get(refund.saleId)??0)+amount);
  }
  const rows=accepted.map(s=>{
   const refundIdr=refundBySale.get(s.id)??0;
   if(refundIdr>s.netBeforeRefundIdr)fail("EXEC_SALES_REFUND_EXCEEDS_SALE",s.id);
   return Object.freeze({...s,refundIdr,netSalesIdr:s.netBeforeRefundIdr-refundIdr});
  }).filter(s=>s.businessDate>=periodStart(requestedDate,period));
  const includedIds=new Set(rows.map(x=>x.id));
  const settlementRows=settlements.filter(x=>includedIds.has(x.saleId));
  for(const x of settlementRows)if(x.tenantId!==tenantId||!branchMap.has(x.branchId))fail("EXEC_SALES_SETTLEMENT_SCOPE_MISMATCH","Settlement outside authorized scope");
  const result={
   tenantId,period,businessDate:requestedDate,branchIds:allowedIds,
   timezoneByBranch:Object.fromEntries(branches.map(b=>[b.id,b.timezone])),
   grossSalesIdr:sum(rows,x=>x.grossIdr),
   discountIdr:sum(rows,x=>x.discountIdr),
   refundIdr:sum(rows,x=>x.refundIdr),
   netSalesIdr:sum(rows,x=>x.netSalesIdr),
   paidTransactionCount:rows.length,
   settlement:{matchedIdr:sum(settlementRows,x=>money(x.matchedAmountIdr,"matchedAmountIdr")),unmatchedCount:settlementRows.filter(x=>x.status!=="matched").length},
   transactions:rows.map(x=>({id:x.id,transactionCode:x.transactionCode,branchId:x.branchId,businessDate:x.businessDate,paidAt:x.paidAt,grossIdr:x.grossIdr,discountIdr:x.discountIdr,refundIdr:x.refundIdr,netSalesIdr:x.netSalesIdr}))
  };
  await fn(deps,"appendAudit")(tx,{actorId,tenantId,action:"executive.sales_monitor.read",metadata:{period,businessDate:requestedDate,branchCount:allowedIds.length,transactionCount:rows.length}});
  return Object.freeze(result);
 });
}
