import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const edge = await readFile(
  new URL("../../supabase/functions/dlice-orders/index.ts", import.meta.url),
  "utf8",
);
const migration = await readFile(
  new URL("../../supabase/migrations/20261121130000_atomic_tenant_invite_lifecycle.sql", import.meta.url),
  "utf8",
);

const inviteStart = edge.indexOf('if (action === "erp-invite-tenant-member")');
const acceptStart = edge.indexOf('if (action === "erp-accept-tenant-invite")');
const nextRoute = edge.indexOf('if (action === "erp-list-branch-settings")', acceptStart);
const inviteRoute = edge.slice(inviteStart, acceptStart);
const acceptRoute = edge.slice(acceptStart, nextRoute);

test("tenant invite issuance uses atomic RPC and remains fail-closed before isolation release", () => {
  assert.match(inviteRoute, /if\s*\(\s*!TENANT_ISOLATION_RELEASED\s*\)[\s\S]*?return fail/);
  assert.match(inviteRoute, /admin\.rpc\("dlice_create_tenant_invite_atomic"/);
  assert.doesNotMatch(inviteRoute, /from\("tenant_invites"\)\.(?:insert|update)/);
  assert.doesNotMatch(inviteRoute, /from\("admin_audit_logs"\)\.insert/);
  assert.match(inviteRoute, /delivery:"manual_copy_required"/);
});

test("tenant invite acceptance uses atomic RPC and remains fail-closed before isolation release", () => {
  assert.match(acceptRoute, /if\s*\(\s*!TENANT_ISOLATION_RELEASED\s*\)[\s\S]*?return fail/);
  assert.match(acceptRoute, /admin\.rpc\("dlice_accept_tenant_invite_atomic"/);
  assert.match(acceptRoute, /replayed:result\.replayed===true/);
  assert.doesNotMatch(acceptRoute, /from\("tenant_invites"\)\.(?:select|update)/);
  assert.doesNotMatch(acceptRoute, /from\("tenant_memberships"\)\.(?:upsert|insert)/);
  assert.doesNotMatch(acceptRoute, /from\("admin_audit_logs"\)\.insert/);
});

test("invite RPCs serialize invite state and commit membership plus audit atomically", () => {
  assert.match(migration, /FUNCTION public\.dlice_create_tenant_invite_atomic[\s\S]*?FOR UPDATE|FUNCTION public\.dlice_create_tenant_invite_atomic/);
  assert.match(migration, /FUNCTION public\.dlice_accept_tenant_invite_atomic[\s\S]*?FOR UPDATE/);
  assert.match(migration, /INSERT INTO public\.tenant_memberships[\s\S]*?UPDATE public\.tenant_invites[\s\S]*?INSERT INTO public\.admin_audit_logs/);
  assert.match(migration, /tenant_invite_email_mismatch/);
  assert.match(migration, /tenant_invite_not_pending/);
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.dlice_create_tenant_invite_atomic/);
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.dlice_accept_tenant_invite_atomic/);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.dlice_accept_tenant_invite_atomic[\s\S]*?TO service_role/);
});
