import {
  hasTenantScopedHeadOfficePermission,
  isTenantSensitiveAction,
  resolveTenantScopedBranchIds,
  resolveTenantScopedPermissions,
} from "./tenant-permissions.ts";

Deno.test("Head Office permission requires an active membership and assignment in the target tenant", () => {
  const allowed = hasTenantScopedHeadOfficePermission(
    [{ tenant_id: "tenant-a", status: "active", permissions: ["inventory"] }],
    [{ tenant_id: "tenant-a", is_head_office: true, default_permissions: ["inventory"] }],
    "tenant-a",
    "inventory",
  );
  if (!allowed) throw new Error("Expected matching tenant membership and Head Office assignment to grant access");

  const crossTenantAssignment = hasTenantScopedHeadOfficePermission(
    [{ tenant_id: "tenant-a", status: "active", permissions: ["inventory"] }],
    [{ tenant_id: "tenant-b", is_head_office: true, default_permissions: ["inventory"] }],
    "tenant-a",
    "inventory",
  );
  if (crossTenantAssignment) throw new Error("A Head Office assignment in another tenant must not grant access");
});

Deno.test("inactive membership or non-Head Office assignment cannot approve tenant transfers", () => {
  const inactiveMember = hasTenantScopedHeadOfficePermission(
    [{ tenant_id: "tenant-a", status: "inactive", permissions: ["inventory"] }],
    [{ tenant_id: "tenant-a", is_head_office: true, default_permissions: ["inventory"] }],
    "tenant-a",
    "inventory",
  );
  const nonHeadOffice = hasTenantScopedHeadOfficePermission(
    [{ tenant_id: "tenant-a", status: "active", permissions: ["inventory"] }],
    [{ tenant_id: "tenant-a", is_head_office: false, default_permissions: ["inventory"] }],
    "tenant-a",
    "inventory",
  );
  if (inactiveMember || nonHeadOffice) throw new Error("Approval must require active membership and a Head Office assignment");
});

Deno.test("tenant grants are intersected, never unioned across tenants", () => {
  const permissions = resolveTenantScopedPermissions([
    { tenant_id: "tenant-a", status: "active", permissions: ["orders", "inventory", "pos"] },
    { tenant_id: "tenant-b", status: "active", permissions: ["orders", "reports"] },
  ]);
  if (permissions.join(",") !== "orders") {
    throw new Error(`Expected only shared grant 'orders', got: ${permissions.join(",")}`);
  }
});

Deno.test("global-profile-only grants are not accepted without memberships", () => {
  const permissions = resolveTenantScopedPermissions([]);
  if (permissions.length !== 0) {
    throw new Error("Expected no permissions without an active tenant membership");
  }
});

Deno.test("malformed or missing membership permissions fail closed", () => {
  const permissions = resolveTenantScopedPermissions([
    { tenant_id: "tenant-a", status: "active", permissions: ["inventory"] },
    { tenant_id: "tenant-b", status: "active", permissions: null },
  ]);
  if (permissions.length !== 0) {
    throw new Error("Expected empty permissions when one membership has no explicit grants");
  }
});

Deno.test("wildcard in one membership does not widen another membership", () => {
  const permissions = resolveTenantScopedPermissions([
    { tenant_id: "tenant-a", status: "active", permissions: ["*"] },
    { tenant_id: "tenant-b", status: "active", permissions: ["orders"] },
  ]);
  if (permissions.join(",") !== "orders") {
    throw new Error(`Expected only 'orders', got: ${permissions.join(",")}`);
  }
});

Deno.test("wildcard is retained when every active membership explicitly grants it", () => {
  const permissions = resolveTenantScopedPermissions([
    { tenant_id: "tenant-a", status: "active", permissions: ["*"] },
    { tenant_id: "tenant-b", status: "active", permissions: ["*"] },
  ]);
  if (permissions.join(",") !== "*") {
    throw new Error("Expected explicit all-tenant wildcard grant");
  }
});

