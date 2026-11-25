import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const read=p=>readFileSync(new URL(p,import.meta.url),"utf8");
const sql=read("../../docs/implementation/sql/FRANCHISE_EXPANSION_SCHEMA_DRAFT.sql");
const edge=read("../../supabase/functions/dlice-orders/index.ts");
const erp=read("../../erp.html");

test("Franchise agreement creation seeds all ten opening gates atomically",()=>{
 assert.match(sql,/insert into public\.franchise_opening_gates\(agreement_id,gate_key\)/);
 for(const gate of ["legal_signed","site_approved","permits","fitout","equipment","staffing","training","inventory","pos_ready","brand_audit"])
  assert.match(sql,new RegExp("'"+gate+"'"));
});

test("Opening gate verification requires signed agreement, evidence and independent reviewer",()=>{
 assert.match(sql,/create or replace function public\.franchise_review_opening_gate/);
 assert.match(sql,/SIGNED_FRANCHISE_AGREEMENT_REQUIRED_FOR_OPENING_GATE/);
 assert.match(sql,/FRANCHISE_OPENING_GATE_EVIDENCE_REQUIRED/);
 assert.match(sql,/INDEPENDENT_FRANCHISE_GATE_VERIFIER_REQUIRED/);
 assert.match(sql,/PASSED_FRANCHISE_OPENING_GATE_IS_FINAL/);
 assert.match(sql,/revoke all on function public\.franchise_review_opening_gate/);
 assert.match(sql,/grant execute on function public\.franchise_review_opening_gate[^;]*to service_role/);
});

test("Signed agreement activation atomically verifies all ten effective opening gates",()=>{
 const start=sql.indexOf("create or replace function public.franchise_activate_signed_agreement");
 const end=sql.indexOf("revoke all on function public.franchise_activate_signed_agreement",start);
 const body=sql.slice(start,end);
 assert.match(body,/update public\.franchise_agreements set tenant_id/);
 assert.match(body,/perform public\.franchise_assert_opening_ready\(v\.id,current_date\)/);
 assert.match(sql,/if v_count<>10 then raise exception/);
 assert.match(sql,/FRANCHISE_AGREEMENT_VERSION_NOT_EFFECTIVE/);
});

test("Franchise Edge action and ERP UI expose the opening gate workflow",()=>{
 assert.match(edge,/erp-franchise-review-opening-gate/);
 assert.match(edge,/admin\.rpc\("franchise_review_opening_gate"/);
 assert.match(edge,/franchise_opening_gates\(id,gate_key,status,evidence_reference,verified_by,verified_at\)/);
 assert.match(erp,/data-fr-review-opening-gate/);
 assert.match(erp,/erp-franchise-review-opening-gate/);
});

test("Franchise agreement date validation uses real YYYY-MM-DD digit patterns",()=>{
 assert.match(edge,/!\/^\\d\{4\}-\\d\{2\}-\\d\{2\}\$\//);
 assert.doesNotMatch(edge,/\^d\{4\}-d\{2\}-d\{2\}\$/);
});
