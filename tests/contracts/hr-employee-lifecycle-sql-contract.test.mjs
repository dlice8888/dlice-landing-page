import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const sql=readFileSync(new URL("../../docs/implementation/sql/HR_EMPLOYEE_LIFECYCLE_EXTENSION_DRAFT.sql",import.meta.url),"utf8");

test("HR employee identity is tenant-scoped and linked to existing Auth/profile/branch foundations",()=>{
 assert.match(sql,/unique\(tenant_id,employee_user_id\)/);
 assert.match(sql,/foreign key\(tenant_id,primary_branch_id\) references public\.branches\(tenant_id,id\)/);
 assert.match(sql,/join public\.tenant_memberships tm/);
 assert.match(sql,/join public\.branch_assignments ba/);
 assert.match(sql,/join public\.admin_profiles ap/);
 assert.match(sql,/INDEPENDENT_HR_EMPLOYEE_CREATOR_REQUIRED/);
});

test("employee lifecycle event history is append-only and service-role-only",()=>{
 assert.match(sql,/hr_employee_lifecycle_events_append_only/);
 assert.match(sql,/revoke all on public\.hr_employee_records,public\.hr_employee_lifecycle_events from public,anon,authenticated/);
 assert.match(sql,/grant select,insert on public\.hr_employee_lifecycle_events to service_role/);
});

test("transfer and position change close prior tenant assignments and create a new effective assignment atomically",()=>{
 assert.match(sql,/HR_TRANSFER_REQUIRES_DIFFERENT_TARGET_BRANCH/);
 assert.match(sql,/HR_POSITION_CHANGE_REQUIRES_DIFFERENT_POSITION/);
 assert.match(sql,/HR_REACTIVATION_REQUIRES_BRANCH_AND_POSITION/);
 assert.match(sql,/employment_status='inactive',[\s\S]*ends_on=p_effective_on-1/);
 assert.match(sql,/insert into public\.branch_assignments\(branch_id,user_id,job_position_id,employment_status,starts_on,ends_on,assigned_by\)/);
});

test("leave transitions require an approved leave request and update branch assignment state",()=>{
 assert.match(sql,/status='approved' for update/);
 assert.match(sql,/employment_status='on_leave'/);
 assert.match(sql,/employment_status='active'/);
});

test("termination is two-step, blocks pending timesheets and revokes only the selected tenant membership",()=>{
 assert.match(sql,/offboarding_pending/);
 assert.match(sql,/HR_PENDING_TIMESHEETS_BLOCK_TERMINATION/);
 assert.match(sql,/INDEPENDENT_OFFBOARDING_APPROVER_REQUIRED/);
 assert.match(sql,/HR_OPEN_LEAVE_BLOCKS_TERMINATION/);
 assert.match(sql,/FUTURE_DATED_LIFECYCLE_EVENT_REQUIRES_SCHEDULED_WORKER/);
 assert.match(sql,/HR_CANNOT_REVOKE_LAST_TENANT_OWNER/);
 assert.match(sql,/HR_ACTIVE_TENANT_MEMBERSHIP_REQUIRED/);
 assert.match(sql,/HR_LIFECYCLE_IDEMPOTENCY_COLLISION/);
 assert.match(sql,/update public\.tenant_memberships set status='revoked'/);
 assert.doesNotMatch(sql,/update public\.admin_profiles set is_active=false/);
});

test("reactivation requires an active Auth profile and a revoked tenant membership",()=>{
 assert.match(sql,/HR_AUTH_PROFILE_MUST_BE_REACTIVATED_FIRST/);
 assert.match(sql,/status='revoked'/);
 assert.match(sql,/set status='active'/);
});
