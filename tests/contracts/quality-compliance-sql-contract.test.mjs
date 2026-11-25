import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const sql=readFileSync(new URL("../../docs/implementation/sql/QUALITY_COMPLIANCE_ADAPTERS_EXTENSION_DRAFT.sql",import.meta.url),"utf8");
const adapter=readFileSync(new URL("../../src/supabase-quality-compliance-adapter.mjs",import.meta.url),"utf8");
const pgtap=readFileSync(new URL("../../docs/implementation/sql/QUALITY_COMPLIANCE_PGTAP_DRAFT.sql",import.meta.url),"utf8");

test("Quality persistence and atomic RPC surface covers inspection, recall, supplier and CAPA",()=>{
 for(const name of ["quality_register_food_lot","quality_link_food_lot_distribution","quality_record_food_safety_inspection","quality_initiate_food_recall","quality_record_supplier_quality_inspection","quality_submit_supplier_capa","quality_verify_supplier_capa","quality_approve_food_safety_policy","quality_approve_supplier_quality_policy"])
  assert.match(sql,new RegExp("function public\\."+name));
 assert.match(sql,/security invoker/);
 assert.doesNotMatch(sql,/security definer/i);
});

test("unsafe food lots are quarantined and recalls require persisted distribution traceability",()=>{
 assert.match(sql,/FOOD_RECALL_TRACEABILITY_INCOMPLETE/);
 assert.match(sql,/food_lot_distributions/);
 assert.match(sql,/status='recalled'/);
 assert.match(sql,/TEMPERATURE_OUT_OF_POLICY/);
 assert.match(sql,/ALLERGEN_DECLARATION_MISMATCH/);
});

test("supplier quality creates quarantine and CAPA; release requires independent verification",()=>{
 assert.match(sql,/SUPPLIER_RECEIPT_ALREADY_QUARANTINED/);
 assert.match(sql,/INDEPENDENT_SUPPLIER_CAPA_REVIEWER_REQUIRED/);
 assert.match(sql,/SUPPLIER_QUARANTINE_NOT_HELD/);
 assert.match(sql,/status='released'/);
});

test("Supabase adapter invokes one database RPC per operation and never composes REST writes",()=>{
 assert.match(adapter,/client\.rpc\(functionName, args\)/);
 assert.doesNotMatch(adapter,/\.from\(/);
 assert.doesNotMatch(adapter,/withTenantTransaction/);
});

test("pgTAP draft verifies RLS, least privilege, invoker functions and append-only evidence",()=>{
 assert.match(pgtap,/select plan\(32\)/);
 assert.match(pgtap,/has_table_privilege\('anon'/);
 assert.match(pgtap,/has_function_privilege\('authenticated'/);
 assert.match(pgtap,/SECURITY INVOKER/);
 assert.match(pgtap,/food_safety_inspections_append_only/);
});
