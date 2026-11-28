import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";

const migrationDir = new URL("../../supabase/migrations/", import.meta.url);
const testDir = new URL("../../supabase/tests/", import.meta.url);
const domainMigrations = [
  "20261128025950_20261126192455_crm_loyalty_financial_close.sql",
  "20261128030011_20261126192458_hr_workforce_payroll_finance.sql",
  "20261128030020_20261126192501_delivery_fulfillment_provider.sql",
  "20261128030021_20261126192504_franchise_expansion.sql",
  "20261128030024_20261126192506_procurement_supplier.sql",
  "20261128030026_20261126192509_bi_analytics.sql",
  "20261128030028_20261126192512_saas_tenant_billing.sql",
  "20261128030031_20261126192514_executive_command_center.sql"
];
const draftFiles = [
  "CRM_LOYALTY_SCHEMA_DRAFT.sql","CRM_LOYALTY_ADAPTERS_EXTENSION_DRAFT.sql",
  "CRM_FINANCIAL_CLOSE_REVIEW_EXTENSION_DRAFT.sql","CRM_LOYALTY_EXPIRY_EXTENSION_DRAFT.sql",
  "HR_WORKFORCE_SCHEMA_DRAFT.sql","HR_EMPLOYEE_LIFECYCLE_EXTENSION_DRAFT.sql",
  "HR_PAYROLL_FINANCE_SCHEMA_DRAFT.sql","HR_PAYROLL_PAYMENT_ADAPTERS_DRAFT.sql",
  "DELIVERY_FULFILLMENT_SCHEMA_DRAFT.sql","DELIVERY_PROVIDER_STORAGE_SCHEMA_DRAFT.sql",
  "DELIVERY_ATOMIC_ADAPTERS_EXTENSION_DRAFT.sql","FRANCHISE_EXPANSION_SCHEMA_DRAFT.sql",
  "PROCUREMENT_SUPPLIER_SCHEMA_DRAFT.sql","BI_ANALYTICS_SCHEMA_DRAFT.sql",
  "SAAS_TENANT_BILLING_SCHEMA_DRAFT.sql","EXECUTIVE_COMMAND_CENTER_SCHEMA_DRAFT.sql"
];
const drafts = new URL("../../docs/implementation/sql/", import.meta.url);
const tables = new Set(draftFiles.flatMap(name =>
  [...readFileSync(new URL(name,drafts),"utf8").matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?public\.([a-z0-9_]+)/gi)].map(m=>m[1])
));

test("all eight domain SQL drafts are represented by official timestamped migrations",()=>{
 const files=new Set(readdirSync(migrationDir));
 for(const name of domainMigrations)assert.ok(files.has(name),name+" is missing");
 assert.ok(files.has("20261124134101_pos_checkout_lifecycle.sql"));
 assert.ok(files.has("20261124134222_pos_checkout_fk_supporting_indexes.sql"));
 assert.equal(tables.size,71);
});
test("each official domain migration retains server-only RLS and ACL boundaries",()=>{
 for(const name of domainMigrations){
  const sql=readFileSync(new URL(name,migrationDir),"utf8");
  assert.match(sql,/enable row level security/i,name+": RLS missing");
  assert.match(sql,/revoke all on public\.%I from anon,authenticated/i,name+": client revoke missing");
  assert.match(sql,/grant select,insert,update,delete on public\.%I to service_role/i,name+": service role grant missing");
  assert.doesNotMatch(sql,/DESIGN DRAFT ONLY|NOT A MIGRATION/i,name+": draft marker remains");
  assert.doesNotMatch(sql,/public\.storage\.objects/i,name+": invalid storage qualification");
  const unmatched=sql.split(/\r?\n/).filter(line=>/!~/.test(line)&&((line.match(/'/g)??[]).length%2)===1);
  assert.deepEqual(unmatched,[],name+": regex quote imbalance");
 }
});
test("Delivery webhook and Franchise applicant validators are complete SQL predicates",()=>{
 const delivery=readFileSync(new URL(domainMigrations[2],migrationDir),"utf8");
 const franchise=readFileSync(new URL(domainMigrations[3],migrationDir),"utf8");
 assert.ok(delivery.includes("or p_payload_sha256 !~ '^[0-9a-f]{64}$' then"));
 assert.ok(franchise.includes("or p_applicant_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'"));
});
test("every new domain table has an executable pgTAP RLS/ACL assertion",()=>{
 const sql=readFileSync(new URL("eight_domain_rls_acl.test.sql",testDir),"utf8");
 assert.match(sql,/select plan\(994\)/);
 for(const name of tables)assert.ok(sql.includes("public."+name),name+": no ACL test");
});
test("all SQL draft regex predicates have balanced string literals",()=>{
 for(const name of draftFiles){
  const sql=readFileSync(new URL(name,drafts),"utf8");
  const unmatched=sql.split(/\r?\n/).filter(line=>/!~/.test(line)&&((line.match(/'/g)??[]).length%2)===1);
  assert.deepEqual(unmatched,[],name+": regex quote imbalance");
 }
});
test("CRM identity, loyalty and campaign acceptance remains in canonical pgTAP",()=>{
 const sql=readFileSync(new URL("crm_loyalty.test.sql",testDir),"utf8");
 assert.match(sql,/select plan\(44\)/i);
 assert.match(sql,/select \* from finish\(\)/i);
});
