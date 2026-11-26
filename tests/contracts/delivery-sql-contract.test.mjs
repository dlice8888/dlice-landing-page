import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const read=p=>readFileSync(new URL(p,import.meta.url),"utf8");
const base=read("../../docs/implementation/sql/DELIVERY_FULFILLMENT_SCHEMA_DRAFT.sql");
const provider=read("../../docs/implementation/sql/DELIVERY_PROVIDER_STORAGE_SCHEMA_DRAFT.sql");
const atomic=read("../../docs/implementation/sql/DELIVERY_ATOMIC_ADAPTERS_EXTENSION_DRAFT.sql");
const edge=read("../../supabase/functions/dlice-orders/index.ts");
test("Delivery adapter SQL dependencies exist in the declared replay order",()=>{
 for(const name of ["delivery_provider_configs","delivery_provider_quotes","delivery_storage_evidence","delivery_cost_reconciliations","delivery_outbox"])
  assert.match(provider,new RegExp("create table if not exists public\\."+name));
 for(const name of ["delivery_dispatches","delivery_provider_events","delivery_proof_of_delivery"])
  assert.match(base,new RegExp("create table if not exists public\\."+name));
 assert.match(atomic,/references public\.finance_journal_entries\(id\)/);
 assert.match(atomic,/amount_idr=p_provider_settlement_idr/);
});
test("Delivery booking, verified webhook, worker queue and reconciliation are atomic SQL RPCs",()=>{
 for(const fn of ["delivery_request_provider_config","delivery_create_provider_quote","delivery_book_dispatch_from_quote","delivery_confirm_provider_booking","delivery_ingest_verified_provider_event","delivery_claim_outbox_batch","delivery_finish_outbox","delivery_get_outbox_job_context","delivery_reconcile_cost"])
  assert.match(atomic,new RegExp("create or replace function public\\."+fn));
 assert.match(atomic,/for update skip locked/);
 assert.match(atomic,/DELIVERY_OUTBOX_CLAIM_MISMATCH/);
 assert.match(atomic,/DELIVERY_QUOTE_IDEMPOTENCY_COLLISION/);
 assert.match(atomic,/DELIVERY_RECONCILIATION_IDEMPOTENCY_COLLISION/);
 assert.match(atomic,/DELIVERY_PROOF_REQUIRED/);
});
test("Delivery provider evidence is append-only and privileged RPCs are not exposed to browser roles",()=>{
 assert.match(atomic,/delivery_provider_events_append_only/);
 assert.match(atomic,/delivery_cost_reconciliations_append_only/);
 assert.match(atomic,/delivery_storage_evidence_append_only/);
 assert.match(atomic,/revoke all on function public\.delivery_reconcile_cost/);
 assert.match(atomic,/grant execute on function public\.delivery_reconcile_cost[^;]*to service_role/);
 assert.doesNotMatch(atomic,/security definer/i);
});
test("Delivery Edge actions authenticate Platform Owner and authorize selected branch before RPC",()=>{
 const start=edge.indexOf('const deliveryProviderConfigActions=new Set(');
 const end=edge.indexOf('const qualityActions = new Set([',start);
 assert.ok(start>=0&&end>start);
 const block=edge.slice(start,end);
 assert.match(block,/if\(!isPlatformOwner\)/);
 assert.match(block,/const deliveryAtomicActions=new Set\(/);
 assert.match(block,/admin\.from\("branches"\)/);
 assert.match(block,/branch\.tenant_id/);
 assert.match(block,/admin\.rpc\(name,args\)/);
 assert.match(block,/delivery_approve_provider_config/);
 assert.match(block,/delivery_reconcile_cost/);
});
