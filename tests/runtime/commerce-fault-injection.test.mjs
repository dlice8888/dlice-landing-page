// Dependency-free mock runtime fault-injection harness.
// In-memory simulation only; this is NOT a Supabase/API E2E test.
import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

const evidence = [];
function record(id, request, response, before, after, compensation = "not_required") {
  const row = {
    scenarioId: id, adapter: "in_memory_mock",
    request: { ...request, authorization: "[REDACTED]", idempotencyKey: request.idempotencyKey ? "[REDACTED]" : undefined },
    response: { httpStatus: response.httpStatus, outcome: response.outcome },
    database: { before, after }, compensation,
    timestamp: new Date().toISOString(), secretsPrinted: false,
  };
  evidence.push(row);
  console.log("FAULT_INJECTION_EVIDENCE " + JSON.stringify(row));
}
class MockCommerce {
  constructor() { this.orders = new Map(); this.payments = new Map(); this.objects = new Set(); this.events = new Set(); this.locks = new Map(); }
  snapshot() {
    return {
      orders: [...this.orders.values()].map(x => ({ id: x.id, status: x.status })),
      payments: [...this.payments.values()].map(x => ({ id: x.id, status: x.status })),
      objects: [...this.objects].sort(), events: [...this.events].sort(),
    };
  }
  async serialized(key, fn) {
    const prior = this.locks.get(key) || Promise.resolve();
    let release;
    const gate = new Promise(resolve => { release = resolve; });
    const tail = prior.then(() => gate);
    this.locks.set(key, tail);
    await prior;
    try { return await fn(); }
    finally { release(); if (this.locks.get(key) === tail) this.locks.delete(key); }
  }
  async createOrder(key, payload, loseResponse = false) {
    return this.serialized("order:" + key, async () => {
      const existing = [...this.orders.values()].find(x => x.key === key);
      if (existing) return JSON.stringify(existing.payload) === JSON.stringify(payload)
        ? { httpStatus: 200, outcome: "idempotent_replay", order: existing }
        : { httpStatus: 409, outcome: "idempotency_payload_mismatch", order: existing };
      const order = { id: randomUUID(), key, payload, status: "created" };
      this.orders.set(order.id, order);
      if (loseResponse) throw new Error("simulated_response_lost_after_commit");
      return { httpStatus: 201, outcome: "created", order };
    });
  }
  async uploadProof(id, options = {}) {
    const object = "proof/" + id;
    if (options.failUpload) return { httpStatus: 503, outcome: "storage_upload_failed", compensation: "not_required" };
    this.objects.add(object);
    if (options.failDb) {
      if (options.failDelete) return { httpStatus: 500, outcome: "database_write_failed", compensation: "failed_orphan_object" };
      this.objects.delete(object);
      return { httpStatus: 500, outcome: "database_write_failed", compensation: "object_deleted" };
    }
    this.payments.set(id, { id, status: "proof_submitted", object });
    return { httpStatus: 201, outcome: "proof_recorded", compensation: "not_required" };
  }
  async expire(id, now) {
    const p = this.payments.get(id);
    if (!p || p.status !== "pending") return { httpStatus: 409, outcome: "not_expirable" };
    if (now < p.expiresAt) return { httpStatus: 409, outcome: "not_expired" };
    p.status = "expired"; return { httpStatus: 200, outcome: "expired" };
  }
  async webhook(id, eventId) {
    if (this.events.has(eventId)) return { httpStatus: 200, outcome: "duplicate_webhook_ignored" };
    this.events.add(eventId);
    const p = this.payments.get(id);
    if (!p) return { httpStatus: 404, outcome: "payment_not_found" };
    if (p.status === "expired" || p.status === "superseded") return { httpStatus: 409, outcome: "late_webhook_ignored" };
    p.status = "paid"; return { httpStatus: 200, outcome: "paid" };
  }
}
test("checkout: 12 concurrent same-key requests create one order", async () => {
  const db = new MockCommerce(), before = db.snapshot(), payload = { branch: "demo", qty: 2 };
  const results = await Promise.all(Array.from({ length: 12 }, () => db.createOrder("idem-concurrent", payload)));
  assert.equal(db.orders.size, 1);
  assert.equal(results.filter(x => x.outcome === "created").length, 1);
  assert.equal(results.filter(x => x.outcome === "idempotent_replay").length, 11);
  record("checkout_concurrent_idempotency", { method: "POST", path: "/orders", idempotencyKey: "idem-concurrent", concurrentRequests: 12 }, { httpStatus: 201, outcome: "one_created_eleven_replayed" }, before, db.snapshot());
});
test("checkout: lost response after commit retries without duplicate", async () => {
  const db = new MockCommerce(), before = db.snapshot(), payload = { total: 125000 };
  await assert.rejects(db.createOrder("idem-lost", payload, true), /response_lost/);
  const retry = await db.createOrder("idem-lost", payload);
  assert.equal(db.orders.size, 1); assert.equal(retry.outcome, "idempotent_replay");
  record("checkout_lost_response_retry", { method: "POST", path: "/orders", idempotencyKey: "idem-lost", retry: true }, retry, before, db.snapshot());
});
test("checkout: changed payload on same key returns conflict", async () => {
  const db = new MockCommerce(), before = db.snapshot();
  await db.createOrder("idem-mismatch", { total: 100 });
  const result = await db.createOrder("idem-mismatch", { total: 999 });
  assert.equal(result.httpStatus, 409); assert.equal(db.orders.size, 1);
  record("checkout_payload_mismatch", { method: "POST", path: "/orders", idempotencyKey: "idem-mismatch" }, result, before, db.snapshot());
});
test("payment proof: storage upload failure creates no row or object", async () => {
  const db = new MockCommerce(), before = db.snapshot(), result = await db.uploadProof("pay-upload", { failUpload: true });
  assert.equal(result.httpStatus, 503); assert.equal(db.payments.size, 0); assert.equal(db.objects.size, 0);
  record("payment_storage_upload_failure", { method: "POST", path: "/payment-proofs", paymentId: "pay-upload" }, result, before, db.snapshot(), result.compensation);
});
test("payment proof: database failure deletes uploaded object", async () => {
  const db = new MockCommerce(), before = db.snapshot(), result = await db.uploadProof("pay-db", { failDb: true });
  assert.equal(result.compensation, "object_deleted"); assert.equal(db.objects.size, 0); assert.equal(db.payments.size, 0);
  record("payment_db_failure_compensated", { method: "POST", path: "/payment-proofs", paymentId: "pay-db" }, result, before, db.snapshot(), result.compensation);
});
test("payment proof: failed compensation reports orphan object", async () => {
  const db = new MockCommerce(), before = db.snapshot(), result = await db.uploadProof("pay-orphan", { failDb: true, failDelete: true });
  assert.equal(result.compensation, "failed_orphan_object"); assert.ok(db.objects.has("proof/pay-orphan")); assert.equal(db.payments.size, 0);
  record("payment_compensation_failure_orphan", { method: "POST", path: "/payment-proofs", paymentId: "pay-orphan" }, result, before, db.snapshot(), result.compensation);
});
test("payment expiry: worker expires due pending payment only", async () => {
  const db = new MockCommerce(), before = db.snapshot(); db.payments.set("pay-expire", { id: "pay-expire", status: "pending", expiresAt: 1000 });
  const result = await db.expire("pay-expire", 1001);
  assert.equal(result.outcome, "expired"); assert.equal(db.payments.get("pay-expire").status, "expired");
  record("payment_expiry_worker", { method: "WORKER", path: "/payment-expiry", paymentId: "pay-expire", now: 1001 }, result, before, db.snapshot());
});
test("payment expiry: early invocation leaves payment pending", async () => {
  const db = new MockCommerce(), before = db.snapshot(); db.payments.set("pay-early", { id: "pay-early", status: "pending", expiresAt: 1000 });
  const result = await db.expire("pay-early", 999);
  assert.equal(result.outcome, "not_expired"); assert.equal(db.payments.get("pay-early").status, "pending");
  record("payment_expiry_early_guard", { method: "WORKER", path: "/payment-expiry", paymentId: "pay-early", now: 999 }, result, before, db.snapshot());
});
test("webhook arriving after expiry cannot resurrect payment", async () => {
  const db = new MockCommerce(), before = db.snapshot(); db.payments.set("pay-late", { id: "pay-late", status: "expired" });
  const result = await db.webhook("pay-late", "evt-late");
  assert.equal(result.httpStatus, 409); assert.equal(db.payments.get("pay-late").status, "expired");
  record("late_webhook_after_expiry", { method: "POST", path: "/payment-webhook", paymentId: "pay-late", eventId: "evt-late" }, result, before, db.snapshot());
});
test("duplicate webhook delivery is idempotently ignored", async () => {
  const db = new MockCommerce(), before = db.snapshot(); db.payments.set("pay-hook", { id: "pay-hook", status: "pending" });
  await db.webhook("pay-hook", "evt-dup"); const result = await db.webhook("pay-hook", "evt-dup");
  assert.equal(result.outcome, "duplicate_webhook_ignored");
  record("duplicate_webhook_delivery", { method: "POST", path: "/payment-webhook", paymentId: "pay-hook", eventId: "evt-dup", deliveries: 2 }, result, before, db.snapshot());
});
test("late webhook for superseded attempt is ignored", async () => {
  const db = new MockCommerce(), before = db.snapshot(); db.payments.set("pay-old", { id: "pay-old", status: "superseded" });
  const result = await db.webhook("pay-old", "evt-old");
  assert.equal(result.outcome, "late_webhook_ignored"); assert.equal(db.payments.get("pay-old").status, "superseded");
  record("late_webhook_after_supersession", { method: "POST", path: "/payment-webhook", paymentId: "pay-old", eventId: "evt-old" }, result, before, db.snapshot());
});
test("evidence records are unique, sanitized, and explicitly mock-backed", () => {
  assert.equal(evidence.length, 11);
  assert.equal(new Set(evidence.map(x => x.scenarioId)).size, evidence.length);
  assert.ok(evidence.every(x => x.adapter === "in_memory_mock" && x.secretsPrinted === false));
});
