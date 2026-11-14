import { resolveTenantScopedPermissions } from "./tenant-permissions.ts";

Deno.test("tenant grants are intersected, never unioned across tenants", () => {
  const permissions = resolveTenantScopedPermissions([
    { tenant_id: "tenant-a", permissions: ["orders", "inventory", "pos"] },
    { tenant_id: "tenant-b", permissions: ["orders", "reports"] },
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
    { tenant_id: "tenant-a", permissions: ["inventory"] },
    { tenant_id: "tenant-b", permissions: null },
  ]);
  if (permissions.length !== 0) {
    throw new Error("Expected empty permissions when one membership has no explicit grants");
  }
});

Deno.test("wildcard in one membership does not widen another membership", () => {
  const permissions = resolveTenantScopedPermissions([
    { tenant_id: "tenant-a", permissions: ["*"] },
    { tenant_id: "tenant-b", permissions: ["orders"] },
  ]);
  if (permissions.join(",") !== "orders") {
    throw new Error(`Expected only 'orders', got: ${permissions.join(",")}`);
  }
});

Deno.test("wildcard is retained when every active membership explicitly grants it", () => {
  const permissions = resolveTenantScopedPermissions([
    { tenant_id: "tenant-a", permissions: ["*"] },
    { tenant_id: "tenant-b", permissions: ["*"] },
  ]);
  if (permissions.join(",") !== "*") {
    throw new Error("Expected explicit all-tenant wildcard grant");
  }
});
