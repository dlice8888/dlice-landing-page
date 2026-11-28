/**
 * Fail-closed authorization for company -> region -> branch -> shift -> transaction.
 * Resolve ancestry from trusted DB records; never trust client-supplied parent ids.
 */
const fail=(c,m)=>{const e=new Error(m);e.code=c;throw e;};
const levels=["company","region","branch","shift","transaction"];
export function authorizeExecutiveDrilldown({actor,target,ancestry,scope}) {
 if(!actor?.userId||!actor.tenantId||!target?.id||!levels.includes(target.level))fail("EXECUTIVE_DRILLDOWN_IDENTITY_REQUIRED","Actor and target identity are required");
 if(!Array.isArray(ancestry)||ancestry.length!==levels.indexOf(target.level)+1)fail("EXECUTIVE_ANCESTRY_INCOMPLETE","Full ancestry from company to requested target is required");
 for(let i=0;i<ancestry.length;i++){
  const node=ancestry[i];if(node.level!==levels[i]||!node.id||node.tenantId!==actor.tenantId)fail("EXECUTIVE_TENANT_OR_ANCESTRY_MISMATCH","Ancestry is invalid or crosses tenant boundary");
  if(i>0&&node.parentId!==ancestry[i-1].id)fail("EXECUTIVE_PARENT_CHAIN_INVALID","Every drilldown node must link to its verified parent");
  if(i===2&&scope?.branchIds&&!scope.branchIds.includes(node.id))fail("EXECUTIVE_BRANCH_SCOPE_DENIED","Actor is not assigned to this branch");
 }
 const role=actor.platformOwner===true||actor.permissions?.includes("executive.drilldown.all")||actor.permissions?.includes("executive.drilldown.scoped");
 if(!role)fail("EXECUTIVE_DRILLDOWN_FORBIDDEN","Explicit executive drilldown permission is required");
 if(actor.platformOwner!==true&&actor.permissions.includes("executive.drilldown.scoped")&&target.level==="company")fail("EXECUTIVE_COMPANY_SCOPE_DENIED","Scoped executive cannot access company-wide drilldown");
 return Object.freeze({allowed:true,tenantId:actor.tenantId,targetLevel:target.level,targetId:target.id,ancestryIds:Object.freeze(ancestry.map(x=>x.id))});
}
