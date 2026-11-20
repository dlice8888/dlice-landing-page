export function resolveTenantFixtures({
  userA,
  userB,
  membershipsA,
  membershipsB,
  branchesA,
  branchesB,
  branchCodeA,
  branchCodeB,
}) {
  const list = (value) => Array.isArray(value) ? value : [];
  const activeMembershipsA = list(membershipsA).filter(
    (membership) => membership?.user_id === userA && membership?.status === "active",
  );
  const activeMembershipsB = list(membershipsB).filter(
    (membership) => membership?.user_id === userB && membership?.status === "active",
  );
  const branchMatchesA = list(branchesA).filter((branch) => branch?.code === branchCodeA);
  const branchMatchesB = list(branchesB).filter((branch) => branch?.code === branchCodeB);
  const branchARecord = branchMatchesA.length === 1 ? branchMatchesA[0] : null;
  const branchBRecord = branchMatchesB.length === 1 ? branchMatchesB[0] : null;

  const tenantA = branchARecord?.tenant_id ?? null;
  const tenantB = branchBRecord?.tenant_id ?? null;
  const branchA = branchARecord?.id ?? null;
  const branchB = branchBRecord?.id ?? null;
  const tenantIdsDistinct = Boolean(tenantA && tenantB && tenantA !== tenantB);
  const branchIdsDistinct = Boolean(branchA && branchB && branchA !== branchB);
  const identityMatchesFixtures = typeof userA === "string" &&
    typeof userB === "string" &&
    userA.length > 0 &&
    userB.length > 0 &&
    userA !== userB;

  const membershipA = activeMembershipsA.find((membership) => membership.tenant_id === tenantA) ?? null;
  const membershipB = activeMembershipsB.find((membership) => membership.tenant_id === tenantB) ?? null;
  const branchAIsActive = branchARecord?.status === "active";
  const branchBIsActive = branchBRecord?.status === "active";
  const membershipAIsCorrect = tenantIdsDistinct &&
    !!membershipA &&
    activeMembershipsA.every((membership) => membership.tenant_id === tenantA) &&
    !list(membershipsA).some((membership) => membership?.tenant_id === tenantB);
  const membershipBIsCorrect = tenantIdsDistinct &&
    !!membershipB &&
    activeMembershipsB.every((membership) => membership.tenant_id === tenantB) &&
    !list(membershipsB).some((membership) => membership?.tenant_id === tenantA);

  const branchAAssignmentIsCorrect = tenantIdsDistinct &&
    branchIdsDistinct &&
    branchAIsActive &&
    !!branchARecord &&
    list(branchesA).length > 0 &&
    list(branchesA).every((branch) => branch?.tenant_id === tenantA) &&
    !list(branchesA).some((branch) => branch?.id === branchB || branch?.code === branchCodeB);
  const branchBAssignmentIsCorrect = tenantIdsDistinct &&
    branchIdsDistinct &&
    branchBIsActive &&
    !!branchBRecord &&
    list(branchesB).length > 0 &&
    list(branchesB).every((branch) => branch?.tenant_id === tenantB) &&
    !list(branchesB).some((branch) => branch?.id === branchA || branch?.code === branchCodeA);

  const profileAHasSupportedRole = membershipA?.admin_profiles?.role === "sales_admin";
  const profileBHasSupportedRole = membershipB?.admin_profiles?.role === "sales_admin";
  const sameTenantRole = membershipA?.role === "branch_manager" &&
    membershipB?.role === membershipA.role;
  const permissionsA = Array.isArray(membershipA?.permissions)
    ? [...membershipA.permissions].sort()
    : [];
  const permissionsB = Array.isArray(membershipB?.permissions)
    ? [...membershipB.permissions].sort()
    : [];
  const permissionSetsEqual = permissionsA.length > 0 &&
    JSON.stringify(permissionsA) === JSON.stringify(permissionsB);

  const passed = identityMatchesFixtures &&
    tenantIdsDistinct &&
    branchIdsDistinct &&
    membershipAIsCorrect &&
    membershipBIsCorrect &&
    profileAHasSupportedRole &&
    profileBHasSupportedRole &&
    sameTenantRole &&
    permissionSetsEqual &&
    branchAAssignmentIsCorrect &&
    branchBAssignmentIsCorrect;

  return {
    passed,
    tenantA,
    tenantB,
    branchA,
    branchB,
    userIdA: userA ?? null,
    userIdB: userB ?? null,
    identityMatchesFixtures,
    tenantIdsDistinct,
    branchIdsDistinct,
    membershipA,
    membershipB,
    membershipAIsCorrect,
    membershipBIsCorrect,
    profileAHasSupportedRole,
    profileBHasSupportedRole,
    sameTenantRole,
    permissionsA,
    permissionsB,
    permissionSetsEqual,
    branchAAssignmentIsCorrect,
    branchBAssignmentIsCorrect,
    branchAIsActive,
    branchBIsActive,
    branchMatchCounts: {
      tenantA: branchMatchesA.length,
      tenantB: branchMatchesB.length,
    },
  };
}
