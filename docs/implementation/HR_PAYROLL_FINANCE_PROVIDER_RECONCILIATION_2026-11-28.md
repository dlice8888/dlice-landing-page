# HR Payroll ↔ Finance Journal & Payment Reconciliation — 2026-11-28

## Candidate implementation

The HR migration already provides payroll calculation, approval, Finance posting and reconciliation RPCs. This batch adds the missing provider/beneficiary/payment-batch access path.

### Payroll lifecycle

1. Approved timesheets and effective compensation rates produce a payroll run.
2. Payroll run must be approved before Finance posting preparation.
3. Finance posting is prepared from the existing account mapping, posted to `finance_journal_entries`, and reconciled by an independent actor. The payment batch preparation RPC rejects payroll/Finance states that are not reconciled.
4. Provider configuration is requested by secret reference and approved by a different actor. Provider secret values are held only in Edge Function Secrets.
5. Beneficiary profiles are requested using an employee-specific secret reference. The server reads a structured secret, validates bank code/account number/account name, computes a SHA-256 fingerprint, and stores only the secret reference and fingerprint. Raw account data is not written to database or browser.
6. Payment batch is prepared only when all payroll lines have approved beneficiary profiles and an approved provider configuration.
7. A generic HMAC-SHA256 provider webhook verifies the raw request body before calling `hr_apply_payroll_provider_event`. Provider events are idempotent and amount/item/batch scoped.
8. An independent reviewer approves the batch; a different independent reconciler verifies that every payment item is settled and provider evidence is complete before reconciliation.

## Files changed

- `supabase/functions/dlice-orders/index.ts` (provider config, beneficiary, batch and reconciliation actions)
- `supabase/functions/hr-payroll-provider-webhook/index.ts` (raw-body HMAC-SHA256 verification)
- `erp.html` (provider, beneficiary, batch and item review UI)
- `tests/contracts/hr-payroll-payment-workflows.test.mjs`
- `.github/workflows/quality-checks.yml`

## Provider limitations and acceptance boundary

- This is a generic HMAC callback adapter, not a provider-specific payout dispatcher. The actual provider API, signature header, event schema, credentials and idempotency contract must be approved before deployment. The webhook is not deployed.
- Configure webhook function deployment with JWT gateway verification disabled only because provider callbacks use HMAC authentication; the function independently verifies the signature before any database write. All HR management actions remain behind the authenticated `dlice-orders` API and Platform Owner gate.
- Provider credentials and beneficiary details are not present in staging. No provider E2E has been run.
- No staging migration, Edge deployment, merge or release was performed.
