import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";

const fail = (message) => { console.error("FAIL:", message); process.exitCode = 1; };
const pass = (message) => console.log("PASS:", message);
const read = (file) => fs.readFileSync(file, "utf8");

for (const file of ["index.html", "admin.html", "track.html"]) {
  if (!fs.existsSync(file)) { fail(`Missing ${file}`); continue; }
  const html = read(file);
  if (!html.toLowerCase().includes("<!doctype html")) fail(`${file}: missing doctype`);
  const scripts = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)];
  for (let i = 0; i < scripts.length; i++) {
    const attrs = scripts[i][1] || "";
    const body = scripts[i][2] || "";
    if (/\bsrc\s*=/.test(attrs) || !body.trim()) continue;
    try { new vm.Script(body, { filename: `${file}#inline-script-${i + 1}` }); }
    catch (error) { fail(`${file} inline script ${i + 1}: ${error.message}`); }
  }
  pass(`${file}: HTML and inline JavaScript syntax checked`);
}

for (const file of ["assets/js/funnel-analytics.js"]) {
  try { new vm.Script(read(file), { filename: file }); pass(`${file}: JavaScript syntax checked`); }
  catch (error) { fail(`${file}: ${error.message}`); }
}

try {
  const config = JSON.parse(read("vercel.json"));
  if (!Array.isArray(config.headers) || !config.headers.length) fail("vercel.json has no security headers");
  else pass("vercel.json parses and includes security headers");
} catch (error) { fail(`vercel.json: ${error.message}`); }

const edge = read("supabase/functions/dlice-orders/index.ts");
for (const [label, pattern] of [
  ["no hard-coded production Supabase URL fallback", /const SUPABASE_URL = Deno\.env\.get\("SUPABASE_URL"\);/],
  ["server-side admin login action", /action === "admin-login"/],
  ["tracking rate limit", /consumeRateLimit\("track-order-by-code"/],
  ["database-backed rate limit RPC", /admin\.rpc\("consume_rate_limit"/],
  ["privacy-preserving funnel event action", /action === "record-funnel-event"/],
]) {
  if (pattern.test(edge)) pass(label); else fail(label);
}
if (/service_role\s*[:=]\s*["'][^"']+["']/i.test(edge)) fail("possible hard-coded service-role credential");
else pass("no obvious hard-coded service-role credential pattern");

for (const file of [
  "supabase/migrations/20261020090000_add_free_rate_limiting.sql",
  "supabase/migrations/20261020093000_add_privacy_preserving_funnel_metrics.sql"
]) {
  try {
    const sql = read(file);
    if (!/enable row level security/i.test(sql)) fail(`${file}: RLS not enabled`);
    if (!/revoke all.*anon.*authenticated/is.test(sql)) fail(`${file}: public role revocation missing`);
    pass(`${file}: migration safety markers checked`);
  } catch (error) { fail(`${file}: ${error.message}`); }
}

if (process.exitCode) process.exit(process.exitCode);
console.log("Quality checks completed.");
