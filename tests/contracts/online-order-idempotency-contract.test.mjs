import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const edge = await readFile(
  new URL("../../supabase/functions/dlice-orders/index.ts", import.meta.url),
  "utf8",
);
const migration = await readFile(
  new URL("../../supabase/migrations/20261121130000_atomic_online_order_idempotency.sql", import.meta.url),
  "utf8",
);
const page = await readFile(new URL("../../index.html", import.meta.url), "utf8");

test("public online checkout requires a 256-bit idempotency key", () => {
  assert.match(edge, /const idempotencyKey = safeText\(body\.idempotency_key, 64\)\.toLowerCase\(\)/);
  assert.match(edge, /trackingToken = idempotencyKey/);
  assert.match(edge, /idempotency_key_hash:\s*trackingHash/);
  assert.match(edge, /idempotency_request_fingerprint:\s*requestFingerprint/);
});

test("database serializes retries and rejects payload mismatch", () => {
  assert.match(migration, /pg_advisory_xact_lock\(hashtextextended\(v_idempotency_key_hash,0\)\)/);
  assert.match(migration, /idempotency_key_payload_mismatch/);
  assert.match(migration, /return v_existing\.response \|\| jsonb_build_object\('idempotent_replay',true\)/);
  assert.match(migration, /insert into public\.online_order_idempotency/i);
});

test("idempotency ledger is inaccessible to browser roles", () => {
  assert.match(migration, /ALTER TABLE public\.online_order_idempotency ENABLE ROW LEVEL SECURITY/i);
  assert.match(migration, /REVOKE ALL ON TABLE public\.online_order_idempotency FROM PUBLIC, anon, authenticated/i);
  assert.match(migration, /GRANT ALL ON TABLE public\.online_order_idempotency TO service_role/i);
});

test("browser persists one checkout key across retry and clears it only after success", () => {
  assert.match(page, /sessionStorage\.getItem\(ORDER_IDEMPOTENCY_STORAGE_KEY\)/);
  assert.match(page, /sessionStorage\.setItem\(ORDER_IDEMPOTENCY_STORAGE_KEY,pendingOrderIdempotencyKey\)/);
  assert.match(page, /idempotency_key:pendingOrderIdempotencyKey/);
  assert.match(page, /sessionStorage\.removeItem\(ORDER_IDEMPOTENCY_STORAGE_KEY\)/);
});
