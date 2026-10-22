#!/usr/bin/env node
/**
 * Idempotently provision disposable QA identities in Supabase STAGING only.
 * Never logs passwords, access tokens, or the service-role key.
 */
import { createClient } from "@supabase/supabase-js";

const required = [
  "STAGING_SUPABASE_URL", "STAGING_SUPABASE_SERVICE_ROLE_KEY",
  "STAGING_TEST_BRANCH_A_USERNAME", "STAGING_TEST_BRANCH_A_PASSWORD",
  "STAGING_TEST_NO_PERMISSION_USERNAME", "STAGING_TEST_NO_PERMISSION_PASSWORD",
  "STAGING_TEST_INACTIVE_USERNAME", "STAGING_TEST_INACTIVE_PASSWORD",
];
const missing = required.filter((k) => !process.env[k]);
if (missing.length) {
  console.error("BLOCKED: staging QA bootstrap is missing required environment variables:", missing.join(", "));
  process.exit(2);
}
const url = process.env.STAGING_SUPABASE_URL.replace(/\/$/, "");
if (url !== "https://higoadrzxnhzbbwhdbmh.supabase.co") {
  console.error("BLOCKED: refusing to create QA identities outside the known D’Lice staging Supabase project.");
  process.exit(2);
}
const admin = createClient(url, process.env.STAGING_SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const specs = [
  { key: "BRANCH_A", username: process.env.STAGING_TEST_BRANCH_A_USERNAME, password: process.env.STAGING_TEST_BRANCH_A_PASSWORD, active: true, permissions: null, position: "branch_manager", branch: "DLC-B001", label: "Branch A Manager" },
  { key: "NO_PERMISSION", username: process.env.STAGING_TEST_NO_PERMISSION_USERNAME, password: process.env.STAGING_TEST_NO_PERMISSION_PASSWORD, active: true, permissions: [], position: "cashier", branch: "DLC-B001", label: "No-Permission Staff" },
  { key: "INACTIVE", username: process.env.STAGING_TEST_INACTIVE_USERNAME, password: process.env.STAGING_TEST_INACTIVE_PASSWORD, active: false, permissions: [], position: "cashier", branch: "DLC-B002", label: "Inactive Staff" },
];
const ownerUsername = (process.env.STAGING_TEST_OWNER_USERNAME || "").toLowerCase();
const seen = new Set();
for (const s of specs) {
  if (!/^[a-zA-Z0-9._-]{3,32}$/.test(s.username || "") || (s.password || "").length < 12 || (s.password || "").length > 128) {
    console.error(`BLOCKED: invalid username/password policy for ${s.label}; usernames must be 3–32 allowed characters and passwords 12–128 characters.`);
    process.exit(2);
  }
  const u = s.username.toLowerCase();
  if (u === ownerUsername || seen.has(u)) {
    console.error("BLOCKED: QA usernames must be unique and must not match the Owner test username.");
    process.exit(2);
  }
  seen.add(u);
}
const { data: profiles, error: profileReadError } = await admin.from("admin_profiles").select("user_id,role,username").eq("role", "owner");
if (profileReadError || !profiles?.length) {
  console.error("BLOCKED: could not identify an existing Owner profile for QA assignment audit fields.");
  process.exit(2);
}
const ownerId = profiles[0].user_id;
const { data: branches, error: branchesError } = await admin.from("branches").select("id,code").in("code", ["DLC-B001", "DLC-B002"]);
if (branchesError) throw new Error("Could not read staging QA branches.");
const branchIds = new Map((branches || []).map((b) => [b.code, b.id]));
if (!branchIds.has("DLC-B001") || !branchIds.has("DLC-B002")) {
  console.error("BLOCKED: expected staging test branches DLC-B001 and DLC-B002 are missing.");
  process.exit(2);
}
const { data: positions, error: positionsError } = await admin.from("job_positions").select("id,code").in("code", ["branch_manager", "cashier"]);
if (positionsError) throw new Error("Could not read staging job positions.");
const positionIds = new Map((positions || []).map((p) => [p.code, p.id]));
if (!positionIds.has("branch_manager") || !positionIds.has("cashier")) {
  console.error("BLOCKED: required staging job positions are missing.");
  process.exit(2);
}
async function findAuthUser(email) {
  for (let page = 1; page <= 20; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw new Error("Could not inspect staging Auth users.");
    const found = data.users.find((u) => (u.email || "").toLowerCase() === email);
    if (found) return found;
    if (data.users.length < 1000) return null;
  }
  throw new Error("Staging Auth user pagination limit reached.");
}
for (const s of specs) {
  const email = `${s.username.toLowerCase()}@accounts.dlice.internal`;
  let user = await findAuthUser(email);
  if (user) {
    const { data, error } = await admin.auth.admin.updateUserById(user.id, {
      password: s.password, email_confirm: true, ban_duration: "none",
    });
    if (error || !data.user) throw new Error(`Could not reconcile staging Auth account for ${s.label}.`);
    user = data.user;
  } else {
    const { data, error } = await admin.auth.admin.createUser({
      email, password: s.password, email_confirm: true,
    });
    if (error || !data.user) throw new Error(`Could not create staging Auth account for ${s.label}.`);
    user = data.user;
  }
  const { error: upsertError } = await admin.from("admin_profiles").upsert({
    user_id: user.id,
    username: s.username,
    role: "sales_admin",
    display_name: `STAGING QA — ${s.label}`,
    is_active: s.active,
    permissions: s.permissions,
    updated_at: new Date().toISOString(),
  }, { onConflict: "user_id" });
  if (upsertError) throw new Error(`Could not configure staging profile for ${s.label}.`);
  const branchId = branchIds.get(s.branch);
  const jobPositionId = positionIds.get(s.position);
  const { error: assignmentError } = await admin.from("branch_assignments").upsert({
    branch_id: branchId,
    user_id: user.id,
    job_position_id: jobPositionId,
    employment_status: s.active ? "active" : "inactive",
    starts_on: new Date().toISOString().slice(0, 10),
    ends_on: null,
    assigned_by: ownerId,
    updated_at: new Date().toISOString(),
  }, { onConflict: "branch_id,user_id,job_position_id" });
  if (assignmentError) throw new Error(`Could not configure branch assignment for ${s.label}.`);
  console.log(`PASS QA_ACCOUNT_CONFIGURED: ${s.label}; active=${s.active}; branch=${s.branch}; permissions=${s.permissions === null ? "position defaults" : s.permissions.length ? "explicit limited" : "none"}`);
}
console.log("PASS STAGING_QA_ACCOUNT_BOOTSTRAP: 3 accounts reconciled; no credentials printed.");
