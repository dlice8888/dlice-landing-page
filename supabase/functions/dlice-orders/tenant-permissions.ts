/**
 * Resolve the permissions available to an authenticated actor across active tenant memberships.
 *
 * The API currently has several legacy handlers whose permission checks do not receive a
 * branch/tenant argument. Until those handlers are fully converted to explicit tenant context,
 * use the intersection of membership grants rather than their union. This is intentionally
 * restrictive: a permission granted in one tenant is never inherited by another tenant.
 * Global admin_profiles.permissions and job-position defaults are not authorization sources.
 */
export type TenantMembershipPermission = {
  tenant_id?: string;
  role?: string;
  permissions?: unknown;
};

export function resolveTenantScopedPermissions(
  memberships: TenantMembershipPermission[],
): string[] {
  if (!Array.isArray(memberships) || memberships.length === 0) return [];

  const permissionSets = memberships.map((membership) => {
    const values = Array.isArray(membership.permissions)
      ? membership.permissions
      : [];
    return new Set(
      values
        .filter((value): value is string => typeof value === "string")
        .map((value) => value.trim())
        .filter((value) => value.length > 0),
    );
  });

  // A wildcard is a grant for that membership only; it does not widen a narrower
  // membership. Therefore wildcard sets are neutral when intersecting memberships.
  const constrainedSets = permissionSets.filter((set) => !set.has("*"));
  if (constrainedSets.length === 0) return ["*"];

  const [first, ...rest] = constrainedSets;
  return [...first]
    .filter((permission) => rest.every((set) => set.has(permission)))
    .sort();
}
