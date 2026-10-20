import fs from "node:fs";
import vm from "node:vm";

const fail = (message) => { console.error("FAIL:", message); process.exitCode = 1; };
const pass = (message) => console.log("PASS:", message);
const read = (file) => fs.readFileSync(file, "utf8");
const edge = read("supabase/functions/dlice-orders/index.ts");
const html = read("index.html");
const track = read("track.html");

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
];

for (const [label, ok] of checks) {
  if (ok) pass(label);
  else fail(label);
}

// Guard against accidental parse regressions in inline scripts while keeping
// this test dependency-free; full browser E2E remains a separate release gate.
for (const file of ["index.html", "admin.html", "track.html"]) {
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
