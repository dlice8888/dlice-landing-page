import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const migration = readFileSync(new URL("../../supabase/migrations/20261126192458_hr_workforce_payroll_finance.sql", import.meta.url), "utf8");
const api = readFileSync(new URL("../../supabase/functions/dlice-orders/index.ts", import.meta.url), "utf8");
const webhook = readFileSync(new URL("../../supabase/functions/hr-payroll-provider-webhook/index.ts", import.meta.url), "utf8");
const erp = readFileSync(new URL("../../erp.html", import.meta.url), "utf8");

test("HR payment batch schema links reconciled payroll and Finance posting", () => {
  assert.match(migration, /create table if not exists public\.hr_payroll_payment_batches/);
  assert.match(migration, /create table if not exists public\.hr_payroll_payment_items/);
  assert.match(migration, /create table if not exists public\.hr_payroll_provider_events/);
  assert.match(migration, /create table if not exists public\.hr_payroll_payment_reconciliations/);
  assert.match(migration, /RECONCILED_FINANCE_POSTING_REQUIRED/);
  assert.match(migration, /APPROVED_BENEFICIARY_PROFILE_REQUIRED_FOR_EVERY_PAYROLL_LINE/);
  assert.match(migration, /INDEPENDENT_PAYROLL_PAYMENT_APPROVER_REQUIRED/);
  assert.match(migration, /INDEPENDENT_PAYROLL_PAYMENT_RECONCILER_REQUIRED/);
  assert.match(migration, /SETTLED_PROVIDER_EVENT_MISSING_FOR_PAYMENT_ITEM/);
});

test("HR server API stores only beneficiary secret references and fingerprints", () => {
  for (const action of ["erp-hr-request-payroll-payment-provider","erp-hr-approve-payroll-payment-provider","erp-hr-request-payroll-beneficiary","erp-hr-approve-payroll-beneficiary","erp-hr-prepare-payroll-payment-batch","erp-hr-approve-payroll-payment-batch","erp-hr-list-payroll-payment-items","erp-hr-reconcile-payroll-payment-batch"]) {
    assert.ok(api.includes(action), `missing ${action}`);
  }
  assert.match(api, /beneficiary_fingerprint_sha256:fingerprint/);
  assert.match(api, /hr_payroll_beneficiary_profiles/);
  assert.match(api, /Deno\.env\.get\(secretRef\)/);
});

test("Payroll provider webhook verifies raw-body HMAC before accepting provider events", () => {
  assert.match(webhook, /req\.text\(\)/);
  assert.match(webhook, /crypto\.subtle\.importKey/);
  assert.match(webhook, /crypto\.subtle\.sign/);
  assert.match(webhook, /constantTimeEqual\(signature, expected\)/);
  assert.match(webhook, /p_signature_verified: true/);
  assert.match(webhook, /p_actor_user_id: null/);
  assert.match(webhook, /hr_apply_payroll_provider_event/);
});

test("HR UI includes provider, beneficiary, payment batch and reconciliation workflows", () => {
  for (const id of ["hrPaymentProviderForm","hrBeneficiaryForm","hrPaymentBatchForm","hrPaymentBatchList","hrPaymentItemList"]) assert.ok(erp.includes(id));
  assert.ok(erp.includes("erp-hr-reconcile-payroll-payment-batch"));
  assert.ok(erp.includes("hr-payroll-provider-webhook"));
});
