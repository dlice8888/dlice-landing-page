import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const paths=[
 "../../docs/implementation/sql/BI_ANALYTICS_SCHEMA_DRAFT.sql",
 "../../docs/implementation/sql/CRM_FINANCIAL_CLOSE_REVIEW_EXTENSION_DRAFT.sql",
 "../../docs/implementation/sql/CRM_LOYALTY_ADAPTERS_EXTENSION_DRAFT.sql",
 "../../docs/implementation/sql/CRM_LOYALTY_EXPIRY_EXTENSION_DRAFT.sql",
 "../../docs/implementation/sql/CRM_LOYALTY_SCHEMA_DRAFT.sql",
 "../../docs/implementation/sql/DELIVERY_FULFILLMENT_SCHEMA_DRAFT.sql",
 "../../docs/implementation/sql/DELIVERY_PROVIDER_STORAGE_SCHEMA_DRAFT.sql",
 "../../docs/implementation/sql/EXECUTIVE_COMMAND_CENTER_SCHEMA_DRAFT.sql",
 "../../docs/implementation/sql/FRANCHISE_EXPANSION_SCHEMA_DRAFT.sql",
 "../../docs/implementation/sql/HR_EMPLOYEE_LIFECYCLE_EXTENSION_DRAFT.sql",
 "../../docs/implementation/sql/HR_PAYROLL_FINANCE_SCHEMA_DRAFT.sql",
 "../../docs/implementation/sql/HR_PAYROLL_PAYMENT_ADAPTERS_DRAFT.sql",
 "../../docs/implementation/sql/HR_WORKFORCE_SCHEMA_DRAFT.sql",
 "../../docs/implementation/sql/PROCUREMENT_SUPPLIER_SCHEMA_DRAFT.sql",
 "../../docs/implementation/sql/SAAS_TENANT_BILLING_SCHEMA_DRAFT.sql",
];
test("all active transactional workflow SQL drafts have balanced dollar quoting",()=>{
 for(const path of paths){
  const sql=readFileSync(new URL(path,import.meta.url),"utf8");
  const markers=sql.match(/\$\$/g)||[];
  assert.equal(markers.length%2,0,path+" has unbalanced $$ delimiters");
  assert.doesNotMatch(sql,/\bas\s+\$(?:\s|$)/im,path+" contains malformed AS delimiter");
  assert.doesNotMatch(sql,/\bdo\s+\$(?:\s|$)/im,path+" contains malformed DO delimiter");
  assert.doesNotMatch(sql,/\bend\s+\$(?:\s|$)/im,path+" contains malformed END delimiter");
 }
});
