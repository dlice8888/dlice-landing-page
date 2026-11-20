// GitHub Actions OIDC -> short-lived Supabase sessions for two pre-existing staging users.
// This endpoint never creates users, memberships, tenants, roles, or branch assignments.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
import { createRemoteJWKSet, jwtVerify } from "https://esm.sh/jose@5.9.6";

const url = Deno.env.get("SUPABASE_URL") ?? "";
const secretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
const serviceKey = (secretKeys ? JSON.parse(secretKeys).default : Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")) ?? "";
const publishableKeys = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
const publicKey = (publishableKeys ? JSON.parse(publishableKeys).default : (Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY"))) ?? "";
const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const auth = createClient(url, publicKey, { auth: { persistSession: false, autoRefreshToken: false } });
const jwks = createRemoteJWKSet(new URL("https://token.actions.githubusercontent.com/.well-known/jwks"));
const expectedAudience = "dlice-staging-tenant-isolation";
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
});

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const origin = req.headers.get("origin");
  if (origin) return json({ error: "origin_not_allowed" }, 403);
  const authorization = req.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer (.+)$/i);
  if (!match) return json({ error: "github_oidc_token_required" }, 401);

  let body: { tenant?: string };
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }
  const slot = body.tenant;
  if (slot !== "A" && slot !== "B") return json({ error: "invalid_tenant_slot" }, 400);

  let claims: Record<string, unknown>;
  try {
    const verified = await jwtVerify(match[1], jwks, { issuer: "https://token.actions.githubusercontent.com", audience: expectedAudience });
    claims = verified.payload as Record<string, unknown>;
  } catch {
    return json({ error: "github_oidc_verification_failed" }, 401);
  }

  const exact = (claim: string, expected: string) => claims[claim] === expected;
  const required = {
    repository_id: Deno.env.get("GITHUB_REPOSITORY_ID") ?? "",
    repository_owner_id: Deno.env.get("GITHUB_OWNER_ID") ?? "",
    ref: "refs/heads/staging",
    workflow_ref: "dlice8888/dlice-landing-page/.github/workflows/staging-tenant-isolation-acceptance.yml@refs/heads/staging",
    environment: "staging",
  };
  if (!required.repository_id || !required.repository_owner_id ||
      !exact("repository", "dlice8888/dlice-landing-page") ||
      !exact("sub", "repo:dlice8888/dlice-landing-page:environment:staging") ||
      !exact("repository_id", required.repository_id) ||
      !exact("repository_owner_id", required.repository_owner_id) ||
      !exact("ref", required.ref) ||
      !exact("workflow_ref", required.workflow_ref) ||
      !exact("environment", required.environment) ||
      !exact("event_name", "workflow_dispatch") ||
      !/^\d+$/.test(String(claims.run_id ?? "")) ||
      !/^\d+$/.test(String(claims.run_attempt ?? "")) ||
      typeof claims.jti !== "string" || claims.jti.length < 8) {
    return json({ error: "github_workflow_identity_not_allowed" }, 403);
  }

  const userId = Deno.env.get(slot === "A" ? "STAGING_TENANT_A_USER_ID" : "STAGING_TENANT_B_USER_ID") ?? "";
  const otherId = Deno.env.get(slot === "A" ? "STAGING_TENANT_B_USER_ID" : "STAGING_TENANT_A_USER_ID") ?? "";
  const isUuid = (value: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
  if (!isUuid(userId) || !isUuid(otherId) || userId === otherId) return json({ error: "staging_identity_configuration_invalid" }, 503);

  const { data: userResult, error: userError } = await admin.auth.admin.getUserById(userId);
  const user = userResult?.user;
  if (userError || !user?.email || user.id !== userId || Boolean((user as unknown as { banned_until?: string | null }).banned_until)) {
    return json({ error: "staging_auth_identity_unavailable" }, 403);
  }
  const { data: profile, error: profileError } = await admin.from("admin_profiles")
    .select("is_active").eq("user_id", userId).maybeSingle();
  if (profileError || profile?.is_active !== true) return json({ error: "staging_identity_inactive" }, 403);
  const { data: memberships, error: membershipError } = await admin.from("tenant_memberships")
    .select("tenant_id,role,status").eq("user_id", userId).eq("status", "active");
  const activeTenantIds = new Set((memberships ?? []).map((membership) => membership.tenant_id));
  if (membershipError || !memberships?.length || activeTenantIds.size !== 1 ||
      memberships.some((membership) => membership.role !== "branch_manager" || !membership.tenant_id)) {
    return json({ error: "staging_tenant_membership_not_eligible" }, 403);
  }

  // Reserve this run/attempt/slot before issuing. Unique constraints make replay/concurrent
  // requests fail closed. The migration must be applied before enabling this endpoint.
  const { error: reserveError } = await admin.from("staging_machine_session_issuances").insert({
    github_run_id: String(claims.run_id),
    github_run_attempt: Number(claims.run_attempt),
    github_jti: String(claims.jti),
    tenant_slot: slot,
    auth_user_id: userId,
  });
  if (reserveError) return json({ error: "session_issuance_already_used_or_audit_unavailable" }, 409);

  const { data: link, error: linkError } = await admin.auth.admin.generateLink({
    type: "magiclink", email: user.email,
  });
  const tokenHash = link?.properties?.hashed_token;
  if (linkError || !tokenHash) return json({ error: "short_lived_session_creation_failed" }, 503);
  const { data: sessionData, error: sessionError } = await auth.auth.verifyOtp({
    token_hash: tokenHash, type: "magiclink",
  });
  if (sessionError || !sessionData.session || sessionData.user?.id !== userId) {
    return json({ error: "short_lived_session_exchange_failed" }, 503);
  }
  const expiresAt = sessionData.session.expires_at;
  const nowSeconds = Math.floor(Date.now() / 1000);
  if (typeof expiresAt !== "number" || !Number.isInteger(expiresAt) || expiresAt <= nowSeconds || expiresAt - nowSeconds > 3600) {
    return json({ error: "session_lifetime_out_of_policy" }, 503);
  }
  return json({
    session: {
      access_token: sessionData.session.access_token,
      expires_at: sessionData.session.expires_at,
      token_type: sessionData.session.token_type,
    },
    identity: { user_id: userId, tenant_slot: slot },
  });
});
