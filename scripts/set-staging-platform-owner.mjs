#!/usr/bin/env node
/**
 * One-time, staging-only repair for the existing Platform Owner Auth claim.
 * Uses the official Supabase Auth Admin REST API. Never use SQL for auth.users.
 */
import { pathToFileURL } from "node:url";

export const STAGING_PROJECT_REF = "higoadrzxnhzbbwhdbmh";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function fail(code, message) {
  const error = new Error(message);
  error.code = code;
  throw error;
}

function safeObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

async function readAuthUser(response, operation) {
  if (!response.ok) fail("OWNER_AUTH_ADMIN_HTTP_ERROR", `${operation} failed (HTTP ${response.status})`);
  const payload = await response.json();
  const user = payload?.user ?? payload;
  if (!user || typeof user.id !== "string") fail("OWNER_AUTH_ADMIN_RESPONSE_INVALID", `${operation} returned no Auth user`);
  return user;
}

export async function setStagingPlatformOwnerClaim({ supabaseUrl, serviceRoleKey, ownerUserId, fetchImpl = globalThis.fetch }) {
  if (!supabaseUrl || !serviceRoleKey || typeof fetchImpl !== "function") fail("OWNER_AUTH_ADMIN_CONFIG_REQUIRED", "Staging URL, service-role key and fetch are required");
  if (!UUID_RE.test(ownerUserId ?? "")) fail("OWNER_AUTH_ADMIN_UUID_INVALID", "A verified existing Owner UUID is required");

  let url;
  try { url = new URL(supabaseUrl); } catch { fail("OWNER_AUTH_ADMIN_URL_INVALID", "Staging Supabase URL is invalid"); }
  if (url.protocol !== "https:" || url.hostname !== `${STAGING_PROJECT_REF}.supabase.co` || url.pathname !== "/") {
    fail("OWNER_AUTH_ADMIN_STAGING_ONLY", "Refusing to modify any project other than the approved D'Lice staging project");
  }

  const endpoint = `${url.origin}/auth/v1/admin/users/${encodeURIComponent(ownerUserId)}`;
  const headers = { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}`, "Content-Type": "application/json" };
  const before = await readAuthUser(await fetchImpl(endpoint, { method: "GET", headers }), "Owner lookup");
  if (before.id !== ownerUserId) fail("OWNER_AUTH_ADMIN_IDENTITY_MISMATCH", "Auth user UUID did not match the verified Owner UUID");
  if (before.banned_until && Date.parse(before.banned_until) > Date.now()) fail("OWNER_AUTH_ADMIN_USER_BANNED", "Existing Owner Auth user is currently banned; no change was made");

  // Verify the same existing identity is an active Owner in the staging application database.
  const profileUrl = new URL("/rest/v1/admin_profiles", url.origin);
  profileUrl.searchParams.set("select", "user_id,role,is_active");
  profileUrl.searchParams.set("user_id", `eq.${ownerUserId}`);
  const profileResponse = await fetchImpl(profileUrl.toString(), { method: "GET", headers });
  if (!profileResponse.ok) fail("OWNER_AUTH_ADMIN_PROFILE_LOOKUP_FAILED", `Owner profile lookup failed (HTTP ${profileResponse.status})`);
  const profiles = await profileResponse.json();
  const profile = Array.isArray(profiles) ? profiles.find((row) => row?.user_id === ownerUserId) : null;
  if (!profile || profile.role !== "owner" || profile.is_active !== true) {
    fail("OWNER_AUTH_ADMIN_PROFILE_NOT_ACTIVE_OWNER", "The existing Auth identity is not an active owner profile; no metadata change was made");
  }

  const previousMetadata = safeObject(before.app_metadata);
  const nextMetadata = { ...previousMetadata, platform_owner: true };
  const updateResponse = await fetchImpl(endpoint, { method: "PUT", headers, body: JSON.stringify({ app_metadata: nextMetadata }) });
  await readAuthUser(updateResponse, "Owner metadata update");

  // Independently GET the persisted value; do not trust only the PUT response.
  const verified = await readAuthUser(await fetchImpl(endpoint, { method: "GET", headers }), "Owner metadata verification");
  if (verified.id !== ownerUserId || verified.app_metadata?.platform_owner !== true) {
    fail("OWNER_AUTH_ADMIN_VERIFY_FAILED", "Owner metadata did not verify after update");
  }

  return Object.freeze({
    projectRef: STAGING_PROJECT_REF,
    userId: ownerUserId,
    platformOwnerBoolean: true,
    preservedMetadataKeys: Object.keys(previousMetadata).sort(),
    updated: true,
  });
}

async function main() {
  const args = process.argv.slice(2);
  const ownerUserId = args[0] === "--confirm-staging-owner-uuid" ? args[1] : null;
  if (!ownerUserId || args.length !== 2) {
    console.error("Usage: STAGING_SUPABASE_URL=... STAGING_SUPABASE_SERVICE_ROLE_KEY=... node scripts/set-staging-platform-owner.mjs --confirm-staging-owner-uuid <verified-existing-owner-uuid>");
    process.exitCode = 2;
    return;
  }
  try {
    const result = await setStagingPlatformOwnerClaim({
      supabaseUrl: process.env.STAGING_SUPABASE_URL,
      serviceRoleKey: process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY,
      ownerUserId,
    });
    console.log(JSON.stringify(result, null, 2));
  } catch (error) {
    console.error(`Owner Auth repair failed: ${error.code ?? "UNKNOWN"} — ${error.message}`);
    process.exitCode = 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
