import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const secretKeysRaw = Deno.env.get("SUPABASE_SECRET_KEYS");
const SERVICE_KEY = secretKeysRaw ? JSON.parse(secretKeysRaw)["default"] : Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const signatureHeader = (Deno.env.get("DLICE_PAYROLL_SIGNATURE_HEADER") ?? "x-dlice-signature").toLowerCase();
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
});
const hex = (bytes: Uint8Array) => [...bytes].map((value) => value.toString(16).padStart(2, "0")).join("");
const constantTimeEqual = (a: string, b: string) => {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return mismatch === 0;
};
const sha256 = async (value: string) => hex(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))));
const hmacSha256 = async (secret: string, raw: string) => {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return hex(new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(raw))));
};

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!SUPABASE_URL || !SERVICE_KEY) return json({ error: "Server configuration unavailable" }, 500);
  const length = Number(req.headers.get("content-length") ?? "0");
  if (length > 65536) return json({ error: "Payload too large" }, 413);
  const raw = await req.text();
  if (!raw || new TextEncoder().encode(raw).length > 65536) return json({ error: "Payload too large or empty" }, 413);
  const signature = (req.headers.get(signatureHeader) ?? "").trim().replace(/^sha256=/i, "").toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(signature)) return json({ error: "Invalid provider signature" }, 401);

  let event: Record<string, unknown>;
  try { event = JSON.parse(raw); } catch { return json({ error: "Invalid JSON body" }, 400); }
  const tenantId = String(event.tenant_id ?? "");
  const batchId = String(event.payment_batch_id ?? "");
  const itemId = String(event.payment_item_id ?? "");
  const eventId = String(event.provider_event_id ?? "").trim();
  const eventKind = String(event.event_kind ?? "");
  const amount = Number(event.amount_idr);
  const occurredAt = String(event.occurred_at ?? "");
  const providerReference = event.provider_reference == null ? null : String(event.provider_reference);
  if (!/^[0-9a-f-]{36}$/i.test(tenantId) || !/^[0-9a-f-]{36}$/i.test(batchId) ||
      !/^[0-9a-f-]{36}$/i.test(itemId) || !eventId || eventId.length > 180 ||
      !["accepted", "settled", "failed", "reversed"].includes(eventKind) ||
      !Number.isSafeInteger(amount) || amount <= 0 || Number.isNaN(Date.parse(occurredAt)) ||
      (eventKind === "settled" && !providerReference)) {
    return json({ error: "Invalid provider event fields" }, 422);
  }

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: batch, error: batchError } = await admin.from("hr_payroll_payment_batches")
    .select("id,tenant_id,provider_config_id,status")
    .eq("id", batchId).eq("tenant_id", tenantId).maybeSingle();
  if (batchError || !batch || !["approved", "processing"].includes(batch.status)) return json({ error: "Payment batch not found or not approved" }, 404);
  const { data: provider, error: providerError } = await admin.from("hr_payroll_payment_provider_configs")
    .select("id,provider_id,credential_secret_reference,status")
    .eq("id", batch.provider_config_id).eq("tenant_id", tenantId).eq("status", "active").maybeSingle();
  if (providerError || !provider) return json({ error: "Approved provider configuration unavailable" }, 409);
  if (event.provider_id != null && String(event.provider_id) !== provider.provider_id) return json({ error: "Provider identity mismatch" }, 403);
  const secretValue = Deno.env.get(provider.credential_secret_reference);
  if (!secretValue) return json({ error: "Provider webhook secret unavailable" }, 503);
  let secret = secretValue;
  try {
    const credentials = JSON.parse(secretValue);
    if (typeof credentials.webhook_secret === "string") secret = credentials.webhook_secret;
  } catch { /* Plain HMAC secret is also supported. */ }
  if (secret.length < 32) return json({ error: "Provider webhook secret unavailable" }, 503);
  const expected = await hmacSha256(secret, raw);
  if (!constantTimeEqual(signature, expected)) return json({ error: "Provider signature verification failed" }, 401);

  const payloadHash = await sha256(raw);
  const { data, error } = await admin.rpc("hr_apply_payroll_provider_event", {
    p_tenant_id: tenantId,
    p_payment_batch_id: batchId,
    p_payment_item_id: itemId,
    p_provider_event_id: eventId,
    p_event_kind: eventKind,
    p_amount_idr: amount,
    p_provider_reference: providerReference,
    p_payload_sha256: payloadHash,
    p_occurred_at: new Date(occurredAt).toISOString(),
    p_signature_verified: true,
    p_actor_user_id: null,
  });
  if (error) {
    const code = error.code === "23505" ? 409 : error.code === "42501" ? 403 : 422;
    return json({ error: "Provider event was not accepted", code: error.message }, code);
  }
  return json({ ok: true, provider_event: data }, 200);
});
