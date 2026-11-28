import test from "node:test";
import assert from "node:assert/strict";
import { createSupabaseBiAdapter } from "../../src/supabase-bi-analytics-adapter.mjs";
import { runBiEvidenceIngestion } from "../../src/workers/bi-evidence-ingestion-worker.mjs";
import { readFileSync } from "node:fs";
const read=p=>readFileSync(new URL(p,import.meta.url),"utf8");
const sql=read("../../docs/implementation/sql/BI_ANALYTICS_SCHEMA_DRAFT.sql");
const edge=read("../../supabase/functions/dlice-orders/index.ts");
const erp=read("../../erp.html");

test("BI Supabase adapter calls one atomic RPC per evidence mutation",async()=>{
 const calls=[];const adapter=createSupabaseBiAdapter({rpc:async(name,args)=>{calls.push({name,args});return {data:{ok:true},error:null}}});
 await adapter.recordSourceWatermark({tenantId:"t",sourceKey:"pos_sales",windowStart:"2026-01-01T00:00:00Z",windowEnd:"2026-01-02T00:00:00Z",maxSourceUpdatedAt:"2026-01-02T00:00:00Z",expectedCount:5,observedCount:5,ingestionRunId:"run-key-123",actorId:"u"});
 await adapter.createReconciliationRun({tenantId:"t",periodStart:"2026-01-01",periodEnd:"2026-01-02",sourceDomain:"pos",sourceReference:"recon-ref-123",expectedTotal:100,observedTotal:100,tolerance:0,idempotencyKey:"recon-key-123",actorId:"u"});
 await adapter.createMetricSnapshot({tenantId:"t",metricId:"m",periodStart:"2026-01-01T00:00:00Z",periodEnd:"2026-01-02T00:00:00Z",metricValue:100,sourceWatermarkIds:["w"],reconciliationRunIds:["r"],formulaVersion:1,idempotencyKey:"snapshot-key-123",actorId:"u"});
 assert.deepEqual(calls.map(x=>x.name),["bi_record_source_watermark","bi_create_reconciliation_run","bi_create_metric_snapshot"]);
 assert.equal(calls[0].args.p_actor_user_id,"u");
});

test("BI worker persists watermarks, pending reconciliation and draft snapshot but never self-publishes",async()=>{
 const calls=[];const adapter={
  recordSourceWatermark:async x=>{calls.push(["watermark",x]);return {watermark_id:"wm-1",watermark_status:"complete"};},
  createReconciliationRun:async x=>{calls.push(["reconciliation",x]);return {reconciliation_id:"recon-1",reconciliation_status:"pending"};},
  createMetricSnapshot:async x=>{calls.push(["snapshot",x]);return {snapshot_id:"snap-1",snapshot_status:"draft"};},
  publishMetricSnapshot:async()=>{throw new Error("worker must not publish")}
 };
 const result=await runBiEvidenceIngestion({tenantId:"tenant-a",actorId:"worker-user",periodStart:"2026-01-01T00:00:00Z",periodEnd:"2026-01-02T00:00:00Z",
  runIdempotencyKey:"daily-run-20260102",metrics:[{id:"metric-a",formulaVersion:2,sourceEntities:["pos_sales"],ownerDomain:"POS"}],
  collectSource:async()=>({windowStart:"2026-01-01T00:00:00Z",windowEnd:"2026-01-02T00:00:00Z",maxSourceUpdatedAt:"2026-01-02T00:00:00Z",expectedCount:10,observedCount:10}),
  calculateMetric:async()=>({metricValue:250,dimensionKey:"branch_id",dimensionValue:"branch-a",reconciliation:{expectedTotal:250,observedTotal:250,tolerance:0,sourceReference:"source-recon-123"}}),adapter});
 assert.equal(result.status,"pending_review");assert.equal(result.published,false);
 assert.deepEqual(calls.map(x=>x[0]),["watermark","reconciliation","snapshot"]);
 assert.equal(calls[2][1].reconciliationRunIds[0],"recon-1");
});

test("BI worker records a failed metric when source evidence collection fails",async()=>{
 const adapter={recordSourceWatermark:async()=>{throw new Error("source down")},createReconciliationRun:async()=>{throw new Error("must not run")},createMetricSnapshot:async()=>{throw new Error("must not run")}};
 const result=await runBiEvidenceIngestion({tenantId:"t",actorId:"u",periodStart:"2026-01-01",periodEnd:"2026-01-02",runIdempotencyKey:"run-key-0001",
  metrics:[{id:"m",formulaVersion:1,sourceEntities:["orders"]}],collectSource:async()=>({}),calculateMetric:async()=>({metricValue:1,reconciliation:{expectedTotal:1,observedTotal:1,tolerance:0}}),adapter});
 assert.equal(result.status,"partial");assert.equal(result.results[0].status,"failed");
});

test("BI SQL enforces completeness, independent reconciliation/lineage approval and tenant-bound publishing",()=>{
 for(const fn of ["bi_record_source_watermark","bi_create_reconciliation_run","bi_review_reconciliation_run","bi_register_metric_source_lineage","bi_create_metric_snapshot","bi_publish_metric_snapshot"])
  assert.match(sql,new RegExp("create or replace function public\\."+fn));
 assert.match(sql,/BI_WATERMARK_IDEMPOTENCY_COLLISION/);
 assert.match(sql,/INDEPENDENT_BI_RECONCILIATION_REVIEWER_REQUIRED/);
 assert.match(sql,/INDEPENDENT_BI_LINEAGE_APPROVER_REQUIRED/);
 assert.match(sql,/BI_METRIC_SOURCE_LINEAGE_INCOMPLETE/);
 assert.match(sql,/BI_SOURCE_WATERMARK_INCOMPLETE_STALE_OR_OUT_OF_SCOPE/);
 assert.match(sql,/INDEPENDENT_BI_SNAPSHOT_PUBLISHER_REQUIRED/);
 assert.match(sql,/grant execute on function public\.bi_review_reconciliation_run[^;]*to service_role/);
});

test("BI Edge mutation actions verify tenant ownership and Platform Owner gate",()=>{
 assert.match(edge,/const biExecutiveActions=new Set\(\[[\s\S]*erp-bi-review-reconciliation/);
 assert.match(edge,/if\(!isOwner\)return fail\("BI dan Executive Command Center/);
 assert.match(edge,/eq\("id",reconciliationId\)\.eq\("tenant_id",tenantId\)/);
 assert.match(edge,/eq\("id",snapshotId\)\.eq\("tenant_id",tenantId\)/);
 assert.match(edge,/bi_review_reconciliation_run/);
 assert.match(edge,/bi_publish_metric_snapshot/);
});

test("BI ERP UI exposes review and publish actions without displaying drafts as published",()=>{
 assert.match(erp,/id="biReconciliationList"/);
 assert.match(erp,/data-bi-review-reconciliation/);
 assert.match(erp,/data-bi-publish-snapshot/);
 assert.match(erp,/erp-bi-review-reconciliation/);
 assert.match(erp,/erp-bi-publish-snapshot/);
});
