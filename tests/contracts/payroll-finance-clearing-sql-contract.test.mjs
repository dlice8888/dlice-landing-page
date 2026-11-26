import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const sql=readFileSync(new URL("../../docs/implementation/sql/HR_PAYROLL_PAYMENT_FINANCE_CLEARING_DRAFT.sql",import.meta.url),"utf8");

test("payroll finance clearing SQL uses balanced dollar-quoted PL/pgSQL bodies",()=>{
 const delimiters=sql.match(/\$\$/g)||[];
 assert.equal(delimiters.length%2,0);
 assert.ok(delimiters.length>=10);
 assert.doesNotMatch(sql,/\bas\s+\$(?:\s|$)/i);
 assert.doesNotMatch(sql,/\bend\s+\$(?:\s|$)/i);
});

test("bank statement and reconciliation evidence is immutable and service-role-only",()=>{
 assert.match(sql,/hr_payroll_bank_statement_lines_append_only/);
 assert.match(sql,/hr_payroll_bank_reconciliation_append_only/);
 assert.match(sql,/hr_payroll_reversal_exception_append_only/);
 assert.match(sql,/revoke update,delete on public\.hr_payroll_bank_statement_lines from service_role/);
 assert.match(sql,/grant select,insert on public\.hr_payroll_payment_bank_reconciliations to service_role/);
});

test("finance clearing functions use invoker security and append exact reconciliation evidence",()=>{
 assert.match(sql,/hr_reconcile_payroll_payment_bank_batch/);
 assert.match(sql,/hr_post_payroll_payment_finance_clearing/);
 assert.match(sql,/security invoker/);
 assert.doesNotMatch(sql,/security definer/i);
});
