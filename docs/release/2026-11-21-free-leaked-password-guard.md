# Free breached-password guard — 2026-11-21

## Why this exists

Supabase staging is on the Free plan and the built-in leaked-password protection setting is disabled. Enabling the Supabase-native setting is not available on the current plan without a paid upgrade, which is explicitly out of scope.

## Free application-layer mitigation

- Add a server-side guard to the official D’Lice password creation/reset paths: initial Owner bootstrap, staff account creation, and staff password reset.
- Use the free Pwned Passwords range endpoint with k-anonymity: compute SHA-1 locally and send only the first five hexadecimal characters. The raw password and full hash never leave the Edge Function.
- Send `Add-Padding: true` to reduce response-size leakage.
- Reject a compromised password with HTTP 422.
- Fail closed with HTTP 503 if the check service times out or returns an error; no Auth mutation is attempted.
- Never log the password, full hash, or API response body.

## Limitations — feature remains blocked

This does **not** enable Supabase's native leaked-password protection and cannot enforce policy on arbitrary direct calls to Supabase Auth endpoints. It currently covers the application's three official password mutation flows only. Do not mark the PRD feature DONE or release the security gate until all password mutation paths are inventoried and covered, direct Auth bypass is resolved or the native feature becomes available, and staging negative/positive tests pass.

## Validation

- Deno unit tests: compromised password, clean password, API failure, k-anonymity prefix-only request and padding.
- Node contract tests: all three official Auth mutation paths call the guard.
- Free quality checks and disposable migration replay (no migration is introduced by this PR).
- No plan upgrade, no shared staging mutation, no production change.
