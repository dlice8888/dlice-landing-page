import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = readFileSync(new URL("../../supabase/functions/dlice-orders/index.ts", import.meta.url), "utf8");
const migration = readFileSync(new URL("../../supabase/migrations/20261108090000_atomic_tenant_audit_operations.sql", import.meta.url), "utf8");
const runner = readFileSync(new URL("../runtime/dlice-tenant-jwt-isolation.mjs", import.meta.url), "utf8");

const start = source.indexOf('if (action === "platform-bootstrap-tenant-b-owner")');
assert.notEqual(start, -1, "staging Tenant B bootstrap action must exist");
const end = source.indexOf("const hasPerm =", start);
assert.ok(end > start, "bootstrap action must be a bounded handler block");
const block = source.slice(start, end);
for (const required of [
  "if (!isPlatformOwner)",
  'Deno.env.get("DLICE_TENANT_B_BOOTSTRAP_ENABLED") !== "true"',
  "higoadrzxnhzbbwhdbmh.supabase.co",
  "00000000-0000-4000-8000-000000000002",
  "90000000-0000-4000-8000-000000000004",
  'tenant.slug !== "dlice-qa-isolation-b"',
  'targetProfile.role !== "sales_admin"',
  "targetProfile.is_active !== true",
  "!authResult.user.email_confirmed_at",
  'admin.rpc("platform_bootstrap_tenant_owner"',
  "bootstrapResult.audit_recorded !== true",
]) assert.ok(block.includes(required), `bootstrap guard missing: ${required}`);
assert.ok(!/body\.(password|jwt|access_token|secret)/i.test(block), "bootstrap action must never accept credentials or secrets");
assert.ok(!block.includes("admin_profiles").valueOf() || !block.includes(".update({ permissions"), "bootstrap must not mutate global admin_profiles.permissions");

const helperStart = source.indexOf("const hasTenantPermissionForBranch =");
const helperEnd = source.indexOf("const isTenantOwnerForBranch", helperStart);
assert.ok(helperStart > 0 && helperEnd > helperStart, "tenant-membership permission helper must exist");
const helper = source.slice(helperStart, helperEnd);
assert.ok(helper.includes('select("role,permissions")'), "permissions must be loaded from tenant_memberships");
assert.ok(helper.includes('.eq("tenant_id", branch.tenant_id)'), "permission lookup must be tenant scoped");
assert.ok(helper.includes('.eq("user_id", actor.user.id)'), "permission lookup must bind to authenticated actor");
assert.ok(helper.includes('.eq("status", "active")'), "permission lookup must require active membership");

const warehouseStart = source.indexOf('if (action === "erp-create-warehouse")');
const warehouseEnd = source.indexOf('if (action === "erp-list-integrations")', warehouseStart);
const warehouse = source.slice(warehouseStart, warehouseEnd);
assert.ok(warehouse.includes('admin.rpc("erp_create_warehouse_with_audit"'), "warehouse insert and audit must use atomic DB RPC");
assert.ok(!warehouse.includes('admin.from("admin_audit_logs").insert'), "warehouse handler must not write audit separately");

const poStart = source.indexOf('if (action === "erp-update-purchase-order")');
const poEnd = source.indexOf('if (action === "erp-list-fulfillment-orders")', poStart);
const po = source.slice(poStart, poEnd);
assert.ok(po.includes('admin.rpc("erp_transition_purchase_order_with_audit"'), "PO status and audit must use atomic DB RPC");
assert.ok(!po.includes('admin.from("admin_audit_logs").insert'), "PO handler must not write audit separately");
assert.ok(po.includes('hasTenantPermissionForBranch(old.branch_id,"procurement")'), "PO permission must be tenant scoped");

for (const fn of ["platform_bootstrap_tenant_owner", "erp_create_warehouse_with_audit", "erp_transition_purchase_order_with_audit"]) {
  assert.ok(migration.includes(`create or replace function public.${fn}(`), `migration missing ${fn}`);
  assert.ok(migration.includes("security invoker"), "privileged operations must not silently bypass RLS with SECURITY DEFINER");
  assert.ok(migration.includes(`to service_role`), "RPC must be executable by service_role");
}
assert.ok(migration.includes("insert into public.admin_audit_logs"), "migration must write durable audit events");
assert.ok(migration.includes("insert into public.tenant_memberships"), "bootstrap must write tenant membership");
assert.ok(!migration.includes("update public.admin_profiles"), "tenant bootstrap must not mutate global profile permissions");
assert.ok(migration.includes("for update"), "PO transition must serialize concurrent state changes");

const probeNames = [
  "tenant-a-login", "tenant-b-login", "tenant-identities-distinct",
  "tenant-a-own-branch-read", "tenant-b-own-branch-read",
  "tenant-a-cross-tenant-read-denied", "tenant-b-cross-tenant-read-denied",
  "tenant-a-cross-tenant-write-denied", "tenant-b-cross-tenant-write-denied",
];
for (const name of probeNames) assert.ok(runner.includes(name), `runner missing independent probe ${name}`);
assert.ok(runner.includes("executedProbeCount"), "runner must report executed probe count");
assert.ok(runner.includes("status, executed, evidence"), "each probe must record status, executed, and evidence");
assert.ok(!runner.includes("assert.ok("), "an assertion must not abort subsequent probes");

assert.ok(source.includes("const TENANT_ISOLATION_RELEASED = false"), "tenant isolation release gate must remain closed");
assert.ok(source.includes("const PUBLIC_TENANT_ROUTING_RELEASED = false"), "public tenant routing gate must remain closed");
const publicGate = source.slice(source.indexOf('if (action === "list-online-branches")'), source.indexOf('if (action === "create-order")'));
assert.ok(publicGate.includes("if (!PUBLIC_TENANT_ROUTING_RELEASED)"), "public branch/catalog routing must remain fail-closed");
assert.ok(source.includes('if (!PUBLIC_TENANT_ROUTING_RELEASED) return fail("Katalog publik'), "public product catalog must remain fail-closed");

console.log("PASS: tenant bootstrap/audit atomic RPCs, tenant-scoped permissions, PO/warehouse audit transactions, nine independent probe records, and closed public routing gates are statically enforced.");