Deno.test("inactive memberships cannot contribute permissions", () => {
  const permissions = resolveTenantScopedPermissions([
    { tenant_id: "tenant-a", status: "inactive", permissions: ["*"] },
    { tenant_id: "tenant-b", status: "active", permissions: ["orders"] },
  ]);
  if (permissions.join(",") !== "orders") {
    throw new Error(`Expected only active membership grants, got: ${permissions.join(",")}`);
  }
});

Deno.test("only the narrow tenant-scoped P01-P09 probe surface is available before release", () => {
  const protectedActions = [
    "admin-list-orders",
    "admin-set-permissions",
    "erp-create-pos-sale",
    "erp-list-finance",
    "erp-accept-tenant-invite",
    "erp-stock-movement",
    "erp-save-inventory",
  ];
  if (protectedActions.some((action) => !isTenantSensitiveAction(action))) {
    throw new Error("Uncertified admin/ERP routes must remain tenant-sensitive");
  }
  const scopedAcceptanceActions = [
    "erp-list-tenant-memberships",
    "erp-list-branches",
    "erp-list-inventory",
    "erp-create-stock-transfer",
  ];
  if (scopedAcceptanceActions.some((action) => isTenantSensitiveAction(action))) {
    throw new Error("Only the four branch/tenant-scoped P01-P09 probes may pass the pre-release gate");
  }
  const exemptActions = ["admin-login", "admin-session-info", "track-order"];
  if (exemptActions.some((action) => isTenantSensitiveAction(action))) {
    throw new Error("Authentication bootstrap, session introspection and customer tracking are not admin/ERP routes");
  }
});

Deno.test("tenant owners receive only their own tenant branches", () => {
  const ids = resolveTenantScopedBranchIds(
    [
      { tenant_id: "tenant-a", role: "tenant_owner", status: "active" },
      { tenant_id: "tenant-b", role: "member", status: "active" },
    ],
    [{ branch_id: "branch-b-1" }],
    [
      { id: "branch-a-1", tenant_id: "tenant-a" },
      { id: "branch-a-2", tenant_id: "tenant-a" },
      { id: "branch-b-1", tenant_id: "tenant-b" },
      { id: "branch-c-1", tenant_id: "tenant-c" },
    ],
  );
  if (ids.join(",") !== "branch-a-1,branch-a-2,branch-b-1") {
    throw new Error(`Unexpected tenant branch scope: ${ids.join(",")}`);
  }
});

Deno.test("ordinary tenant members receive only explicitly assigned branches inside active tenants", () => {
  const ids = resolveTenantScopedBranchIds(
    [
      { tenant_id: "tenant-a", role: "member", status: "active" },
      { tenant_id: "tenant-b", role: "member", status: "inactive" },
    ],
    [
      { branch_id: "branch-a-1" },
      { branch_id: "branch-b-1" },
      { branch_id: "branch-c-1" },
    ],
    [
      { id: "branch-a-1", tenant_id: "tenant-a" },
      { id: "branch-b-1", tenant_id: "tenant-b" },
      { id: "branch-c-1", tenant_id: "tenant-c" },
      { id: "branch-a-2", tenant_id: "tenant-a" },
    ],
  );
  if (ids.join(",") !== "branch-a-1") {
    throw new Error(`Cross-tenant or unassigned branch leaked: ${ids.join(",")}`);
  }
});

Deno.test("missing tenant membership or malformed branch scope fails closed", () => {
  const ids = resolveTenantScopedBranchIds(
    [{ tenant_id: "tenant-a", role: "member", status: "inactive" }],
    [{ branch_id: "branch-a-1" }],
    [{ id: "branch-a-1", tenant_id: "tenant-a" }],
  );
  if (ids.length !== 0) throw new Error("Inactive membership must produce an empty branch scope");
});
