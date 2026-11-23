// Trusted staging-only passwordless authentication for existing Supabase Auth identities.
// This helper never creates users, resets passwords, or logs emails, magic-link hashes, or sessions.
import { isServiceRoleKey, serviceRoleHeaders } from "./supabase-api-key.mjs";

function isUuid(value) {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function adminHeaders(serviceRoleKey) {
  if (!isServiceRoleKey(serviceRoleKey)) {
    throw new TypeError("STAGING_SUPABASE_SERVICE_ROLE_KEY is not a supported service-role key");
  }
  return {
    ...serviceRoleHeaders(serviceRoleKey),
    "content-type": "application/json",
  };
}

export async function findActiveOwnerUserId({ baseUrl, serviceRoleKey }) {
  const base = String(baseUrl || "").replace(/\/$/, "");
  const url = new URL(base);
  if (url.protocol !== "https:" || url.hostname !== "higoadrzxnhzbbwhdbmh.supabase.co") {
    throw new Error("staging_target_mismatch");
  }
  const query = new URLSearchParams({
    select: "user_id",
    role: "eq.owner",
    is_active: "eq.true",
    limit: "2",
  });
  const response = await fetch(`${base}/rest/v1/admin_profiles?${query}`, {
    method: "GET",
    headers: { ...adminHeaders(serviceRoleKey), accept: "application/json" },
    redirect: "manual",
  });
  const profiles = await response.json().catch(() => null);
  if (!response.ok || !Array.isArray(profiles) || profiles.length !== 1 ||
      !isUuid(profiles[0]?.user_id)) {
    throw new Error("active_owner_profile_lookup_failed");
  }
  return profiles[0].user_id;
}

export async function tokenForExistingUser({ baseUrl, publicKey, serviceRoleKey, userId }) {
  const base = String(baseUrl || "").replace(/\/$/, "");
  const url = new URL(base);
  if (url.protocol !== "https:" || url.hostname !== "higoadrzxnhzbbwhdbmh.supabase.co") {
    throw new Error("staging_target_mismatch");
  }
  if (!isUuid(userId)) throw new Error("existing_auth_user_id_invalid");
  if (typeof publicKey !== "string" || !publicKey.trim() || publicKey.startsWith("sb_secret_")) {
    throw new Error("public_supabase_key_invalid");
  }

  const headers = adminHeaders(serviceRoleKey);
  const userResponse = await fetch(`${base}/auth/v1/admin/users/${encodeURIComponent(userId)}`, {
    method: "GET",
    headers,
    redirect: "manual",
  });
  const user = await userResponse.json().catch(() => ({}));
  if (!userResponse.ok || user.id !== userId ||
      typeof user.email !== "string" || !user.email_confirmed_at) {
    throw new Error("existing_auth_user_not_found_or_unconfirmed");
  }

  const linkResponse = await fetch(`${base}/auth/v1/admin/generate_link`, {
    method: "POST",
    headers,
    body: JSON.stringify({ type: "magiclink", email: user.email }),
    redirect: "manual",
  });
  const link = await linkResponse.json().catch(() => ({}));
  const tokenHash = link.properties?.hashed_token ?? link.hashed_token;
  if (!linkResponse.ok || typeof tokenHash !== "string" || tokenHash.length < 20) {
    throw new Error("existing_auth_magic_link_generation_failed");
  }

  const verifyResponse = await fetch(`${base}/auth/v1/verify`, {
    method: "POST",
    headers: { apikey: publicKey, "content-type": "application/json" },
    body: JSON.stringify({ type: "magiclink", token_hash: tokenHash }),
    redirect: "manual",
  });
  const session = await verifyResponse.json().catch(() => ({}));
  if (!verifyResponse.ok || session.user?.id !== userId ||
      typeof session.access_token !== "string" || session.access_token.split(".").length !== 3) {
    throw new Error("existing_auth_magic_link_verification_failed");
  }
  return { accessToken: session.access_token, userId };
}

export async function revokeLocalSession({ baseUrl, publicKey, accessToken }) {
  if (typeof accessToken !== "string" || accessToken.split(".").length !== 3) return false;
  const base = String(baseUrl || "").replace(/\/$/, "");
  const url = new URL(base);
  if (url.protocol !== "https:" || url.hostname !== "higoadrzxnhzbbwhdbmh.supabase.co") {
    throw new Error("staging_target_mismatch");
  }
  const response = await fetch(`${base}/auth/v1/logout?scope=local`, {
    method: "POST",
    headers: {
      apikey: publicKey,
      authorization: `Bearer ${accessToken}`,
    },
    redirect: "manual",
  });
  return response.status === 204 || response.ok;
}
