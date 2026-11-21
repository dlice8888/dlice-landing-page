import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const edge = await readFile(
  new URL("../../supabase/functions/dlice-orders/index.ts", import.meta.url),
  "utf8",
);
const helper = await readFile(
  new URL("../../supabase/functions/dlice-orders/password-security.ts", import.meta.url),
  "utf8",
);

test("new staff, reset staff and initial Owner passwords use the breach guard", () => {
  for (const action of ["admin-create-staff", "admin-reset-staff-password", "admin-bootstrap-owner"]) {
    const start = edge.indexOf(`if (action === "${action}")`);
    assert.notEqual(start, -1, `missing ${action} handler`);
    const next = edge.indexOf("\n  if (action ===", start + 1);
    const block = edge.slice(start, next === -1 ? edge.length : next);
    assert.match(block, /checkNewPassword\(password, origin\)/, `${action} must check password before Auth mutation`);
  }
});

test("breach check uses k-anonymity, padding and a fail-closed result", () => {
  assert.match(helper, /api\.pwnedpasswords\.com\/range/);
  assert.match(helper, /hash\.slice\(0, 5\)/);
  assert.match(helper, /hash\.slice\(5\)/);
  assert.match(helper, /Add-Padding/);
  assert.match(helper, /AbortSignal\.timeout\(3000\)/);
  assert.match(helper, /return "unavailable"/);
  assert.doesNotMatch(helper, /console\.(log|error).*password/i);
});
