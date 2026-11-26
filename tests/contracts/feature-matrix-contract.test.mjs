import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const matrix = JSON.parse(readFileSync("docs/audit/FNB_OS_IMPLEMENTATION_MATRIX.json", "utf8"));
const scoringStandard = readFileSync("docs/audit/FEATURE_PROGRESS_SCORING_STANDARD_20261121.md", "utf8");

const weightDimensions = [
  ["Code and UI implementation", "code_and_ui"],
  ["Database integrity and migrations", "database_and_data_integrity"],
  ["Authorization and tenant/branch scope", "authorization_and_tenant_scope"],
  ["Automated contract and unit tests", "automated_tests"],
  ["End-to-end browser or API workflow", "workflow_e2e"],
  ["Operational reconciliation and observability", "reconciliation_and_observability"],
];

test("feature counts and progress metadata match the matrix rows", () => {
  const features = matrix.domains.flatMap((domain) => domain.features);
  const counts = Object.fromEntries(
    ["PARTIAL", "NOT VERIFIED", "BLOCKED", "DONE"].map((status) => [
      status,
      features.filter((feature) => feature.audit_status === status).length,
    ]),
  );
  const scoredPartial = features.filter(
    (feature) => feature.audit_status === "PARTIAL" && Number.isFinite(feature.progress_percent),
  ).length;

  assert.equal(features.length, 189);
  assert.deepEqual(counts, { PARTIAL: 145, "NOT VERIFIED": 39, BLOCKED: 5, DONE: 0 });
  assert.equal(matrix.progress_scoring.scored_partial_features, scoredPartial);
  assert.equal(matrix.progress_scoring.unscored_partial_features, counts.PARTIAL - scoredPartial);
});

test("matrix scoring weights match the canonical scoring standard", () => {
  const expectedWeights = Object.fromEntries(weightDimensions.map(([label, key]) => {
    const escapedLabel = label.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const match = scoringStandard.match(new RegExp(`^\\| ${escapedLabel} \\| (\\d+)% \\|$`, "m"));
    assert.ok(match, `missing scoring dimension from standard: ${label}`);
    return [key, Number(match[1])];
  }));

  assert.equal(Object.values(expectedWeights).reduce((sum, weight) => sum + weight, 0), 100);
  assert.deepEqual(matrix.progress_scoring.weights, expectedWeights);
});
