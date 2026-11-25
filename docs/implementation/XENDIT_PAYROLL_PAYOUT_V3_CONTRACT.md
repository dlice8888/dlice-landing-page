# Xendit Payout v3 — D’Lice Payroll Adapter Contract

Status: implementation scaffold / staging-only. No provider account, commercial agreement, credential, bank beneficiary, or live payout is assumed to exist.

## Official contract

- Create payout: POST https://api.xendit.co/v3/payouts
- API version header: `api-version: 2025-09-01`
- Authentication: HTTP Basic using the Xendit Secret API Key as username and an empty password.
- Required permission: `MONEY-OUT`.
- Idempotency: `idempotency-key`, max 100 characters. Xendit documents same key + same body as returning the initial payout; same key + different body as duplicate error.
- Webhook endpoint configured in Xendit Dashboard under PAYOUT.
- Events: `v3_payout.succeeded`, `v3_payout.failed`, `v3_payout.reversed`, `v3_payout.rejected`, `v3_payout.pending_compliance`.

References:
- https://docs.xendit.co/apidocs/create-payout-v3
- https://docs.xendit.co/apidocs/payout-v3-webhook
- https://docs.xendit.co/docs/payouts-set-up-webhooks
- https://docs.xendit.co/v1/docs/handling-webhooks

## Implementation boundary

`src/providers/xendit-payout-v3.mjs` implements the HTTP contract and webhook normalization. Network dispatch is locked unless `enableTestNetwork: true` and the credential begins with `xnd_development_`. A production-prefixed key is rejected even when the test switch is enabled. Tests inject fetch and never contact Xendit.

`executeApprovedPayrollPayment` now requires the trusted `loadApprovedPayrollPayoutProviderPayload` repository port. It must resolve the beneficiary from the server-side token/vault reference and return the complete provider request body inside a tenant-authorized transaction. It must not accept bank account details from a browser or persist raw bank details in logs. The orchestration verifies IDR amount, source/destination currency, and the immutable provider reference against the approved payment intent before dispatch.

## Webhook security

The adapter validates the configured Xendit callback token using constant-time comparison, then validates the raw JSON payload and event/status pair. The callback token must be stored as a server-only secret from the Xendit Dashboard webhook configuration. The callback endpoint must pass the original raw body and the received `x-callback-token` header; do not parse and reserialize the body before verification.

The payout-specific API reference documents event payloads but does not enumerate the callback header in its schema. The implementation uses Xendit's documented callback-token mechanism; confirm the exact header shown in the merchant Dashboard's payout webhook test before enabling endpoint delivery. Fail closed if the configured header/token contract differs.

The webhook verifier produces a stable SHA-256 event fingerprint. The receiving persistence adapter must enforce a unique constraint on (provider, event fingerprint), locate the payment by provider payout ID/reference ID, verify tenant and amount, and persist event + state transition atomically. Duplicate fingerprints must be acknowledged without applying a second state transition. Do not treat webhook receipt alone as Finance reconciliation.

## Settlement and Finance rules

- `ACCEPTED` / routing / pending-compliance states are submitted or pending, never paid.
- `v3_payout.succeeded` with status `SUCCEEDED` is provider evidence that the partner bank credited the beneficiary.
- `failed` / `rejected` remain unpaid and require the documented provider failure reason.
- `reversed` must create a compensating/reversal event; never rewrite the original success as if it never happened.
- Finance reconciliation requires exact match on tenant, payroll run, provider payout ID, immutable reference ID, currency IDR, amount, and posted payroll journal. Any mismatch is an exception, not a partial success.
- Payroll journal remains balanced and immutable; settlement does not re-post payroll expense. A separate bank/provider clearing and reversal journal policy must be approved before final posting.

## Environment and release gates

- No credentials, bank account numbers, webhook secrets, or employee PII in GitHub.
- No production key, live network, payout dispatch, migration, merge, or deployment in this work.
- Staging credentials must be Xendit development/test credentials stored only in the staging secret manager.
- Before provider activation: D’Lice must complete provider onboarding, confirm IDR bank coverage, obtain MONEY-OUT permission, configure payout webhooks, and approve legal/compliance/purpose-of-funds settings.
- Before any real payout: require an explicit separate approval, a controlled low-value test plan, dual authorization, reconciliation, and production release gate.
