import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = readFileSync(new URL("../../supabase/functions/dlice-orders/index.ts", import.meta.url), "utf8");
const start = source.indexOf('if (action === "platform-bootstrap-tenant-b-owner")');
assert.notEqual(start, -1, "staging Tenant B bootstrap action must exist");
const end = source.indexOf("const hasPerm =", start);
assert.ok(end > start, "bootstrap action must be a bounded handler block");
const block = source.slice(start, end);

for (const required of [
  "if (!isPlatformOwner)",
  'Deno.env.get("DLICE_TENANT_B_BOOTSTRAP_ENABLED") !== "true"',
  'higoadrzxnhzbbwhdbmh.supabase.co',
  "00000000-0000-4000-8000-000000000002",
  "90000000-0000-4000-8000-000000000004",
  'tenant.slug !== "dlice-qa-isolation-b"',
  'targetProfile.role !== "sales_admin"',
  "targetProfile.is_active !== true",
  "!authResult.user.email_confirmed_at",
  'status: "active"',
  'action: "platform_bootstrap_tenant_owner"',
  "if (auditError)",
  "permissionsError",
]) assert.ok(block.includes(required), `bootstrap guard missing: ${required}`);

assert.ok(!/body\.(password|jwt|access_token|secret)/i.test(block), "bootstrap action must never accept credentials or secrets");
assert.ok(block.indexOf("if (!isPlatformOwner)") < block.indexOf("tenant_memberships").valueOf(), "platform authorization must precede membership writes");

const helperStart = source.indexOf("const isTenantOwnerForBranch =");
const helperEnd = source.indexOf("const branchIdsForActor", helperStart);
assert.ok(helperStart > 0 && helperEnd > helperStart, "tenant-owner scoped authorization helper must exist");
const helper = source.slice(helperStart, helperEnd);
assert.ok(helper.includes('["tenant_owner", "tenant_admin"]'), "scoped owner helper must allow only tenant owner/admin");
assert.ok(helper.includes('.eq("user_id", actor.user.id)'), "scoped owner helper must bind to authenticated actor");
assert.ok(helper.includes('.eq("status", "active")'), "scoped owner helper must require active membership");

const warehouseStart = source.indexOf('if (action === "erp-create-warehouse")');
const warehouseEnd = source.indexOf('if (action === "erp-list-integrations")', warehouseStart);
const warehouse = source.slice(warehouseStart, warehouseEnd);
assert.ok(warehouse.includes('action:"erp_warehouse_created"'), "warehouse creation must create audit event");
assert.ok(warehouse.includes("if(auditError)"), "warehouse must roll back if audit insert fails");

const requisitionStart = source.indexOf('if (action === "erp-transition-purchase-requisition")');
const requisitionEnd = source.indexOf('if (action === "erp-list-purchase-orders")', requisitionStart);
const requisition = source.slice(requisitionStart, requisitionEnd);
assert.ok(requisition.includes("tenantOwnerApprover"), "tenant owner/admin must be allowed to approve scoped requisitions");
assert.ok(requisition.includes("old.requested_by === actor.user.id"), "requisition maker-checker must remain enforced");

const poStart = source.indexOf('if (action === "erp-update-purchase-order")');
const poEnd = source.indexOf('if (action === "erp-list-fulfillment-orders")', poStart);
const po = source.slice(poStart, poEnd);
assert.ok(po.includes("isTenantOwnerForBranch(old.branch_id)"), "tenant owner/admin must be allowed to approve scoped purchase orders");
assert.ok(po.includes("old.requested_by===actor.user.id"), "purchase-order maker-checker must remain enforced");

const reconciliation = source.slice(source.indexOf('if (action === "erp-reconcile-purchase-requisition")'), source.indexOf('if (action === "erp-list-purchase-requisitions")'));
assert.ok(reconciliation.includes("isTenantOwnerForBranch(requisition.branch_id)"), "tenant owner/admin must be allowed to reconcile requisition audit");
const receiptReconciliation = source.slice(source.indexOf('if (action === "erp-reconcile-purchase-receipt")'), source.indexOf('if (action === "erp-set-product-stock-tracking")'));
assert.ok(receiptReconciliation.includes("isTenantOwnerForBranch(receipt.branch_id)"), "tenant owner/admin must be allowed to reconcile goods receipt");
assert.ok(source.includes("const TENANT_ISOLATION_RELEASED = false"), "bootstrap must not release tenant isolation");

console.log("PASS: staging Tenant B bootstrap is platform-owner-only, staging-only, tenant-scoped, audited, and maker-checker protected.");
