import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { setTimeout as delay } from "node:timers/promises";

const required = ["LOCAL_SUPABASE_URL", "LOCAL_SERVICE_ROLE_KEY", "LOCAL_ANON_KEY", "LOCAL_DATABASE_URL", "SUPABASE_WORKDIR"];
for (const name of required) {
  if (!process.env[name]) throw new Error(`Missing required local runtime input: ${name}`);
}
const baseUrl = process.env.SUPABASE_URL.replace(/\/$/, "");
const functionUrl = `${baseUrl}/functions/v1/dlice-orders`;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const anonKey = process.env.SUPABASE_ANON_KEY;
const databaseUrl = process.env.DATABASE_URL;
const workdir = process.env.SUPABASE_WORKDIR;
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const records = [];
const record = (scenario, status, details = {}) => {
  const item = { scenario, status, timestamp: new Date().toISOString(), ...details };
  records.push(item);
  process.stdout.write(`${JSON.stringify(item)}\n`);
};
const psql = (query) => {
  const result = spawn("psql", [databaseUrl, "-X", "-v", "ON_ERROR_STOP=1", "-qAt", "-c", query], { encoding: "utf8" });
  return new Promise((resolve, reject) => {
    let stdout = "", stderr = "";
    result.stdout.on("data", (chunk) => stdout += chunk);
    result.stderr.on("data", (chunk) => stderr += chunk);
    result.on("close", (code) => code === 0 ? resolve(stdout.trim()) : reject(new Error(`psql failed (${code}): ${stderr.slice(-1200)}`)));
  });
};
const post = async (url, body) => {
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json", apikey: anonKey, authorization: `Bearer ${anonKey}` },
    body: JSON.stringify(body),
  });
  const raw = await response.text();
  let json = {};
  try { json = JSON.parse(raw); } catch {}
  return { status: response.status, json, raw };
};
const serviceHeaders = { apikey: serviceKey, authorization: `Bearer ${serviceKey}`, "content-type": "application/json" };
const objectCount = (orderId) => psql(`select count(*) from storage.objects where bucket_id='dlice-payment-proofs' and name like '${orderId}/%'`);
const paymentCount = (orderId) => psql(`select count(*) from public.payment_records where order_id='${orderId}'`);
const orderCountForKey = (key) => psql(`select count(*) from public.orders where tracking_token_hash='${sha256(key)}'`);
const checkoutBody = (key, dayOffset) => {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + dayOffset);
  return {
    action: "create-order", idempotency_key: key, customer_name: "QA Runtime",
    customer_whatsapp: "6280000000099", requested_date: date.toISOString().slice(0, 10),
    requested_time: "12:00", receiving_method: "pickup",
    branch_id: "c1000000-0000-4000-8000-000000000002",
    items: [{ slug: "qa-runtime-faults-local", quantity: 1 }],
  };
};
const callPayment = (token, orderId) => post(functionUrl, {
  action: "upload-proof", tracking_token: token, method: "bank_transfer", receipt_version: 1,
  upload_request_id: randomUUID(), mime_type: "image/png",
  file_base64: Buffer.from([137,80,78,71,13,10,26,10,0,0,0,0]).toString("base64"),
});
const waitForFunction = async () => {
  for (let attempt = 0; attempt < 90; attempt++) {
    try {
      const result = await post(functionUrl, { action: "__runtime_probe__" });
      if (result.status < 500) return;
    } catch {}
    await delay(1000);
  }
  throw new Error("Local Edge Function did not become ready within 90 seconds.");
};
const functionEnv = { ...process.env };
for (const key of ["SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEYS"]) delete functionEnv[key];
const functionProcess = spawn("supabase", ["functions", "serve", "dlice-orders", "--no-verify-jwt"], {
  cwd: workdir, stdio: "ignore", env: functionEnv,
});
let lostResponseServer;
try {
  await waitForFunction();

  // Same idempotency key under concurrent HTTP requests must produce one durable order.
  const sharedKey = "1".repeat(64);
  const sameKeyResponses = await Promise.all(Array.from({ length: 4 }, () => post(functionUrl, checkoutBody(sharedKey, 3))));
  assert.ok(sameKeyResponses.every((r) => r.status === 200 || r.status === 201), "all same-key requests must resolve successfully");
  const sameOrderIds = new Set(sameKeyResponses.map((r) => r.json.order_id));
  assert.equal(sameOrderIds.size, 1, "concurrent same-key checkout must return one order ID");
  assert.equal(await orderCountForKey(sharedKey), "1", "concurrent same-key checkout must persist one order");
  record("checkout_concurrent_same_idempotency_key", "PASS", { requests: 4, uniqueOrderIds: sameOrderIds.size, persistedOrders: 1 });

  // Simulate the response being lost after the server committed the order.
  lostResponseServer = createServer(async (req, res) => {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    await fetch(functionUrl, {
      method: "POST",
      headers: { "content-type": "application/json", apikey: anonKey, authorization: `Bearer ${anonKey}` },
      body: Buffer.concat(chunks),
    }).then((response) => response.arrayBuffer());
    res.writeHead(502, { "content-type": "application/json" });
    res.end(JSON.stringify({ error: "injected_client_response_loss" }));
  });
  await new Promise((resolve) => lostResponseServer.listen(0, "127.0.0.1", resolve));
  const proxyPort = lostResponseServer.address().port;
  const retryKey = "2".repeat(64);
  const firstLost = await post(`http://127.0.0.1:${proxyPort}`, checkoutBody(retryKey, 3));
  assert.equal(firstLost.status, 502, "client must observe a lost response after server commit");
  const retry = await post(functionUrl, checkoutBody(retryKey, 3));
  assert.equal(retry.status, 200, "retry after lost response must return idempotent success");
  assert.equal(await orderCountForKey(retryKey), "1", "lost-response retry must not duplicate the order");
  record("checkout_retry_after_lost_response", "PASS", { firstClientStatus: 502, retryStatus: retry.status, persistedOrders: 1 });

  // Two distinct customers compete for the final unit of capacity.
  const raceKeys = ["3".repeat(64), "4".repeat(64)];
  const capacityRace = await Promise.all(raceKeys.map((key) => post(functionUrl, checkoutBody(key, 4))));
  assert.equal(capacityRace.filter((r) => r.status === 201).length, 1, "exactly one competing checkout must win final capacity");
  assert.equal(capacityRace.filter((r) => r.status === 409).length, 1, "the losing checkout must receive a capacity conflict");
  const raceDate = new Date(); raceDate.setUTCDate(raceDate.getUTCDate() + 4);
  const raceCount = await psql(`select count(*) from public.orders where requested_date='${raceDate.toISOString().slice(0,10)}' and branch_id='c1000000-0000-4000-8000-000000000002'`);
  assert.equal(raceCount, "1", "final capacity must not be oversold");
  record("checkout_concurrent_final_capacity", "PASS", { requests: 2, accepted: 1, rejected: 1, persistedOrders: 1 });

  // Storage upload failure: the bucket limit is reduced below the test file size.
  await psql("update storage.buckets set file_size_limit=1 where id='dlice-payment-proofs'");
  const uploadFailure = await callPayment("a".repeat(64), "d2000000-0000-4000-8000-000000000101");
  assert.equal(uploadFailure.status, 500, "Storage upload failure must be surfaced");
  assert.equal(await paymentCount("d2000000-0000-4000-8000-000000000101"), "0", "failed upload must not create payment rows");
  assert.equal(await objectCount("d2000000-0000-4000-8000-000000000101"), "0", "failed upload must not leave objects");
  await psql("update storage.buckets set file_size_limit=5242880 where id='dlice-payment-proofs'");
  record("payment_storage_upload_failure", "PASS", { httpStatus: uploadFailure.status, paymentRows: 0, orphanObjects: 0 });

  // RPC failure after a successful Storage upload must trigger compensation.
  await psql(`create or replace function public.dlice_fault_fail_payment_insert() returns trigger language plpgsql as $$ begin if new.order_id in ('d2000000-0000-4000-8000-000000000102','d2000000-0000-4000-8000-000000000103') then raise exception 'injected_payment_rpc_failure'; end if; return new; end $$; create trigger dlice_fault_fail_payment_insert before insert on public.payment_records for each row execute function public.dlice_fault_fail_payment_insert();`);
  const rpcFailure = await callPayment("b".repeat(64), "d2000000-0000-4000-8000-000000000102");
  assert.equal(rpcFailure.status, 500, "atomic RPC failure must be surfaced");
  assert.equal(await paymentCount("d2000000-0000-4000-8000-000000000102"), "0", "failed RPC must roll back payment rows");
  assert.equal(await objectCount("d2000000-0000-4000-8000-000000000102"), "0", "successful compensation must remove uploaded object");
  record("payment_rpc_failure_compensation_success", "PASS", { httpStatus: rpcFailure.status, paymentRows: 0, orphanObjects: 0 });

  // Force compensation itself to fail; the harness must observe the orphan and clean it afterward.
  await psql(`create or replace function public.dlice_fault_fail_proof_delete() returns trigger language plpgsql as $$ begin if old.bucket_id='dlice-payment-proofs' and old.name like 'd2000000-0000-4000-8000-000000000103/%' then raise exception 'injected_compensation_failure'; end if; return old; end $$; create trigger dlice_fault_fail_proof_delete before delete on storage.objects for each row execute function public.dlice_fault_fail_proof_delete();`);
  const compensationFailure = await callPayment("c".repeat(64), "d2000000-0000-4000-8000-000000000103");
  assert.equal(compensationFailure.status, 500, "RPC failure with failed compensation must be surfaced");
  const orphanCount = await objectCount("d2000000-0000-4000-8000-000000000103");
  assert.equal(orphanCount, "1", "failed compensation must leave one observable orphan for operator cleanup");
  await psql("drop trigger dlice_fault_fail_proof_delete on storage.objects");
  const orphanListResponse = await fetch(`${baseUrl}/storage/v1/object/list/dlice-payment-proofs`, { method: "POST", headers: serviceHeaders, body: JSON.stringify({ prefix: "d2000000-0000-4000-8000-000000000103", limit: 100 }) });
  assert.equal(orphanListResponse.status, 200, "operator cleanup must list the disposable orphan");
  const orphanList = await orphanListResponse.json();
  for (const object of orphanList) {
    await fetch(`${baseUrl}/storage/v1/object/dlice-payment-proofs/d2000000-0000-4000-8000-000000000103/${encodeURIComponent(object.name)}`, { method: "DELETE", headers: serviceHeaders });
  }
  await psql("drop trigger dlice_fault_fail_payment_insert on public.payment_records");
  await psql("drop function public.dlice_fault_fail_payment_insert()");
  await psql("drop function public.dlice_fault_fail_proof_delete()");
  assert.equal(await objectCount("d2000000-0000-4000-8000-000000000103"), "0", "operator cleanup must remove the observed orphan");
  record("payment_compensation_failure_and_operator_cleanup", "PASS", { orphanObserved: Number(orphanCount), orphanAfterCleanup: 0 });

  // Deterministically expire the reservation after Storage accepts the object but before the RPC.
  await psql(`create or replace function public.dlice_fault_expire_after_upload() returns trigger language plpgsql as $$ begin if new.bucket_id='dlice-payment-proofs' and new.name like 'd2000000-0000-4000-8000-000000000104/%' then update public.order_reservations set status='expired',expires_at=now()-interval '1 second' where order_id='d2000000-0000-4000-8000-000000000104'; end if; return new; end $$; create trigger dlice_fault_expire_after_upload after insert on storage.objects for each row execute function public.dlice_fault_expire_after_upload();`);
  const expiryRace = await callPayment("d".repeat(64), "d2000000-0000-4000-8000-000000000104");
  assert.equal(expiryRace.status, 409, "RPC must reject a reservation expired during upload");
  assert.equal(await paymentCount("d2000000-0000-4000-8000-000000000104"), "0", "expiry race must not create a payment record");
  assert.equal(await objectCount("d2000000-0000-4000-8000-000000000104"), "0", "expiry race must compensate the uploaded object");
  await psql("drop trigger dlice_fault_expire_after_upload on storage.objects");
  await psql("drop function public.dlice_fault_expire_after_upload()");
  record("payment_upload_racing_expiry", "PASS", { httpStatus: expiryRace.status, paymentRows: 0, orphanObjects: 0 });

  // Invoke the real expiry worker against an expired disposable reservation.
  const expiryWorkerResult = await psql("select public.expire_stale_order_reservations(50)->>'expired_orders'");
  assert.ok(Number(expiryWorkerResult) >= 1, "expiry worker must process at least one expired order");
  const workerState = await psql("select fulfillment_status from public.orders where id='d2000000-0000-4000-8000-000000000105'");
  assert.equal(workerState, "failed", "expiry worker must close the expired order");
  record("expiry_worker_runtime_invocation", "PASS", { expiredOrders: Number(expiryWorkerResult), orderState: workerState });

  const failures = records.filter((item) => item.status !== "PASS");
  if (failures.length) throw new Error(`${failures.length} runtime scenario(s) failed.`);
  process.stdout.write(`RUNTIME_FAULT_INJECTION_SUMMARY ${JSON.stringify({ pass: records.length, fail: 0, blocked: 0, skipped: 0 })}\n`);
} catch (error) {
  record("runtime_harness", "FAIL", { message: String(error).slice(0, 500) });
  process.exitCode = 1;
} finally {
  if (lostResponseServer) await new Promise((resolve) => lostResponseServer.close(resolve));
  functionProcess.kill("SIGTERM");
}
