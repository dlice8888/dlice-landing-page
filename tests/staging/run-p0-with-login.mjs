#!/usr/bin/env node
/**
 * Obtain short-lived JWTs from staging Supabase Auth using disposable-user credentials,
 * then run the P0 suite in-process. Credentials/tokens are never printed.
 * This is for CI only; do not pass production credentials.
 */
const required = [
  "SUPABASE_URL", "SUPABASE_ANON_KEY",
  "STAGING_TEST_OWNER_EMAIL", "STAGING_TEST_OWNER_PASSWORD",
  "STAGING_TEST_BRANCH_A_EMAIL", "STAGING_TEST_BRANCH_A_PASSWORD",
  "STAGING_TEST_NO_PERMISSION_EMAIL", "STAGING_TEST_NO_PERMISSION_PASSWORD",
  "STAGING_TEST_INACTIVE_EMAIL", "STAGING_TEST_INACTIVE_PASSWORD",
];
const missing = required.filter((key) => !process.env[key]);
if (missing.length) {
  console.error("BLOCKED: missing required staging credential variables:", missing.join(", "));
  process.exit(2);
}
const base = process.env.SUPABASE_URL.replace(/\/$/, "");
async function tokenFor(label, email, password) {
  const response = await fetch(`${base}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: {
      apikey: process.env.SUPABASE_ANON_KEY,
      "content-type": "application/json",
    },
    body: JSON.stringify({ email, password }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || typeof body.access_token !== "string") {
    console.error(`BLOCKED: could not obtain short-lived token for ${label}; Auth returned HTTP ${response.status}. Check the disposable staging identity and credentials.`);
    process.exit(2);
  }
  return body.access_token;
}

process.env.TEST_OWNER_JWT = await tokenFor(
  "Owner",
  process.env.STAGING_TEST_OWNER_EMAIL,
  process.env.STAGING_TEST_OWNER_PASSWORD,
);
process.env.TEST_STAFF_JWT = await tokenFor(
  "Branch A manager",
  process.env.STAGING_TEST_BRANCH_A_EMAIL,
  process.env.STAGING_TEST_BRANCH_A_PASSWORD,
);
process.env.TEST_NO_PERMISSION_STAFF_JWT = await tokenFor(
  "no-permission staff",
  process.env.STAGING_TEST_NO_PERMISSION_EMAIL,
  process.env.STAGING_TEST_NO_PERMISSION_PASSWORD,
);
process.env.TEST_INACTIVE_STAFF_JWT = await tokenFor(
  "inactive staff",
  process.env.STAGING_TEST_INACTIVE_EMAIL,
  process.env.STAGING_TEST_INACTIVE_PASSWORD,
);

// Keep the bearer tokens in this process only; the test suite never prints them.
await import("./p0-http-smoke.mjs");
