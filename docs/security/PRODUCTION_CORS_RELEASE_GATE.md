# Production Edge Function CORS release gate

The production dlice-orders source uses an explicit allowlist:
- https://dlice.vercel.app
- https://dlice-landing-page.vercel.app

Allowed origins receive an exact Access-Control-Allow-Origin value and Vary: Origin. Foreign-origin OPTIONS preflights and POST requests return HTTP 403 without an ACAO header. Requests without an Origin header receive no ACAO fallback; this does not authenticate or reject non-browser clients.

CORS is only a browser boundary. Sensitive actions still require server-side authentication and authorization.

## Verification status

- Static CORS contract tests are included in .github/workflows/production-cors-contract.yml.
- Deno type-check is included in the same workflow.
- Runtime probes against the production Supabase hostname were not completed in the earlier execution environment because DNS resolution failed before reaching Supabase.
- This source PR does not deploy the Edge Function or change production resources. Do not deploy until the production-origin preflight matrix is verified from a network that can reach the production Supabase endpoint.
