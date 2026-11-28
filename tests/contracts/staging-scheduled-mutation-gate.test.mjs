import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const files = [
  ".github/workflows/staging-kds-pos-stock-positive-e2e.yml",
  ".github/workflows/staging-procurement-positive-e2e.yml",
];

for (const file of files) {
  test(`${file} cannot run staging mutations on a schedule or implicit push`, () => {
    const workflow = readFileSync(file, "utf8");
    assert.doesNotMatch(workflow, /^\s{2}schedule:/m, "positive-path mutation workflow must not have a schedule trigger");
    assert.match(workflow, /^\s{2}workflow_dispatch:/m, "manual dispatch must be available");
    assert.match(workflow, /confirm_staging_mutations:[\s\S]{0,180}required:\s*true[\s\S]{0,80}default:\s*false/,
      "explicit confirmation must be required and default to false");
    assert.match(workflow, /github\.event_name == 'workflow_dispatch'[\s\S]{0,100}inputs\.confirm_staging_mutations == true/,
      "job condition must require manual dispatch and explicit confirmation");
    assert.match(workflow, /^\s+environment:\s*staging\s*$/m,
      "staging environment protection must remain in the job");
    assert.doesNotMatch(workflow, /github\.event_name == 'schedule'/,
      "schedule must never be an alternate authorization path");
  });
}
