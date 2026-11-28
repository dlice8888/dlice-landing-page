import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL("../../supabase/migrations/20261128030021_20261126192504_franchise_expansion.sql", import.meta.url),
  "utf8",
);

function functionBody(name) {
  const marker = `create or replace function public.${name}(`;
  const start = migration.indexOf(marker);
  assert.notEqual(start, -1, `missing function ${name}`);
  const bodyStart = migration.indexOf("as $$", start);
  const bodyEnd = migration.indexOf("$$;", bodyStart + 5);
  assert.ok(bodyStart > start && bodyEnd > bodyStart, `could not delimit ${name}`);
  return migration.slice(bodyStart + 5, bodyEnd);
}

test("franchise application approval requires an independent reviewer", () => {
  assert.equal((migration.match(/create or replace function public\.franchise_review_application\(/g) ?? []).length, 1);
  const body = functionBody("franchise_review_application");
  assert.match(body, /p_decision='approved' and v_app\.created_by=p_actor_user_id/);
  assert.match(body, /INDEPENDENT_FRANCHISE_APPROVER_REQUIRED/);
  assert.match(body, /v_checks<>6 or v_passed<>6/);
  assert.match(body, /FRANCHISE_SITE_NOT_APPROVED/);
});

test("agreement signature and activation remain separate guarded transitions", () => {
  assert.equal((migration.match(/create or replace function public\.franchise_record_agreement_signature\(/g) ?? []).length, 1);
  const signature = functionBody("franchise_record_agreement_signature");
  assert.match(signature, /signed_document_reference/);
  assert.match(signature, /signed_pending_provisioning/);
  assert.doesNotMatch(signature, /set agreement_status='active'/);

  const activation = functionBody("franchise_activate_signed_agreement");
  assert.match(activation, /SIGNED_AGREEMENT_REQUIRED/);
  assert.match(activation, /FRANCHISE_BRANCH_TENANT_MISMATCH/);
  assert.match(activation, /INDEPENDENT_AGREEMENT_ACTIVATOR_REQUIRED/);
  assert.match(activation, /franchise_assert_opening_ready/);
});

test("franchise lifecycle RPCs are SECURITY INVOKER and service-role scoped", () => {
  for (const name of [
    "franchise_review_application",
    "franchise_record_agreement_signature",
    "franchise_activate_signed_agreement",
  ]) {
    assert.match(migration, new RegExp(`create or replace function public\\.${name}\\([\\s\\S]*?security invoker`, "i"));
    assert.match(migration, new RegExp(`revoke all on function public\\.${name}\\(`, "i"));
    assert.match(migration, new RegExp(`grant execute on function public\\.${name}\\(`, "i"));
  }
});
