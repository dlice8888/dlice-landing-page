import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
const read=async name=>readFile(new URL("../../supabase/migrations/"+name,import.meta.url),"utf8");
test("T01 migration versions KPI, derives branch business date and records traceable sale snapshots",async()=>{
 const sql=await read("20261128101500_executive_sales_monitor.sql");
 for(const token of ["branch_business_day_policies","executive_kpi_formula_versions","executive_kpi_formula_one_active_idx","sales-net-v1","pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_branch_id::text,0))","executive_sales_monitor_snapshots","executive_sales_monitor_snapshot_rows","s.created_at at time zone b.timezone","s.payment_status in ('paid','refunded')","r.status='processed'","s.status='matched'","finance_journal_entries","EXECUTIVE_REFUND_EXCEEDS_SALE_TOTAL","tender_mismatch_count","admin_audit_logs","p_branch_ids","set_branch_business_day_cutoff","get_branch_business_day_cutoff"])
  assert.ok(sql.includes(token),"missing T01 contract: "+token);
 assert.ok(sql.includes("revoke all on function public.executive_sales_monitor_snapshot"));
 assert.ok(sql.includes("grant execute on function public.executive_sales_monitor_snapshot")&&sql.includes("to service_role"));
});
test("T02 migration persists inbox, delegation, expiry and atomic source transitions",async()=>{
 const sql=await read("20261128102000_executive_approval_center.sql");
 for(const token of ["executive_approval_policies","executive_approval_requests","executive_approval_delegations","executive_approval_decisions","expires_at","claim_expires_at","APPROVAL_SELF_APPROVAL_DENIED","APPROVAL_STALE_VERSION","APPROVAL_AMOUNT_LIMIT","APPROVAL_CLAIMED_BY_OTHER","APPROVAL_CLAIM_REQUIRED","a.status<>'claimed' or a.claimed_by is distinct from p_actor_user_id","purchase_requisition","refund_record","hr_payroll_run","branch_ops_compliance_check","get diagnostics v_updated=row_count","if v_updated<>1","admin_audit_logs","list_pending_approvals","claim_approval","decide_approval","list_approval_decision_history","create_approval_delegation","approve_approval_delegation","revoke_approval_delegation","list_approval_delegations","executive_approval_actor_role","branch_assignments","job_positions","tenant_owner","branch_manager"])
  assert.ok(sql.includes(token),"missing T02 contract: "+token);
 assert.ok(sql.includes("revoke all on function public.decide_approval")&&sql.includes("grant execute on function public.decide_approval")&&sql.includes("to service_role"));
});

test("T02 delegation approval and revocation fail closed when actor membership is absent",async()=>{
 const sql=await read("20261128102000_executive_approval_center.sql");
 assert.ok(sql.includes("v_role is distinct from 'tenant_owner'"));
 assert.ok(sql.includes("v_row.delegator_user_id<>p_actor_user_id and v_role is distinct from 'tenant_owner'"));
 assert.ok(sql.includes("APPROVAL_DELEGATION_SELF_APPROVAL_DENIED"));
});
