import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const html=readFileSync(new URL("../../erp.html",import.meta.url),"utf8");
test("Executive approval center exposes scoped queue, evidence, claim and decision UI",()=>{
 for(const id of ["executiveApprovalBranch","executiveApprovalDomain","executiveApprovalText","executiveApprovalList","loadExecutiveApprovals"])assert.match(html,new RegExp('id="'+id+'"'));
 assert.match(html,/erp-list-pending-approvals/);
 assert.match(html,/erp-claim-approval/);
 assert.match(html,/erp-decide-approval/);
 assert.match(html,/approvalReason-/);
 assert.match(html,/source_version/);
 assert.match(html,/item\.evidence/);
});
test("approval UI requires claim and reason before approve or reject",()=>{
 assert.match(html,/if\(!claim\)throw new Error\('Claim approval diperlukan/);
 assert.match(html,/reason\.length<8/);
 assert.match(html,/disabled/);
 assert.match(html,/crypto\.randomUUID\(\)/);
});
