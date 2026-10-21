#!/usr/bin/env node
/**
 * Obtain short-lived JWTs through the D'Lice username-based admin-login action,
 * then run the P0 suite in-process. Credentials/tokens are never printed.
 * Use only disposable staging usernames/passwords; never production credentials.
 */
const required = [
  "SUPABASE_URL", "SUPABASE_ANON_KEY", "STAGING_EDGE_FUNCTION_URL",
  "ALLOWED_PREVIEW_ORIGIN",
  "STAGING_TEST_OWNER_USERNAME", "STAGING_TEST_OWNER_PASSWORD",
  "STAGING_TEST_BRANCH_A_USERNAME", "STAGING_TEST_BRANCH_A_PASSWORD",
  "STAGING_TEST_NO_PERMISSION_USERNAME", "STAGING_TEST_NO_PERMISSION_PASSWORD",
  "STAGING_TEST_INACTIVE_USERNAME", "STAGING_TEST_INACTIVE_PASSWORD",
];
const missing = required.filter((key) => !process.env[key]);
if (missing.length) {
  console.error("BLOCKED: missing required staging test variables:", missing.join(", "));
  process.exit(2);
}
const edgeUrl = process.env.STAGING_EDGE_FUNCTION_URL;
async function tokenFor(label, username, password) {
  let response;
  try {
    response = await fetch(edgeUrl, {
      method: "POST",
      headers: {
        apikey: process.env.SUPABASE_ANON_KEY,
        "content-type": "application/json",
        origin: process.env.ALLOWED_PREVIEW_ORIGIN,
      },
      body: JSON.stringify({ action: "admin-login", username, password }),
    });
  } catch (error) {
    console.error(`BLOCKED: could not reach staging username login for ${label}; check staging network and Edge Function URL.`);
    process.exit(2);
  }
  const body = await response.json().catch(() => ({}));
  const token = body?.session?.access_token;
  if (!response.ok || typeof token !== "string") {
    console.error(`BLOCKED: could not obtain short-lived token for ${label}; username login returned HTTP ${response.status}. Check the disposable staging account, password, status, and role setup.`);
    process.exit(2);
  }
  return token;
}

process.env.TEST_OWNER_JWT = await tokenFor(
  "Owner",
  process.env.STAGING_TEST_OWNER_USERNAME,
  process.env.STAGING_TEST_OWNER_PASSWORD,
);
process.env.TEST_STAFF_JWT = await tokenFor(
  "Branch A manager",
  process.env.STAGING_TEST_BRANCH_A_USERNAME,
  process.env.STAGING_TEST_BRANCH_A_PASSWORD,
);
process.env.TEST_NO_PERMISSION_STAFF_JWT = await tokenFor(
  "no-permission staff",
  process.env.STAGING_TEST_NO_PERMISSION_USERNAME,
  process.env.STAGING_TEST_NO_PERMISSION_PASSWORD,
);
// The public username-login action correctly refuses inactive profiles. For this
// negative test only, mint a normal staging Auth token using the internal synthetic
// email mapping, then verify the Edge Function rejects the inactive profile.
async function tokenForInactiveProfile(username, password) {
  const base = process.env.SUPABASE_URL.replace(/\\/$/, "");
  const internalEmail = `${username.toLowerCase()}@accounts.dlice.internal`;
  let response;
  try {
    response = await fetch(`${base}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: {
        apikey: process.env.SUPABASE_ANON_KEY,
        "content-type": "application/json",
      },
      body: JSON.stringify({ email: internalEmail, password }),
    });
  } catch {
    console.error("BLOCKED: could not reach staging Auth for inactive-profile negative test.");
    process.exit(2);
  }
  const body = await response.json().catch(() => ({}));
  if (!response.ok || typeof body.access_token !== "string") {
    console.error(`BLOCKED: could not obtain staging Auth token for inactive-profile negative test; Auth returned HTTP ${response.status}.`);
    process.exit(2);
  }
  return body.access_token;
}
process.env.TEST_INACTIVE_STAFF_JWT = await tokenForInactiveProfile(
  process.env.STAGING_TEST_INACTIVE_USERNAME,
  process.env.STAGING_TEST_INACTIVE_PASSWORD,
);

// Keep bearer tokens in this process only; the test suite never prints them.
await import("./p0-http-smoke.mjs");
