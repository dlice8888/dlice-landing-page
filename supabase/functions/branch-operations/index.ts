import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
import { createBranchOperationsRepository } from "../_shared/branch-operations-repository.ts";

const URL = Deno.env.get("SUPABASE_URL") ?? "";
const publishableKeysRaw = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
const secretKeysRaw = Deno.env.get("SUPABASE_SECRET_KEYS");
const PUBLIC_KEY = publishableKeysRaw ? JSON.parse(publishableKeysRaw)["default"] : Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE_KEY = secretKeysRaw ? JSON.parse(secretKeysRaw)["default"] : Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const allowedOrigins = new Set((Deno.env.get("DLICE_ALLOWED_ORIGINS") ?? "").split(",").map(v => v.trim()).filter(Boolean));
const cors = (origin: string | null) => ({
  ...(origin && allowedOrigins.has(origin) ? { "Access-Control-Allow-Origin": origin } : {}),
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
});
const reply = (body: unknown, status: number, origin: string | null) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors(origin), "Content-Type": "application/json", "Cache-Control": "no-store" } });
const safe = (v: unknown, max = 200) => typeof v === "string" ? v.trim().slice(0, max) : "";
const fail = (message: string, status: number, origin: string | null) => reply({ error: message }, status, origin);
const idempotency = (v: unknown) => {
  const value = safe(v, 120);
  if (!/^[A-Za-z0-9._:-]{8,120}$/.test(value)) throw new Error("idempotencyKey invalid");
  return value;
};

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (req.method === "OPTIONS") {
    if (origin && !allowedOrigins.has(origin)) return fail("Origin tidak diizinkan.", 403, origin);
    return new Response("ok", { headers: cors(origin) });
  }
  if (req.method !== "POST") return fail("Metode tidak didukung.", 405, origin);
  if (origin && !allowedOrigins.has(origin)) return fail("Origin tidak diizinkan.", 403, origin);
  if (!URL || !PUBLIC_KEY || !SERVICE_KEY) return fail("Konfigurasi server tidak lengkap.", 500, origin);

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token || token === authHeader) return fail("Sesi tidak valid.", 401, origin);
  const authClient = createClient(URL, PUBLIC_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await authClient.auth.getUser(token);
  if (authError || !authData.user) return fail("Sesi tidak valid.", 401, origin);
  const actorId = authData.user.id;
  const service = createClient(URL, SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

  let body: Record<string, unknown> = {};
  let uploadFile: File | null = null;
  let isMultipart = false;
  const requestBytes = Number(req.headers.get("content-length") ?? "0");
  if (requestBytes > 8 * 1024 * 1024 + 64 * 1024) return fail("Payload terlalu besar.", 413, origin);
  try {
    const contentType = req.headers.get("content-type") ?? "";
    if (contentType.includes("multipart/form-data")) {
      isMultipart = true;
      const form = await req.formData();
      body = Object.fromEntries([...form.entries()].filter(([, value]) => typeof value === "string")) as Record<string, unknown>;
      const file = form.get("file");
      if (file instanceof File) uploadFile = file;
    } else {
      const length = Number(req.headers.get("content-length") ?? "0");
      if (length > 128_000) return fail("Payload terlalu besar.", 413, origin);
      body = await req.json();
    }
  } catch { return fail("Format permintaan tidak valid.", 400, origin); }

  const tenantId = safe(body.tenant_id, 80);
  const branchId = safe(body.branch_id, 80);
  const action = safe(body.action, 40);
  if (!tenantId || !branchId) return fail("Tenant dan cabang wajib dipilih.", 422, origin);

  const { data: profile, error: profileError } = await service.from("admin_profiles")
    .select("role,is_active").eq("user_id", actorId).maybeSingle();
  if (profileError || !profile?.is_active) return fail("Akun operasional tidak aktif.", 403, origin);
  const { data: membership, error: membershipError } = await service.from("tenant_memberships")
    .select("tenant_id,role,permissions,status").eq("tenant_id", tenantId).eq("user_id", actorId).eq("status", "active").maybeSingle();
  if (membershipError || !membership) return fail("Keanggotaan tenant tidak aktif.", 403, origin);
  const { data: branch, error: branchError } = await service.from("branches")
    .select("id,tenant_id,status").eq("id", branchId).eq("tenant_id", tenantId).maybeSingle();
  if (branchError || !branch || branch.status !== "active") return fail("Cabang tidak valid atau tidak aktif.", 404, origin);
  const { data: assignment, error: assignmentError } = await service.from("branch_assignments")
    .select("id").eq("branch_id", branchId).eq("user_id", actorId).eq("employment_status", "active")
    .or("ends_on.is.null,ends_on.gte." + new Date().toISOString().slice(0, 10)).maybeSingle();
  const tenantAdmin = ["tenant_owner", "tenant_admin"].includes(String(membership.role));
  const branchManager = ["branch_manager", "manager"].includes(String(membership.role));
  const grants = Array.isArray(membership.permissions) ? membership.permissions : [];
  const permitted = tenantAdmin || (!!assignment && (branchManager || grants.includes("*") || grants.includes("branch_operations") || grants.includes("branch_operations_approve") || grants.includes("branches") || grants.includes("operations")));
  if (assignmentError || !permitted) return fail("Akses Branch Operations tidak diizinkan.", 403, origin);

  const repo = createBranchOperationsRepository(service, { tenantId, branchId, actorId });
  try {
    if (action === "upload-evidence" && isMultipart && uploadFile) {
      const purpose = safe(body.purpose, 40);
      if (!["branch_incident", "branch_compliance", "branch_maintenance"].includes(purpose)) return fail("Tujuan bukti tidak valid.", 422, origin);
      const allowedMime = new Set(["image/jpeg", "image/png", "application/pdf"]);
      if (!allowedMime.has(uploadFile.type) || uploadFile.size < 1 || uploadFile.size > 8 * 1024 * 1024) return fail("File harus JPG, PNG, atau PDF maksimal 8 MB.", 422, origin);
      const header = new Uint8Array(await uploadFile.slice(0, 8).arrayBuffer());
      const isJpeg = header[0] === 0xff && header[1] === 0xd8 && header[2] === 0xff;
      const isPng = header.length === 8 && header[0] === 0x89 && header[1] === 0x50 && header[2] === 0x4e && header[3] === 0x47 && header[4] === 0x0d && header[5] === 0x0a && header[6] === 0x1a && header[7] === 0x0a;
      const isPdf = new TextDecoder().decode(header.slice(0, 5)) === "%PDF-";
      if (!(uploadFile.type === "image/jpeg" && isJpeg) && !(uploadFile.type === "image/png" && isPng) && !(uploadFile.type === "application/pdf" && isPdf)) return fail("Isi file tidak sesuai dengan MIME type.", 422, origin);
      const extension = uploadFile.type === "image/jpeg" ? "jpg" : uploadFile.type === "image/png" ? "png" : "pdf";
      const path = `${tenantId}/${branchId}/${actorId}/${crypto.randomUUID()}.${extension}`;
      // Upload only after server-side Auth + tenant membership + branch assignment checks.
      // The bucket has no anon/authenticated Storage policies and is never public.
      const { error: uploadError } = await service.storage.from("branch-ops-evidence").upload(path, uploadFile, { contentType: uploadFile.type, upsert: false });
      if (uploadError) return fail("Upload bukti ditolak oleh kebijakan Storage.", 403, origin);
      const registered = await repo.registerEvidenceAsset({ objectPath: path, purpose, mimeType: uploadFile.type, sizeBytes: uploadFile.size });
      return reply({ ok: true, evidence_asset_id: registered, object_path: path }, 201, origin);
    }
    if (action === "create-task") {
      const result = await repo.createTask({
        assigneeId: safe(body.assignee_id, 80), idempotencyKey: idempotency(body.idempotency_key),
        title: safe(body.title, 200), description: safe(body.description, 4000) || null,
        dueAt: safe(body.due_at, 80), priority: safe(body.priority, 20) || "normal",
        sourceType: safe(body.source_type, 40) || "manual", sourceId: safe(body.source_id, 80) || null,
      });
      return reply(result, 200, origin);
    }
    if (action === "record-incident") {
      const result = await repo.recordIncident({
        idempotencyKey: idempotency(body.idempotency_key), category: safe(body.category, 80),
        description: safe(body.description, 4000), severity: safe(body.severity, 20),
        occurredAt: safe(body.occurred_at, 80) || null,
        evidenceAssetIds: Array.isArray(body.evidence_asset_ids) ? body.evidence_asset_ids.map(v => safe(v, 80)) : [],
      });
      return reply(result, 200, origin);
    }
    if (action === "create-maintenance-order") {
      const result = await repo.createMaintenanceOrder({
        equipmentId: safe(body.equipment_id, 80), idempotencyKey: idempotency(body.idempotency_key),
        maintenanceType: safe(body.maintenance_type, 30), scheduledAt: safe(body.scheduled_at, 80),
        description: safe(body.description, 4000), assignedTo: safe(body.assigned_to, 80) || null,
      });
      return reply(result, 200, origin);
    }
    if (action === "publish-compliance") {
      const result = await repo.publishComplianceSnapshot({
        periodStart: safe(body.period_start, 10), periodEnd: safe(body.period_end, 10),
        idempotencyKey: idempotency(body.idempotency_key), sourceRevision: safe(body.source_revision, 160),
      });
      return reply(result, 200, origin);
    }
    if (action === "submit-compliance-check") {
      const result = await repo.submitComplianceCheck({
        checkKey: safe(body.check_key, 100), title: safe(body.title, 200),
        weight: Number(body.weight), businessDate: safe(body.business_date, 10),
        evidenceAssetId: safe(body.evidence_asset_id, 80),
      });
      return reply(result, 201, origin);
    }
    if (action === "review-compliance-check") {
      const result = await repo.reviewComplianceCheck({
        checkId: safe(body.check_id, 80), result: safe(body.result, 30),
      });
      return reply(result, 200, origin);
    }
    if (action === "list") {
      const kind = safe(body.kind, 30);
      return reply({ items: await repo.list(kind) }, 200, origin);
    }
    return fail("Aksi tidak dikenal.", 400, origin);
  } catch (error) {
    const code = (error as any)?.code;
    const status = code === "42501" ? 403 : code === "23505" ? 409 : 422;
    return fail(safe((error as Error)?.message, 200) || "Workflow gagal diproses.", status, origin);
  }
});
