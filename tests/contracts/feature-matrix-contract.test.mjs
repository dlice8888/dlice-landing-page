import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const matrix = JSON.parse(readFileSync("docs/audit/FNB_OS_IMPLEMENTATION_MATRIX.json", "utf8"));
const evidenceLedger = JSON.parse(readFileSync("docs/audit/PRD_FEATURE_EVIDENCE_LEDGER_20261126.json", "utf8"));
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


test("implementation matrix and evidence ledger reconcile every stable PRD feature ID", () => {
  const matrixFeatures = matrix.domains.flatMap((domain) => domain.features);
  const ledgerById = new Map(evidenceLedger.feature_rows.map((feature) => [feature.feature_id, feature]));
  assert.equal(ledgerById.size, 189);
  assert.equal(new Set(matrixFeatures.map((feature) => feature.feature_id)).size, 189);
  for (const feature of matrixFeatures) {
    const ledgerFeature = ledgerById.get(feature.feature_id);
    assert.ok(ledgerFeature, `missing ledger row for ${feature.feature_id}`);
    assert.equal(feature.audit_status, ledgerFeature.audit_status, `status drift for ${feature.feature_id}`);
    assert.equal(feature.work_status, ledgerFeature.work_status, `work status drift for ${feature.feature_id}`);
    assert.equal(feature.progress_pct, ledgerFeature.progress_pct, `progress score drift for ${feature.feature_id}`);
  }
  assert.deepEqual(evidenceLedger.current_audit_status_counts, {
    PARTIAL: 145,
    "NOT VERIFIED": 39,
    BLOCKED: 5,
    DONE: 0,
  });
  assert.equal(matrix.feature_totals.total, 189);
  assert.equal(matrix.feature_totals.partial, 145);
  assert.equal(matrix.feature_totals.not_verified, 39);
  assert.equal(matrix.feature_totals.blocked, 5);
  assert.equal(matrix.feature_totals.done, 0);
});
