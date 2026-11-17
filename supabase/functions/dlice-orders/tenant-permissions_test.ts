import {
  hasTenantScopedHeadOfficePermission,
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
