import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const draft = readFileSync(new URL("../../docs/implementation/sql/BRANCH_OPERATIONS_CONCRETE_PERSISTENCE_DRAFT.sql", import.meta.url), "utf8");
const adapter = readFileSync(new URL("../../src/branch-operations-supabase-repository.mjs", import.meta.url), "utf8");
const edge = readFileSync(new URL("../../supabase/functions/_shared/branch-operations-repository.ts", import.meta.url), "utf8");

const signatures = [
  ["branch_ops_register_equipment", "uuid,uuid,uuid,text,text"],
  ["branch_ops_create_task", "uuid,uuid,uuid,uuid,text,text,text,timestamptz,text,text,uuid"],
  ["branch_ops_update_task_status", "uuid,uuid,uuid,uuid,text"],
  ["branch_ops_record_incident", "uuid,uuid,uuid,text,text,text,text,timestamptz,uuid[]"],
  ["branch_ops_update_incident_status", "uuid,uuid,uuid,uuid,text"],
  ["branch_ops_create_maintenance_order", "uuid,uuid,uuid,uuid,text,text,timestamptz,text,uuid,uuid[]"],
  ["branch_ops_update_work_order_status", "uuid,uuid,uuid,uuid,text"],
  ["branch_ops_register_evidence_asset", "uuid,uuid,uuid,text,text,text,bigint"],
  ["branch_ops_submit_compliance_check", "uuid,uuid,uuid,text,text,integer,date,uuid"],
  ["branch_ops_review_compliance_check", "uuid,uuid,uuid,uuid,text"],
  ["branch_ops_publish_compliance_snapshot", "uuid,uuid,uuid,date,date,text,text"],
];

test("every Branch Operations adapter RPC has the exact canonical SQL signature", () => {
  for (const [name, args] of signatures) {
    assert.ok(draft.includes(`create or replace function public.${name}(`), `SQL defines ${name}`);
    assert.ok(draft.includes(`revoke all on function public.${name}(${args}) from public,anon,authenticated;`), `${name} revokes client ACL`);
    assert.ok(draft.includes(`grant execute on function public.${name}(${args}) to service_role;`), `${name} grants service_role ACL`);
    assert.ok(adapter.includes(`"${name}"`), `Node adapter calls ${name}`);
    assert.ok(edge.includes(`"${name}"`), `Edge adapter calls ${name}`);
  }
});

test("scope parameters are tenant, branch and verified actor for every callable RPC", () => {
  for (const [name] of signatures) {
    const start = draft.indexOf(`create or replace function public.${name}(`);
    const end = draft.indexOf(") returns", start);
    assert.notEqual(start, -1, `${name} declaration found`);
    const declaration = draft.slice(start, end);
    assert.match(declaration, /p_tenant_id uuid\s*,\s*p_branch_id uuid\s*,\s*p_actor_id uuid/);
  }
});

test("trigger function is not exposed as an executable public API", () => {
  assert.match(draft, /revoke all on function public\.branch_ops_prevent_immutable_record_mutation\(\) from public,anon,authenticated;/);
});
