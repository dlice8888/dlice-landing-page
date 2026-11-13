import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const workflow = readFileSync(".github/workflows/staging-auth-tenant-negative.yml", "utf8");
const triggers = workflow.split(/^permissions:\s*$/m, 1)[0];

test("authenticated staging probes do not execute pull request code with staging secrets", () => {
  assert.match(triggers, /^  push:\s*\n\s+branches:\s*\[staging\]/m);
  assert.doesNotMatch(triggers, /\bpull_request\b/);
  assert.match(workflow, /^\s+environment:\s*staging\s*$/m);
  assert.match(workflow, /STAGING_TEST_BRANCH_A_PASSWORD:\s*\$\{\{\s*secrets\.STAGING_TEST_BRANCH_A_PASSWORD\s*\}\}/);
});
