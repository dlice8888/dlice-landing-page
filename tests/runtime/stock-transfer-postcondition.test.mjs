import test from "node:test";
import assert from "node:assert/strict";
import { inspectStockTransferAbsence } from "./stock-transfer-postcondition.mjs";

const request = {
  base: "https://staging.example.supabase.co",
  serviceRoleKey: "service-role-test-key",
  transferNumber: "SECURITY-DENY-A-test-id",
  idempotencyKey: "tenant-isolation-a-test-id",
};

test("confirms both generated transfer identifiers are absent without including them in evidence", async () => {
  const calls = [];
  const result = await inspectStockTransferAbsence({
    ...request,
    fetchImpl: async (url, options) => {
      calls.push({ url: new URL(url), options });
      return { ok: true, status: 200, json: async () => [] };
    },
  });

  assert.equal(result.passed, true);
  assert.deepEqual(result.evidence.databasePostcondition.checks, [
    { field: "transfer_number", absent: true, httpStatus: 200, rows: 0 },
    { field: "idempotency_key", absent: true, httpStatus: 200, rows: 0 },
  ]);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].url.searchParams.get("transfer_number"), `eq.${request.transferNumber}`);
  assert.equal(calls[1].url.searchParams.get("idempotency_key"), `eq.${request.idempotencyKey}`);
  for (const { options } of calls) {
    assert.equal(options.headers.apikey, request.serviceRoleKey);
    assert.equal(options.headers.authorization, `Bearer ${request.serviceRoleKey}`);
  }
  assert.equal(JSON.stringify(result.evidence).includes(request.transferNumber), false);
  assert.equal(JSON.stringify(result.evidence).includes(request.idempotencyKey), false);
});

test("fails the postcondition when a stock transfer row is present", async () => {
  const result = await inspectStockTransferAbsence({
    ...request,
    fetchImpl: async (url) => {
      const query = new URL(url).searchParams;
      return {
        ok: true,
        status: 200,
        json: async () => query.has("transfer_number") ? [{ id: "stored-row" }] : [],
      };
    },
  });

  assert.equal(result.passed, false);
  assert.equal(result.evidence.databasePostcondition.checks[0].absent, false);
  assert.equal(result.evidence.databasePostcondition.checks[0].rows, 1);
});

test("fails closed when the database postcondition cannot be queried", async () => {
  const result = await inspectStockTransferAbsence({
    ...request,
    fetchImpl: async () => ({ ok: false, status: 403 }),
  });

  assert.equal(result.passed, false);
  assert.ok(result.evidence.databasePostcondition.checks.every((check) =>
    check.absent === false && check.httpStatus === 403 && check.rows === null));
});
