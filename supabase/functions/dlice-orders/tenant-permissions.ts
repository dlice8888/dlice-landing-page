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
  status: string;
  permissions?: unknown;
};

export type TenantHeadOfficeAssignment = {
  tenant_id?: string;
  is_head_office?: boolean;
  default_permissions?: unknown;
};

export function hasTenantScopedHeadOfficePermission(
  memberships: TenantMembershipPermission[],
  assignments: TenantHeadOfficeAssignment[],
  tenantId: string,
  permission: string,
): boolean {
  const isActiveMemberWithPermission = memberships.some((membership) => {
    if (membership.tenant_id !== tenantId || membership.status !== "active") return false;
    if (!Array.isArray(membership.permissions)) return false;
    return membership.permissions.includes(permission) || membership.permissions.includes("*");
  });
  if (!isActiveMemberWithPermission) return false;

  return assignments.some((assignment) =>
    assignment.tenant_id === tenantId &&
    assignment.is_head_office === true &&
    Array.isArray(assignment.default_permissions) &&
    assignment.default_permissions.includes(permission)
  );
}

export function resolveTenantScopedPermissions(
  memberships: TenantMembershipPermission[],
): string[] {
  if (!Array.isArray(memberships) || memberships.length === 0) return [];

  const activeMemberships = memberships.filter((membership) => membership.status === "active");
  if (activeMemberships.length === 0) return [];

  const permissionSets = activeMemberships.map((membership) => {
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

/**
 * Admin and ERP actions are tenant-sensitive by default. Only the narrow
 * acceptance surface below is allowed before the global release flag is enabled:
 * - membership lookup is self-only (actor user_id is never caller supplied);
 * - branch listing derives IDs from active memberships and assignments;
 * - inventory reads require branchAccess for the requested branch;
 * - stock-transfer creation checks access to BOTH source and destination before
 *   validation or mutation. These four routes are the P01-P09 isolation probes.
 *
 * All other admin/ERP routes remain fail-closed until separately certified.
 */
const TENANT_SCOPED_ACCEPTANCE_ACTIONS = new Set([
  "erp-list-tenant-memberships",
  "erp-list-branches",
  "erp-list-inventory",
  "erp-create-stock-transfer",
]);

export function isTenantSensitiveAction(action: string): boolean {
  if (action === "admin-login" || action === "admin-session-info") return false;
  if (TENANT_SCOPED_ACCEPTANCE_ACTIONS.has(action)) return false;
  return action.startsWith("admin-") || action.startsWith("erp-");
}

export type TenantBranchMembership = {
  tenant_id?: string;
  role?: string;
  status: string;
};

export type TenantBranchAssignment = {
  branch_id: string;
};

export type TenantBranch = {
  id: string;
  tenant_id?: string;
};

/**
 * Resolve a user's branch set from active tenant memberships and active
 * assignments. Tenant owners/admins receive only branches in their own tenant;
 * other members receive only explicitly assigned branches within a tenant
 * where they hold an active membership.
 */
export function resolveTenantScopedBranchIds(
  memberships: TenantBranchMembership[],
  assignments: TenantBranchAssignment[],
  branches: TenantBranch[],
): string[] {
  if (!Array.isArray(memberships) || !Array.isArray(assignments) || !Array.isArray(branches)) return [];

  const activeMemberships = memberships.filter(
    (membership) => membership.status === "active" && typeof membership.tenant_id === "string",
  );
  const tenantIds = new Set(activeMemberships.map((membership) => membership.tenant_id as string));
  if (tenantIds.size === 0) return [];

  const ownerTenantIds = new Set(
    activeMemberships
      .filter((membership) => ["tenant_owner", "tenant_admin"].includes(String(membership.role)))
      .map((membership) => membership.tenant_id as string),
  );
  const assignedBranchIds = new Set(assignments.map((assignment) => assignment.branch_id));

  return [...new Set(
    branches
      .filter((branch) =>
        typeof branch.tenant_id === "string" &&
        tenantIds.has(branch.tenant_id) &&
        (ownerTenantIds.has(branch.tenant_id) || assignedBranchIds.has(branch.id))
      )
      .map((branch) => branch.id),
  )].sort();
}
