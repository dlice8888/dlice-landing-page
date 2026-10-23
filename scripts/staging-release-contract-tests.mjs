import fs from "node:fs";
import vm from "node:vm";

const fail = (message) => { console.error("FAIL:", message); process.exitCode = 1; };
const pass = (message) => console.log("PASS:", message);
const read = (file) => fs.readFileSync(file, "utf8");
const edge = read("supabase/functions/dlice-orders/index.ts");
const html = read("index.html");
const track = read("track.html");
const erp = read("erp.html");
const branchChecklistMigration = read("supabase/migrations/20261021182634_branch_operation_checklists.sql");
const retention = read("supabase/migrations/20261020171825_safe_operational_retention_and_rpc_acl.sql");

const checks = [
  ["transaction IDs use the agreed DLC date/sequence format", /DLC-\$\{part\("day"\)\}\/\$\{part\("month"\)\}\/\$\{part\("year"\)\}-\$\{String\(orderNumber\)\.padStart\(5,\s*"0"\)\}/.test(edge)],
  ["order tracking validates the DLC transaction-code shape", /DLC-\(\\d\{2\}\)\\\/\(\\d\{2\}\)\\\/\(\\d\{4\}\)-\(\\d\{5\}\)/.test(edge)],
  ["payment proof is stored in the private payment-proof bucket", /storage\.from\("dlice-payment-proofs"\)\.upload/.test(edge)],
  ["payment proof upload prevents overwriting existing objects", /storage\.from\("dlice-payment-proofs"\)\.upload\([\s\S]{0,300}?upsert:\s*false/.test(edge)],
  ["payment proof accepts only explicit image/PDF MIME types", /"image\/jpeg"[\s\S]{0,180}"application\/pdf"/.test(edge)],
  ["payment proof has a server-side encoded-size limit", /encoded\.length\s*>\s*7_000_000/.test(edge)],
  ["payment proof rejects malformed base64 payloads", edge.includes("const payload = encoded.replace") && edge.includes("payload.length > 7_000_000") && edge.includes("Data bukti pembayaran tidak valid.")],
  ["payment proof validates actual file signatures, not only claimed MIME", edge.includes("const signatureMatches") && edge.includes("asciiAt(0, \"RIFF\")") && edge.includes("asciiAt(0, \"%PDF-\")") && edge.includes("if (!signatureMatches[mime])")],
  ["payment proof rejects empty files before storage", /binary\.byteLength\s*===\s*0/.test(edge)],
  ["payment verification uses the atomic database RPC", /rpc\("admin_apply_payment_verification"/.test(edge)],
  ["operational status uses the atomic database RPC", /rpc\("admin_apply_operational_status_change"/.test(edge)],
  ["order creation has server-side rate limiting", /action === "create-order"[\s\S]{0,250}consumeRateLimit\("create-order"/.test(edge)],
  ["tracking has server-side rate limiting", /consumeRateLimit\("track-order-by-code"/.test(edge)],
  ["server computes authoritative order totals from product data", /unit_price_idr|line_total_idr/.test(edge) && /create-order/.test(edge)],
  ["multi-item checkout controls exist in the customer page", /quantity|cart|items/i.test(html) && /order_items|product_id|quantity/.test(edge)],
  ["tracking page includes order lookup and status display", /track|tracking|transaction_code/i.test(track)],
  ["retention only targets ephemeral rate limits and old aggregate metrics", /delete from public\.request_rate_limits[\s\S]*?updated_at < now\(\) - interval '30 days'[\s\S]*?delete from public\.funnel_daily_metrics[\s\S]*?metric_date < current_date - 730/.test(retention)],
  ["retention function preserves orders, payments, proofs, notifications and audit logs", /orders_payment_proofs_notifications_audit_logs', 'preserved'/.test(retention) && !/delete from public\.(orders|order_items|payment_records|notification_log|admin_audit_logs)/.test(retention)],
  ["cleanup RPC is not executable by public client roles", /revoke all on function public\.cleanup_operational_data\(\) from public, anon, authenticated;[\s\S]*?grant execute on function public\.cleanup_operational_data\(\) to service_role/.test(retention)],
  ["retention job is scheduled once daily", /cron\.schedule\([\s\S]*?'dlice-operational-retention'[\s\S]*?'17 3 \* \* \*'/.test(retention)],
  ["trigger helper is not a public callable API", /revoke all on function public\.set_updated_at\(\) from public, anon, authenticated/.test(retention)],
  ["branch checklist actions are explicitly permission-gated", /"erp-list-branch-checklists": "branches"[\s\S]*?"erp-start-branch-checklist": "branches"[\s\S]*?"erp-update-branch-checklist-item": "branches"[\s\S]*?"erp-complete-branch-checklist": "branches"/.test(edge)],
  ["branch checklist actions verify active branch assignment", /const checklistContext = async[\s\S]{0,500}branchAccess\(branchId\)/.test(edge) && /if \(!await branchAccess\(run\.branch_id\)\)/.test(edge)],
  ["branch checklist business date uses the branch timezone", /new Intl\.DateTimeFormat\("en-GB", \{[\s\S]{0,180}timeZone: branch\.timezone/.test(edge)],
  ["branch checklist item updates use optimistic concurrency", /eq\("id", runId\)\.eq\("version", run\.version\)/.test(edge)],
  ["critical checklist failures block completion", /criticalFailures = items\.filter\(\(item\) => item\.critical && item\.status !== "passed"\)/.test(edge) && /Checklist tertahan: semua item kritis/.test(edge)],
  ["branch checklist table denies direct client access", /ALTER TABLE public\.branch_operation_checklist_runs ENABLE ROW LEVEL SECURITY/i.test(branchChecklistMigration) && /AS RESTRICTIVE FOR ALL TO anon, authenticated\s+USING \(false\) WITH CHECK \(false\)/i.test(branchChecklistMigration) && /REVOKE ALL ON TABLE public\.branch_operation_checklist_runs FROM anon, authenticated/i.test(branchChecklistMigration)],
  ["ERP workspace exposes opening/closing checklist view", /id="operationsView"/.test(erp) && /startOpeningChecklist/.test(erp) && /startClosingChecklist/.test(erp) && /erp-complete-branch-checklist/.test(erp)],
];

for (const [label, ok] of checks) {
  if (ok) pass(label);
  else fail(label);
}

// Guard against accidental parse regressions in inline scripts while keeping
// this test dependency-free; full browser E2E remains a separate release gate.
for (const file of ["index.html", "admin.html", "track.html", "erp.html"]) {
  const source = read(file);
  for (const [i, match] of [...source.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)].entries()) {
    const attrs = match[1] || "";
    const body = match[2] || "";
    if (/\bsrc\s*=/.test(attrs) || !body.trim()) continue;
    try {
      if (/\btype\s*=\s*["']module["']/i.test(attrs)) {
        // Module syntax is checked by the existing quality-check script.
        if (!/\bimport\b/.test(body)) new vm.Script(body);
      } else new vm.Script(body, { filename: `${file}#${i + 1}` });
    } catch (error) {
      fail(`${file} inline script ${i + 1}: ${error.message}`);
    }
  }
}
if (process.exitCode) process.exit(process.exitCode);
console.log("Staging release contract checks completed. These checks do not replace browser E2E.");
