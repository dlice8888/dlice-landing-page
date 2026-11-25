import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const edge = readFileSync(new URL("../../supabase/functions/dlice-orders/index.ts", import.meta.url), "utf8");
const erp = readFileSync(new URL("../../erp.html", import.meta.url), "utf8");

test("CRM expiry and earning-rule actions are registered behind the CRM Platform Owner gate", () => {
  for (const action of [
    "erp-crm-list-earning-rules",
    "erp-crm-request-earning-rule",
    "erp-crm-approve-earning-rule",
    "erp-crm-expire-loyalty-points",
  ]) assert.match(edge, new RegExp('"' + action + '"'));
  assert.match(edge, /if \(crmActions\.has\(action\)\)/);
  assert.match(edge, /if \(!isPlatformOwner\)/);
});

test("CRM earning rule UI requires validity days and independent approval", () => {
  assert.match(erp, /id="crmEarningValidity"/);
  assert.match(erp, /erp-crm-request-earning-rule/);
  assert.match(erp, /erp-crm-approve-earning-rule/);
  assert.match(erp, /reviewer lain/);
});

test("CRM ledger UI runs expiry and exposes adjustment/reversal rather than bypass earn/redeem", () => {
  assert.match(erp, /id="crmExpirePointsBtn"/);
  assert.match(erp, /erp-crm-expire-loyalty-points/);
  assert.match(erp, /id="crmLedgerReverses"/);
  assert.match(erp, /option value="adjustment"/);
  assert.match(erp, /option value="reversal"/);
  assert.doesNotMatch(erp, /option value="earn"/);
  assert.doesNotMatch(erp, /option value="redeem"/);
});
