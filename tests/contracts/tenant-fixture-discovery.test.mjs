import assert from "node:assert/strict";
import test from "node:test";
import { resolveTenantFixtures } from "../runtime/tenant-fixture-discovery.mjs";

const ids = {
  userA: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  userB: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
  tenantA: "11111111-1111-4111-8111-111111111111",
  tenantB: "22222222-2222-4222-8222-222222222222",
  branchA: "33333333-3333-4333-8333-333333333333",
  branchB: "44444444-4444-4444-8444-444444444444",
};
const membership = (user_id, tenant_id) => ({
  user_id,
  tenant_id,
  status: "active",
  role: "branch_manager",
  permissions: ["inventory.read", "stock_transfer.create"],
  admin_profiles: { role: "sales_admin" },
});
const branch = (id, tenant_id, code) => ({ id, tenant_id, code, status: "active" });
const validFixture = () => ({
  ...ids,
  membershipsA: [membership(ids.userA, ids.tenantA)],
  membershipsB: [membership(ids.userB, ids.tenantB)],
  branchesA: [branch(ids.branchA, ids.tenantA, "QA-DLICE-A")],
  branchesB: [branch(ids.branchB, ids.tenantB, "QA-TENANT-B")],
  branchCodeA: "QA-DLICE-A",
  branchCodeB: "QA-TENANT-B",
});

test("discovers two distinct tenants and assigned branches from authenticated responses", () => {
  const result = resolveTenantFixtures(validFixture());
  assert.equal(result.passed, true);
  assert.equal(result.tenantA, ids.tenantA);
  assert.equal(result.tenantB, ids.tenantB);
  assert.equal(result.branchA, ids.branchA);
  assert.equal(result.branchB, ids.branchB);
  assert.equal(result.userIdA, ids.userA);
  assert.equal(result.userIdB, ids.userB);
});

test("rejects two QA branch codes resolving to the same tenant", () => {
  const input = validFixture();
  input.branchesB = [branch(ids.branchB, ids.tenantA, "QA-TENANT-B")];
  input.membershipsB = [membership(ids.userB, ids.tenantA)];
  const result = resolveTenantFixtures(input);
  assert.equal(result.tenantIdsDistinct, false);
  assert.equal(result.passed, false);
});

test("rejects missing or duplicate QA branch-code matches", () => {
  const missing = validFixture();
  missing.branchesA = [];
  assert.equal(resolveTenantFixtures(missing).passed, false);

  const duplicate = validFixture();
  duplicate.branchesA.push(branch("55555555-5555-4555-8555-555555555555", ids.tenantA, "QA-DLICE-A"));
  assert.equal(resolveTenantFixtures(duplicate).passed, false);
});

test("rejects any foreign-tenant branch visible to either identity", () => {
  const input = validFixture();
  input.branchesA.push(branch(ids.branchB, ids.tenantB, "QA-TENANT-B"));
  assert.equal(resolveTenantFixtures(input).branchAAssignmentIsCorrect, false);
  assert.equal(resolveTenantFixtures(input).passed, false);
});

test("rejects inactive or missing tenant membership", () => {
  const input = validFixture();
  input.membershipsA = [{ ...membership(ids.userA, ids.tenantA), status: "inactive" }];
  assert.equal(resolveTenantFixtures(input).membershipAIsCorrect, false);
  assert.equal(resolveTenantFixtures(input).passed, false);
});

test("rejects identical Auth identities", () => {
  const input = validFixture();
  input.userB = input.userA;
  input.membershipsB = [membership(input.userB, ids.tenantB)];
  assert.equal(resolveTenantFixtures(input).identityMatchesFixtures, false);
  assert.equal(resolveTenantFixtures(input).passed, false);
});

test("rejects unsupported global role or tenant membership role", () => {
  const input = validFixture();
  input.membershipsB = [{ ...membership(ids.userB, ids.tenantB), admin_profiles: { role: "branch_worker" } }];
  assert.equal(resolveTenantFixtures(input).profileBHasSupportedRole, false);
  assert.equal(resolveTenantFixtures(input).passed, false);

  const wrongTenantRole = validFixture();
  wrongTenantRole.membershipsA = [{ ...membership(ids.userA, ids.tenantA), role: "viewer" }];
  assert.equal(resolveTenantFixtures(wrongTenantRole).sameTenantRole, false);
  assert.equal(resolveTenantFixtures(wrongTenantRole).passed, false);
});

test("rejects empty or different permission sets", () => {
  const empty = validFixture();
  empty.membershipsA = [{ ...membership(ids.userA, ids.tenantA), permissions: [] }];
  assert.equal(resolveTenantFixtures(empty).permissionSetsEqual, false);
  assert.equal(resolveTenantFixtures(empty).passed, false);

  const different = validFixture();
  different.membershipsB = [{ ...membership(ids.userB, ids.tenantB), permissions: ["inventory.read"] }];
  assert.equal(resolveTenantFixtures(different).permissionSetsEqual, false);
  assert.equal(resolveTenantFixtures(different).passed, false);
});


test("rejects inactive QA branch fixtures even when identity and tenant membership match", () => {
  const input = validFixture();
  input.branchesA = [branch(ids.branchA, ids.tenantA, "QA-DLICE-A")];
  input.branchesA[0].status = "suspended";
  const result = resolveTenantFixtures(input);
  assert.equal(result.branchAIsActive, false);
  assert.equal(result.passed, false);
});
