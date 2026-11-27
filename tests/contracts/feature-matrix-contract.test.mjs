import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const matrix = JSON.parse(readFileSync("docs/audit/FNB_OS_IMPLEMENTATION_MATRIX.json", "utf8"));
const ledger = JSON.parse(readFileSync("docs/audit/PRD_FEATURE_EVIDENCE_LEDGER_20261126.json", "utf8"));
const scoringStandard = readFileSync("docs/audit/FEATURE_PROGRESS_SCORING_STANDARD_20261121.md", "utf8");

const weightDimensions = [
  ["Code and UI implementation", "code_and_ui"],
  ["Database integrity and migrations", "database_and_data_integrity"],
  ["Authorization and tenant/branch scope", "authorization_and_tenant_scope"],
  ["Automated contract and unit tests", "automated_tests"],
  ["End-to-end browser or API workflow", "workflow_e2e"],
  ["Operational reconciliation and observability", "reconciliation_and_observability"],
];

const statusCounts = (rows) => Object.fromEntries(
  ["PARTIAL", "NOT VERIFIED", "BLOCKED", "DONE"].map((status) => [
    status,
    rows.filter((feature) => feature.audit_status === status).length,
  ]),
);

test("the evidence ledger is the single canonical source for all 189 stable PRD feature IDs", () => {
  const matrixFeatures = matrix.domains.flatMap((domain) => domain.features);
  const ledgerFeatures = ledger.feature_rows;
  const ledgerIds = ledgerFeatures.map((feature) => feature.feature_id);
  const matrixIds = matrixFeatures.map((feature) => feature.feature_id);
  const ledgerById = new Map(ledgerFeatures.map((feature) => [feature.feature_id, feature]));

  assert.equal(ledger.prd_feature_count, 189);
  assert.equal(ledgerFeatures.length, 189);
  assert.equal(new Set(ledgerIds).size, 189, "ledger feature IDs must be unique");
  assert.equal(matrixFeatures.length, 189);
  assert.equal(new Set(matrixIds).size, 189, "matrix feature IDs must be unique");

  const canonicalCounts = statusCounts(ledgerFeatures);
  assert.deepEqual(canonicalCounts, {
    PARTIAL: ledger.source_counts.PARTIAL,
    "NOT VERIFIED": ledger.source_counts["NOT VERIFIED"],
    BLOCKED: ledger.source_counts.BLOCKED,
    DONE: ledger.source_counts.DONE,
  });
  assert.equal(ledger.source_counts.TOTAL, 189);
  assert.deepEqual(statusCounts(matrixFeatures), canonicalCounts);

  for (const feature of matrixFeatures) {
    const canonical = ledgerById.get(feature.feature_id);
    assert.ok(canonical, `matrix feature ${feature.feature_id} is absent from the canonical ledger`);
    assert.equal(feature.audit_status, canonical.audit_status, `${feature.feature_id}: matrix status differs from canonical ledger`);
  }
});

test("matrix progress metadata matches feature-level weighted scores", () => {
  const features = matrix.domains.flatMap((domain) => domain.features);
  const scoredPartial = features.filter(
    (feature) => feature.audit_status === "PARTIAL" && Number.isFinite(feature.progress_pct),
  ).length;

  assert.equal(matrix.progress_scoring.scored_partial_features, scoredPartial);
  assert.equal(matrix.progress_scoring.unscored_partial_features,
    features.filter((feature) => feature.audit_status === "PARTIAL").length - scoredPartial);
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
