import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const edge = readFileSync("supabase/functions/dlice-orders/index.ts", "utf8");
const migration = readFileSync("supabase/migrations/20261121150000_atomic_customer_payment_proof.sql", "utf8");
const checkout = readFileSync("index.html", "utf8");

test("customer proof handler uses one atomic database RPC instead of split writes", () => {
  const start = edge.indexOf('if(action==="upload-proof")');
  const end = edge.indexOf('Bukti tersimpan secara privat dan menunggu verifikasi admin.', start);
  assert.notEqual(start, -1, "upload-proof action exists");
  assert.notEqual(end, -1, "upload-proof success response exists");
  const handler = edge.slice(start, end + 100);
  assert.match(handler, /submit_customer_payment_proof_atomic/);
  assert.match(handler, /p_order_id:\s*order\.id/);
  assert.match(handler, /p_upload_key:/);
  assert.match(handler, /if \(proofError \|\| !proofResult\?\.ok\)/);
  assert.match(handler, /storage\.from\("dlice-payment-proofs"\)\.remove\(\[path\]\)/);
  assert.doesNotMatch(handler, /admin\.from\("payment_records"\)\.(insert|update)/);
  assert.doesNotMatch(handler, /admin\.from\("order_reservations"\)\.update/);
  assert.doesNotMatch(handler, /admin\.from\("orders"\)\.update/);
});

test("database RPC serializes expiry and proof submission and records one atomic audit trail", () => {
  assert.match(migration, /CREATE OR REPLACE FUNCTION public\.submit_customer_payment_proof_atomic/);
  assert.match(migration, /SECURITY INVOKER/);
  assert.match(migration, /SET search_path TO ''/);
  assert.match(migration, /FROM public\.orders[\s\S]*?FOR UPDATE/);
  assert.match(migration, /FROM public\.order_reservations[\s\S]*?FOR UPDATE/);
  assert.match(migration, /CREATE UNIQUE INDEX IF NOT EXISTS payment_records_proof_upload_key_uidx/);
  assert.match(migration, /INSERT INTO public\.order_status_history/);
  assert.match(migration, /INSERT INTO public\.admin_audit_logs/);
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.submit_customer_payment_proof_atomic[\s\S]*?FROM PUBLIC, anon, authenticated/);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.submit_customer_payment_proof_atomic[\s\S]*?TO service_role/);
});

test("customer browser keeps the same upload idempotency key across retries in the active order session", () => {
  assert.match(checkout, /activeOrder\.proofUploadRequestId \|\|= crypto\.randomUUID\(\)/);
  assert.match(checkout, /upload_request_id:activeOrder\.proofUploadRequestId/);
  assert.match(checkout, /activeOrder\.proofUploadRequestId=null/);
});
