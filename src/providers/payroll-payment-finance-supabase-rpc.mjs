/**
 * Server-only Supabase RPC bridge for payroll payout Finance commands.
 *
 * The Supabase client supplied here must be created in a trusted server/Edge
 * runtime with a server-only credential. Never import this module into a
 * browser bundle and never pass service-role credentials through its API.
 *
 * Reads/locks remain repository ports in the caller. All multi-row writes are
 * delegated to atomic SECURITY INVOKER RPCs in the approved SQL draft.
 */
function required(value, name) {
  if (typeof value !== "string" || value.trim() === "") {
    throw Object.assign(new Error(`${name} is required`), { code: "PAYROLL_FINANCE_RPC_INPUT_INVALID" });
  }
  return value.trim();
}

export function createPayrollPaymentFinanceRpcAdapter({ supabase } = {}) {
  if (!supabase || typeof supabase.rpc !== "function") {
    throw Object.assign(new Error("A trusted Supabase RPC client is required"), {
      code: "PAYROLL_FINANCE_SUPABASE_CLIENT_REQUIRED",
    });
  }

  async function invoke(functionName, args) {
    const { data, error } = await supabase.rpc(functionName, args);
    if (error) {
      const failure = new Error("Payroll Finance database operation failed");
      failure.code = "PAYROLL_FINANCE_DATABASE_OPERATION_FAILED";
      failure.operation = functionName;
      failure.databaseCode = error.code ?? null;
      throw failure;
    }
    return data;
  }

  return Object.freeze({
    approvePayrollPaymentFinanceMapping: ({ tenantId, mappingId, actorId }) =>
      invoke("hr_approve_payroll_payment_finance_mapping", {
        p_tenant_id: required(tenantId, "tenantId"),
        p_mapping_id: required(mappingId, "mappingId"),
        p_actor_user_id: required(actorId, "actorId"),
      }),

    postPayrollPaymentFinanceClearing: ({ tenantId, paymentBatchId, actorId }) =>
      invoke("hr_post_payroll_payment_finance_clearing", {
        p_tenant_id: required(tenantId, "tenantId"),
        p_payment_batch_id: required(paymentBatchId, "paymentBatchId"),
        p_actor_user_id: required(actorId, "actorId"),
      }),

    importPayrollBankStatementLine: ({
      tenantId, branchId, bankAccountFingerprintSha256, statementReference,
      providerPayoutReference, amountIdr, bookedAt, lineSha256,
      importBatchReference, actorId,
    }) => invoke("hr_import_payroll_bank_statement_line", {
      p_tenant_id: required(tenantId, "tenantId"),
      p_branch_id: required(branchId, "branchId"),
      p_bank_account_fingerprint_sha256: required(bankAccountFingerprintSha256, "bankAccountFingerprintSha256"),
      p_statement_reference: required(statementReference, "statementReference"),
      p_provider_payout_reference: required(providerPayoutReference, "providerPayoutReference"),
      p_amount_idr: amountIdr,
      p_booked_at: required(bookedAt, "bookedAt"),
      p_line_sha256: required(lineSha256, "lineSha256"),
      p_import_batch_reference: required(importBatchReference, "importBatchReference"),
      p_actor_user_id: required(actorId, "actorId"),
    }),

    matchPayrollPaymentBankStatement: ({ tenantId, clearingId, statementLineId, actorId }) =>
      invoke("hr_match_payroll_payment_bank_statement", {
        p_tenant_id: required(tenantId, "tenantId"),
        p_clearing_id: required(clearingId, "clearingId"),
        p_statement_line_id: required(statementLineId, "statementLineId"),
        p_actor_user_id: required(actorId, "actorId"),
      }),

    reconcilePayrollPaymentBankBatch: ({ tenantId, paymentBatchId, actorId }) =>
      invoke("hr_reconcile_payroll_payment_bank_batch", {
        p_tenant_id: required(tenantId, "tenantId"),
        p_payment_batch_id: required(paymentBatchId, "paymentBatchId"),
        p_actor_user_id: required(actorId, "actorId"),
      }),

    quarantineReversedPayrollPaymentClearing: ({ tenantId, paymentItemId, providerEventId, actorId }) =>
      invoke("hr_mark_payroll_payment_reversal_exception", {
        p_tenant_id: required(tenantId, "tenantId"),
        p_payment_item_id: required(paymentItemId, "paymentItemId"),
        p_provider_event_id: required(providerEventId, "providerEventId"),
        p_actor_user_id: required(actorId, "actorId"),
      }),
  });
}
