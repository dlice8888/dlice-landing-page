import test from "node:test";
import assert from "node:assert/strict";
import { createPayrollPaymentFinanceRpcAdapter } from "../../src/providers/payroll-payment-finance-supabase-rpc.mjs";

test("Supabase payroll Finance RPC adapter maps scoped arguments to database RPC names", async () => {
  const calls = [];
  const adapter = createPayrollPaymentFinanceRpcAdapter({
    supabase: { rpc: async (name, args) => { calls.push({ name, args }); return { data: { status: "ok" }, error: null }; } },
  });
  const result = await adapter.postPayrollPaymentFinanceClearing({
    tenantId: "tenant-a", paymentBatchId: "batch-a", actorId: "actor-a",
  });
  assert.deepEqual(result, { status: "ok" });
  assert.deepEqual(calls[0], {
    name: "hr_post_payroll_payment_finance_clearing",
    args: { p_tenant_id: "tenant-a", p_payment_batch_id: "batch-a", p_actor_user_id: "actor-a" },
  });
});

test("Supabase payroll Finance RPC adapter rejects missing tenant or actor scope", async () => {
  const adapter = createPayrollPaymentFinanceRpcAdapter({
    supabase: { rpc: async () => ({ data: {}, error: null }) },
  });
  await assert.rejects(adapter.reconcilePayrollPaymentBankBatch({
    tenantId: "tenant-a", paymentBatchId: "batch-a",
  }), { code: "PAYROLL_FINANCE_RPC_INPUT_INVALID" });
});

test("Supabase payroll Finance RPC adapter never returns raw database error details", async () => {
  const adapter = createPayrollPaymentFinanceRpcAdapter({
    supabase: { rpc: async () => ({ data: null, error: { code: "42501", message: "sensitive detail" } }) },
  });
  await assert.rejects(adapter.postPayrollPaymentFinanceClearing({
    tenantId: "tenant-a", paymentBatchId: "batch-a", actorId: "actor-a",
  }), (error) => {
    assert.equal(error.code, "PAYROLL_FINANCE_DATABASE_OPERATION_FAILED");
    assert.equal(error.message, "Payroll Finance database operation failed");
    assert.equal(error.databaseCode, "42501");
    assert.equal(error.message.includes("sensitive detail"), false);
    return true;
  });
});
