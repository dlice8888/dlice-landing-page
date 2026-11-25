import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
import {
  hasTenantScopedHeadOfficePermission,
  isTenantSensitiveAction,
  resolveTenantScopedBranchIds,
  resolveTenantScopedPermissions,
} from "./tenant-permissions.ts";
import { checkPwnedPassword } from "./password-security.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const secretKeysRaw = Deno.env.get("SUPABASE_SECRET_KEYS");
const SERVICE_KEY = secretKeysRaw ? JSON.parse(secretKeysRaw)["default"] : Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const publishableKeysRaw = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
const PUBLIC_KEY = publishableKeysRaw ? JSON.parse(publishableKeysRaw)["default"] : Deno.env.get("SUPABASE_ANON_KEY");
const admin = createClient(SUPABASE_URL ?? "", SERVICE_KEY ?? "", { auth: { persistSession: false } });
const authClient = createClient(SUPABASE_URL ?? "", PUBLIC_KEY ?? "", { auth: { persistSession: false } });

const configuredOrigins = new Set(
  (Deno.env.get("DLICE_ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => /^https:\/\/[a-z0-9.-]+(?::\d+)?$/.test(value)),
);
// Origin access is driven exclusively by DLICE_ALLOWED_ORIGINS; no source-code bypass.
// Keep exact matching only. Production and staging use the same fail-closed parser.
const isAllowedOrigin = (origin: string | null) => {
  if (!origin) return true;
  return configuredOrigins.has(origin);
};
const corsHeaders = (origin: string | null) => ({
  // Never emit a fallback ACAO header for a missing or denied origin.
  ...(origin && isAllowedOrigin(origin) ? { "Access-Control-Allow-Origin": origin } : {}),
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-requested-with",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
});
const json = (body: unknown, status = 200, origin: string | null = null) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders(origin), "Content-Type": "application/json", "Cache-Control": "no-store" } });
const fail = (message: string, status = 400, origin: string | null = null) => json({ error: message }, status, origin);
const sha256 = async (value: string) => {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((v) => v.toString(16).padStart(2, "0")).join("");
};
const checkNewPassword = async (password: string, origin: string | null): Promise<Response | null> => {
  const result = await checkPwnedPassword(password);
  if (result === "compromised") return fail("Kata sandi ini terdeteksi dalam daftar kebocoran. Gunakan kata sandi baru yang unik.", 422, origin);
  if (result === "unavailable") return fail("Pemeriksaan keamanan kata sandi sementara tidak tersedia. Tidak ada perubahan akun yang dilakukan; coba lagi nanti.", 503, origin);
  return null;
};
const usernameEmail = (username: string) => `${username.toLowerCase()}@accounts.dlice.internal`;
const validUsername = (username: string) => /^[a-zA-Z0-9._-]{3,32}$/.test(username);
const randomToken = () => {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return [...bytes].map((v) => v.toString(16).padStart(2, "0")).join("");
};
const normPhone = (value: string) => value.replace(/[^0-9]/g, "").replace(/^0/, "62");
const safeText = (value: unknown, max: number) => typeof value === "string" ? value.trim().slice(0, max) : "";
const todayDate = () => new Date().toISOString().slice(0, 10);
const SUPPORTED_BRANCH_TIMEZONES = new Set(["Asia/Jakarta", "Asia/Makassar", "Asia/Jayapura"]);
// Fail closed: tenant-aware catalog, finance, reporting and audit isolation has not passed negative E2E.
// Do not enable until cross-tenant read/write denial tests pass for every tenant-scoped action.
const TENANT_ISOLATION_RELEASED = false;
// Platform-owner bypass requires two independent server-controlled sources: the UUID allowlist and Supabase Auth app_metadata.platform_owner=true.
// Never use user_metadata for authorization. If either source is absent or mismatched, fail closed.
const PLATFORM_OWNER_USER_IDS = new Set(
  (Deno.env.get("DLICE_PLATFORM_OWNER_USER_IDS") ?? "").split(",").map((value) => value.trim()).filter((value) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)),
);
// Legacy actions whose data model/query paths are not yet certified tenant-scoped.
// Keep non-platform-owner access closed until each action has a passing negative test.
const TENANT_SCOPE_UNCERTIFIED_ACTIONS = new Set([
  "admin-list-orders", "admin-update-status", "admin-verify-payment", "admin-proof-url",
  "admin-list-products", "admin-configure-product", "admin-save-product", "admin-upload-product-photo",
  "admin-list-staff", "admin-create-staff", "admin-set-permissions", "admin-set-active", "admin-reset-staff-password",
  "admin-payment-settings", "admin-save-payment-settings", "admin-upload-qris",
  "erp-list-recipes", "erp-save-recipe", "erp-activate-recipe", "erp-retire-recipe",
  "erp-list-product-modifiers", "erp-save-product-modifier", "erp-list-recipe-substitutions", "erp-save-recipe-substitution", "erp-set-product-stock-tracking",
  "erp-list-settlements", "erp-create-settlement", "erp-match-settlement",
  "erp-list-fiscal-periods", "erp-create-fiscal-period", "erp-close-fiscal-period", "erp-reopen-fiscal-period",
  "erp-list-tax-settings", "erp-save-tax-setting",
  "erp-save-branch", "erp-list-branch-settings", "erp-save-branch-setting", "erp-save-assignment", "erp-list-assignments",
  "erp-accept-tenant-invite", "erp-save-inventory",
  "erp-list-refunds", "erp-create-refund", "erp-review-refund", "erp-process-refund",
  "erp-overview", "erp-reports", "erp-export-report", "erp-list-audit-logs", "admin-list-audit-logs",
  "admin-upload-media", "admin-delete-media", "erp-upload-media",
]);
const requestIp = (req: Request) => req.headers.get("cf-connecting-ip") || req.headers.get("x-real-ip") || req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "unknown";
const consumeRateLimit = async (scope: string, key: string, limit: number, windowSeconds: number): Promise<boolean | null> => {
  const bucket = await sha256(`${scope}:${key}`);
  const { data, error } = await admin.rpc("consume_rate_limit", { p_bucket_key: bucket, p_limit: limit, p_window_seconds: windowSeconds });
  if (error) return null;
  return data === true;
};

const formatTransactionCode = (orderNumber: number | string, createdAt: string, timezone = "Asia/Jakarta") => {
  const safeTimezone = SUPPORTED_BRANCH_TIMEZONES.has(timezone) ? timezone : "Asia/Jakarta";
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: safeTimezone, day: "2-digit", month: "2-digit", year: "numeric",
  }).formatToParts(new Date(createdAt));
  const part = (type: string) => parts.find((item) => item.type === type)?.value ?? "";
  return `DLC-${part("day")}/${part("month")}/${part("year")}-${String(orderNumber).padStart(5, "0")}`;
};
const getAdmin = async (req: Request) => {
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const { data: userData, error: userError } = await authClient.auth.getUser(token);
  if (userError || !userData.user) return null;
  const { data: profile, error } = await admin.from("admin_profiles").select("role,is_active,display_name,username").eq("user_id", userData.user.id).maybeSingle();
  if (error || !profile?.is_active) return null;
  if (profile.role === "owner" && PLATFORM_OWNER_USER_IDS.has(userData.user.id) && userData.user.app_metadata?.platform_owner === true) {
    return { user: userData.user, profile: { ...profile, permissions: ["*"] } };
  }
  // Never authorize tenant actions from global admin_profiles.permissions or position defaults.
  // The intersection is deliberately fail-closed for users with multiple tenant memberships:
  // a permission granted in Tenant A cannot silently become a grant in Tenant B.
  const { data: memberships, error: membershipError } = await admin
    .from("tenant_memberships")
    .select("tenant_id,role,permissions,status")
    .eq("user_id", userData.user.id)
    .eq("status", "active");
  if (membershipError || !memberships?.length) return null;
  const permissions = resolveTenantScopedPermissions(memberships);
  return { user: userData.user, profile: { ...profile, permissions } };
};

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (req.method === "OPTIONS") {
    if (origin && !isAllowedOrigin(origin)) return fail("Origin tidak diizinkan.", 403, origin);
    return new Response("ok", { headers: corsHeaders(origin) });
  }
  if (req.method !== "POST") return fail("Metode tidak didukung.", 405, origin);
  if (origin && !isAllowedOrigin(origin)) return fail("Origin tidak diizinkan.", 403, origin);
  if (!SUPABASE_URL || !SERVICE_KEY || !PUBLIC_KEY) return fail("Konfigurasi server belum lengkap.", 500, origin);
  let body: Record<string, unknown>;
  try {
    const length = Number(req.headers.get("content-length") ?? "0");
    if (length > 7_000_000) return fail("Permintaan terlalu besar.", 413, origin);
    body = await req.json();
  } catch { return fail("Format permintaan tidak valid.", 400, origin); }
  const action = safeText(body.action, 40);

  // Public catalog and checkout still use the legacy global product/branch model.
  // Keep them closed until host/domain -> tenant resolution and tenant-scoped
  // catalog/order queries have passed positive and cross-tenant negative tests.
  const PUBLIC_TENANT_ROUTING_RELEASED = false;
  const PUBLIC_TENANT_ROUTING_REQUIRED_ACTIONS = new Set([
    "list-online-branches",
    "list-products",
    "create-order",
  ]);
  if (!PUBLIC_TENANT_ROUTING_RELEASED && PUBLIC_TENANT_ROUTING_REQUIRED_ACTIONS.has(action)) {
    return fail(
      "Katalog dan pemesanan publik sementara ditutup sampai routing tenant dan isolasi katalog/pesanan terverifikasi.",
      423,
      origin,
    );
  }

  if (action === "admin-login") {
    const username = safeText(body.username, 32).toLowerCase();
    const password = typeof body.password === "string" ? body.password : "";
    if (!validUsername(username) || password.length < 1 || password.length > 128) return fail("Nama pengguna atau kata sandi tidak sesuai.", 401, origin);
    const ipLimit = await consumeRateLimit("admin-login-ip", requestIp(req), 20, 15 * 60);
    const accountLimit = await consumeRateLimit("admin-login-account", username, 6, 15 * 60);
    if (ipLimit === null || accountLimit === null) return fail("Layanan keamanan sementara tidak tersedia. Coba lagi nanti.", 503, origin);
    if (!ipLimit || !accountLimit) return fail("Terlalu banyak percobaan login. Coba lagi dalam 15 menit.", 429, origin);
    const loginClient = createClient(SUPABASE_URL ?? "", PUBLIC_KEY ?? "", { auth: { persistSession: false, autoRefreshToken: false } });
    const { data, error } = await loginClient.auth.signInWithPassword({ email: usernameEmail(username), password });
    if (error || !data.session) return fail("Nama pengguna atau kata sandi tidak sesuai.", 401, origin);
    const { data: profile } = await admin.from("admin_profiles").select("is_active").eq("user_id", data.user.id).maybeSingle();
    if (!profile?.is_active) {
      await loginClient.auth.signOut();
      return fail("Akun tidak aktif. Hubungi Owner.", 403, origin);
    }
    return json({ session: data.session }, 200, origin);
  }

  if (action === "track-order-by-code") {
    const limited = await consumeRateLimit("track-order-by-code", requestIp(req), 8, 10 * 60);
    if (limited === null) return fail("Layanan keamanan sementara tidak tersedia. Coba lagi nanti.", 503, origin);
    if (!limited) return fail("Terlalu banyak percobaan pelacakan. Coba lagi dalam 10 menit.", 429, origin);
  }
  if (action === "track-order") {
    const limited = await consumeRateLimit("track-order-token", requestIp(req), 20, 10 * 60);
    if (limited === null) return fail("Layanan keamanan sementara tidak tersedia. Coba lagi nanti.", 503, origin);
    if (!limited) return fail("Terlalu banyak permintaan tracking. Coba lagi dalam 10 menit.", 429, origin);
  }


  if (action === "list-online-branches") {
    const method=safeText(body.receiving_method,20);
    if(!["pickup","delivery"].includes(method))return fail("Metode penerimaan tidak valid.",422,origin);
    const city=safeText(req.headers.get("cf-ipcity")||req.headers.get("x-vercel-ip-city")||"",80).toLowerCase();
    let q=admin.from("branches").select("id,code,name,address,city,province,pickup_enabled,delivery_enabled").eq("status","active").eq("accepts_online_orders",true);
    q=method==="pickup"?q.eq("pickup_enabled",true):q.eq("delivery_enabled",true);
    const {data,error}=await q.order("name");if(error)return fail("Cabang online belum dapat dimuat.",500,origin);
    const branches=data||[],matched=city?branches.filter((b:any)=>String(b.city||"").toLowerCase()===city):[];
    return json({branches,ip_city_match:matched.length===1?matched[0].id:null,selection_source:matched.length===1?"ip_estimate":"customer_choice",ip_location_hint:city||null,needs_customer_choice:matched.length!==1},200,origin);
  }

  if (action === "create-order") {
    const limited = await consumeRateLimit("create-order", requestIp(req), 10, 10 * 60);
    if (limited === null) return fail("Layanan keamanan sementara tidak tersedia. Coba lagi nanti.", 503, origin);
    if (!limited) return fail("Terlalu banyak permintaan pesanan. Coba lagi dalam 10 menit.", 429, origin);
  }

  if (action === "record-funnel-event") {
    const limited = await consumeRateLimit("funnel-events", requestIp(req), 120, 60);
    if (limited === null) return fail("Layanan keamanan sementara tidak tersedia.", 503, origin);
    if (!limited) return fail("Terlalu banyak event. Coba lagi nanti.", 429, origin);
    const eventName = safeText(body.event_name, 40);
    const allowedEvents = ["page_view","menu_view","add_to_order","checkout_start","order_created","proof_uploaded","whatsapp_click"];
    if (!allowedEvents.includes(eventName)) return fail("Event tidak valid.", 422, origin);
    const { error } = await admin.rpc("record_funnel_event", { p_event: eventName });
    if (error) return fail("Event tidak dapat dicatat.", 500, origin);
    return json({ ok: true }, 200, origin);
  }

  if (action === "admin-funnel-summary") {
    const actor = await getAdmin(req);
    if (!actor) return fail("Sesi operasional tidak valid.", 401, origin);
    const funnelPlatformOwner = actor.profile.role === "owner" && PLATFORM_OWNER_USER_IDS.has(actor.user.id) && actor.user.app_metadata?.platform_owner === true;
    if (!TENANT_ISOLATION_RELEASED && !funnelPlatformOwner) return fail("Ringkasan funnel lintas tenant ditutup sampai isolasi tenant terverifikasi.", 423, origin);
    if (!actor.profile.permissions.includes("*") && !actor.profile.permissions.includes("orders")) return fail("Akses ringkasan tidak diizinkan.", 403, origin);
    const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    const { data, error } = await admin.from("funnel_daily_metrics").select("metric_date,event_name,event_count").gte("metric_date", since).order("metric_date", { ascending: true });
    if (error) return fail("Ringkasan funnel belum tersedia.", 500, origin);
    return json({ since, metrics: data || [] }, 200, origin);
  }

  if (action === "list-products") {
    const { data, error } = await admin.from("products").select("id,slug,name,description,unit_price_idr,is_active,image_path,category,display_order,badge").eq("is_active", true).order("display_order").order("name");
    if (error) return fail("Menu belum dapat dimuat.", 500, origin);
    const products = (data ?? []).map((p) => ({ ...p, image_url: p.image_path ? admin.storage.from("dlice-product-photos").getPublicUrl(p.image_path).data.publicUrl : null }));
    return json({ products }, 200, origin);
  }


  if (action === "get-payment-instructions") {
    const token=safeText(body.tracking_token,100),method=safeText(body.method,30);if(token.length!==64||!["bank_transfer","dlice_qris"].includes(method))return fail("Token/metode tidak valid.",422,origin);
    const hash=await sha256(token),{data:o}=await admin.from("orders").select("id,payment_status,receipt_version").eq("tracking_token_hash",hash).maybeSingle();if(!o)return fail("Pesanan tidak ditemukan.",404,origin);
    const {data:s}=await admin.from("payment_settings").select("method,display_name,instructions,account_name,account_number,qr_storage_path,is_enabled,updated_at").eq("method",method).eq("is_enabled",true).maybeSingle();if(!s)return fail("Metode belum diaktifkan Owner.",409,origin);
    let qr_url=null;if(method==="dlice_qris"&&s.qr_storage_path){const {data:u}=await admin.storage.from("dlice-payment-assets").createSignedUrl(s.qr_storage_path,3600);qr_url=u?.signedUrl||null;}if(method==="dlice_qris"&&!qr_url)return fail("QRIS belum tersedia.",409,origin);
    return json({method,display_name:s.display_name,instructions:s.instructions,account_name:s.account_name,account_number:s.account_number,qr_url,settings_updated_at:s.updated_at,receipt_version:o.receipt_version},200,origin);
  }
  if (action === "confirm-receipt") {
    const token=safeText(body.tracking_token,100),version=Number(body.receipt_version),method=safeText(body.method,30);if(token.length!==64||!Number.isInteger(version))return fail("Konfirmasi struk tidak valid.",422,origin);
    const hash=await sha256(token),{data:o}=await admin.from("orders").select("id,order_number,created_at,timezone,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,delivery_address,customer_notes,product_subtotal_idr,payment_status,receipt_version").eq("tracking_token_hash",hash).maybeSingle();
    if(!o)return fail("Pesanan tidak ditemukan.",404,origin);if(version!==o.receipt_version)return fail("Struk berubah; tinjau dan konfirmasi ulang.",409,origin);if(!["unpaid","pending_verification"].includes(o.payment_status))return fail("Struk tidak dapat dikonfirmasi pada status ini.",409,origin);
    let instruction=null;if(method){if(!["bank_transfer","dlice_qris"].includes(method))return fail("Metode tidak valid.",422,origin);const {data:s}=await admin.from("payment_settings").select("method,display_name,instructions,account_name,account_number,qr_storage_path,updated_at,is_enabled").eq("method",method).eq("is_enabled",true).maybeSingle();if(!s)return fail("Metode belum diaktifkan Owner.",409,origin);if(method==="dlice_qris"&&!s.qr_storage_path)return fail("QRIS belum diunggah.",409,origin);instruction={method:s.method,display_name:s.display_name,instructions:s.instructions,account_name:s.account_name,account_number:s.account_number,qr_storage_path:s.qr_storage_path,settings_updated_at:s.updated_at};}
    const {data:items,error}=await admin.from("order_items").select("product_name_snapshot,quantity,unit_price_idr,line_total_idr").eq("order_id",o.id);if(error||!items?.length)return fail("Detail struk gagal dimuat.",500,origin);
    const receipt={transaction_code:formatTransactionCode(o.order_number,o.created_at,o.timezone),receipt_version:version,customer_name:o.customer_name,customer_whatsapp:o.customer_whatsapp,requested_date:o.requested_date,requested_time:o.requested_time,receiving_method:o.receiving_method,delivery_address:o.delivery_address,customer_notes:o.customer_notes,items,subtotal_idr:o.product_subtotal_idr,payment_method:method||null,payment_instruction:instruction,confirmed_at:new Date().toISOString()};
    const {error:e}=await admin.from("orders").update({receipt_confirmed_version:version,receipt_confirmed_at:new Date().toISOString(),receipt_snapshot:receipt}).eq("id",o.id).eq("receipt_version",version);if(e)return fail("Konfirmasi struk gagal disimpan.",500,origin);
    return json({ok:true,receipt},200,origin);
  }
  if (action === "update-order-items") {
    const token=safeText(body.tracking_token,100);if(token.length!==64||!Array.isArray(body.items))return fail("Perubahan pesanan tidak valid.",422,origin);const hash=await sha256(token),items=[];
    for(const x of body.items.slice(0,20)){const slug=safeText(x?.slug,80),quantity=Number(x?.quantity);if(!/^[a-z0-9-]+$/.test(slug)||!Number.isInteger(quantity)||quantity<1||quantity>100)return fail("Menu/jumlah tidak valid.",422,origin);const prev=items.find(i=>i.slug===slug);if(prev)prev.quantity+=quantity;else items.push({slug,quantity});}
    if(!items.length||items.some(i=>i.quantity>100))return fail("Pilih minimal satu menu.",422,origin);const {data:o}=await admin.from("orders").select("id").eq("tracking_token_hash",hash).maybeSingle();if(!o)return fail("Pesanan tidak ditemukan.",404,origin);
    const {data:u,error}=await admin.rpc("update_order_with_reservations",{p_order_id:o.id,p_tracking_token_hash:hash,p_items:items});if(error){const msg=error.message||"";return fail(msg.includes("capacity_exceeded")?"Kapasitas menu tidak mencukupi.":msg.includes("reservation_expired")?"Reservasi berakhir; hubungi admin.":msg.includes("proof_already_uploaded")?"Bukti sudah diunggah; hubungi admin.":"Perubahan pesanan gagal.",409,origin);}
    const {data:m}=await admin.from("orders").select("order_number,created_at,timezone,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,delivery_address,customer_notes,product_subtotal_idr,receipt_version").eq("id",o.id).single();const {data:lines}=await admin.from("order_items").select("product_name_snapshot,quantity,unit_price_idr,line_total_idr").eq("order_id",o.id);
    return json({ok:true,...u,receipt:{...m,transaction_code:formatTransactionCode(m.order_number,m.created_at,m.timezone),items:lines||[],subtotal_idr:m.product_subtotal_idr}},200,origin);
  }
  if (action === "finalize-order-whatsapp") {
    const token=safeText(body.tracking_token,100),version=Number(body.receipt_version);if(token.length!==64||!Number.isInteger(version))return fail("Data akhir tidak valid.",422,origin);const hash=await sha256(token);
    const {data:o}=await admin.from("orders").select("id,order_number,created_at,timezone,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,delivery_address,customer_notes,product_subtotal_idr,receipt_version,receipt_confirmed_version,receipt_snapshot").eq("tracking_token_hash",hash).maybeSingle();
    if(!o)return fail("Pesanan tidak ditemukan.",404,origin);if(o.receipt_version!==version||o.receipt_confirmed_version!==version||!o.receipt_snapshot?.payment_method||!o.receipt_snapshot?.payment_instruction)return fail("Struk/instruksi belum dikonfirmasi.",409,origin);
    const {data:p}=await admin.from("payment_records").select("method,status,proof_storage_path,receipt_version").eq("order_id",o.id).order("created_at",{ascending:false}).limit(1).maybeSingle();if(!p?.proof_storage_path||p.receipt_version!==version||p.method!==o.receipt_snapshot.payment_method)return fail("Bukti belum terhubung ke struk terbaru.",409,origin);
    const {data:lines}=await admin.from("order_items").select("product_name_snapshot,quantity,line_total_idr").eq("order_id",o.id);const code=formatTransactionCode(o.order_number,o.created_at,o.timezone),lineText=(lines||[]).map(i=>`• ${i.product_name_snapshot} × ${i.quantity} — Rp${Number(i.line_total_idr).toLocaleString("id-ID")}`).join("\n");
    const msg=`PESANAN BARU D’LICE — ${code}\nNama: ${o.customer_name}\nWhatsApp: ${o.customer_whatsapp}\nTanggal: ${o.requested_date} ${o.requested_time} waktu lokal cabang\nPenerimaan: ${o.receiving_method==="delivery"?"Delivery — "+(o.delivery_address||""):"Pickup"}\nMetode: ${p.method==="dlice_qris"?"QRIS D’Lice":"Transfer bank"}\n${lineText}\nTotal produk: Rp${Number(o.product_subtotal_idr).toLocaleString("id-ID")}\nCatatan: ${o.customer_notes||"-"}\nBukti pembayaran diunggah; menunggu verifikasi.`;
    const key=`customer-order:${o.id}:${version}`,{data:existing}=await admin.from("notification_log").select("status").eq("idempotency_key",key).maybeSingle();if(!existing){const {error}=await admin.from("notification_log").insert({order_id:o.id,notification_type:"customer_order_whatsapp",status:"manual_action_required",idempotency_key:key,recipient_whatsapp:"6285397710002",message_text:msg});if(error)return fail("Notifikasi gagal dicatat.",500,origin);}
    await admin.from("orders").update({final_whatsapp_requested_at:new Date().toISOString()}).eq("id",o.id);return json({ok:true,whatsapp_url:`https://wa.me/6285397710002?text=${encodeURIComponent(msg)}`,notification_status:existing?.status||"manual_action_required"},200,origin);
  }
  if (action === "track-order-by-code") {
    const code=safeText(body.transaction_code,30).toUpperCase();
    const submittedPhone=normPhone(safeText(body.customer_whatsapp,30));
    const match=code.match(/^DLC-(\d{2})\/(\d{2})\/(\d{4})-(\d{5})$/);
    if(!match||submittedPhone.length<9||submittedPhone.length>16)return fail("ID pesanan atau data verifikasi tidak valid.",422,origin);
    const day=Number(match[1]),month=Number(match[2]),year=Number(match[3]),orderNumber=Number(match[4]);
    const dateCheck=new Date(Date.UTC(year,month-1,day));
    if(dateCheck.getUTCFullYear()!==year||dateCheck.getUTCMonth()!==month-1||dateCheck.getUTCDate()!==day)return fail("ID pesanan atau data verifikasi tidak valid.",422,origin);
    const start=new Date(Date.UTC(year,month-1,day)-8*60*60*1000).toISOString();
    const end=new Date(Date.UTC(year,month-1,day+1)-8*60*60*1000).toISOString();
    const {data:o}=await admin.from("orders").select("id,order_number,created_at,timezone,requested_date,requested_time,receiving_method,delivery_address,payment_status,operational_status,product_subtotal_idr,customer_whatsapp").eq("order_number",orderNumber).gte("created_at",start).lt("created_at",end).maybeSingle();
    const normalizedCode=o?formatTransactionCode(o.order_number,o.created_at,o.timezone):"";
    const savedPhone=normPhone(String(o?.customer_whatsapp??""));
    if(!o||normalizedCode!==code||!savedPhone||savedPhone!==submittedPhone)return fail("ID pesanan atau nomor WhatsApp tidak cocok.",404,origin);
    const {data:history}=await admin.from("order_status_history").select("status_type,old_status,new_status,note,created_at").eq("order_id",o.id).order("created_at",{ascending:false}).limit(30);
    const {data:items}=await admin.from("order_items").select("product_name_snapshot,quantity,line_total_idr").eq("order_id",o.id);
    return json({order:{transaction_code:normalizedCode,requested_date:o.requested_date,requested_time:o.requested_time,receiving_method:o.receiving_method,delivery_address:o.delivery_address,payment_status:o.payment_status,operational_status:o.operational_status,product_subtotal_idr:o.product_subtotal_idr,items:items||[],updated_at:history?.[0]?.created_at||o.created_at,history:history||[]}},200,origin);
  }

  if (action === "track-order") {
    const token=safeText(body.tracking_token,100);if(token.length!==64)return fail("Token tracking tidak valid.",422,origin);const hash=await sha256(token),{data:o}=await admin.from("orders").select("id,order_number,created_at,timezone,requested_date,requested_time,receiving_method,delivery_address,payment_status,operational_status,product_subtotal_idr").eq("tracking_token_hash",hash).maybeSingle();if(!o)return fail("Pesanan tidak ditemukan.",404,origin);
    const {data:history}=await admin.from("order_status_history").select("status_type,old_status,new_status,note,created_at").eq("order_id",o.id).order("created_at",{ascending:false}).limit(30);const {data:items}=await admin.from("order_items").select("product_name_snapshot,quantity,line_total_idr").eq("order_id",o.id);
    return json({order:{transaction_code:formatTransactionCode(o.order_number,o.created_at,o.timezone),requested_date:o.requested_date,requested_time:o.requested_time,receiving_method:o.receiving_method,delivery_address:o.delivery_address,payment_status:o.payment_status,operational_status:o.operational_status,product_subtotal_idr:o.product_subtotal_idr,items:items||[],updated_at:history?.[0]?.created_at||o.created_at,history:history||[]}},200,origin);
  }

  if (action === "create-order") {
    const customerName = safeText(body.customer_name, 120);
    const customerWhatsapp = normPhone(safeText(body.customer_whatsapp, 30));
    const requestedDate = safeText(body.requested_date, 10);
    const requestedTime = safeText(body.requested_time, 80);
    const receivingMethod = safeText(body.receiving_method, 20);
    const deliveryAddress = safeText(body.delivery_address, 600);
    const notes = safeText(body.customer_notes, 1000);
    if (customerName.length < 2 || customerWhatsapp.length < 9 || customerWhatsapp.length > 16 || !/^\d{4}-\d{2}-\d{2}$/.test(requestedDate) || !requestedTime || !["pickup", "delivery"].includes(receivingMethod)) return fail("Periksa nama, nomor WhatsApp, tanggal, waktu, dan metode penerimaan.", 422, origin);
    if (receivingMethod === "delivery" && deliveryAddress.length < 8) return fail("Alamat pengantaran wajib diisi lengkap.", 422, origin);
    if (!Array.isArray(body.items) || body.items.length < 1 || body.items.length > 20) return fail("Pilih minimal satu menu.", 422, origin);
    const normalized: { slug: string; quantity: number }[] = [];
    for (const raw of body.items as Record<string, unknown>[]) {
      const slug = safeText(raw?.slug, 80);
      const quantity = Number(raw?.quantity);
      if (!/^[a-z0-9-]+$/.test(slug) || !Number.isInteger(quantity) || quantity < 1 || quantity > 100) return fail("Menu atau jumlah tidak valid.", 422, origin);
      const existing = normalized.find((i) => i.slug === slug);
      if (existing) existing.quantity += quantity; else normalized.push({ slug, quantity });
    }
    const { data: products, error: productError } = await admin.from("products").select("id,slug,unit_price_idr,is_active").in("slug", normalized.map((i) => i.slug));
    if (productError || !products || products.length !== normalized.length) return fail("Ada menu yang tidak dikenal.", 422, origin);
    if (products.some((p) => !p.is_active || p.unit_price_idr == null)) return fail("Harga menu belum ditetapkan. Silakan hubungi D’Lice melalui WhatsApp.", 409, origin);
    const receivingMethodKey=receivingMethod;
    const requestedBranchId=safeText(body.branch_id,80);
    const cityHint=safeText(req.headers.get("cf-ipcity")||req.headers.get("x-vercel-ip-city")||"",80).toLowerCase();
    let branchQuery=admin.from("branches").select("id,city,status,accepts_online_orders,pickup_enabled,delivery_enabled,daily_order_capacity").eq("status","active").eq("accepts_online_orders",true);
    branchQuery=receivingMethodKey==="pickup"?branchQuery.eq("pickup_enabled",true):branchQuery.eq("delivery_enabled",true);
    const {data:eligibleBranches,error:branchError}=await branchQuery;
    if(branchError)return fail("Cabang pemenuhan belum dapat diverifikasi.",503,origin);
    const choices=eligibleBranches||[];
    if(!choices.length)return fail("Belum ada cabang aktif yang dikonfigurasi untuk pesanan online. Silakan hubungi D’Lice.",409,origin);
    const ipMatches=cityHint?choices.filter((b:any)=>String(b.city||"").toLowerCase()===cityHint):[];
    const selectedBranchId=requestedBranchId||(ipMatches.length===1?ipMatches[0].id:(choices.length===1?choices[0].id:""));
    if(!selectedBranchId)return json({error:"Pilih cabang pemenuhan untuk melanjutkan.",code:"branch_selection_required",branches:choices.map((b:any)=>({id:b.id,city:b.city})),ip_location_hint:cityHint||null},409,origin);
    const chosen=choices.find((b:any)=>b.id===selectedBranchId);
    if(!chosen)return fail("Cabang tidak aktif atau tidak melayani metode penerimaan ini.",422,origin);
    const branchSelectionSource=ipMatches.length===1&&ipMatches[0].id===chosen.id?"ip_estimate":requestedBranchId?"customer_choice":"customer_choice";
    if(receivingMethodKey==="delivery"&&(!deliveryAddress||deliveryAddress.length<8))return fail("Alamat delivery wajib diisi lengkap.",422,origin);
    const items = normalized.map((item) => ({ product_id: products.find((p) => p.slug === item.slug)!.id, quantity: item.quantity }));
    const trackingToken = randomToken();
    const trackingHash = await sha256(trackingToken);
    const { data: created, error } = await admin.rpc("create_order_with_reservations", {
      p_order: {
        customer_name: customerName, customer_whatsapp: customerWhatsapp, requested_date: requestedDate,
        requested_time: requestedTime, receiving_method: receivingMethod, delivery_address: receivingMethod === "delivery" ? deliveryAddress : null,
        customer_notes: notes || null, branch_id: selectedBranchId, branch_selection_source: branchSelectionSource,
      },
      p_items: items,
      p_tracking_token_hash: trackingHash,
    });
    if (error) {
      const e = error.message ?? "";
      const messages: Record<string, string> = {
        capacity_exceeded: "Maaf, kapasitas salah satu menu untuk tanggal tersebut sudah tidak mencukupi.",
        capacity_not_configured: "Kapasitas menu untuk tanggal tersebut belum dibuka. Silakan hubungi admin.",
        branch_capacity_not_configured: "Kapasitas menu di cabang untuk tanggal tersebut belum dibuka. Silakan pilih tanggal lain atau hubungi admin.",
        branch_capacity_exceeded: "Kapasitas cabang untuk menu/tanggal tersebut sudah penuh. Pilih cabang atau tanggal lain.",
        branch_daily_capacity_exceeded: "Cabang sudah mencapai kapasitas pesanan pada tanggal tersebut. Pilih tanggal lain atau cabang lain.",
        branch_not_online: "Cabang ini belum dibuka untuk menerima pesanan online.",
        branch_method_unavailable: "Cabang tidak melayani metode penerimaan yang dipilih.",
        same_day_cutoff_passed: "Batas pemesanan hari ini pukul 18.00 waktu lokal cabang sudah lewat.",
        date_in_past: "Tanggal pesanan tidak boleh di masa lalu.",
        product_unavailable_or_price_missing: "Harga atau ketersediaan menu belum disiapkan.",
      };
      const key = Object.keys(messages).find((k) => e.includes(k));
      return fail(messages[key ?? ""] ?? "Pesanan belum dapat dibuat. Periksa tanggal, menu, dan kapasitas.", 409, origin);
    }
    const { data: orderMeta, error: orderMetaError } = await admin.from("orders").select("order_number,created_at,timezone,receipt_version,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,delivery_address,customer_notes,product_subtotal_idr").eq("id", created.order_id).single();
    if (orderMetaError || !orderMeta) return fail("Pesanan tersimpan, tetapi kode transaksi belum dapat ditampilkan. Hubungi admin D’Lice.", 500, origin);
    const { data: lines } = await admin.from("order_items").select("product_name_snapshot,quantity,unit_price_idr,line_total_idr").eq("order_id", created.order_id);
    const transactionCode = formatTransactionCode(orderMeta.order_number, orderMeta.created_at, orderMeta.timezone);
    return json({
      order_id: created.order_id, order_number: orderMeta.order_number, transaction_code: transactionCode,
      tracking_token: trackingToken, subtotal_idr: created.subtotal_idr,
      reservation_expires_at: created.reservation_expires_at, receipt_version: orderMeta.receipt_version, items: lines ?? [],
      receipt: { transaction_code: transactionCode, receipt_version: orderMeta.receipt_version, customer_name: orderMeta.customer_name, customer_whatsapp: orderMeta.customer_whatsapp, requested_date: orderMeta.requested_date, requested_time: orderMeta.requested_time, receiving_method: orderMeta.receiving_method, delivery_address: orderMeta.delivery_address, customer_notes: orderMeta.customer_notes, items: lines ?? [], subtotal_idr: orderMeta.product_subtotal_idr },
      message: "Pesanan tersimpan. Lanjutkan pembayaran dalam 15 menit; jika Anda menyatakan sudah membayar atau mengirim bukti sebelum tenggat, kapasitas akan ditahan sampai admin memeriksa.",
    }, 201, origin);
  }

  if (action === "declare-payment" || action === "upload-proof") {
    const token = safeText(body.tracking_token, 100);
    if (token.length !== 64) return fail("Token pelacakan tidak valid.", 401, origin);
    const tokenHash = await sha256(token);
    const { data: order, error: orderError } = await admin.from("orders").select("id,payment_status,requested_date,requested_time,receiving_method,customer_whatsapp,product_subtotal_idr,receipt_version,receipt_confirmed_version,receipt_snapshot").eq("tracking_token_hash", tokenHash).maybeSingle();
    if (orderError || !order) return fail("Pesanan tidak ditemukan.", 404, origin);
    const { data: reservations, error: reservationError } = await admin.from("order_reservations").select("id,status,expires_at").eq("order_id", order.id);
    if (reservationError || !reservations?.length) return fail("Reservasi pesanan tidak ditemukan.", 409, origin);
    if (reservations.some((r) => r.status === "expired" || r.status === "released")) return fail("Reservasi sudah berakhir. Hubungi admin untuk memeriksa ketersediaan.", 409, origin);
    const allStillActive = reservations.every((r) => r.status === "active" && new Date(r.expires_at).getTime() > Date.now());
    if(action==="upload-proof"){const method=safeText(body.method,30),version=Number(body.receipt_version);if(!["bank_transfer","dlice_qris"].includes(method)||!Number.isInteger(version))return fail("Metode/versi struk tidak valid.",422,origin);if(version!==order.receipt_version||order.receipt_confirmed_version!==version||order.receipt_snapshot?.payment_method!==method||!order.receipt_snapshot?.payment_instruction)return fail("Struk dan instruksi pembayaran terbaru wajib dikonfirmasi.",409,origin);}
    if (action === "declare-payment") {
      const { data: proofPayment, error: proofLookupError } = await admin.from("payment_records").select("id,proof_storage_path").eq("order_id", order.id).eq("status", "pending_verification").not("proof_storage_path", "is", null).order("created_at", { ascending: false }).limit(1).maybeSingle();
      if (proofLookupError) return fail("Status bukti pembayaran belum dapat diperiksa.", 500, origin);
      if (!proofPayment?.proof_storage_path) return fail("Unggah bukti pembayaran terlebih dahulu. Bukti wajib tersedia sebelum pembayaran dapat diverifikasi.", 422, origin);
      if (!allStillActive && !reservations.every((r) => r.status === "held_for_verification")) return fail("Batas 15 menit telah lewat. Hubungi admin; jangan melakukan pembayaran baru sebelum dikonfirmasi.", 409, origin);
      const { error: updateError } = await admin.from("order_reservations").update({ status: "held_for_verification", payment_declared_at: new Date().toISOString() }).eq("order_id", order.id).eq("status", "active");
      if (updateError) return fail("Pernyataan pembayaran belum tersimpan.", 500, origin);
      await admin.from("orders").update({ payment_status: "pending_verification" }).eq("id", order.id);
      await admin.from("order_status_history").insert({ order_id: order.id, status_type: "payment", old_status: order.payment_status, new_status: "pending_verification", note: "Customer confirmed payment after uploading proof" });
      return json({ ok: true, message: "Bukti pembayaran sudah tercatat dan menunggu pemeriksaan admin." }, 200, origin);
    }
    if (!allStillActive && !reservations.every((r) => r.status === "held_for_verification")) return fail("Reservasi sudah berakhir; hubungi admin sebelum mengunggah bukti.", 409, origin);
    const mime = safeText(body.mime_type, 50);
    const encoded = safeText(body.file_base64, 7_000_000);
    const extByMime: Record<string, string> = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "application/pdf": "pdf" };
    if (!extByMime[mime] || !encoded || encoded.length > 7_000_000) return fail("Format atau ukuran bukti tidak didukung (maksimal 5 MB).", 422, origin);
    let binary: Uint8Array;
    try {
      const payload = encoded.replace(/^data:[^,]+,/, "");
      if (!payload || payload.length > 7_000_000 || !/^[A-Za-z0-9+\\/]*={0,2}$/.test(payload)) {
        return fail("Data bukti pembayaran tidak valid.", 422, origin);
      }
      binary = Uint8Array.from(atob(payload), (c) => c.charCodeAt(0));
    } catch {
      return fail("Data bukti pembayaran tidak valid.", 422, origin);
    }
    if (binary.byteLength === 0) return fail("File bukti pembayaran kosong.", 422, origin);
    if (binary.byteLength > 5 * 1024 * 1024) return fail("Ukuran bukti maksimal 5 MB.", 413, origin);
    const startsWith = (signature: number[]) => signature.every((byte, index) => binary[index] === byte);
    const asciiAt = (offset: number, expected: string) =>
      [...expected].every((char, index) => binary[offset + index] === char.charCodeAt(0));
    const signatureMatches: Record<string, boolean> = {
      "image/jpeg": startsWith([0xff, 0xd8, 0xff]),
      "image/png": startsWith([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      "image/webp": asciiAt(0, "RIFF") && asciiAt(8, "WEBP"),
      "application/pdf": asciiAt(0, "%PDF-"),
    };
    if (!signatureMatches[mime]) return fail("Isi file tidak sesuai dengan format bukti yang dipilih.", 422, origin);
    const { data: existingPending, error: pendingLookupError } = await admin.from("payment_records").select("id,proof_storage_path").eq("order_id", order.id).eq("status", "pending_verification").order("created_at", { ascending: false }).limit(1).maybeSingle();
    if (pendingLookupError) return fail("Data pembayaran belum dapat diperiksa.", 500, origin);
    const path = `${order.id}/${crypto.randomUUID()}.${extByMime[mime]}`;
    const { error: uploadError } = await admin.storage.from("dlice-payment-proofs").upload(path, binary, { contentType: mime, upsert: false });
    if (uploadError) return fail("Unggahan bukti gagal. Coba kembali.", 500, origin);
    const paymentValues = { method: body.method === "dlice_qris" ? "dlice_qris" : "bank_transfer", amount_idr: order.product_subtotal_idr, proof_storage_path: path, receipt_version: order.receipt_version, payment_instruction_snapshot: order.receipt_snapshot.payment_instruction };
    const { error: payError } = existingPending
      ? await admin.from("payment_records").update(paymentValues).eq("id", existingPending.id)
      : await admin.from("payment_records").insert({ order_id: order.id, ...paymentValues, status: "pending_verification" });
    if (payError) return fail("Bukti tersimpan tetapi pencatatan pembayaran gagal; hubungi admin dan jangan unggah ulang dulu.", 500, origin);
    await admin.from("order_reservations").update({ status: "held_for_verification", proof_received_at: new Date().toISOString() }).eq("order_id", order.id).eq("status", "active");
    await admin.from("orders").update({ payment_status: "pending_verification" }).eq("id", order.id);
    await admin.from("order_status_history").insert({ order_id: order.id, status_type: "payment", old_status: order.payment_status, new_status: "pending_verification", note: "Payment proof uploaded; awaiting admin verification" });
    return json({ ok: true, message: "Bukti tersimpan secara privat dan menunggu verifikasi admin." }, 200, origin);
  }

  if (action === "admin-bootstrap-owner") {
    const bootstrapSecret = Deno.env.get("DLICE_OWNER_BOOTSTRAP_SECRET");
    if (!bootstrapSecret || safeText(body.bootstrap_secret, 256) !== bootstrapSecret) return fail("Proses penyiapan awal akun tidak diizinkan.", 403, origin);
    const { count, error: countError } = await admin.from("admin_profiles").select("user_id", { count: "exact", head: true }).eq("role", "owner");
    if (countError) return fail("Status owner tidak dapat diperiksa.", 500, origin);
    if ((count ?? 0) > 0) return fail("Akun Pemilik sudah tersedia; proses penyiapan awal ditutup.", 409, origin);
    const username = safeText(body.username, 32);
    const password = typeof body.password === "string" ? body.password : "";
    if (!validUsername(username) || username.toLowerCase() !== "dlice8888" || password.length < 12) return fail("Nama pengguna atau kata sandi penyiapan awal tidak memenuhi ketentuan.", 422, origin);
    const passwordCheck = await checkNewPassword(password, origin);
    if (passwordCheck) return passwordCheck;
    const { data: created, error: createError } = await admin.auth.admin.createUser({ email: usernameEmail(username), password, email_confirm: true, app_metadata: { platform_owner: true }, user_metadata: { username } });
    if (createError || !created.user) return fail("Akun Pemilik gagal dibuat.", 500, origin);
    const { data: bootstrapResult, error: bootstrapError } = await admin.rpc("dlice_bootstrap_initial_owner", { p_user_id: created.user.id, p_username: username });
    if (bootstrapError) {
      if (typeof bootstrapError.code !== "string" || !/^[0-9A-Z]{5}$/.test(bootstrapError.code)) {
        return fail("Hasil bootstrap belum dapat dipastikan. Verifikasi akun Auth dan transaksi database sebelum mencoba kembali.", 503, origin);
      }
      const { error: cleanupError } = await admin.auth.admin.deleteUser(created.user.id);
      if (cleanupError) return fail("Bootstrap gagal; profil, membership, dan audit tidak tersimpan, tetapi akun Auth sementara memerlukan pembersihan operator.", 500, origin);
      return fail("Profil, membership, dan audit Pemilik gagal dibuat secara atomik.", bootstrapError.code === "23505" ? 409 : 500, origin);
    }
    return json({ ok: true, user_id: created.user.id, tenant_id: bootstrapResult?.tenant_id ?? null, platform_owner_allowlist_update_required: true }, 201, origin);
  }

  const actor = await getAdmin(req);
  if (!actor) return fail("Silakan masuk terlebih dahulu untuk mengakses operasional.", 401, origin);
  const isPlatformOwner = actor.profile.role === "owner" && PLATFORM_OWNER_USER_IDS.has(actor.user.id) && actor.user.app_metadata?.platform_owner === true;
  if (
    !TENANT_ISOLATION_RELEASED &&
    !isPlatformOwner &&
    (isTenantSensitiveAction(action) || TENANT_SCOPE_UNCERTIFIED_ACTIONS.has(action))
  ) {
    return fail("Akses sementara ditutup sampai cakupan tenant untuk tindakan ini lolos pengujian isolasi.", 423, origin);
  }

  const actorCanAccessBranch = async (branchId: string | null | undefined): Promise<boolean> => {
    if (isPlatformOwner) return true;
    if (!branchId) return false;
    const { data: branch, error: branchError } = await admin.from("branches").select("tenant_id").eq("id", branchId).maybeSingle();
    if (branchError || !branch?.tenant_id) return false;
    const { data: membership, error: membershipError } = await admin.from("tenant_memberships").select("role").eq("tenant_id", branch.tenant_id).eq("user_id", actor.user.id).eq("status", "active").maybeSingle();
    if (membershipError || !membership) return false;
    if (["tenant_owner", "tenant_admin"].includes(String(membership.role))) return true;
    const { data, error } = await admin.from("branch_assignments").select("id").eq("branch_id", branchId).eq("user_id", actor.user.id).eq("employment_status", "active").lte("starts_on", todayDate()).or(`ends_on.is.null,ends_on.gte.${todayDate()}`).limit(1);
    return !error && !!data?.length;
  };
  const actorBranchIds = async (): Promise<string[]> => {
    if (isPlatformOwner) return [];
    const { data: memberships, error: membershipError } = await admin.from("tenant_memberships").select("tenant_id,role").eq("user_id", actor.user.id).eq("status", "active");
    if (membershipError) throw new Error("Keanggotaan tenant gagal dimuat.");
    const membershipRows = memberships || [];
    const tenantIds = [...new Set(membershipRows.map((x: { tenant_id: string }) => x.tenant_id))];
    if (!tenantIds.length) return [];
    const assigned = await admin.from("branch_assignments").select("branch_id").eq("user_id", actor.user.id).eq("employment_status", "active").lte("starts_on", todayDate()).or(`ends_on.is.null,ends_on.gte.${todayDate()}`);
    if (assigned.error) throw new Error("Penugasan cabang gagal dimuat.");
    const assignedRows = (assigned.data || []).map((x: { branch_id: string }) => ({ branch_id: x.branch_id }));
    const { data: branches, error: branchesError } = await admin.from("branches").select("id,tenant_id").in("tenant_id", tenantIds);
    if (branchesError) throw new Error("Pemetaan tenant-cabang gagal dimuat.");
    return resolveTenantScopedBranchIds(membershipRows, assignedRows, branches || []);
  };
  const hasHQPermission = async (permission: string): Promise<boolean> => {
    if (isPlatformOwner) return true;
    if (!actor.profile.permissions.includes(permission)) return false;
    const { data, error } = await admin.from("branch_assignments").select("job_positions(is_head_office,default_permissions)").eq("user_id", actor.user.id).eq("employment_status", "active").lte("starts_on", todayDate()).or(`ends_on.is.null,ends_on.gte.${todayDate()}`);
    return !error && (data || []).some((x: any) => x.job_positions?.is_head_office === true && Array.isArray(x.job_positions?.default_permissions) && x.job_positions.default_permissions.includes(permission));
  };
  const hasHQPermissionForTenant = async (permission: string, tenantId: string): Promise<boolean | null> => {
    if (isPlatformOwner) return true;
    if (!actor.profile.permissions.includes(permission)) return false;
    const [membershipResult, assignmentResult] = await Promise.all([
      admin.from("tenant_memberships").select("tenant_id,status,permissions")
        .eq("tenant_id", tenantId).eq("user_id", actor.user.id).eq("status", "active"),
      admin.from("branch_assignments")
        .select("branches!inner(tenant_id),job_positions!inner(is_head_office,default_permissions)")
        .eq("user_id", actor.user.id).eq("employment_status", "active")
        .eq("branches.tenant_id", tenantId)
        .lte("starts_on", todayDate()).or(`ends_on.is.null,ends_on.gte.${todayDate()}`),
    ]);
    if (membershipResult.error || assignmentResult.error) return null;
    const assignments = (assignmentResult.data || []).map((assignment: {
      branches: { tenant_id: string } | { tenant_id: string }[] | null;
      job_positions: { is_head_office: boolean; default_permissions: unknown } |
        { is_head_office: boolean; default_permissions: unknown }[] | null;
    }) => {
      const branch = Array.isArray(assignment.branches) ? assignment.branches[0] : assignment.branches;
      const position = Array.isArray(assignment.job_positions) ? assignment.job_positions[0] : assignment.job_positions;
      return {
        tenant_id: branch?.tenant_id,
        is_head_office: position?.is_head_office,
        default_permissions: position?.default_permissions,
      };
    });
    return hasTenantScopedHeadOfficePermission(
      membershipResult.data || [],
      assignments,
      tenantId,
      permission,
    );
  };

  const permissionForAction: Record<string, string> = {
    "admin-list-orders": "orders",
    "admin-update-status": "orders",
    "admin-verify-payment": "orders",
    "admin-proof-url": "orders",
    "admin-configure-product": "catalog",
    "admin-list-products": "catalog",
    "admin-save-product": "catalog",
    "admin-upload-product-photo": "catalog",
    "admin-list-staff": "staff",
    "admin-create-staff": "staff",
    "admin-set-permissions": "staff",
    "admin-set-active": "staff",
    "admin-reset-staff-password": "staff",
    "admin-payment-settings": "settings",
    "admin-save-payment-settings": "settings",
    "admin-upload-qris": "settings",
    "admin-mark-notification-sent": "orders",
    "admin-retry-payment-notification": "orders",
    "erp-overview": "reports",
    "erp-list-branch-checklists": "branches",
    "erp-start-branch-checklist": "branches",
    "erp-update-branch-checklist-item": "branches",
    "erp-complete-branch-checklist": "branches",
    "erp-save-branch": "branches",
    "erp-save-assignment": "staff",
    "erp-list-inventory": "inventory",
    "erp-save-inventory": "inventory",
    "erp-stock-movement": "inventory",
    "erp-list-stock-transfers": "inventory",
    "erp-create-stock-transfer": "inventory",
    "erp-transition-stock-transfer": "inventory",
    "erp-list-stock-counts": "inventory",
    "erp-create-stock-count": "inventory",
    "erp-update-stock-count-item": "inventory",
    "erp-post-stock-count": "inventory",
    "erp-list-shifts": "pos",
    "erp-open-shift": "pos",
    "erp-close-shift": "pos",
    "erp-create-pos-sale": "pos",
    "erp-list-expenses": "finance",
    "erp-create-expense": "finance",
    "erp-review-expense": "finance",
    "erp-list-purchase-requisitions": "procurement",
    "erp-create-purchase-requisition": "procurement",
    "erp-transition-purchase-requisition": "procurement",
    "erp-reconcile-purchase-requisition": "procurement",
    "erp-list-purchase-orders": "procurement",
    "erp-create-purchase-order": "procurement",
    "erp-update-purchase-order": "procurement",
  };
  const requiredPermission = permissionForAction[action];
  if (requiredPermission && !isPlatformOwner && !actor.profile.permissions.includes("*") && !actor.profile.permissions.includes(requiredPermission)) {
    return fail("Akses ditolak. Pemilik belum memberikan izin untuk bagian ini.", 403, origin);
  }


  if(action==="admin-session-info"){return json({role:actor.profile.role,permissions:actor.profile.permissions||[],display_name:actor.profile.display_name||actor.profile.username||""},200,origin);}

  if(action==="admin-payment-settings"){if(!isPlatformOwner)return fail("Hanya Owner.",403,origin);const {data,error}=await admin.from("payment_settings").select("method,display_name,instructions,account_name,account_number,qr_storage_path,is_enabled,updated_at").order("method");if(error)return fail("Pengaturan gagal dimuat.",500,origin);const settings=[];for(const s of data||[]){let qr_url=null;if(s.qr_storage_path){const {data:u}=await admin.storage.from("dlice-payment-assets").createSignedUrl(s.qr_storage_path,3600);qr_url=u?.signedUrl||null;}settings.push({...s,qr_url});}return json({settings},200,origin);}
  if(action==="admin-save-payment-settings"){if(!isPlatformOwner)return fail("Hanya Owner.",403,origin);const method=safeText(body.method,30),display_name=safeText(body.display_name,100),instructions=safeText(body.instructions,1000),account_name=safeText(body.account_name,120),account_number=safeText(body.account_number,80),is_enabled=body.is_enabled===true;if(!["bank_transfer","dlice_qris"].includes(method))return fail("Metode tidak valid.",422,origin);const {data:current}=await admin.from("payment_settings").select("qr_storage_path").eq("method",method).maybeSingle();if(is_enabled&&method==="bank_transfer"&&(!display_name||!account_name||!account_number))return fail("Lengkapi bank, nama pemilik, dan nomor rekening.",422,origin);if(is_enabled&&method==="dlice_qris"&&!current?.qr_storage_path)return fail("Unggah QRIS dahulu.",422,origin);const {error}=await admin.from("payment_settings").upsert({method,display_name:display_name||(method==="dlice_qris"?"QRIS D’Lice":"Transfer bank"),instructions:instructions||null,account_name:method==="bank_transfer"?account_name||null:null,account_number:method==="bank_transfer"?account_number||null:null,is_enabled,updated_by:actor.user.id,updated_at:new Date().toISOString()},{onConflict:"method"});if(error)return fail("Pengaturan gagal disimpan.",500,origin);await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"update_payment_settings",entity_type:"payment_settings",entity_id:method,metadata:{method,is_enabled}});return json({ok:true},200,origin);}
  if(action==="admin-upload-qris"){if(!isPlatformOwner)return fail("Hanya Owner.",403,origin);const mime=safeText(body.mime_type,50),encoded=safeText(body.file_base64,6500000),ext={"image/jpeg":"jpg","image/png":"png","image/webp":"webp"}[mime];if(!ext||!encoded||encoded.length>6500000)return fail("QRIS harus JPG/PNG/WebP maksimal 4,5 MB.",422,origin);const binary=Uint8Array.from(atob(encoded.replace(/^data:[^,]+,/,"")),c=>c.charCodeAt(0));if(binary.byteLength>4.5*1024*1024)return fail("Ukuran QRIS maksimal 4,5 MB.",413,origin);const path=`qris/${crypto.randomUUID()}.${ext}`;const {error:up}=await admin.storage.from("dlice-payment-assets").upload(path,binary,{contentType:mime,upsert:false});if(up)return fail("Unggahan QRIS gagal.",500,origin);const {error}=await admin.from("payment_settings").upsert({method:"dlice_qris",display_name:"QRIS D’Lice",qr_storage_path:path,is_enabled:false,updated_by:actor.user.id,updated_at:new Date().toISOString()},{onConflict:"method"});if(error)return fail("QRIS diunggah tetapi pengaturan gagal disimpan.",500,origin);return json({ok:true},200,origin);}

  if(action==="admin-retry-payment-notification"){
    const orderId=safeText(body.order_id,80);
    const {data:o}=await admin.from("orders").select("id,branch_id,order_number,created_at,timezone,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,delivery_address,product_subtotal_idr,payment_status").eq("id",orderId).maybeSingle();
    if(!o)return fail("Pesanan tidak ditemukan.",404,origin);if(!await actorCanAccessBranch(o.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);if(o.payment_status!=="paid")return fail("Konfirmasi pembayaran hanya tersedia setelah pembayaran terverifikasi.",409,origin);
    const {data:existing}=await admin.from("notification_log").select("status,message_text,recipient_whatsapp").eq("order_id",orderId).eq("notification_type","payment_verified_whatsapp").order("created_at",{ascending:false}).limit(1).maybeSingle();
    if(existing?.status==="sent")return fail("Konfirmasi pembayaran sudah tercatat terkirim.",409,origin);
    if(existing?.message_text)return json({ok:true,order_id:orderId,notification_type:"payment_verified_whatsapp",whatsapp_url:`https://wa.me/${existing.recipient_whatsapp}?text=${encodeURIComponent(existing.message_text)}`,notification:existing.status,message:"Buka ulang pesan konfirmasi yang tersimpan, lalu tandai terkirim setelah benar-benar dikirim."},200,origin);
    const token=randomToken(),hash=await sha256(token);await admin.from("orders").update({tracking_token_hash:hash}).eq("id",orderId);
    const {data:lines}=await admin.from("order_items").select("product_name_snapshot,quantity,line_total_idr").eq("order_id",orderId);
    const {data:payment}=await admin.from("payment_records").select("method").eq("order_id",orderId).order("created_at",{ascending:false}).limit(1).maybeSingle();
    const code=formatTransactionCode(o.order_number,o.created_at,o.timezone),publicBase=origin&&isAllowedOrigin(origin)?origin:"https://dlice.vercel.app",track=`${publicBase}/track.html?token=${token}`,items=(lines||[]).map(i=>`• ${i.product_name_snapshot} × ${i.quantity} — Rp${Number(i.line_total_idr).toLocaleString("id-ID")}`).join("\\n");
    const msg=`Halo ${o.customer_name}, pembayaran pesanan D’Lice ${code} sudah diverifikasi.\\nTotal diterima: Rp${Number(o.product_subtotal_idr).toLocaleString("id-ID")}\\nMetode: ${payment?.method==="dlice_qris"?"QRIS D’Lice":"Transfer bank"}\\nTanggal: ${o.requested_date}, ${o.requested_time} waktu lokal cabang\\nPenerimaan: ${o.receiving_method==="delivery"?"Delivery — "+(o.delivery_address||""):"Pickup"}\\nDetail:\\n${items}\\n\\nCek progress pesanan melalui tautan tracking pribadi ini: ${track}\\nSimpan tautan ini. Untuk bantuan, kirim kode ${code} ke WhatsApp D’Lice. Terima kasih 💗`;
    const key=`payment-verified:${orderId}`,{error}=await admin.from("notification_log").insert({order_id:orderId,notification_type:"payment_verified_whatsapp",status:"manual_action_required",idempotency_key:key,recipient_whatsapp:o.customer_whatsapp,message_text:msg});
    if(error)return fail("Notifikasi tidak berhasil dibuat. Periksa log sebelum mencoba lagi.",500,origin);
    return json({ok:true,order_id:orderId,notification_type:"payment_verified_whatsapp",whatsapp_url:`https://wa.me/${o.customer_whatsapp}?text=${encodeURIComponent(msg)}`,notification:"manual_action_required",message:"Konfirmasi pembayaran dibuat. Kirim pesan dan tandai terkirim setelah benar-benar terkirim."},200,origin);
  }
  if(action==="admin-mark-notification-sent"){const orderId=safeText(body.order_id,80),type=safeText(body.notification_type,60);if(!orderId||!["payment_verified_whatsapp","customer_order_whatsapp"].includes(type))return fail("Notifikasi tidak valid.",422,origin);const {data:n}=await admin.from("notification_log").select("id,order_id").eq("order_id",orderId).eq("notification_type",type).order("created_at",{ascending:false}).limit(1).maybeSingle();if(!n)return fail("Catatan notifikasi tidak ditemukan.",404,origin);const {data:notificationOrder}=await admin.from("orders").select("branch_id").eq("id",n.order_id).maybeSingle();if(!await actorCanAccessBranch(notificationOrder?.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);const {error}=await admin.from("notification_log").update({status:"sent",sent_at:new Date().toISOString(),attempts:1,last_error:null}).eq("id",n.id);if(error)return fail("Status pengiriman gagal dicatat.",500,origin);await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"mark_whatsapp_notification_sent",entity_type:"notification",entity_id:n.id,metadata:{order_id:orderId,notification_type:type}});return json({ok:true},200,origin);}

  if (action === "admin-list-staff") {
    if (!isPlatformOwner) return fail("Hanya Pemilik yang dapat mengelola izin staf.", 403, origin);
    const { data, error } = await admin.from("admin_profiles").select("user_id,username,role,display_name,is_active,permissions").order("created_at", { ascending: true });
    if (error) return fail("Daftar staf gagal dimuat.", 500, origin);
    return json({ staff: data ?? [], available_permissions: ["orders", "catalog", "finance", "reports", "settings", "staff", "branches", "inventory", "procurement", "pos", "audit", "hr", "production"] }, 200, origin);
  }

  if (action === "admin-create-staff") {
    if (!isPlatformOwner) return fail("Hanya Pemilik yang dapat membuat akun staf.", 403, origin);
    const username = safeText(body.username, 32);
    const displayName = safeText(body.display_name, 120);
    const password = typeof body.password === "string" ? body.password : "";
    const permissions = body.permissions;
    const allowed = new Set(["orders", "catalog", "finance", "reports", "settings", "staff", "branches", "inventory", "procurement", "pos", "audit", "hr", "production"]);
    if (!validUsername(username) || !displayName || password.length < 8 || !Array.isArray(permissions) || permissions.some((p) => typeof p !== "string" || !allowed.has(p))) return fail("Nama pengguna, nama staf, kata sandi (minimal 8 karakter), atau izin akses tidak valid.", 422, origin);
    const passwordCheck = await checkNewPassword(password, origin);
    if (passwordCheck) return passwordCheck;
    const { data: created, error: createError } = await admin.auth.admin.createUser({ email: usernameEmail(username), password, email_confirm: true, user_metadata: { username, display_name: displayName } });
    if (createError || !created.user) return fail(createError?.message?.includes("already") ? "Username sudah digunakan." : "Akun admin gagal dibuat.", 409, origin);
    const normalizedPermissions = [...new Set(permissions)].sort();
    const { data: profileResult, error: profileError } = await admin.rpc("dlice_create_admin_profile_audited", {
      p_actor_user_id: actor.user.id,
      p_target_user_id: created.user.id,
      p_username: username,
      p_display_name: displayName,
      p_permissions: normalizedPermissions,
    });
    if (profileError) return fail("Akun Auth telah dibuat, tetapi hasil penyimpanan profil/audit belum dapat dipastikan. Jangan membuat akun baru; minta pemeriksaan admin.", 500, origin);
    if (!profileResult?.ok) {
      await admin.auth.admin.deleteUser(created.user.id);
      return fail("Profil staf tidak berhasil dibuat; akun Auth sementara dibersihkan.", 409, origin);
    }
    return json({ ok: true, username }, 201, origin);
  }

  if (action === "admin-set-permissions") {
    if (!isPlatformOwner) return fail("Hanya Pemilik yang dapat mengubah izin akses staf.", 403, origin);
    const userId = safeText(body.user_id, 80);
    const permissions = body.permissions;
    const allowed = new Set(["orders", "catalog", "finance", "reports", "settings", "staff", "branches", "inventory", "procurement", "pos", "audit", "hr", "production"]);
    if (!userId || !Array.isArray(permissions) || permissions.some((p) => typeof p !== "string" || !allowed.has(p))) return fail("Daftar izin tidak valid.", 422, origin);
    const { data: target, error: targetError } = await admin.from("admin_profiles").select("user_id,role").eq("user_id", userId).maybeSingle();
    if (targetError || !target) return fail("Akun staf tidak ditemukan.", 404, origin);
    if (target.role === "owner") return fail("Izin akun Pemilik tidak dapat dibatasi melalui panel ini.", 409, origin);
    const normalizedPermissions = [...new Set(permissions)].sort();
    const { data: result, error } = await admin.rpc("dlice_update_admin_permissions_audited", {
      p_actor_user_id: actor.user.id,
      p_target_user_id: userId,
      p_permissions: normalizedPermissions,
    });
    if (error) return fail("Izin akses staf gagal disimpan dan audit tidak dapat dipastikan.", 500, origin);
    if (!result?.ok) return fail("Izin akses staf tidak berhasil diperbarui.", 409, origin);
    return json({ ok: true, permissions: result.permissions }, 200, origin);
  }


if (action === "admin-set-profile-role") {
    if (!isPlatformOwner) return fail("Hanya Pemilik platform yang dapat mengubah klasifikasi profil.", 403, origin);
    const userId = safeText(body.user_id, 80);
    const nextRole = safeText(body.profile_role, 30);
    if (!userId || !["sales_admin", "branch_worker"].includes(nextRole)) {
      return fail("Akun atau jenis profil tidak valid.", 422, origin);
    }
    const { data: target, error: targetError } = await admin
      .from("admin_profiles").select("user_id,role").eq("user_id", userId).maybeSingle();
    if (targetError || !target) return fail("Profil akun tidak ditemukan.", 404, origin);
    if (target.role === "owner") return fail("Profil Owner tidak dapat diubah melalui aksi ini.", 409, origin);

    if (nextRole === "branch_worker") {
      const { data: memberships, error: membershipError } = await admin
        .from("tenant_memberships").select("tenant_id,role")
        .eq("user_id", userId).eq("status", "active");
      if (membershipError) return fail("Keanggotaan tenant belum dapat diverifikasi.", 503, origin);
      if (!memberships?.length || memberships.some((membership: any) => ["tenant_owner", "tenant_admin"].includes(String(membership.role)))) {
        return fail("Profil pekerja memerlukan keanggotaan pekerja aktif dan tidak boleh memiliki peran Tenant Owner/Admin.", 409, origin);
      }
      const { data: assignments, error: assignmentError } = await admin
        .from("branch_assignments")
        .select("id,branch_id,branches(tenant_id)")
        .eq("user_id", userId).eq("employment_status", "active")
        .lte("starts_on", todayDate())
        .or(`ends_on.is.null,ends_on.gte.${todayDate()}`);
      if (assignmentError) return fail("Penugasan cabang belum dapat diverifikasi.", 503, origin);
      const tenantIds = new Set(memberships.map((membership: any) => membership.tenant_id));
      const validAssignments = (assignments || []).filter((assignment: any) => tenantIds.has(assignment.branches?.tenant_id));
      const hasCrossTenantAssignment = (assignments || []).some((assignment: any) => !tenantIds.has(assignment.branches?.tenant_id));
      if (!validAssignments.length || hasCrossTenantAssignment) {
        return fail("Profil pekerja memerlukan assignment aktif pada tenant miliknya dan tidak boleh memiliki assignment lintas tenant.", 409, origin);
      }
    }

    const { data: roleResult, error: roleError } = await admin.rpc("dlice_update_admin_profile_role_audited", {
      p_actor_user_id: actor.user.id,
      p_target_user_id: userId,
      p_next_role: nextRole,
    });
    if (roleError || !roleResult?.ok) return fail("Klasifikasi profil dan audit tidak dapat dipastikan; perubahan dibatalkan.", 409, origin);
    return json({ ok: true, user_id: userId, profile_role: roleResult.profile_role }, 200, origin);
  }

    if (action === "admin-set-active") {
    if (!isPlatformOwner) return fail("Hanya Pemilik yang dapat mengubah status akun staf.", 403, origin);
    const userId = safeText(body.user_id, 80);
    const isActive = body.is_active;
    if (!userId || typeof isActive !== "boolean") return fail("Akun dan status aktif wajib ditentukan.", 422, origin);
    const { data: target, error: targetError } = await admin.from("admin_profiles").select("user_id,role,is_active").eq("user_id", userId).maybeSingle();
    if (targetError || !target) return fail("Akun staf tidak ditemukan.", 404, origin);
    if (target.role === "owner") return fail("Status akun Pemilik tidak dapat diubah melalui aksi ini.", 409, origin);
    const { data: activeResult, error: activeError } = await admin.rpc("dlice_set_admin_profile_active_audited", {
      p_actor_user_id: actor.user.id,
      p_target_user_id: userId,
      p_is_active: isActive,
    });
    if (activeError || !activeResult?.ok) return fail("Status akun staf dan audit tidak dapat dipastikan; perubahan dibatalkan.", 500, origin);
    return json({ ok: true, user_id: userId, is_active: activeResult.is_active }, 200, origin);
  }


  if (action === "admin-reset-staff-password") {
    if (!isPlatformOwner) return fail("Hanya Pemilik yang dapat mereset kata sandi staf.", 403, origin);
    const userId = safeText(body.user_id, 80);
    const password = typeof body.password === "string" ? body.password : "";
    if (!userId || password.length < 8 || password.length > 128) return fail("Akun dan kata sandi 8–128 karakter wajib diberikan.", 422, origin);
    const { data: target, error: targetError } = await admin.from("admin_profiles").select("user_id,role").eq("user_id", userId).maybeSingle();
    if (targetError || !target) return fail("Akun staf tidak ditemukan.", 404, origin);
    if (target.role === "owner") return fail("Kata sandi akun Pemilik tidak dapat diubah melalui aksi staf.", 409, origin);
    const passwordCheck = await checkNewPassword(password, origin);
    if (passwordCheck) return passwordCheck;
    const { data: auditId, error: auditIntentError } = await admin.rpc("dlice_begin_admin_password_reset_audit", {
      p_actor_user_id: actor.user.id,
      p_target_user_id: userId,
    });
    if (auditIntentError || typeof auditId !== "string") {
      return fail("Audit intent reset kata sandi gagal dicatat; kata sandi tidak diubah.", 503, origin);
    }

    const { data: updated, error } = await admin.auth.admin.updateUserById(userId, { password });
    const resetSucceeded = !error && !!updated.user;
    const { data: auditResult, error: auditFinishError } = await admin.rpc("dlice_finish_admin_password_reset_audit", {
      p_actor_user_id: actor.user.id,
      p_audit_log_id: auditId,
      p_succeeded: resetSucceeded,
      p_error_code: resetSucceeded ? null : "auth_admin_update_failed",
    });
    if (auditFinishError || !auditResult?.ok) {
      return fail("Hasil reset kata sandi belum dapat direkonsiliasi; audit intent tetap tersimpan untuk pemulihan.", 500, origin);
    }
    if (!resetSucceeded) return fail("Kata sandi staf gagal diperbarui; kegagalan telah dicatat.", 500, origin);
    return json({ ok: true, user_id: userId }, 200, origin);
  }

  if (action === "admin-list-orders") {
    let query = admin.from("orders").select("id,branch_id,order_number,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,delivery_address,customer_notes,product_subtotal_idr,payment_status,operational_status,created_at,timezone,order_items(product_name_snapshot,quantity,unit_price_idr,line_total_idr),payment_records(id,method,status,amount_idr,proof_storage_path,created_at),notification_log(id,notification_type,status,message_text,recipient_whatsapp,created_at)").order("created_at", { ascending: false }).limit(100);
    if (!isPlatformOwner) {
      let ids: string[];
      try { ids = await actorBranchIds(); } catch { return fail("Penugasan cabang gagal dimuat.", 503, origin); }
      query = ids.length ? query.in("branch_id", ids) : query.eq("branch_id", "00000000-0000-0000-0000-000000000000");
    }
    const { data, error } = await query;
    if (error) return fail("Daftar pesanan gagal dimuat.", 500, origin);
    const orders = (data ?? []).map((order) => ({ ...order, transaction_code: formatTransactionCode(order.order_number, order.created_at, order.timezone) }));
    return json({ orders, role: actor.profile.role, permissions: actor.profile.permissions }, 200, origin);
  }

  if (action === "admin-list-products") {
    const { data, error } = await admin.from("products").select("id,slug,name,description,unit_price_idr,is_active,image_path,category,display_order,badge").order("display_order").order("name");
    if (error) return fail("Katalog gagal dimuat.", 500, origin);
    const products = (data ?? []).map((p) => ({ ...p, image_url: p.image_path ? admin.storage.from("dlice-product-photos").getPublicUrl(p.image_path).data.publicUrl : null }));
    return json({ products }, 200, origin);
  }

  if (action === "admin-upload-product-photo") {
    const mime = safeText(body.mime_type, 50);
    const encoded = safeText(body.file_base64, 6_500_000);
    const extByMime: Record<string, string> = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" };
    if (!extByMime[mime] || !encoded || encoded.length > 6_500_000) return fail("Foto harus JPG, PNG, atau WebP dan maksimal 4,5 MB.", 422, origin);
    const binary = Uint8Array.from(atob(encoded.replace(/^data:[^,]+,/, "")), (ch) => ch.charCodeAt(0));
    if (binary.byteLength > 4_500_000) return fail("Ukuran foto maksimal 4,5 MB.", 413, origin);
    const path = `products/${crypto.randomUUID()}.${extByMime[mime]}`;
    const { error } = await admin.storage.from("dlice-product-photos").upload(path, binary, { contentType: mime, upsert: false });
    if (error) return fail("Foto gagal diunggah ke Storage.", 500, origin);
    const image_url = admin.storage.from("dlice-product-photos").getPublicUrl(path).data.publicUrl;
    await admin.from("admin_audit_logs").insert({ actor_user_id: actor.user.id, action: "upload_product_photo", entity_type: "product_photo", entity_id: path, metadata: { mime_type: mime, size_bytes: binary.byteLength } });
    return json({ image_path: path, image_url }, 201, origin);
  }

  if (action === "admin-save-product") {
    const id = safeText(body.id, 80);
    const name = safeText(body.name, 120);
    const slug = safeText(body.slug, 80).toLowerCase();
    const description = safeText(body.description, 1000);
    const category = safeText(body.category, 20);
    const displayOrder = Number(body.display_order);
    const priceRaw = body.unit_price_idr;
    const price = priceRaw === null || priceRaw === "" || typeof priceRaw === "undefined" ? null : Number(priceRaw);
    const isActive = body.is_active === true;
    const badge = safeText(body.badge, 60) || null;
    const imagePath = safeText(body.image_path, 500) || null;
    if (name.length < 2 || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug) || !["fresh","pastry","other"].includes(category) || !Number.isInteger(displayOrder) || displayOrder < 0 || (price !== null && (!Number.isInteger(price) || price < 0 || price > 100000000))) return fail("Periksa nama menu, kode internal, kategori, urutan, dan harga.", 422, origin);
    if (imagePath && (!imagePath.startsWith("products/") || imagePath.includes(".."))) return fail("Referensi foto tidak valid.", 422, origin);
    const values = { name, slug, description: description || null, category, display_order: displayOrder, unit_price_idr: price, is_active: isActive, badge, image_path: imagePath };
    let saved;
    let error;
    if (id) {
      const result = await admin.from("products").update(values).eq("id", id).select("id,slug,name,description,unit_price_idr,is_active,image_path,category,display_order,badge").maybeSingle();
      saved = result.data; error = result.error;
    } else {
      const result = await admin.from("products").insert(values).select("id,slug,name,description,unit_price_idr,is_active,image_path,category,display_order,badge").maybeSingle();
      saved = result.data; error = result.error;
    }
    if (error || !saved) return fail(error?.code === "23505" ? "Slug produk sudah digunakan." : "Produk gagal disimpan.", error?.code === "23505" ? 409 : 500, origin);
    await admin.from("admin_audit_logs").insert({ actor_user_id: actor.user.id, action: id ? "update_product_catalog" : "create_product_catalog", entity_type: "product", entity_id: saved.id, metadata: { slug, category, display_order: displayOrder, is_active: isActive } });
    return json({ product: { ...saved, image_url: saved.image_path ? admin.storage.from("dlice-product-photos").getPublicUrl(saved.image_path).data.publicUrl : null } }, 200, origin);
  }

  if (action === "admin-configure-product") {
    if (!await hasHQPermission("catalog")) return fail("Pengaturan kapasitas produk global memerlukan izin Catalog Head Office.", 403, origin);
    const slug = safeText(body.slug, 80);
    const price = Number(body.unit_price_idr);
    const date = safeText(body.service_date, 10);
    const capacity = Number(body.capacity);
    if (!/^[a-z0-9-]+$/.test(slug) || !Number.isInteger(price) || price < 0 || !/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isInteger(capacity) || capacity < 0 || capacity > 10000) return fail("Harga, tanggal, atau batas jumlah item tidak valid.", 422, origin);
    const { data: product, error: pError } = await admin.from("products").update({ unit_price_idr: price }).eq("slug", slug).select("id").single();
    if (pError || !product) return fail("Menu tidak ditemukan.", 404, origin);
    const { error: cError } = await admin.from("product_capacity").upsert({ product_id: product.id, service_date: date, capacity }, { onConflict: "product_id,service_date" });
    if (cError) return fail("Kapasitas gagal disimpan.", 500, origin);
    await admin.from("admin_audit_logs").insert({ actor_user_id: actor.user.id, action: "configure_product_capacity_price", entity_type: "product", entity_id: product.id, metadata: { slug, unit_price_idr: price, service_date: date, capacity } });
    return json({ ok: true }, 200, origin);
  }

  if (action === "admin-proof-url") {
    const path = safeText(body.proof_storage_path, 500);
    if (!path || path.includes("..")) return fail("Path bukti tidak valid.", 422, origin);
    const { data: proofRows, error: proofLookupError } = await admin.from("payment_records").select("order_id,orders(branch_id)").eq("proof_storage_path", path).limit(2);
    if (proofLookupError || !proofRows?.length) return fail("Bukti pembayaran tidak ditemukan.", 404, origin);
    if (!await actorCanAccessBranch((proofRows[0] as any).orders?.branch_id)) return fail("Akses cabang tidak diizinkan.", 403, origin);
    const { data, error } = await admin.storage.from("dlice-payment-proofs").createSignedUrl(path, 60);
    if (error || !data?.signedUrl) return fail("Bukti tidak dapat dibuka.", 404, origin);
    await admin.from("admin_audit_logs").insert({ actor_user_id: actor.user.id, action: "view_payment_proof", entity_type: "payment_proof", entity_id: path, metadata: {} });
    return json({ url: data.signedUrl }, 200, origin);
  }

  if (action === "admin-update-status") {
    const orderId = safeText(body.order_id, 80);
    const next = safeText(body.operational_status, 40);
    const allowed = ["received","confirmed","preparing","ready_for_pickup","waiting_for_courier","in_delivery","completed","cancelled","delivery_issue"];
    if (!allowed.includes(next)) return fail("Status pesanan tidak valid.", 422, origin);
    const { data: oldOrder } = await admin.from("orders").select("branch_id,operational_status,payment_status").eq("id", orderId).maybeSingle();
    if (!oldOrder) return fail("Pesanan tidak ditemukan.", 404, origin);
    if (!await actorCanAccessBranch(oldOrder.branch_id)) return fail("Akses cabang tidak diizinkan.", 403, origin);
    if (["preparing","ready_for_pickup","waiting_for_courier","in_delivery","completed"].includes(next) && oldOrder.payment_status !== "paid") {
      return fail("Pesanan belum dapat diproses. Customer wajib mengunggah bukti pembayaran dan owner/admin harus memverifikasinya terlebih dahulu.", 409, origin);
    }
    if(oldOrder.payment_status==="paid"&&next!==oldOrder.operational_status){const {data:n}=await admin.from("notification_log").select("status").eq("order_id",orderId).eq("notification_type","payment_verified_whatsapp").order("created_at",{ascending:false}).limit(1).maybeSingle();if(!n||n.status!=="sent")return fail("Kirim konfirmasi pembayaran beserta tutorial tracking, lalu tandai terkirim sebelum memperbarui status.",409,origin);}
    if(["cancelled","delivery_issue"].includes(next)&&safeText(body.reason,500).length<4)return fail("Alasan wajib diisi untuk pembatalan/kendala.",422,origin);
    const { data: applied, error } = await admin.rpc("admin_apply_operational_status_change", { p_order_id: orderId, p_actor_user_id: actor.user.id, p_next_status: next, p_reason: safeText(body.reason,500) });
    if (error || applied !== true) return fail("Status tidak berubah. Periksa pembayaran, notifikasi konfirmasi, alasan, dan status terbaru.", 409, origin);
    return json({ ok: true }, 200, origin);
  }


  if (action === "admin-verify-payment") {
    const orderId=safeText(body.order_id,80),result=safeText(body.result,20),note=safeText(body.note,500);if(!["paid","rejected"].includes(result))return fail("Hasil verifikasi tidak valid.",422,origin);
    const {data:o}=await admin.from("orders").select("id,branch_id,order_number,created_at,timezone,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,delivery_address,product_subtotal_idr,payment_status").eq("id",orderId).maybeSingle();if(!o)return fail("Pesanan tidak ditemukan.",404,origin);if(!await actorCanAccessBranch(o.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);if(["paid","refunded"].includes(o.payment_status))return fail("Status pembayaran tidak dapat ditimpa.",409,origin);
    const {data:p}=await admin.from("payment_records").select("id,proof_storage_path,method").eq("order_id",orderId).eq("status","pending_verification").order("created_at",{ascending:false}).limit(1).maybeSingle();if(!p)return fail("Tidak ada pembayaran menunggu verifikasi.",409,origin);if(result==="paid"&&!p.proof_storage_path)return fail("Bukti pembayaran wajib tersedia.",409,origin);
    const {data:applied,error:applyError}=await admin.rpc("admin_apply_payment_verification",{p_order_id:orderId,p_payment_id:p.id,p_actor_user_id:actor.user.id,p_result:result,p_note:note});if(applyError||applied!==true)return fail("Verifikasi gagal atau pesanan sudah berubah. Muat ulang pesanan dan periksa statusnya.",409,origin);
    if(result==="paid"){const token=randomToken(),hash=await sha256(token);await admin.from("orders").update({tracking_token_hash:hash}).eq("id",orderId);const {data:lines}=await admin.from("order_items").select("product_name_snapshot,quantity,line_total_idr").eq("order_id",orderId);const items=(lines||[]).map(i=>`• ${i.product_name_snapshot} × ${i.quantity} — Rp${Number(i.line_total_idr).toLocaleString("id-ID")}`).join("\n");const code=formatTransactionCode(o.order_number,o.created_at,o.timezone),publicBase=origin&&isAllowedOrigin(origin)?origin:"https://dlice.vercel.app",track=`${publicBase}/track.html?token=${token}`,method=p.method==="dlice_qris"?"QRIS D’Lice":"Transfer bank";const msg=`Halo ${o.customer_name}, pembayaran pesanan D’Lice ${code} sudah diverifikasi.\nTotal diterima: Rp${Number(o.product_subtotal_idr).toLocaleString("id-ID")}\nMetode: ${method}\nTanggal: ${o.requested_date}, ${o.requested_time} waktu lokal cabang\nPenerimaan: ${o.receiving_method==="delivery"?"Delivery — "+(o.delivery_address||""):"Pickup"}\nDetail:\n${items}\n\nTutorial cek progress seperti ojol/logistik: buka tautan pribadi berikut, lihat status terakhir dan waktu pembaruan, lalu cek riwayat status. Simpan tautan ini dan jangan bagikan ke orang lain:\n${track}\nJika bermasalah, kirim kode ${code} ke WhatsApp D’Lice. Terima kasih 💗`;const key=`payment-verified:${orderId}`;const {error:le}=await admin.from("notification_log").upsert({order_id:orderId,notification_type:"payment_verified_whatsapp",status:"manual_action_required",idempotency_key:key,recipient_whatsapp:o.customer_whatsapp,message_text:msg},{onConflict:"idempotency_key",ignoreDuplicates:true});if(le)return fail("Pembayaran sudah terverifikasi, tetapi notifikasi gagal dicatat. Retry dari panel staf.",500,origin);return json({ok:true,order_id:orderId,notification_type:"payment_verified_whatsapp",whatsapp_url:`https://wa.me/${o.customer_whatsapp}?text=${encodeURIComponent(msg)}`,notification:"manual_action_required",message:"Kirim konfirmasi beserta tautan tracking, lalu tandai pengiriman berhasil."},200,origin);}
    return json({ok:true,message:"Pembayaran ditolak; riwayat, audit, dan kapasitas diperbarui dalam satu transaksi."},200,origin);
  }


  // Multi-branch POS/ERP actions. All writes run through this authenticated server endpoint.
  const isOwner = isPlatformOwner;
  const hasPerm = (p: string) => isOwner || actor.profile.permissions.includes("*") || actor.profile.permissions.includes(p);
  const tenantIdsForActor = async (): Promise<string[]> => {
    const {data,error}=await admin.from("tenant_memberships").select("tenant_id").eq("user_id",actor.user.id).eq("status","active");
    if(error)throw new Error("Keanggotaan tenant gagal dimuat.");
    return [...new Set((data||[]).map((x:{tenant_id:string})=>x.tenant_id))];
  };
  const branchAccess = async (branchId: string): Promise<boolean> => {
    const {data:branch,error:branchError}=await admin.from("branches").select("tenant_id").eq("id",branchId).maybeSingle();
    if(branchError||!branch)return false;
    const {data:membership,error:membershipError}=await admin.from("tenant_memberships").select("role").eq("tenant_id",branch.tenant_id).eq("user_id",actor.user.id).eq("status","active").maybeSingle();
    if(membershipError||!membership)return false;
    if(["tenant_owner","tenant_admin"].includes(String(membership.role)))return true;
    const {data,error}=await admin.from("branch_assignments").select("id").eq("branch_id",branchId).eq("user_id",actor.user.id).eq("employment_status","active").lte("starts_on",todayDate()).or(`ends_on.is.null,ends_on.gte.${todayDate()}`).limit(1);
    return !error&&!!data?.length;
  };
  const branchIdsForActor = async (): Promise<string[]> => {
    const {data:memberships,error:membershipError}=await admin.from("tenant_memberships").select("tenant_id,role").eq("user_id",actor.user.id).eq("status","active");
    if(membershipError)throw new Error("Keanggotaan tenant gagal dimuat.");
    const membershipsList=memberships||[],tenantIds=[...new Set(membershipsList.map((x:any)=>x.tenant_id))];
    if(!tenantIds.length)return [];
    const ownerTenantIds=membershipsList.filter((x:any)=>["tenant_owner","tenant_admin"].includes(String(x.role))).map((x:any)=>x.tenant_id);
    const owned=ownerTenantIds.length?await admin.from("branches").select("id").in("tenant_id",ownerTenantIds):{data:[],error:null};
    if(owned.error)throw new Error("Cabang tenant gagal dimuat.");
    const assigned=await admin.from("branch_assignments").select("branch_id").eq("user_id",actor.user.id).eq("employment_status","active").lte("starts_on",todayDate()).or(`ends_on.is.null,ends_on.gte.${todayDate()}`);
    if(assigned.error)throw new Error("Penugasan cabang gagal dimuat.");
    const assignedIds=[...new Set((assigned.data||[]).map((x:any)=>x.branch_id))];
    let assignedInTenant:string[]=[];
    if(assignedIds.length){
      const rows=await admin.from("branches").select("id,tenant_id").in("id",assignedIds).in("tenant_id",tenantIds);
      if(rows.error)throw new Error("Pemetaan tenant-cabang gagal dimuat.");
      assignedInTenant=(rows.data||[]).map((x:any)=>x.id);
    }
    return [...new Set([...(owned.data||[]).map((x:any)=>x.id),...assignedInTenant])];
  };

  const hasFinanceHQ = async (): Promise<boolean> => {
    if (isOwner) return true;
    if (!hasPerm("finance")) return false;
    const {data,error}=await admin.from("branch_assignments").select("job_positions(is_head_office,default_permissions)").eq("user_id",actor.user.id).eq("employment_status","active");
    return !error && (data||[]).some((x:any)=>x.job_positions?.is_head_office===true && Array.isArray(x.job_positions?.default_permissions) && x.job_positions.default_permissions.includes("finance"));
  };



  // CRM commands are intentionally Platform Owner-only until the tenant isolation
  // release gate is satisfied. They never accept a client-provided user identity.
  const crmActions = new Set([
    "erp-crm-list-customers",
    "erp-crm-create-customer",
    "erp-crm-record-consent",
    "erp-crm-list-loyalty-ledger",
    "erp-crm-append-loyalty-entry",
    "erp-crm-list-rewards",
    "erp-crm-create-reward",
    "erp-crm-activate-reward",
    "erp-crm-redeem-reward",
    "erp-crm-list-campaigns",
    "erp-crm-create-campaign",
    "erp-crm-approve-campaign",
    "erp-crm-prepare-campaign-audience",
  ]);
  if (crmActions.has(action)) {
    if (!isPlatformOwner) return fail("Modul CRM hanya dapat dikelola Platform Owner sampai validasi isolasi tenant selesai.", 423, origin);
    const tenantId = safeText(body.tenant_id, 64);
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(tenantId)) return fail("Tenant tidak valid.", 422, origin);
    const { data: tenant, error: tenantError } = await admin.from("tenants").select("id,status").eq("id", tenantId).maybeSingle();
    if (tenantError) return fail("Tenant belum dapat diverifikasi.", 503, origin);
    if (!tenant) return fail("Tenant tidak ditemukan.", 404, origin);

  if (action === "erp-crm-list-customers") {
      const search = safeText(body.search, 80).replace(/[%,()]/g, " ");
      let query = admin.from("crm_customers")
        .select("id,tenant_id,branch_id,display_name,phone_e164,email_normalized,status,marketing_status,created_at,updated_at")
        .eq("tenant_id", tenantId).neq("status", "merged")
        .order("created_at", { ascending: false }).limit(100);
      if (search) query = query.or("display_name.ilike.%"+search+"%,phone_e164.ilike.%"+search+"%,email_normalized.ilike.%"+search+"%");
      const { data, error } = await query;
      if (error) return fail("Data CRM belum tersedia. Pastikan skema CRM sudah diterapkan pada batch migrasi final.", 503, origin);
      return json({ customers: data || [] }, 200, origin);
    }

    if (action === "erp-crm-create-customer") {
      const displayName = safeText(body.display_name, 120);
      const rawPhone = safeText(body.phone, 40);
      const digits = rawPhone.replace(/[^0-9]/g, "");
      const normalizedDigits = digits.startsWith("0") ? "62"+digits.slice(1) : digits.startsWith("8") ? "62"+digits : digits;
      const phone = normalizedDigits ? "+"+normalizedDigits : null;
      const email = safeText(body.email, 254).toLowerCase() || null;
      const branchId = safeText(body.branch_id, 64) || null;
      if (!phone && !email) return fail("Nomor telepon atau email wajib diisi.", 422, origin);
      if (phone && !/^\+[1-9][0-9]{7,14}$/.test(phone)) return fail("Nomor telepon tidak valid.", 422, origin);
      if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return fail("Email tidak valid.", 422, origin);
      if (branchId) {
        const { data: branch, error: branchError } = await admin.from("branches").select("id").eq("id", branchId).eq("tenant_id", tenantId).maybeSingle();
        if (branchError) return fail("Cabang belum dapat diverifikasi.", 503, origin);
        if (!branch) return fail("Cabang tidak termasuk tenant yang dipilih.", 403, origin);
      }
      const { data, error } = await admin.from("crm_customers").insert({
        tenant_id: tenantId, branch_id: branchId, display_name: displayName || null,
        phone_e164: phone, email_normalized: email, status: "prospect",
        marketing_status: "unknown", created_by: actor.user.id,
      }).select("id,tenant_id,branch_id,display_name,phone_e164,email_normalized,status,marketing_status,created_at").single();
      if (error) return fail(error.code === "23505" ? "Pelanggan dengan nomor telepon/email tersebut sudah terdaftar pada tenant ini." : "Pelanggan belum dapat disimpan.", error.code === "23505" ? 409 : 503, origin);
      return json({ customer: data }, 201, origin);
    }

    if (action === "erp-crm-record-consent") {
      const customerId = safeText(body.customer_id, 64);
      const purpose = safeText(body.purpose, 40);
      const channel = safeText(body.channel, 20);
      const decision = safeText(body.decision, 20);
      const policyVersion = safeText(body.policy_version, 80);
      const idempotencyKey = safeText(body.idempotency_key, 120);
      const allowed = {
        marketing_email: ["email"], marketing_sms: ["sms"], marketing_whatsapp: ["whatsapp"],
        personalization: ["pos","web","staff"],
      } as Record<string,string[]>;
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(customerId) ||
          !allowed[purpose]?.includes(channel) || !["granted","withdrawn"].includes(decision) ||
          !policyVersion || idempotencyKey.length < 8) return fail("Catatan consent tidak valid.", 422, origin);
      const { data: customer, error: customerError } = await admin.from("crm_customers").select("id")
        .eq("tenant_id", tenantId).eq("id", customerId).maybeSingle();
      if (customerError) return fail("Pelanggan belum dapat diverifikasi.", 503, origin);
      if (!customer) return fail("Pelanggan tidak ditemukan pada tenant ini.", 404, origin);
      const { data, error } = await admin.from("crm_customer_consent_events").insert({
        tenant_id: tenantId, customer_id: customerId, purpose, channel, decision,
        policy_version: policyVersion, idempotency_key: idempotencyKey,
        occurred_at: new Date().toISOString(), actor_user_id: actor.user.id,
      }).select("id,customer_id,purpose,channel,decision,policy_version,occurred_at").single();
      if (error) return fail(error.code === "23505" ? "Kunci idempotensi consent sudah digunakan." : "Consent belum dapat dicatat.", error.code === "23505" ? 409 : 503, origin);
      return json({ consent_event: data }, 201, origin);
    }

    if (action === "erp-crm-list-loyalty-ledger") {
      const customerId = safeText(body.customer_id, 64);
      const { data: customer, error: customerError } = await admin.from("crm_customers").select("id")
        .eq("tenant_id", tenantId).eq("id", customerId).maybeSingle();
      if (customerError) return fail("Pelanggan belum dapat diverifikasi.", 503, origin);
      if (!customer) return fail("Pelanggan tidak ditemukan pada tenant ini.", 404, origin);
      const { data, error } = await admin.from("crm_loyalty_ledger")
        .select("id,entry_kind,points,idempotency_key,source_reference,reverses_entry_id,created_at")
        .eq("tenant_id", tenantId).eq("customer_id", customerId).order("created_at", { ascending: false }).limit(200);
      if (error) return fail("Ledger loyalty belum tersedia. Pastikan skema CRM sudah diterapkan.", 503, origin);
      const balance = (data || []).reduce((sum: number, row: any) => sum + Number(row.points || 0), 0);
      return json({ entries: data || [], balance }, 200, origin);
    }

    if (action === "erp-crm-append-loyalty-entry") {
      const customerId = safeText(body.customer_id, 64);
      const entryKind = safeText(body.entry_kind, 20);
      const points = Number(body.points);
      const idempotencyKey = safeText(body.idempotency_key, 120);
      const sourceReference = safeText(body.source_reference, 160);
      const reversesEntryId = safeText(body.reverses_entry_id, 64) || null;
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(customerId) ||
          !["earn","redeem","adjustment","reversal"].includes(entryKind) ||
          !Number.isSafeInteger(points) || points === 0 || idempotencyKey.length < 8 || !sourceReference) {
        return fail("Perintah poin loyalty tidak valid.", 422, origin);
      }
      const { data, error } = await admin.rpc("crm_append_loyalty_entry", {
        p_tenant_id: tenantId, p_customer_id: customerId, p_entry_kind: entryKind,
        p_points: points, p_idempotency_key: idempotencyKey, p_source_reference: sourceReference,
        p_reverses_entry_id: reversesEntryId, p_actor_user_id: actor.user.id,
      });
      if (error) {
        const duplicate = error.code === "23505";
        const insufficient = String(error.message || "").includes("INSUFFICIENT_POINTS");
        return fail(duplicate ? "Perintah loyalty duplikat." : insufficient ? "Saldo poin tidak mencukupi." : "Perintah loyalty ditolak.", duplicate || insufficient ? 409 : 422, origin);
      }
      return json({ ledger: data }, 201, origin);
    }

    if (action === "erp-crm-list-rewards") {
      const { data, error } = await admin.from("crm_rewards")
        .select("id,name,description,points_cost,starts_at,expires_at,status,created_at")
        .eq("tenant_id", tenantId).order("created_at", { ascending: false }).limit(100);
      if (error) return fail("Daftar reward belum tersedia. Pastikan skema CRM sudah diterapkan.", 503, origin);
      return json({ rewards: data || [] }, 200, origin);
    }

    if (action === "erp-crm-activate-reward") {
      const rewardId = safeText(body.reward_id, 64);
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(rewardId)) return fail("Reward tidak valid.", 422, origin);
      const { data: reward, error: rewardError } = await admin.from("crm_rewards").select("id,status,starts_at,expires_at")
        .eq("tenant_id", tenantId).eq("id", rewardId).maybeSingle();
      if (rewardError) return fail("Reward belum dapat diverifikasi.", 503, origin);
      if (!reward || !["draft","paused"].includes(reward.status)) return fail("Status reward tidak dapat diaktifkan.", 409, origin);
      if (Date.parse(reward.expires_at) <= Date.now()) return fail("Masa berlaku reward sudah berakhir.", 422, origin);
      const { data, error } = await admin.from("crm_rewards").update({ status: "active", updated_at: new Date().toISOString() })
        .eq("tenant_id", tenantId).eq("id", rewardId).select("id,name,status,starts_at,expires_at").single();
      if (error) return fail("Reward belum dapat diaktifkan.", 503, origin);
      return json({ reward: data }, 200, origin);
    }

    if (action === "erp-crm-redeem-reward") {
      const customerId = safeText(body.customer_id, 64);
      const rewardId = safeText(body.reward_id, 64);
      const idempotencyKey = safeText(body.idempotency_key, 120);
      const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      if (!uuidPattern.test(customerId) || !uuidPattern.test(rewardId) || idempotencyKey.length < 8) return fail("Permintaan penukaran reward tidak valid.", 422, origin);
      const { data, error } = await admin.rpc("crm_redeem_reward", {
        p_tenant_id: tenantId, p_customer_id: customerId, p_reward_id: rewardId,
        p_idempotency_key: idempotencyKey, p_actor_user_id: actor.user.id,
      });
      if (error) {
        const duplicate = error.code === "23505";
        const insufficient = String(error.message || "").includes("INSUFFICIENT_POINTS");
        const inactive = String(error.message || "").includes("REWARD_NOT_ACTIVE");
        return fail(duplicate ? "Permintaan penukaran sudah pernah diproses." : insufficient ? "Saldo poin tidak mencukupi." : inactive ? "Reward tidak aktif atau sudah kedaluwarsa." : "Penukaran reward ditolak.", duplicate || insufficient || inactive ? 409 : 422, origin);
      }
      return json({ voucher: data }, 201, origin);
    }

    if(action==="erp-crm-list-campaigns"){
      const {data,error}=await admin.from("crm_marketing_campaigns").select("id,name,channel,purpose,subject,status,scheduled_at,approved_by,approved_at,created_by,created_at,crm_campaign_recipients(id,status)").eq("tenant_id",tenantId).order("created_at",{ascending:false}).limit(100);
      if(error)return fail("Campaign CRM belum tersedia. Terapkan migrasi pada batch final.",503,origin);
      return json({campaigns:data||[]},200,origin);
    }
    if(action==="erp-crm-create-campaign"){
      const name=safeText(body.name,120),channel=safeText(body.channel,20),subject=safeText(body.subject,200)||null,template=safeText(body.message_template,10000);
      const purpose=channel==="email"?"marketing_email":channel==="sms"?"marketing_sms":channel==="whatsapp"?"marketing_whatsapp":"";
      if(name.length<2||!purpose||template.length<1)return fail("Definisi campaign atau channel tidak valid.",422,origin);
      const {data,error}=await admin.from("crm_marketing_campaigns").insert({tenant_id:tenantId,name,channel,purpose,subject,message_template:template,status:"draft",created_by:actor.user.id})
       .select("id,name,channel,purpose,status,created_at").single();
      if(error)return fail("Campaign CRM gagal disimpan.",503,origin);
      await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"crm.campaign.created",entity_type:"crm_marketing_campaign",entity_id:data.id,metadata:{tenant_id:tenantId,channel,purpose}});
      return json({campaign:data},201,origin);
    }
    if(action==="erp-crm-approve-campaign"||action==="erp-crm-prepare-campaign-audience"){
      const campaignId=safeText(body.campaign_id,64);
      if(!/^[0-9a-f-]{36}$/i.test(campaignId))return fail("Campaign tidak valid.",422,origin);
      const rpc=action==="erp-crm-approve-campaign"?"crm_approve_campaign":"crm_prepare_campaign_audience";
      const args=action==="erp-crm-approve-campaign"?{p_tenant_id:tenantId,p_campaign_id:campaignId,p_actor_user_id:actor.user.id}:{p_tenant_id:tenantId,p_campaign_id:campaignId,p_actor_user_id:actor.user.id};
      const {data,error}=await admin.rpc(rpc,args);
      if(error)return fail(action==="erp-crm-approve-campaign"?"Approval campaign ditolak. Pembuat tidak boleh menyetujui campaign sendiri.":"Audience belum dapat disiapkan. Campaign harus disetujui dan consent pelanggan masih aktif.",409,origin);
      return json({campaign:data},200,origin);
    }

    if (action === "erp-crm-create-reward") {
      const name = safeText(body.name, 120);
      const description = safeText(body.description, 1000) || null;
      const pointsCost = Number(body.points_cost);
      const startsAt = safeText(body.starts_at, 40);
      const expiresAt = safeText(body.expires_at, 40);
      if (!name || !Number.isSafeInteger(pointsCost) || pointsCost <= 0 ||
          !startsAt || !expiresAt || Number.isNaN(Date.parse(startsAt)) ||
          Number.isNaN(Date.parse(expiresAt)) || Date.parse(expiresAt) <= Date.parse(startsAt)) {
        return fail("Definisi reward tidak valid.", 422, origin);
      }
      const { data, error } = await admin.from("crm_rewards").insert({
        tenant_id: tenantId, name, description, points_cost: pointsCost,
        starts_at: startsAt, expires_at: expiresAt, status: "draft", created_by: actor.user.id,
      }).select("id,name,points_cost,starts_at,expires_at,status").single();
      if (error) return fail("Reward belum dapat disimpan.", 503, origin);
      return json({ reward: data }, 201, origin);
    }
  }

  // HR attendance reads/writes are branch-scoped. The branch tenant is always
  // derived from the database; no caller-supplied tenant_id is trusted.
  const hrActions = new Set([
    "erp-hr-list-employees",
    "erp-hr-list-attendance",
    "erp-hr-record-attendance",
    "erp-hr-list-schedules",
    "erp-hr-create-schedule",
    "erp-hr-list-leave-requests",
    "erp-hr-create-leave-request",
    "erp-hr-confirm-leave-coverage",
    "erp-hr-review-leave-request",
    "erp-hr-list-timesheets",
    "erp-hr-generate-timesheet",
    "erp-hr-submit-timesheet",
    "erp-hr-approve-timesheet",
  ]);
  if (hrActions.has(action)) {
    if (!isPlatformOwner) return fail("Modul HR sementara dibatasi untuk Platform Owner sampai validasi isolasi tenant selesai.", 423, origin);
    const branchId = safeText(body.branch_id, 64);
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(branchId)) return fail("Cabang tidak valid.", 422, origin);
    if (!(await actorCanAccessBranch(branchId))) return fail("Akses cabang tidak diizinkan.", 403, origin);
    const { data: branch, error: branchError } = await admin.from("branches").select("id,tenant_id,status").eq("id", branchId).maybeSingle();
    if (branchError) return fail("Cabang belum dapat diverifikasi.", 503, origin);
    if (!branch || !branch.tenant_id) return fail("Cabang tidak ditemukan.", 404, origin);

    if (action === "erp-hr-list-employees") {
      const { data, error } = await admin.from("branch_assignments")
        .select("user_id,job_position_id,starts_on,ends_on,employment_status,job_positions(title),admin_profiles(display_name,username,is_active)")
        .eq("branch_id", branchId).eq("employment_status", "active").lte("starts_on", todayDate())
        .or("ends_on.is.null,ends_on.gte."+todayDate()).order("starts_on", { ascending: false });
      if (error) return fail("Daftar staf cabang belum dapat dimuat.", 503, origin);
      const employees = (data || []).filter((row: any) => row.admin_profiles?.is_active === true).map((row: any) => ({
        user_id: row.user_id, display_name: row.admin_profiles?.display_name || row.admin_profiles?.username || row.user_id,
        username: row.admin_profiles?.username || null, job_position_id: row.job_position_id,
        job_title: row.job_positions?.title || null, starts_on: row.starts_on,
      }));
      return json({ employees }, 200, origin);
    }

    if (action === "erp-hr-list-attendance") {
      const { data, error } = await admin.from("hr_attendance_events")
        .select("id,employee_user_id,event_type,occurred_at,source,notes,idempotency_key")
        .eq("tenant_id", branch.tenant_id).eq("branch_id", branchId)
        .order("occurred_at", { ascending: false }).limit(150);
      if (error) return fail("Data absensi belum tersedia. Pastikan skema HR diterapkan pada batch migrasi final.", 503, origin);
      return json({ attendance: data || [] }, 200, origin);
    }

    if(action==="erp-hr-list-schedules"){
      const {data,error}=await admin.from("hr_shift_schedules").select("id,employee_user_id,job_position_id,starts_at,ends_at,status,notes,job_positions(title)").eq("tenant_id",branch.tenant_id).eq("branch_id",branchId).gte("starts_at",new Date(Date.now()-7*86400000).toISOString()).order("starts_at").limit(200);
      if(error)return fail("Roster belum tersedia. Terapkan migrasi HR pada batch final.",503,origin);
      return json({schedules:data||[]},200,origin);
    }
    if(action==="erp-hr-create-schedule"){
      const employeeId=safeText(body.employee_user_id,64),positionId=safeText(body.job_position_id,64),startsAt=safeText(body.starts_at,40),endsAt=safeText(body.ends_at,40),notes=safeText(body.notes,500)||null;
      if(!/^[0-9a-f-]{36}$/i.test(employeeId)||!/^[0-9a-f-]{36}$/i.test(positionId)||!startsAt||!endsAt||Number.isNaN(Date.parse(startsAt))||Number.isNaN(Date.parse(endsAt))||Date.parse(endsAt)<=Date.parse(startsAt))return fail("Jadwal shift tidak valid.",422,origin);
      const {data,error}=await admin.rpc("hr_create_shift_schedule",{p_tenant_id:branch.tenant_id,p_branch_id:branchId,p_employee_user_id:employeeId,p_job_position_id:positionId,p_starts_at:startsAt,p_ends_at:endsAt,p_created_by:actor.user.id,p_notes:notes});
      if(error)return fail("Jadwal ditolak. Periksa penugasan aktif dan konflik shift.",409,origin);
      return json({schedule:data},201,origin);
    }
    if(action==="erp-hr-list-timesheets"){
      const {data,error}=await admin.from("hr_timesheets").select("id,employee_user_id,period_start,period_end,total_minutes,status,submitted_at,approved_by,approved_at,attendance_event_ids").eq("tenant_id",branch.tenant_id).eq("branch_id",branchId).order("period_start",{ascending:false}).limit(100);
      if(error)return fail("Timesheet belum tersedia. Terapkan migrasi HR pada batch final.",503,origin);
      return json({timesheets:data||[]},200,origin);
    }
    if(action==="erp-hr-generate-timesheet"){
      const employeeId=safeText(body.employee_user_id,64),start=safeText(body.period_start,10),end=safeText(body.period_end,10);
      if(!/^[0-9a-f-]{36}$/i.test(employeeId)||!/^\d{4}-\d{2}-\d{2}$/.test(start)||!/^\d{4}-\d{2}-\d{2}$/.test(end))return fail("Periode timesheet tidak valid.",422,origin);
      const {data,error}=await admin.rpc("hr_generate_timesheet",{p_tenant_id:branch.tenant_id,p_branch_id:branchId,p_employee_user_id:employeeId,p_period_start:start,p_period_end:end,p_created_by:actor.user.id});
      if(error)return fail("Timesheet gagal dibuat. Pastikan semua event absensi berurutan dan memiliki clock-out.",409,origin);
      return json({timesheet:data},201,origin);
    }
    if(action==="erp-hr-submit-timesheet"||action==="erp-hr-approve-timesheet"){
      const timesheetId=safeText(body.timesheet_id,64);
      if(!/^[0-9a-f-]{36}$/i.test(timesheetId))return fail("Timesheet tidak valid.",422,origin);
      const rpc=action==="erp-hr-submit-timesheet"?"hr_submit_timesheet":"hr_approve_timesheet";
      const {data,error}=await admin.rpc(rpc,{p_timesheet_id:timesheetId,p_actor_user_id:actor.user.id});
      if(error)return fail(action==="erp-hr-submit-timesheet"?"Hanya karyawan pemilik timesheet yang dapat mengirim untuk approval.":"Approval ditolak. Approver harus berbeda dari karyawan.",409,origin);
      return json({timesheet:data},200,origin);
    }
    if(action==="erp-hr-list-leave-requests"){
      const {data,error}=await admin.from("hr_leave_requests").select("id,employee_user_id,leave_type,starts_on,ends_on,requested_days,coverage_employee_user_id,coverage_approved,status,reason,requested_by,reviewed_by,reviewed_at,review_note").eq("tenant_id",branch.tenant_id).eq("branch_id",branchId).order("created_at",{ascending:false}).limit(150);
      if(error)return fail("Data cuti belum tersedia. Terapkan migrasi HR pada batch final.",503,origin);
      return json({leave_requests:data||[]},200,origin);
    }
    if(action==="erp-hr-create-leave-request"){
      const employeeId=safeText(body.employee_user_id,64),leaveType=safeText(body.leave_type,30),startsOn=safeText(body.starts_on,10),endsOn=safeText(body.ends_on,10),coverageId=safeText(body.coverage_employee_user_id,64)||null,reason=safeText(body.reason,500);
      if(!/^[0-9a-f-]{36}$/i.test(employeeId)||!/^\d{4}-\d{2}-\d{2}$/.test(startsOn)||!/^\d{4}-\d{2}-\d{2}$/.test(endsOn)||!["annual","sick","unpaid","maternity","paternity","other"].includes(leaveType)||reason.length<3||(coverageId&&!/^[0-9a-f-]{36}$/i.test(coverageId)))return fail("Permintaan cuti tidak valid.",422,origin);
      const {data,error}=await admin.rpc("hr_create_leave_request",{p_tenant_id:branch.tenant_id,p_branch_id:branchId,p_employee_user_id:employeeId,p_leave_type:leaveType,p_starts_on:startsOn,p_ends_on:endsOn,p_coverage_employee_user_id:coverageId,p_reason:reason,p_actor_user_id:actor.user.id});
      if(error)return fail("Permintaan cuti ditolak. Karyawan harus mengajukan sendiri dan memiliki penugasan aktif.",409,origin);
      return json({leave_request:data},201,origin);
    }
    if(action==="erp-hr-confirm-leave-coverage"){
      const requestId=safeText(body.leave_request_id,64),approved=body.approved===true,note=safeText(body.note,500)||"";
      if(!/^[0-9a-f-]{36}$/i.test(requestId))return fail("Permintaan cuti tidak valid.",422,origin);
      const {data,error}=await admin.rpc("hr_confirm_leave_coverage",{p_leave_request_id:requestId,p_actor_user_id:actor.user.id,p_approved:approved,p_note:note});
      if(error)return fail("Konfirmasi coverage ditolak. Hanya staf pengganti yang ditunjuk dapat mengonfirmasi.",403,origin);
      return json({coverage:data},200,origin);
    }
    if(action==="erp-hr-review-leave-request"){
      const requestId=safeText(body.leave_request_id,64),approve=body.approve===true,note=safeText(body.note,500)||"";
      if(!/^[0-9a-f-]{36}$/i.test(requestId))return fail("Permintaan cuti tidak valid.",422,origin);
      const {data,error}=await admin.rpc("hr_review_leave_request",{p_leave_request_id:requestId,p_actor_user_id:actor.user.id,p_approve:approve,p_note:note});
      if(error)return fail("Review cuti ditolak. Reviewer harus independen dan coverage wajib dikonfirmasi.",409,origin);
      return json({review:data},200,origin);
    }

    if (action === "erp-hr-record-attendance") {
      const employeeUserId = safeText(body.employee_user_id, 64);
      const eventType = safeText(body.event_type, 20);
      const idempotencyKey = safeText(body.idempotency_key, 120);
      const notes = safeText(body.notes, 500) || null;
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(employeeUserId) ||
          !["clock_in","clock_out","break_start","break_end"].includes(eventType) || idempotencyKey.length < 8) {
        return fail("Perintah absensi tidak valid.", 422, origin);
      }
      const source = employeeUserId === actor.user.id ? "mobile" : "manager";
      const { data, error } = await admin.rpc("hr_record_attendance", {
        p_tenant_id: branch.tenant_id, p_branch_id: branchId, p_employee_user_id: employeeUserId,
        p_event_type: eventType, p_source: source, p_idempotency_key: idempotencyKey,
        p_notes: notes, p_recorded_by: actor.user.id,
      });
      if (error) {
        const duplicate = error.code === "23505";
        const forbidden = error.code === "42501";
        const invalidState = String(error.message || "").includes("ATTENDANCE_") || String(error.message || "").includes("BREAK_") || String(error.message || "").includes("CLOCK_OUT_");
        return fail(duplicate ? "Perintah absensi sudah pernah dicatat." : forbidden ? "Staf tidak memiliki penugasan aktif pada tenant/cabang ini." : invalidState ? "Urutan event absensi tidak sesuai. Periksa clock-in, istirahat, dan clock-out terakhir." : "Absensi belum dapat disimpan.", duplicate || invalidState ? 409 : forbidden ? 403 : 422, origin);
      }
      return json({ attendance_event: data }, 201, origin);
    }  }

    const procurementInvoiceActions=new Set(["erp-procurement-list-invoices","erp-procurement-match-invoice"]);
  if(procurementInvoiceActions.has(action)){
    if(!hasPerm("procurement"))return fail("Izin invoice procurement tidak diizinkan.",403,origin);
    const branchId=safeText(body.branch_id,64),invoiceId=safeText(body.invoice_id,64);
    if(action==="erp-procurement-list-invoices"){
      if(!branchId||!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
      const {data,error}=await admin.from("procurement_supplier_invoices").select("id,supplier_id,purchase_order_id,supplier_invoice_number,invoice_date,due_date,subtotal_idr,tax_idr,total_idr,status,created_at,procurement_invoice_match_lines(id,match_status,quantity_variance,unit_cost_variance_idr)").eq("branch_id",branchId).order("created_at",{ascending:false}).limit(100);
      if(error)return fail("Invoice supplier belum tersedia. Terapkan migrasi pada batch final.",503,origin);
      return json({invoices:data||[]},200,origin);
    }
    if(!/^[0-9a-f-]{36}$/i.test(invoiceId)||!Array.isArray(body.lines)||body.lines.length<1||body.lines.length>100)
      return fail("Invoice atau baris pencocokan tidak valid.",422,origin);
    const lines=body.lines.map((x:any)=>({purchase_order_item_id:safeText(x.purchase_order_item_id,64),receipt_item_id:safeText(x.receipt_item_id,64),invoiced_quantity:Number(x.invoiced_quantity),invoiced_unit_cost_idr:Number(x.invoiced_unit_cost_idr)}));
    if(lines.some((x:any)=>!/^[0-9a-f-]{36}$/i.test(x.purchase_order_item_id)||!/^[0-9a-f-]{36}$/i.test(x.receipt_item_id)||!Number.isFinite(x.invoiced_quantity)||x.invoiced_quantity<=0||!Number.isSafeInteger(x.invoiced_unit_cost_idr)||x.invoiced_unit_cost_idr<0))
      return fail("Satu atau lebih baris invoice tidak valid.",422,origin);
    const {data:invoice,error:invoiceError}=await admin.from("procurement_supplier_invoices").select("id,tenant_id,branch_id,status").eq("id",invoiceId).maybeSingle();
    if(invoiceError)return fail("Invoice belum dapat diverifikasi.",503,origin);
    if(!invoice)return fail("Invoice tidak ditemukan.",404,origin);
    if(!await branchAccess(invoice.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);
    const tolerance=Number(body.tolerance_idr??0);
    if(!Number.isSafeInteger(tolerance)||tolerance<0||tolerance>1000000)return fail("Toleransi harga tidak valid.",422,origin);
    const {data,error}=await admin.rpc("procurement_match_supplier_invoice",{p_invoice_id:invoiceId,p_lines:lines,p_tolerance_idr:tolerance,p_actor_user_id:actor.user.id});
    if(error)return fail("Three-way match gagal. Periksa PO, receipt yang diterima, supplier, jumlah, dan toleransi.",409,origin);
    return json({match:data},200,origin);
  }

  const procurementLinkActions=new Set(["erp-procurement-list-supplier-links","erp-procurement-create-supplier-link","erp-procurement-approve-supplier-link"]);
  if(procurementLinkActions.has(action)){
    if(!isOwner)return fail("Pengelolaan kepemilikan supplier sementara hanya dapat diakses Platform Owner.",403,origin);
    const tenantId=safeText(body.tenant_id,64);
    if(!/^[0-9a-f-]{36}$/i.test(tenantId))return fail("Tenant wajib dipilih.",422,origin);
    const {data:tenant,error:tenantError}=await admin.from("tenants").select("id").eq("id",tenantId).maybeSingle();
    if(tenantError)return fail("Tenant belum dapat diverifikasi.",503,origin);
    if(!tenant)return fail("Tenant tidak ditemukan.",404,origin);
    if(action==="erp-procurement-list-supplier-links"){
      const [links,suppliers]=await Promise.all([
        admin.from("supplier_tenant_links").select("id,supplier_id,status,relationship_type,created_by,approved_by,approved_at,created_at").eq("tenant_id",tenantId).order("created_at",{ascending:false}),
        admin.from("suppliers").select("id").eq("is_active",true).order("id").limit(500)
      ]);
      if(links.error||suppliers.error)return fail("Data supplier ownership belum tersedia. Terapkan migrasi pada batch final.",503,origin);
      return json({links:links.data||[],available_suppliers:suppliers.data||[]},200,origin);
    }
    if(action==="erp-procurement-create-supplier-link"){
      const supplierId=safeText(body.supplier_id,64),relationship=safeText(body.relationship_type,20);
      if(!/^[0-9a-f-]{36}$/i.test(supplierId)||!["exclusive","shared"].includes(relationship))return fail("Supplier atau jenis hubungan tidak valid.",422,origin);
      const {data:supplier,error:supplierError}=await admin.from("suppliers").select("id").eq("id",supplierId).eq("is_active",true).maybeSingle();
      if(supplierError)return fail("Supplier belum dapat diverifikasi.",503,origin);
      if(!supplier)return fail("Supplier tidak aktif atau tidak ditemukan.",404,origin);
      const {data,error}=await admin.from("supplier_tenant_links").insert({tenant_id:tenantId,supplier_id:supplierId,relationship_type:relationship,status:"pending",created_by:actor.user.id})
        .select("id,supplier_id,status,relationship_type,created_at").single();
      if(error)return fail(error.code==="23505"?"Supplier sudah memiliki relasi untuk tenant ini.":"Relasi supplier gagal dibuat.",409,origin);
      await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"procurement.supplier_link.requested",entity_type:"supplier_tenant_link",entity_id:data.id,metadata:{tenant_id:tenantId,supplier_id:supplierId,relationship_type:relationship}});
      return json({link:data},201,origin);
    }
    if(action==="erp-procurement-approve-supplier-link"){
      const linkId=safeText(body.link_id,64);
      if(!/^[0-9a-f-]{36}$/i.test(linkId))return fail("Relasi supplier tidak valid.",422,origin);
      const {data:link,error:linkError}=await admin.from("supplier_tenant_links").select("id,tenant_id").eq("tenant_id",tenantId).eq("id",linkId).maybeSingle();
      if(linkError)return fail("Relasi supplier belum dapat diverifikasi.",503,origin);
      if(!link)return fail("Relasi supplier tidak ditemukan.",404,origin);
      const {data,error}=await admin.rpc("procurement_approve_supplier_link",{p_link_id:linkId,p_actor_user_id:actor.user.id});
      if(error)return fail("Persetujuan ditolak. Approver harus berbeda dari pembuat permintaan.",409,origin);
      return json({link:data},200,origin);
    }
  }

  const saasActions=new Set(["erp-saas-list-plan-versions","erp-saas-list-subscriptions","erp-saas-start-trial","erp-saas-cancel-subscription"]);
  if(saasActions.has(action)){
    if(!isOwner)return fail("Pengelolaan paket SaaS hanya dapat diakses Platform Owner.",403,origin);
    if(action==="erp-saas-list-plan-versions"){
      const {data,error}=await admin.from("saas_plan_versions").select("id,plan_key,version,display_name,billing_interval,price_idr,currency,effective_from,effective_to,active,saas_plan_entitlements(entitlement_key,limit_value,enabled,unit)").eq("active",true).order("plan_key").order("version",{ascending:false});
      if(error)return fail("Katalog paket SaaS belum tersedia. Terapkan migrasi pada batch final.",503,origin);
      return json({plans:data||[]},200,origin);
    }
    const tenantId=safeText(body.tenant_id,64);
    if(!/^[0-9a-f-]{36}$/i.test(tenantId))return fail("Tenant wajib dipilih.",422,origin);
    const {data:tenant,error:tenantError}=await admin.from("tenants").select("id").eq("id",tenantId).maybeSingle();
    if(tenantError)return fail("Tenant belum dapat diverifikasi.",503,origin);
    if(!tenant)return fail("Tenant tidak ditemukan.",404,origin);
    if(action==="erp-saas-list-subscriptions"){
      const {data,error}=await admin.from("saas_tenant_subscriptions").select("id,tenant_id,plan_version_id,status,starts_at,current_period_start,current_period_end,trial_ends_at,grace_ends_at,cancelled_at,saas_plan_versions(plan_key,version,display_name,billing_interval,price_idr)").eq("tenant_id",tenantId).order("created_at",{ascending:false}).limit(50);
      if(error)return fail("Subscription tenant belum tersedia. Terapkan migrasi pada batch final.",503,origin);
      return json({subscriptions:data||[]},200,origin);
    }
    if(action==="erp-saas-start-trial"){
      const planId=safeText(body.plan_version_id,64),days=Number(body.trial_days??14);
      if(!/^[0-9a-f-]{36}$/i.test(planId)||!Number.isInteger(days)||days<1||days>60)return fail("Paket atau durasi trial tidak valid.",422,origin);
      const now=new Date(),end=new Date(now.getTime()+days*86400000),periodEnd=new Date(now);
      const {data:plan,error:planError}=await admin.from("saas_plan_versions").select("id,effective_from,effective_to,active,billing_interval").eq("id",planId).maybeSingle();
      if(planError)return fail("Paket belum dapat diverifikasi.",503,origin);
      if(!plan||!plan.active||new Date(plan.effective_from)>now||(plan.effective_to&&new Date(plan.effective_to)<now))return fail("Versi paket tidak aktif pada tanggal mulai.",409,origin);
      if(plan.billing_interval==="annual")periodEnd.setFullYear(periodEnd.getFullYear()+1);else periodEnd.setMonth(periodEnd.getMonth()+1);
      const {data,error}=await admin.from("saas_tenant_subscriptions").insert({tenant_id:tenantId,plan_version_id:planId,status:"trialing",starts_at:now.toISOString(),current_period_start:now.toISOString(),current_period_end:periodEnd.toISOString(),trial_ends_at:end.toISOString(),created_by:actor.user.id})
        .select("id,tenant_id,plan_version_id,status,starts_at,current_period_start,current_period_end,trial_ends_at").single();
      if(error)return fail(error.code==="23505"?"Tenant sudah memiliki subscription aktif atau trial.":"Trial SaaS gagal dibuat.",409,origin);
      await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"saas.subscription.trial_started",entity_type:"saas_tenant_subscription",entity_id:data.id,metadata:{tenant_id:tenantId,plan_version_id:planId,trial_days:days}});
      return json({subscription:data},201,origin);
    }
    if(action==="erp-saas-cancel-subscription"){
      const subscriptionId=safeText(body.subscription_id,64),reason=safeText(body.reason,500);
      if(!/^[0-9a-f-]{36}$/i.test(subscriptionId)||reason.length<8)return fail("ID subscription dan alasan pembatalan wajib valid.",422,origin);
      const {data:old,error:oldError}=await admin.from("saas_tenant_subscriptions").select("id,status").eq("tenant_id",tenantId).eq("id",subscriptionId).maybeSingle();
      if(oldError)return fail("Subscription belum dapat diverifikasi.",503,origin);
      if(!old||!["trialing","active","past_due","suspended"].includes(old.status))return fail("Subscription tidak dapat dibatalkan dari status saat ini.",409,origin);
      const {data,error}=await admin.from("saas_tenant_subscriptions").update({status:"cancelled",cancelled_at:new Date().toISOString(),updated_at:new Date().toISOString()}).eq("tenant_id",tenantId).eq("id",subscriptionId).in("status",["trialing","active","past_due","suspended"]).select("id,status,cancelled_at").maybeSingle();
      if(error||!data)return fail("Pembatalan gagal atau status berubah. Muat ulang.",409,origin);
      await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"saas.subscription.cancelled",entity_type:"saas_tenant_subscription",entity_id:data.id,metadata:{tenant_id:tenantId,reason}});
      return json({subscription:data},200,origin);
    }
  }

  const biExecutiveActions=new Set(["erp-bi-list-snapshots","erp-executive-list-alerts","erp-executive-verify-alert","erp-executive-transition-alert"]);
  if(biExecutiveActions.has(action)){
    if(!isOwner)return fail("BI dan Executive Command Center sementara hanya dapat diakses Platform Owner.",403,origin);
    const tenantId=safeText(body.tenant_id,64);
    if(!/^[0-9a-f-]{36}$/i.test(tenantId))return fail("Tenant wajib dipilih.",422,origin);
    const {data:tenant,error:tenantError}=await admin.from("tenants").select("id").eq("id",tenantId).maybeSingle();
    if(tenantError)return fail("Tenant belum dapat diverifikasi.",503,origin);
    if(!tenant)return fail("Tenant tidak ditemukan.",404,origin);
    if(action==="erp-bi-list-snapshots"){
      const {data,error}=await admin.from("bi_metric_snapshots").select("id,metric_id,period_start,period_end,dimension_key,dimension_value,metric_value,formula_version,status,calculated_at,published_at,bi_metric_definitions(metric_key,display_name,unit)").eq("tenant_id",tenantId).eq("status","published").order("period_end",{ascending:false}).limit(200);
      if(error)return fail("Snapshot BI belum tersedia. Terapkan migrasi pada batch final.",503,origin);
      return json({snapshots:data||[]},200,origin);
    }
    if(action==="erp-executive-list-alerts"){
      const {data,error}=await admin.from("executive_operational_alerts").select("id,branch_id,alert_key,severity,source_domain,source_entity,source_entity_id,evidence_reference,summary,status,assigned_to,resolved_by,resolved_at,verified_by,verified_at,created_at,branches(code,name)").eq("tenant_id",tenantId).order("created_at",{ascending:false}).limit(200);
      if(error)return fail("Alert Executive belum tersedia. Terapkan migrasi pada batch final.",503,origin);
      return json({alerts:data||[]},200,origin);
    }
    if(action==="erp-executive-transition-alert"){
      const alertId=safeText(body.alert_id,64),next=safeText(body.next_status,30),note=safeText(body.note,500)||"",evidence=safeText(body.evidence_reference,500)||"";
      if(!/^[0-9a-f-]{36}$/i.test(alertId)||!["acknowledged","investigating","resolved","dismissed","open"].includes(next))return fail("Perubahan alert tidak valid.",422,origin);
      if(next==="resolved"&&(note.length<8||evidence.length<8))return fail("Penyelesaian alert memerlukan catatan dan referensi bukti.",422,origin);
      const {data,error}=await admin.rpc("executive_transition_alert",{p_alert_id:alertId,p_next_status:next,p_actor_user_id:actor.user.id,p_note:note,p_evidence_reference:evidence});
      if(error)return fail("Perubahan status alert ditolak. Periksa status saat ini dan bukti penyelesaian.",409,origin);
      return json({transition:data},200,origin);
    }
    if(action==="erp-executive-verify-alert"){
      const alertId=safeText(body.alert_id,64),note=safeText(body.note,500),evidence=safeText(body.evidence_reference,500);
      if(!/^[0-9a-f-]{36}$/i.test(alertId)||note.length<8||evidence.length<8)return fail("Catatan dan referensi bukti verifikasi wajib diisi.",422,origin);
      const {data,error}=await admin.rpc("executive_verify_alert",{p_alert_id:alertId,p_actor_user_id:actor.user.id,p_note:note,p_evidence_reference:evidence});
      if(error)return fail("Verifikasi alert ditolak. Verifikator harus berbeda dari petugas penyelesai.",409,origin);
      return json({verification:data},200,origin);
    }
  }

  const franchiseActions=new Set(["erp-franchise-list-applications","erp-franchise-create-application","erp-franchise-add-site","erp-franchise-review-site","erp-franchise-review-check","erp-franchise-review-application","erp-franchise-generate-royalty-statement"]);
  if(franchiseActions.has(action)){
    if(!isOwner)return fail("Workflow Franchise sementara hanya dapat dikelola Platform Owner.",403,origin);
    if(action==="erp-franchise-list-applications"){
      const {data,error}=await admin.from("franchise_applications").select("id,applicant_name,applicant_email,applicant_phone,proposed_region,proposed_city,investment_capacity_idr,status,submitted_at,franchise_sites(id,proposed_address,feasibility_status),franchise_due_diligence_checks(id,check_key,status,evidence_reference,reviewer_user_id)").order("submitted_at",{ascending:false}).limit(100);
      if(error)return fail("Data aplikasi franchise belum tersedia. Terapkan migrasi pada batch final.",503,origin);
      return json({applications:data||[]},200,origin);
    }
    if(action==="erp-franchise-create-application"){
      const name=safeText(body.applicant_name,160),email=safeText(body.applicant_email,254).toLowerCase(),phone=safeText(body.applicant_phone,40),
        region=safeText(body.proposed_region,100),city=safeText(body.proposed_city,100),capacity=Number(body.investment_capacity_idr),
        experience=safeText(body.experience_summary,2000)||null;
      if(name.length<2||!/^\\S+@\\S+\\.\\S+$/.test(email)||phone.length<8||region.length<2||city.length<2||!Number.isSafeInteger(capacity)||capacity<0)
        return fail("Data aplikasi franchise tidak valid.",422,origin);
      const {data,error}=await admin.rpc("franchise_create_application",{p_applicant_name:name,p_applicant_email:email,p_applicant_phone:phone,p_proposed_region:region,p_proposed_city:city,p_investment_capacity_idr:capacity,p_experience_summary:experience,p_created_by:actor.user.id});
      if(error)return fail("Aplikasi franchise dan checklist due diligence gagal disimpan.",503,origin);
      return json({application:data,checklist:["identity","financial","legal","operational_experience","territory_conflict","reputation"]},201,origin);
    }
    if(action==="erp-franchise-add-site"){
      const applicationId=safeText(body.application_id,64),address=safeText(body.proposed_address,500),city=safeText(body.city,100),province=safeText(body.province,100);
      const latitude=body.latitude===null||body.latitude===""?null:Number(body.latitude),longitude=body.longitude===null||body.longitude===""?null:Number(body.longitude);
      const area=body.floor_area_sqm===null||body.floor_area_sqm===""?null:Number(body.floor_area_sqm);
      if(!/^[0-9a-f-]{36}$/i.test(applicationId)||address.length<5||city.length<2||province.length<2||
        ((latitude===null)!==(longitude===null))||(latitude!==null&&(!Number.isFinite(latitude)||latitude< -90||latitude>90))||
        (longitude!==null&&(!Number.isFinite(longitude)||longitude< -180||longitude>180))||
        (area!==null&&(!Number.isFinite(area)||area<=0)))return fail("Data lokasi franchise tidak valid.",422,origin);
      const {data,error}=await admin.from("franchise_sites").insert({application_id:applicationId,proposed_address:address,city,province,latitude,longitude,floor_area_sqm:area})
        .select("id,application_id,proposed_address,city,province,feasibility_status").single();
      if(error)return fail("Lokasi franchise gagal disimpan.",503,origin);
      return json({site:data},201,origin);
    }
    if(action==="erp-franchise-review-check"){
      const checkId=safeText(body.check_id,64),decision=safeText(body.decision,20),evidence=safeText(body.evidence_reference,500),notes=safeText(body.notes,1000)||null;
      if(!/^[0-9a-f-]{36}$/i.test(checkId)||!["passed","failed","waived","pending"].includes(decision)||(["passed","waived"].includes(decision)&&evidence.length<8))
        return fail("Status due diligence dan referensi bukti tidak valid.",422,origin);
      const {data,error}=await admin.rpc("franchise_review_due_diligence_check",{p_check_id:checkId,p_status:decision,p_evidence_reference:evidence,p_actor_user_id:actor.user.id,p_notes:notes});
      if(error)return fail("Review due diligence ditolak. Pemohon tidak boleh menilai pemeriksaannya sendiri.",409,origin);
      return json({check:data},200,origin);
    }
    if(action==="erp-franchise-review-site"){
      const siteId=safeText(body.site_id,64),decision=safeText(body.decision,30),evidence=safeText(body.evidence_reference,500),notes=safeText(body.notes,500)||null;
      if(!/^[0-9a-f-]{36}$/i.test(siteId)||!["approved","rejected","assessing"].includes(decision)||(decision==="approved"&&evidence.length<8))
        return fail("Review kelayakan lokasi memerlukan keputusan dan referensi bukti yang valid.",422,origin);
      const {data,error}=await admin.rpc("franchise_review_site",{p_site_id:siteId,p_status:decision,p_evidence_reference:evidence,p_actor_user_id:actor.user.id,p_notes:notes});
      if(error)return fail("Review kelayakan lokasi gagal disimpan.",409,origin);
      return json({site_review:data},200,origin);
    }
    if(action==="erp-franchise-generate-royalty-statement"){
      const branchId=safeText(body.branch_id,64),agreementId=safeText(body.agreement_id,64),start=safeText(body.period_start,10),end=safeText(body.period_end,10),reconciliationId=safeText(body.reconciliation_run_id,64);
      if(!/^[0-9a-f-]{36}$/i.test(branchId)||!/^[0-9a-f-]{36}$/i.test(agreementId)||!/^[0-9a-f-]{36}$/i.test(reconciliationId)||!/^\d{4}-\d{2}-\d{2}$/.test(start)||!/^\d{4}-\d{2}-\d{2}$/.test(end))return fail("Periode, cabang, agreement, atau reconciliation reference tidak valid.",422,origin);
      const {data,error}=await admin.rpc("franchise_generate_royalty_statement",{p_tenant_id:tenantId,p_branch_id:branchId,p_agreement_id:agreementId,p_period_start:start,p_period_end:end,p_reconciliation_run_id:reconciliationId,p_idempotency_key:crypto.randomUUID(),p_actor_user_id:actor.user.id});
      if(error)return fail("Royalty tidak dapat dihitung. Diperlukan agreement aktif, versi efektif, BI net sales terpublikasi, dan rekonsiliasi lulus.",409,origin);
      return json({royalty_statement:data},201,origin);
    }
    if(action==="erp-franchise-review-application"){
      const applicationId=safeText(body.application_id,64),decision=safeText(body.decision,30),notes=safeText(body.notes,500)||null;
      if(!/^[0-9a-f-]{36}$/i.test(applicationId)||!["screening","due_diligence","approved","rejected"].includes(decision))return fail("Keputusan review franchise tidak valid.",422,origin);
      const {data,error}=await admin.rpc("franchise_review_application",{p_application_id:applicationId,p_decision:decision,p_actor_user_id:actor.user.id,p_notes:notes});
      if(error)return fail("Keputusan belum dapat disimpan. Pastikan seluruh bukti due diligence dan kelayakan lokasi lengkap.",409,origin);
      return json({review:data},200,origin);
    }
  }



  if (action === "erp-list-tenants") {
    if(!hasPerm("branches")&&!isOwner)return fail("Izin tenant tidak diizinkan.",403,origin);
    const tenantIds=await tenantIdsForActor().catch(()=>[]);
    if(!tenantIds.length)return fail("Keanggotaan tenant aktif diperlukan.",403,origin);
    const {data,error}=await admin.from("tenants").select("id,slug,legal_name,status,plan_code,settings,created_at,updated_at,tenant_memberships(user_id,role,status)").in("id",tenantIds).order("legal_name");
    if(error)return fail("Daftar tenant belum tersedia. Pastikan migrasi platform sudah diterapkan.",503,origin);
    return json({tenants:data||[]},200,origin);
  }

  if (action === "erp-list-backup-restore-runs") {
    const tenantIds=await tenantIdsForActor().catch(()=>[]);
    if(!tenantIds.length&&!isOwner)return fail("Keanggotaan tenant aktif diperlukan.",403,origin);
    let q=admin.from("backup_restore_runs").select("id,tenant_id,run_type,status,artifact_reference,started_by,started_at,completed_at,verified_at,restored_at,checksum_sha256,error_code,notes,created_at").order("created_at",{ascending:false}).limit(100);
    if(tenantIds.length)q=q.in("tenant_id",tenantIds);else q=q.is("tenant_id",null);
    const {data,error}=await q;if(error)return fail("Riwayat backup/restore belum tersedia.",503,origin);
    return json({runs:data||[]},200,origin);
  }

  if (action === "erp-list-tenant-memberships") {
    // Self-service only: return active memberships belonging to the authenticated actor.
    // Do not require a global "branches" permission for a user's own membership lookup.
    // Never accept a caller-supplied user_id here; actor identity comes from the verified session.
    // admin_profiles.user_id intentionally has no FK from tenant_memberships.user_id, so
    // embedding admin_profiles in this PostgREST select raises PGRST200 (HTTP 503).
    // getAdmin() has already loaded the authenticated actor's own profile; reuse it instead
    // of relying on a relationship that does not exist in the database schema.
    const {data,error}=await admin.from("tenant_memberships")
      .select("tenant_id,user_id,role,permissions,status,created_at,tenants(slug,legal_name,status)")
      .eq("user_id",actor.user.id)
      .eq("status","active");
    if(error)return fail("Keanggotaan tenant belum tersedia. Pastikan migrasi platform sudah diterapkan.",503,origin);
    const memberships=(data||[]).map((membership)=>({
      ...membership,
      admin_profiles:{
        display_name:actor.profile.display_name,
        username:actor.profile.username,
        role:actor.profile.role,
      },
    }));
    return json({memberships},200,origin);
  }

  if (action === "erp-create-tenant") {
    if (!TENANT_ISOLATION_RELEASED) return fail("Tenant onboarding is paused until cross-tenant isolation tests pass.", 423, origin);
    if(!isOwner)return fail("Hanya Owner platform yang dapat membuat tenant baru.",403,origin);
    const slug=safeText(body.slug,60).toLowerCase(),legalName=safeText(body.legal_name,180);
    if(!/^[a-z0-9][a-z0-9-]{1,60}$/.test(slug)||legalName.length<2)return fail("Slug atau nama legal tenant tidak valid.",422,origin);
    const {data:createdTenant,error}=await admin.rpc("dlice_create_tenant_with_owner",{
      p_actor_user_id:actor.user.id,
      p_slug:slug,
      p_legal_name:legalName,
      p_plan_code:safeText(body.plan_code,40)||"starter",
    });
    if(error||!createdTenant?.tenant)return fail("Tenant, membership, dan audit tidak dapat dibuat secara atomik.",error?.code==="23505"?409:500,origin);
    return json({ok:true,tenant:createdTenant.tenant},201,origin);
  }

  if (action === "erp-invite-tenant-member") {
    if (!TENANT_ISOLATION_RELEASED) return fail("Tenant onboarding is paused until cross-tenant isolation tests pass.", 423, origin);
    if(!hasPerm("branches")&&!isOwner)return fail("Izin undangan tenant tidak diizinkan.",403,origin);
    const tenantId=safeText(body.tenant_id,80),email=safeText(body.email,254).toLowerCase(),role=safeText(body.role,40);
    const allowedRoles=["tenant_admin","branch_manager","cashier","inventory","production","finance","viewer","tenant_member"];
    if(!tenantId||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||!allowedRoles.includes(role))return fail("Data undangan tenant tidak valid.",422,origin);
    const rawToken=randomToken(),tokenHash=await sha256(rawToken),expiresAt=new Date(Date.now()+7*24*60*60*1000).toISOString();
    const {data:result,error}=await admin.rpc("dlice_create_tenant_invite_atomic",{
      p_actor_user_id:actor.user.id,
      p_tenant_id:tenantId,
      p_email:email,
      p_role:role,
      p_token_hash:tokenHash,
      p_expires_at:expiresAt,
    });
    if(error||!result?.ok||!result?.invite)return fail("Undangan gagal dibuat secara atomik.",error?.code==="23505"?409:500,origin);
    return json({ok:true,invite:result.invite,invite_token:rawToken,delivery:"manual_copy_required"},201,origin);
  }

  if (action === "erp-accept-tenant-invite") {
    if (!TENANT_ISOLATION_RELEASED) return fail("Tenant onboarding is paused until cross-tenant isolation tests pass.", 423, origin);
    if(!hasPerm("branches")&&!isOwner)return fail("Izin aktivasi keanggotaan tenant tidak diizinkan.",403,origin);
    const token=safeText(body.invite_token,100),email=String(actor.user.email||"").toLowerCase();
    if(token.length<32||!email)return fail("Token undangan atau email akun tidak valid.",422,origin);
    const tokenHash=await sha256(token);
    const {data:result,error}=await admin.rpc("dlice_accept_tenant_invite_atomic",{
      p_actor_user_id:actor.user.id,
      p_email:email,
      p_token_hash:tokenHash,
    });
    if(error)return fail("Undangan tidak dapat diproses; token mungkin sudah digunakan atau tidak valid.",error?.code==="42501"?403:error?.code==="23505"?409:404,origin);
    if(result?.status==="expired")return fail("Undangan sudah kedaluwarsa.",410,origin);
    if(!result?.ok||!result?.invite)return fail("Undangan tidak dapat diaktifkan.",409,origin);
    return json({ok:true,invite:result.invite,replayed:result.replayed===true},200,origin);
  }

  if (action === "erp-list-branch-settings") {
    if(!hasPerm("branches")&&!hasPerm("finance")&&!hasPerm("inventory")&&!isOwner)return fail("Izin konfigurasi cabang tidak diizinkan.",403,origin);
    const branchId=safeText(body.branch_id,80);
    if(!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    const {data,error}=await admin.from("branch_settings").select("*").eq("branch_id",branchId).is("effective_to",null).order("category").order("setting_key");
    if(error)return fail("Konfigurasi cabang belum tersedia.",503,origin);
    return json({settings:data||[]},200,origin);
  }

  if (action === "erp-save-branch-setting") {
    const branchId=safeText(body.branch_id,80),category=safeText(body.category,30),key=safeText(body.setting_key,100),value=body.setting_value;
    if(!["tax","pricing","menu","policy","timezone","fulfillment"].includes(category)||key.length<2||!value||typeof value!=="object"||Array.isArray(value))return fail("Konfigurasi cabang tidak valid.",422,origin);
    if(!await branchAccess(branchId)||(!isOwner&&!hasPerm("branches")&&!hasPerm("finance")&&!hasPerm("inventory")))return fail("Akses pengaturan cabang tidak diizinkan.",403,origin);
    const {data:branch}=await admin.from("branches").select("tenant_id").eq("id",branchId).maybeSingle();if(!branch)return fail("Cabang tidak ditemukan.",404,origin);
    const {data:latest}=await admin.from("branch_settings").select("version").eq("branch_id",branchId).eq("category",category).eq("setting_key",key).order("version",{ascending:false}).limit(1).maybeSingle();
    const version=Number(latest?.version||0)+1;
    const {data:setting,error}=await admin.from("branch_settings").insert({tenant_id:branch.tenant_id,branch_id:branchId,category,setting_key:key,setting_value:value,version,updated_by:actor.user.id,effective_from:safeText(body.effective_from,10)||todayDate()}).select("*").single();
    if(error||!setting)return fail("Pengaturan cabang gagal disimpan.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"branch_setting_version_created",entity_type:"branch_setting",entity_id:setting.id,metadata:{branch_id:branchId,category,setting_key:key,version}});
    return json({ok:true,setting},201,origin);
  }


  if (action === "erp-list-waste-events") {
    if(!hasPerm("inventory")&&!hasPerm("reports")&&!isOwner)return fail("Izin Inventory/Reports diperlukan.",403,origin);
    const branchId=safeText(body.branch_id,80);
    if(!branchId||!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    const {data:events,error}=await admin.from("inventory_waste_events").select("id,tenant_id,branch_id,inventory_item_id,quantity,reason_code,reason,idempotency_key,payload_fingerprint,status,created_by,created_at,inventory_items(sku,name,unit)").eq("branch_id",branchId).order("created_at",{ascending:false}).limit(200);
    if(error)return fail("Daftar waste belum tersedia.",503,origin);
    const ids=(events||[]).map((event:any)=>event.id);
    const [movementResult,auditResult]=ids.length?await Promise.all([
      admin.from("stock_movements").select("id,inventory_item_id,movement_type,quantity,reference_type,reference_id,created_by,created_at,notes").eq("branch_id",branchId).eq("reference_type","inventory_waste").in("reference_id",ids),
      admin.from("admin_audit_logs").select("actor_user_id,action,entity_type,entity_id,metadata,created_at").in("entity_id",ids)
    ]):[{data:[],error:null},{data:[],error:null}];
    if(movementResult.error||auditResult.error)return fail("Ledger/audit waste gagal dimuat.",503,origin);
    return json({events:events||[],stock_movements:movementResult.data||[],audit_events:auditResult.data||[]},200,origin);
  }

  if (action === "erp-record-waste") {
    if(!hasPerm("inventory"))return fail("Izin Inventory diperlukan untuk mencatat waste.",403,origin);
    const branchId=safeText(body.branch_id,80),itemId=safeText(body.inventory_item_id,80),quantity=Number(body.quantity),reasonCode=safeText(body.reason_code,30),reason=safeText(body.reason,500),key=safeText(body.idempotency_key,120);
    if(!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(!key)return fail("Kunci idempoten wajib diisi untuk mencegah waste ganda.",422,origin);
    const {data,error}=await admin.rpc("erp_record_inventory_waste",{p_branch_id:branchId,p_inventory_item_id:itemId,p_quantity:quantity,p_reason_code:reasonCode,p_reason:reason,p_actor_user_id:actor.user.id,p_idempotency_key:key});
    if(error)return fail(error.message.includes("insufficient_stock")?"Stok tidak mencukupi untuk waste ini.":error.message.includes("invalid_waste_reason")?"Alasan waste tidak valid.":"Pencatatan waste gagal.",409,origin);
    return json(data,200,origin);
  }

  if (action === "erp-list-shift-handovers") {
    if(!hasPerm("branches")&&!hasPerm("pos")&&!hasPerm("reports"))return fail("Izin operasional cabang diperlukan.",403,origin);
    const branchId=safeText(body.branch_id,80),ids=await branchIdsForActor().catch(()=>[]);
    if(branchId&&!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    let q=admin.from("shift_handover_records").select("*,branches(code,name),pos_shifts(status,opened_at,closed_at)").order("created_at",{ascending:false}).limit(300);
    if(branchId)q=q.eq("branch_id",branchId);else q=ids.length?q.in("branch_id",ids):q.eq("branch_id","00000000-0000-0000-0000-000000000000");
    const {data,error}=await q;if(error)return fail("Serah terima shift belum tersedia.",503,origin);
    return json({handovers:data||[]},200,origin);
  }

  if (action === "erp-create-shift-handover") {
    if(!hasPerm("branches")&&!hasPerm("pos"))return fail("Izin operasional cabang diperlukan.",403,origin);
    const shiftId=safeText(body.shift_id,80),cash=Number(body.cash_counted_idr||0),pending=Array.isArray(body.pending_orders)?body.pending_orders:[],waste=Array.isArray(body.waste_summary)?body.waste_summary:[];
    if(!shiftId||!Number.isSafeInteger(cash)||cash<0||pending.length>100||waste.length>100)return fail("Data serah terima tidak valid.",422,origin);
    const {data:shift}=await admin.from("pos_shifts").select("id,branch_id,opened_by,status").eq("id",shiftId).maybeSingle();
    if(!shift)return fail("Shift tidak ditemukan.",404,origin);
    if(!await branchAccess(shift.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(shift.opened_by!==actor.user.id&&!isOwner&&!hasPerm("branches"))return fail("Hanya pembuka shift atau supervisor yang dapat membuat serah terima.",403,origin);
    const {data:branch}=await admin.from("branches").select("tenant_id").eq("id",shift.branch_id).maybeSingle();
    const {data:handover,error}=await admin.from("shift_handover_records").insert({tenant_id:branch.tenant_id,branch_id:shift.branch_id,shift_id:shift.id,outgoing_user_id:actor.user.id,incoming_user_id:safeText(body.incoming_user_id,80)||null,cash_counted_idr:cash,pending_orders:pending,waste_summary:waste,open_issues:safeText(body.open_issues,1000)||null,notes:safeText(body.notes,1000)||null}).select("*").single();
    if(error||!handover)return fail("Serah terima sudah ada atau gagal disimpan.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"shift_handover_submitted",entity_type:"shift_handover",entity_id:handover.id,metadata:{branch_id:shift.branch_id,shift_id:shift.id}});
    return json({ok:true,handover},201,origin);
  }

  if (action === "erp-acknowledge-shift-handover") {
    if(!hasPerm("branches")&&!hasPerm("pos"))return fail("Izin operasional cabang diperlukan.",403,origin);
    const id=safeText(body.handover_id,80),decision=safeText(body.decision,20);
    if(!["acknowledged","exception"].includes(decision))return fail("Keputusan serah terima tidak valid.",422,origin);
    const {data:old}=await admin.from("shift_handover_records").select("*").eq("id",id).maybeSingle();
    if(!old)return fail("Serah terima tidak ditemukan.",404,origin);
    if(!await branchAccess(old.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(old.outgoing_user_id===actor.user.id)return fail("Pembuat serah terima tidak boleh mengakui serah terimanya sendiri.",403,origin);
    if(old.status!=="submitted")return fail("Serah terima sudah diproses.",409,origin);
    if(old.incoming_user_id&&old.incoming_user_id!==actor.user.id&&!isOwner&&!hasPerm("branches"))return fail("Hanya penerima atau supervisor yang dapat mengakui serah terima.",403,origin);
    const {data:updated,error}=await admin.from("shift_handover_records").update({status:decision,acknowledged_at:new Date().toISOString()}).eq("id",id).eq("status","submitted").select("*").maybeSingle();
    if(error||!updated)return fail("Serah terima berubah saat diproses.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"shift_handover_"+decision,entity_type:"shift_handover",entity_id:id,metadata:{branch_id:old.branch_id,shift_id:old.shift_id}});
    return json({ok:true,handover:updated},200,origin);
  }

  if (action === "erp-list-warehouses") {
    if(!hasPerm("inventory")&&!hasPerm("branches")&&!hasPerm("reports"))return fail("Izin Inventory diperlukan.",403,origin);
    const branchId=safeText(body.branch_id,80),ids=await branchIdsForActor().catch(()=>[]);
    if(branchId&&!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    let q=admin.from("warehouses").select("*,branches(code,name)").order("branch_id").order("name").limit(500);
    if(branchId)q=q.eq("branch_id",branchId);else q=ids.length?q.in("branch_id",ids):q.eq("branch_id","00000000-0000-0000-0000-000000000000");
    const {data,error}=await q;if(error)return fail("Gudang belum tersedia.",503,origin);
    return json({warehouses:data||[]},200,origin);
  }

  if (action === "erp-create-warehouse") {
    if(!hasPerm("inventory")&&!hasPerm("branches"))return fail("Izin Inventory/Branches diperlukan.",403,origin);
    const branchId=safeText(body.branch_id,80),code=safeText(body.code,40).toUpperCase(),name=safeText(body.name,120),type=safeText(body.warehouse_type,30)||"branch";
    if(!/^[A-Z0-9_-]{2,40}$/.test(code)||name.length<2||!["central","branch","cold_storage","transit"].includes(type))return fail("Data gudang tidak valid.",422,origin);
    if(!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    const {data:branch}=await admin.from("branches").select("tenant_id").eq("id",branchId).maybeSingle();if(!branch)return fail("Cabang tidak ditemukan.",404,origin);
    const {data:membership}=await admin.from("tenant_memberships").select("role").eq("tenant_id",branch.tenant_id).eq("user_id",actor.user.id).eq("status","active").maybeSingle();
    if(!membership||!["tenant_owner","tenant_admin"].includes(String(membership.role)))return fail("Hanya Tenant Owner/Admin yang dapat membuat gudang.",403,origin);
    const {data:warehouse,error}=await admin.from("warehouses").insert({tenant_id:branch.tenant_id,branch_id:branchId,code,name,warehouse_type:type,is_default:body.is_default===true}).select("*").single();
    if(error||!warehouse)return fail("Gudang gagal dibuat; kode atau gudang default mungkin sudah ada.",409,origin);
    return json({ok:true,warehouse},201,origin);
  }

  if (action === "erp-list-integrations") {
    if(!hasPerm("branches")&&!isOwner)return fail("Izin integrasi tenant tidak diizinkan.",403,origin);
    const tenantIds=await tenantIdsForActor().catch(()=>[]);
    if(!tenantIds.length)return fail("Keanggotaan tenant aktif diperlukan.",403,origin);
    const {data,error}=await admin.from("integration_connections").select("id,tenant_id,provider,display_name,status,config,last_success_at,last_error_at,last_error_code,created_at,updated_at").in("tenant_id",tenantIds).order("provider");
    if(error)return fail("Daftar integrasi belum tersedia.",503,origin);
    return json({integrations:data||[]},200,origin);
  }

  if (action === "erp-save-integration") {
    if(!hasPerm("branches")&&!isOwner)return fail("Izin integrasi tenant tidak diizinkan.",403,origin);
    const tenantId=safeText(body.tenant_id,80),provider=safeText(body.provider,60).toLowerCase(),displayName=safeText(body.display_name,120),status=safeText(body.status,20)||"disabled",config=body.config&&typeof body.config==="object"&&!Array.isArray(body.config)?body.config:{};
    if(!/^[a-z0-9][a-z0-9_-]{1,60}$/.test(provider)||displayName.length<2||!["disabled","pending","active","degraded","revoked"].includes(status))return fail("Konfigurasi integrasi tidak valid.",422,origin);
    const {data:membership}=await admin.from("tenant_memberships").select("role").eq("tenant_id",tenantId).eq("user_id",actor.user.id).eq("status","active").maybeSingle();
    if(!membership||!["tenant_owner","tenant_admin"].includes(String(membership.role)))return fail("Hanya Tenant Owner/Admin yang dapat mengubah integrasi.",403,origin);
    const secretReference=safeText(body.secret_reference,200)||null;
    const {data:connection,error}=await admin.from("integration_connections").upsert({tenant_id:tenantId,provider,display_name:displayName,status,config,secret_reference:secretReference,created_by:actor.user.id,updated_at:new Date().toISOString()},{onConflict:"tenant_id,provider,display_name"}).select("id,tenant_id,provider,display_name,status,config,secret_reference,updated_at").single();
    if(error||!connection)return fail("Integrasi gagal disimpan.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"integration_connection_saved",entity_type:"integration_connection",entity_id:connection.id,metadata:{tenant_id:tenantId,provider,status}});
    return json({ok:true,connection},200,origin);
  }

  if (action === "erp-create-backup-restore-run") {
    const tenantId=safeText(body.tenant_id,80)||null,runType=safeText(body.run_type,20),notes=safeText(body.notes,1000);
    if(!["backup","restore","restore_drill"].includes(runType))return fail("Jenis pekerjaan backup/restore tidak valid.",422,origin);
    if(tenantId){const {data:membership}=await admin.from("tenant_memberships").select("role").eq("tenant_id",tenantId).eq("user_id",actor.user.id).eq("status","active").maybeSingle();if(!membership||!["tenant_owner","tenant_admin"].includes(String(membership.role)))return fail("Akses tenant tidak diizinkan.",403,origin);}
    else if(!isOwner)return fail("Hanya Owner platform yang dapat meminta backup lintas tenant.",403,origin);
    const {data:run,error}=await admin.from("backup_restore_runs").insert({tenant_id:tenantId,run_type:runType,status:"queued",started_by:actor.user.id,notes:notes||null}).select("*").single();
    if(error||!run)return fail("Pencatatan permintaan backup/restore gagal.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"backup_restore_run_requested",entity_type:"backup_restore_run",entity_id:run.id,metadata:{tenant_id:tenantId,run_type:runType}});
    return json({ok:true,run,execution:"metadata_only_external_backup_job_required"},202,origin);
  }

  if (action === "erp-overview") {
    if (!isOwner) return fail("Ringkasan lintas cabang hanya tersedia untuk Owner; gunakan laporan cabang untuk data operasional.",403,origin);
    const fromDate=safeText(body.from_date,10),throughDate=safeText(body.through_date,10);
    const validDate=(value:string)=>{
      if(!/^\d{4}-\d{2}-\d{2}$/.test(value))return false;
      const parsed=new Date(`${value}T00:00:00.000Z`);
      return Number.isFinite(parsed.getTime())&&parsed.toISOString().slice(0,10)===value;
    };
    if(!validDate(fromDate)||!validDate(throughDate)||throughDate>="9999-12-31"||Date.parse(`${throughDate}T00:00:00Z`)<Date.parse(`${fromDate}T00:00:00Z`)||Date.parse(`${throughDate}T00:00:00Z`)-Date.parse(`${fromDate}T00:00:00Z`)>92*86400000)return fail("Rentang tanggal ringkasan tidak valid; gunakan maksimum 93 hari.",422,origin);
    const selectedBranch=safeText(body.branch_id,80);
    if(selectedBranch&&!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(selectedBranch))return fail("Cabang ringkasan tidak valid.",422,origin);
    const branchResult=await admin.from("branches").select("id,code,name,status,city,province,timezone",{count:"exact"}).order("code",{ascending:true}).limit(500);
    if(branchResult.error)return fail("Daftar cabang ringkasan gagal dimuat.",500,origin);
    if((branchResult.count||0)>500)return fail("Ringkasan dibatasi maksimal 500 cabang per permintaan.",422,origin);
    const availableBranches=branchResult.data||[];
    if(selectedBranch&&!availableBranches.some((branch:any)=>branch.id===selectedBranch))return fail("Cabang ringkasan tidak ditemukan.",404,origin);
    const summaryBranches=selectedBranch?availableBranches.filter((branch:any)=>branch.id===selectedBranch):availableBranches;
    const invalidTimezoneBranch=summaryBranches.find((branch:any)=>!SUPPORTED_BRANCH_TIMEZONES.has(branch.timezone));
    if(invalidTimezoneBranch)return fail("Zona waktu cabang tidak didukung. Perbaiki konfigurasi cabang sebelum memuat ringkasan.",422,origin);
    const branchIds=summaryBranches.map((branch:any)=>branch.id);
    const summaryResult=await admin.rpc("dlice_get_command_center_summary",{p_branch_ids:branchIds,p_from_date:fromDate,p_through_date:throughDate});
    if(summaryResult.error||!summaryResult.data)return fail("Ringkasan operasional gagal dimuat.",500,origin);
    return json({ok:true,available_branches:availableBranches,...summaryResult.data},200,origin);
  }

  const branchChecklistTemplates: Record<string, { key: string; label: string; critical: boolean }[]> = {
    opening: [
      { key: "cleanliness", label: "Area layanan dan produksi bersih", critical: true },
      { key: "equipment", label: "Peralatan utama aman dan berfungsi", critical: true },
      { key: "cold_storage", label: "Suhu penyimpanan dingin diperiksa dan sesuai SOP", critical: true },
      { key: "stock_critical", label: "Bahan kritis tersedia dan belum kedaluwarsa", critical: true },
      { key: "cash_drawer", label: "Kas awal dihitung dan dicatat", critical: false },
      { key: "staff_ready", label: "Kehadiran dan kesiapan staf dikonfirmasi", critical: false },
      { key: "production_station", label: "Stasiun produksi dan alat sanitasi siap", critical: true },
    ],
    closing: [
      { key: "cash_reconciliation", label: "Kasir dan selisih kas direkonsiliasi", critical: true },
      { key: "waste", label: "Waste, produk rusak, dan bahan terbuang dicatat", critical: true },
      { key: "stock_secure", label: "Stok disimpan aman dan bahan kedaluwarsa dipisahkan", critical: true },
      { key: "equipment_off", label: "Peralatan dimatikan sesuai SOP", critical: true },
      { key: "cleaning", label: "Pembersihan dan sanitasi akhir selesai", critical: true },
      { key: "incidents", label: "Insiden dan tindak lanjut dicatat", critical: false },
      { key: "premises_secure", label: "Pintu, penyimpanan, dan area kerja diamankan", critical: true },
    ],
  };

  const checklistContext = async (branchId: string) => {
    if (!branchId) return { error: fail("Cabang wajib dipilih.", 422, origin) };
    if (!await branchAccess(branchId)) return { error: fail("Akses cabang tidak diizinkan.", 403, origin) };
    const { data: branch, error } = await admin.from("branches").select("id,status,timezone").eq("id", branchId).maybeSingle();
    if (error) return { error: fail("Cabang gagal dimuat.", 500, origin) };
    if (!branch) return { error: fail("Cabang tidak ditemukan.", 404, origin) };
    if (!SUPPORTED_BRANCH_TIMEZONES.has(branch.timezone)) {
      return { error: fail("Zona waktu cabang tidak valid. Perbaiki konfigurasi cabang sebelum checklist dijalankan.", 422, origin) };
    }
    const parts = new Intl.DateTimeFormat("en-GB", {
      timeZone: branch.timezone,
      year: "numeric", month: "2-digit", day: "2-digit",
    }).formatToParts(new Date());
    const part = (name: string) => parts.find((p) => p.type === name)?.value || "";
    return { branch, businessDate: `${part("year")}-${part("month")}-${part("day")}` };
  };
  const checklistMutationFailure = (error: { code?: string }) => {
    const status = error.code === "42501" ? 403
      : error.code === "P0002" ? 404
      : ["40001", "55000"].includes(error.code || "") ? 409
      : error.code === "22023" ? 422
      : 500;
    const message = error.code === "40001"
      ? "Checklist berubah oleh pengguna lain. Muat ulang sebelum mencoba lagi."
      : error.code === "55000"
      ? "Checklist yang sudah selesai tidak dapat diubah."
      : error.code === "P0002"
      ? "Checklist atau item tidak ditemukan."
      : error.code === "22023"
      ? "Data checklist tidak valid atau belum lengkap."
      : "Perubahan checklist gagal disimpan bersama audit.";
    return fail(message, status, origin);
  };

  if (action === "erp-list-branch-checklists") {
    const branchId = safeText(body.branch_id, 80);
    const context = await checklistContext(branchId);
    if ("error" in context) return context.error;
    const { data, error } = await admin.from("branch_operation_checklist_runs")
      .select("id,branch_id,business_date,checklist_type,template_version,items,status,notes,started_by,completed_by,started_at,completed_at,version,updated_at")
      .eq("branch_id", branchId).eq("business_date", context.businessDate)
      .order("checklist_type");
    if (error) return fail("Checklist cabang gagal dimuat.", 500, origin);
    return json({ business_date: context.businessDate, timezone: context.branch.timezone, branch_status: context.branch.status, runs: data || [], templates: Object.keys(branchChecklistTemplates) }, 200, origin);
  }

  if (action === "erp-start-branch-checklist") {
    const branchId = safeText(body.branch_id, 80);
    const checklistType = safeText(body.checklist_type, 20);
    if (!Object.prototype.hasOwnProperty.call(branchChecklistTemplates, checklistType)) return fail("Jenis checklist tidak valid.", 422, origin);
    const context = await checklistContext(branchId);
    if ("error" in context) return context.error;
    if (context.branch.status !== "active") return fail("Checklist operasional hanya dapat dimulai pada cabang berstatus aktif.", 409, origin);
    const items = branchChecklistTemplates[checklistType].map((item) => ({
      ...item, status: "pending", notes: "", checked_by: null, checked_at: null,
    }));
    const { data: result, error } = await admin.rpc("dlice_manage_branch_checklist", {
      p_action: "start",
      p_actor_user_id: actor.user.id,
      p_branch_id: branchId,
      p_business_date: context.businessDate,
      p_checklist_type: checklistType,
      p_items: items,
    });
    if (error) return checklistMutationFailure(error);
    if (!result?.run) return fail("Checklist gagal dimulai.", 500, origin);
    return json(result, result.existing ? 200 : 201, origin);
  }

  if (action === "erp-update-branch-checklist-item") {
    const runId = safeText(body.run_id, 80);
    const itemKey = safeText(body.item_key, 80);
    const itemStatus = safeText(body.item_status, 20);
    const itemNotes = safeText(body.notes, 500);
    if (!runId || !itemKey || !["passed", "failed", "skipped"].includes(itemStatus)) return fail("Data item checklist tidak valid.", 422, origin);
    if (itemStatus === "failed" && itemNotes.length < 3) return fail("Catatan wajib diisi untuk item yang gagal.", 422, origin);
    const { data: run, error } = await admin.from("branch_operation_checklist_runs")
      .select("id,branch_id,business_date,checklist_type,items,status,version")
      .eq("id", runId).maybeSingle();
    if (error) return fail("Checklist gagal dimuat.", 500, origin);
    if (!run) return fail("Checklist tidak ditemukan.", 404, origin);
    if (!await branchAccess(run.branch_id)) return fail("Akses cabang tidak diizinkan.", 403, origin);
    if (run.status === "completed") return fail("Checklist yang sudah selesai tidak dapat diubah.", 409, origin);
    const { data: result, error: updateError } = await admin.rpc("dlice_manage_branch_checklist", {
      p_action: "update_item",
      p_actor_user_id: actor.user.id,
      p_run_id: runId,
      p_item_key: itemKey,
      p_item_status: itemStatus,
      p_notes: itemNotes,
      p_expected_version: run.version,
    });
    if (updateError) return checklistMutationFailure(updateError);
    if (result?.ok !== true) return fail("Item checklist gagal disimpan.", 500, origin);
    return json(result, 200, origin);
  }

  if (action === "erp-complete-branch-checklist") {
    const runId = safeText(body.run_id, 80);
    if (!runId) return fail("Checklist wajib dipilih.", 422, origin);
    const { data: run, error } = await admin.from("branch_operation_checklist_runs")
      .select("id,branch_id,business_date,checklist_type,items,status,version")
      .eq("id", runId).maybeSingle();
    if (error) return fail("Checklist gagal dimuat.", 500, origin);
    if (!run) return fail("Checklist tidak ditemukan.", 404, origin);
    if (!await branchAccess(run.branch_id)) return fail("Akses cabang tidak diizinkan.", 403, origin);
    const { data: result, error: completeError } = await admin.rpc("dlice_manage_branch_checklist", {
      p_action: "complete",
      p_actor_user_id: actor.user.id,
      p_run_id: runId,
      p_expected_version: run.version,
    });
    if (completeError) return checklistMutationFailure(completeError);
    if (result?.blocked) return fail("Checklist tertahan: semua item kritis harus berstatus lulus.", 409, origin);
    if (result?.ok !== true) return fail("Checklist gagal diselesaikan.", 500, origin);
    return json(result, 200, origin);
  }

  if (action === "erp-list-branches") {
    if(!isOwner&&!["branches","pos","inventory","procurement","finance","reports","hr","staff"].some(hasPerm))return fail("Izin cabang tidak diizinkan.",403,origin);
    const ids=await branchIdsForActor().catch(()=>[]);
    let q=admin.from("branches").select("id,tenant_id,code,name,status,address,city,province,timezone,opening_date,notes,created_at").order("code");
    q=ids?.length?q.in("id",ids):q.eq("id","00000000-0000-0000-0000-000000000000");
    const {data,error}=await q;
    if(error)return fail("Daftar cabang gagal dimuat.",500,origin);
    return json({branches:data||[]},200,origin);
  }

  if (action === "erp-save-branch") {
    if(!isOwner)return fail("Hanya Owner dapat mengubah master cabang.",403,origin);
    const id=safeText(body.id,80),code=safeText(body.code,24).toUpperCase(),name=safeText(body.name,120),status=safeText(body.status,20);
    if(!/^[A-Z0-9-]{2,24}$/.test(code)||!name||!["planned","active","suspended","closed"].includes(status))return fail("Kode, nama, atau status cabang tidak valid.",422,origin);
    const timezone=safeText(body.timezone,80)||"Asia/Jakarta";
    if(!SUPPORTED_BRANCH_TIMEZONES.has(timezone))return fail("Zona waktu cabang tidak didukung.",422,origin);
    const lat=body.latitude==null||body.latitude===""?null:Number(body.latitude),lon=body.longitude==null||body.longitude===""?null:Number(body.longitude),radius=body.service_radius_km==null||body.service_radius_km===""?null:Number(body.service_radius_km),daily=body.daily_order_capacity==null||body.daily_order_capacity===""?null:Number(body.daily_order_capacity);
    if((lat!==null&&(!Number.isFinite(lat)||lat < -90||lat>90))||(lon!==null&&(!Number.isFinite(lon)||lon < -180||lon>180))||(radius!==null&&(!Number.isFinite(radius)||radius<0||radius>500))||(daily!==null&&(!Number.isInteger(daily)||daily<0||daily>100000)))return fail("Koordinat, radius, atau kapasitas harian tidak valid.",422,origin);
    const online=body.accepts_online_orders===true,pickup=body.pickup_enabled!==false,delivery=body.delivery_enabled===true;
    if(online&&status==="active"&&(!safeText(body.city,100)||!safeText(body.address,300)))return fail("Cabang online harus memiliki kota dan alamat.",422,origin);
    const values={code,name,status,address:safeText(body.address,300)||null,city:safeText(body.city,100)||null,province:safeText(body.province,100)||null,timezone,opening_date:safeText(body.opening_date,10)||null,notes:safeText(body.notes,500)||null,latitude:lat,longitude:lon,service_radius_km:radius,accepts_online_orders:online,pickup_enabled:pickup,delivery_enabled:delivery,daily_order_capacity:daily,updated_at:new Date().toISOString()};
    const result=id?await admin.from("branches").update(values).eq("id",id).select("*").single():await admin.from("branches").insert(values).select("*").single();
    if(result.error||!result.data)return fail(result.error?.code==="23505"?"Kode cabang sudah digunakan.":"Cabang gagal disimpan.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"erp_save_branch",entity_type:"branch",entity_id:result.data.id,metadata:{code,status}});
    return json({ok:true,branch:result.data},200,origin);
  }

  if (action === "erp-list-positions") {
    if (!hasPerm("hr") && !hasPerm("staff") && !hasPerm("branches")) return fail("Izin melihat master jabatan tidak diizinkan.", 403, origin);
    const {data,error}=await admin.from("job_positions").select("id,code,title,department,job_description,default_permissions,recommended_headcount_per_branch,is_head_office,is_active").eq("is_active",true).order("is_head_office",{ascending:false}).order("department").order("title");
    if(error)return fail("Daftar jabatan gagal dimuat.",500,origin);
    return json({positions:data||[]},200,origin);
  }

  if (action === "erp-list-assignments") {
    if(!hasPerm("staff")&&!hasPerm("hr")&&!hasPerm("branches"))return fail("Akses penugasan tidak diizinkan.",403,origin);
    const {data,error}=await admin.from("branch_assignments").select("id,branch_id,user_id,job_position_id,employment_status,starts_on,ends_on,branches(code,name,status),job_positions(code,title,department),admin_profiles(username,display_name,role)").order("created_at",{ascending:false}).limit(1000);
    if(error)return fail("Daftar penugasan gagal dimuat.",500,origin);
    const scoped=isOwner?data||[]:(data||[]).filter((x:any)=>x.user_id===actor.user.id);
    return json({assignments:scoped},200,origin);
  }

  if (action === "erp-save-assignment") {
    if(!isOwner)return fail("Hanya Owner yang dapat mengubah penugasan jabatan.",403,origin);
    const branchId=safeText(body.branch_id,80),userId=safeText(body.user_id,80),positionId=safeText(body.job_position_id,80),status=safeText(body.employment_status,20)||"active";
    if(!branchId||!userId||!positionId||!["active","on_leave","inactive"].includes(status))return fail("Cabang, akun, jabatan, atau status tidak valid.",422,origin);
    const {data,error}=await admin.rpc("dlice_save_branch_assignment_audited",{
      p_actor_user_id:actor.user.id,
      p_branch_id:branchId,
      p_user_id:userId,
      p_job_position_id:positionId,
      p_employment_status:status,
      p_starts_on:safeText(body.starts_on,10)||todayDate(),
      p_ends_on:safeText(body.ends_on,10)||null,
    });
    if(error||!data?.ok)return fail("Penugasan dan audit tidak dapat disimpan secara atomik.",409,origin);
    return json({ok:true,assignment:data.assignment},200,origin);
  }

  if (action === "erp-list-inventory") {
    const branchId=safeText(body.branch_id,80);
    if(!branchId||!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    const {data:balances,error:balanceError}=await admin.from("branch_inventory")
      .select("branch_id,inventory_item_id,on_hand,updated_at")
      .eq("branch_id",branchId);
    if(balanceError)return fail("Persediaan gagal dimuat.",500,origin);
    // inventory_items is a shared legacy master without tenant_id. Only expose item metadata
    // referenced by stock rows in the already-authorized branch, never the global catalog.
    const inventoryItemIds=[...new Set((balances||[]).map((row:any)=>row.inventory_item_id).filter(Boolean))];
    const itemsResult=inventoryItemIds.length
      ? await admin.from("inventory_items").select("id,sku,name,unit,category,min_stock,is_active")
          .in("id",inventoryItemIds).order("name").limit(1000)
      : {data:[],error:null};
    if(itemsResult.error)return fail("Persediaan gagal dimuat.",500,origin);
    return json({items:itemsResult.data||[],balances:balances||[]},200,origin);
  }

  if (action === "erp-save-inventory") {
    if (!await hasHQPermission("inventory")) return fail("Master item persediaan global memerlukan izin Inventory Head Office.",403,origin);
    const id=safeText(body.id,80),sku=safeText(body.sku,40).toUpperCase(),name=safeText(body.name,120),unit=safeText(body.unit,20)||"pcs",category=safeText(body.category,40)||"ingredients",minStock=Number(body.min_stock||0);
    if(!/^[A-Z0-9._-]{2,40}$/.test(sku)||!name||!Number.isFinite(minStock)||minStock<0)return fail("SKU, nama, atau minimum stok tidak valid.",422,origin);
    const values={sku,name,unit,category,min_stock:minStock,is_active:body.is_active!==false,updated_at:new Date().toISOString()};
    const result=id?await admin.from("inventory_items").update(values).eq("id",id).select("*").single():await admin.from("inventory_items").insert({...values,created_by:actor.user.id}).select("*").single();
    if(result.error||!result.data)return fail(result.error?.code==="23505"?"SKU sudah digunakan.":"Item persediaan gagal disimpan.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"erp_save_inventory_item",entity_type:"inventory_item",entity_id:result.data.id,metadata:{sku}});
    return json({ok:true,item:result.data},200,origin);
  }

  if (action === "erp-stock-movement") {
    const branchId=safeText(body.branch_id,80),itemId=safeText(body.inventory_item_id,80),type=safeText(body.movement_type,30),qty=Number(body.quantity);
    if(!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(!Number.isFinite(qty)||qty<=0||qty>1000000)return fail("Jumlah pergerakan stok tidak valid.",422,origin);
    const {data,error}=await admin.rpc("erp_record_stock_movement",{p_branch_id:branchId,p_inventory_item_id:itemId,p_movement_type:type,p_quantity:qty,p_notes:safeText(body.notes,500),p_actor_user_id:actor.user.id});
    if(error)return fail(error.message.includes("insufficient_stock")?"Stok tidak mencukupi.":error.message.includes("branch_not_active")?"Cabang belum aktif.":"Pergerakan stok gagal dicatat.",409,origin);
    return json(data,200,origin);
  }


  if (action === "erp-list-stock-transfers") {
    const ids = await branchIdsForActor().catch(() => []);
    const selectedBranch = safeText(body.branch_id, 80);
    if (selectedBranch && !await branchAccess(selectedBranch)) return fail("Akses cabang tidak diizinkan.", 403, origin);
    let sourceQuery = admin.from("stock_transfers").select("id,transfer_number,source_branch_id,destination_branch_id,status,notes,requested_by,shipped_by,received_by,shipped_at,received_at,created_at,updated_at,source_branch:branches!stock_transfers_source_branch_id_fkey(code,name),destination_branch:branches!stock_transfers_destination_branch_id_fkey(code,name),stock_transfer_items(inventory_item_id,quantity,inventory_items(sku,name,unit))").order("created_at", { ascending: false }).limit(250);
    let destinationQuery = admin.from("stock_transfers").select("id,transfer_number,source_branch_id,destination_branch_id,status,notes,requested_by,shipped_by,received_by,shipped_at,received_at,created_at,updated_at,source_branch:branches!stock_transfers_source_branch_id_fkey(code,name),destination_branch:branches!stock_transfers_destination_branch_id_fkey(code,name),stock_transfer_items(inventory_item_id,quantity,inventory_items(sku,name,unit))").order("created_at", { ascending: false }).limit(250);
    if (selectedBranch) { sourceQuery = sourceQuery.eq("source_branch_id", selectedBranch); destinationQuery = destinationQuery.eq("destination_branch_id", selectedBranch); }
    else if (!isOwner) {
      if (!ids?.length) return json({ transfers: [] }, 200, origin);
      sourceQuery = sourceQuery.in("source_branch_id", ids);
      destinationQuery = destinationQuery.in("destination_branch_id", ids);
    }
    const [source, destination] = await Promise.all([sourceQuery, destinationQuery]);
    if (source.error || destination.error) return fail("Daftar transfer stok gagal dimuat.", 500, origin);
    const unique = new Map<string, any>();
    for (const row of [...(source.data || []), ...(destination.data || [])]) unique.set(row.id, row);
    const transfers = [...unique.values()].sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at)).slice(0, 250);
    return json({ transfers }, 200, origin);
  }

  if (action === "erp-create-stock-transfer") {
    const sourceBranchId = safeText(body.source_branch_id, 80), destinationBranchId = safeText(body.destination_branch_id, 80);
    const itemId = safeText(body.inventory_item_id, 80), quantity = Number(body.quantity);
    if (!await branchAccess(sourceBranchId) || !await branchAccess(destinationBranchId)) return fail("Akses ke cabang asal dan tujuan wajib diberikan.", 403, origin);
    if (!itemId || !Number.isFinite(quantity) || quantity <= 0 || quantity > 100000000 || sourceBranchId === destinationBranchId) return fail("Cabang tujuan, item, dan jumlah transfer harus valid.", 422, origin);
    // Enforce tenant equality before the RPC; branch access alone does not
    // prove that both endpoints belong to the same tenant.
    const { data: transferBranches, error: branchScopeError } = await admin.from("branches")
      .select("id,tenant_id")
      .in("id", [sourceBranchId, destinationBranchId]);
    if (branchScopeError) return fail("Cakupan cabang transfer gagal diperiksa.", 500, origin);
    if (transferBranches?.length !== 2) return fail("Cakupan cabang transfer tidak dapat diverifikasi.", 403, origin);
    const sourceTenantId = transferBranches.find((branch: { id: string; tenant_id: string | null }) => branch.id === sourceBranchId)?.tenant_id;
    const destinationTenantId = transferBranches.find((branch: { id: string; tenant_id: string | null }) => branch.id === destinationBranchId)?.tenant_id;
    if (!sourceTenantId || !destinationTenantId || sourceTenantId !== destinationTenantId) {
      return fail("Transfer stok hanya diizinkan antar cabang dalam tenant yang sama.", 403, origin);
    }
    const idempotencyKey = safeText(body.idempotency_key, 160);
    if (idempotencyKey.length < 8) return fail("Kunci idempotensi transfer tidak valid.", 422, origin);
    const transferNumber = safeText(body.transfer_number, 60) || "TRF-" + new Date().toISOString().replace(/[-:.TZ]/g, "").slice(0, 14) + "-" + crypto.randomUUID().slice(0, 8).toUpperCase();
    const { data, error } = await admin.rpc("erp_create_stock_transfer", {
      p_transfer_number: transferNumber, p_source_branch_id: sourceBranchId, p_destination_branch_id: destinationBranchId,
      p_items: [{ inventory_item_id: itemId, quantity }], p_actor_user_id: actor.user.id,
      p_idempotency_key: idempotencyKey, p_notes: safeText(body.notes, 500) || null,
    });
    if (error) return fail(error.message.includes("inactive_or_missing_branch") ? "Cabang asal dan tujuan harus aktif." : error.message.includes("idempotency_key_payload_mismatch") ? "Kunci idempotensi telah digunakan untuk data berbeda." : "Transfer stok gagal dibuat.", 409, origin);
    await admin.from("admin_audit_logs").insert({ actor_user_id: actor.user.id, action: "stock_transfer_created", entity_type: "stock_transfer", entity_id: data?.id, metadata: { source_branch_id: sourceBranchId, destination_branch_id: destinationBranchId, item_id: itemId, quantity } });
    return json({ ok: true, transfer: data }, 201, origin);
  }

  if (action === "erp-transition-stock-transfer") {
    const transferId = safeText(body.transfer_id, 80), transition = safeText(body.transition, 20);
    if (!transferId || !["approve", "pick", "ship", "receive", "reconcile", "cancel"].includes(transition)) return fail("Transisi transfer tidak valid.", 422, origin);
    const { data: transfer, error: transferError } = await admin.from("stock_transfers").select("id,transfer_number,source_branch_id,destination_branch_id,status").eq("id", transferId).maybeSingle();
    if (transferError || !transfer) return fail("Transfer stok tidak ditemukan.", 404, origin);
    // Stock transfers are strictly intra-tenant for every actor and every
    // transition. Platform Owner does not bypass this inventory boundary.
    const { data: transferBranches, error: branchScopeError } = await admin.from("branches")
      .select("id,tenant_id")
      .in("id", [transfer.source_branch_id, transfer.destination_branch_id]);
    if (branchScopeError) return fail("Cakupan cabang transfer gagal diperiksa.", 500, origin);
    if (transferBranches?.length !== 2) return fail("Cakupan cabang transfer tidak dapat diverifikasi.", 403, origin);
    const sourceTenantId = transferBranches.find((branch: { id: string; tenant_id: string | null }) => branch.id === transfer.source_branch_id)?.tenant_id;
    const destinationTenantId = transferBranches.find((branch: { id: string; tenant_id: string | null }) => branch.id === transfer.destination_branch_id)?.tenant_id;
    if (!sourceTenantId || !destinationTenantId || sourceTenantId !== destinationTenantId) {
      return fail("Transfer stok hanya diizinkan antar cabang dalam tenant yang sama.", 403, origin);
    }
    if (transition === "approve") {
      const approvalAuthorized = await hasHQPermissionForTenant("inventory", sourceTenantId);
      if (approvalAuthorized === null) return fail("Otorisasi Inventory Head Office gagal diperiksa.", 500, origin);
      if (!approvalAuthorized) {
        return fail("Persetujuan transfer memerlukan izin Inventory Head Office pada tenant terkait.", 403, origin);
      }
    }
    const branchToCheck = ["receive", "reconcile"].includes(transition) ? transfer.destination_branch_id : transfer.source_branch_id;
    if (transition !== "approve" && !await branchAccess(branchToCheck)) return fail("Akses cabang untuk tindakan ini tidak diizinkan.", 403, origin);
    if (transition === "cancel" && !["draft", "approved", "picked"].includes(transfer.status)) return fail("Transfer hanya dapat dibatalkan sebelum dikirim.", 409, origin);
    const expectedStatus: Record<string, string> = { approve: "draft", pick: "approved", ship: "picked", receive: "shipped", reconcile: "received" };
    if (expectedStatus[transition] && transfer.status !== expectedStatus[transition] && transfer.status !== ({approve:"approved",pick:"picked",ship:"shipped",receive:"received",reconcile:"reconciled"} as Record<string,string>)[transition]) return fail("Tahap transfer belum sesuai. Muat ulang status terbaru.", 409, origin);
    const { data, error } = await admin.rpc("erp_transition_stock_transfer", { p_transfer_id: transferId, p_actor_user_id: actor.user.id, p_transition: transition });
    if (error) return fail(error.message.includes("insufficient_stock_for_transfer") ? "Stok cabang asal tidak mencukupi." : error.message.includes("stock_transfer_ledger_incomplete") ? "Ledger transfer belum lengkap; rekonsiliasi ditahan." : "Status transfer gagal diperbarui.", 409, origin);
    await admin.from("admin_audit_logs").insert({ actor_user_id: actor.user.id, action: "stock_transfer_" + transition, entity_type: "stock_transfer", entity_id: transferId, metadata: { transfer_number: transfer.transfer_number, source_branch_id: transfer.source_branch_id, destination_branch_id: transfer.destination_branch_id } });
    return json({ ok: true, result: data }, 200, origin);
  }

  if (action === "erp-list-stock-counts") {
    const ids = await branchIdsForActor().catch(() => []);
    const selectedBranch = safeText(body.branch_id, 80);
    if (selectedBranch && !await branchAccess(selectedBranch)) return fail("Akses cabang tidak diizinkan.", 403, origin);
    let query = admin.from("stock_counts").select("id,count_number,branch_id,status,notes,counted_by,posted_by,posted_at,created_at,updated_at,branches(code,name),stock_count_items(id,inventory_item_id,expected_quantity,counted_quantity,inventory_items(sku,name,unit))").order("created_at", { ascending: false }).limit(200);
    if (selectedBranch) query = query.eq("branch_id", selectedBranch);
    else if (!isOwner) query = ids?.length ? query.in("branch_id", ids) : query.eq("branch_id", "00000000-0000-0000-0000-000000000000");
    const { data, error } = await query;
    if (error) return fail("Daftar stock opname gagal dimuat.", 500, origin);
    return json({ counts: data || [] }, 200, origin);
  }

  if (action === "erp-create-stock-count") {
    const branchId = safeText(body.branch_id, 80), items = body.items;
    if (!await branchAccess(branchId)) return fail("Akses cabang tidak diizinkan.", 403, origin);
    if (!Array.isArray(items) || items.length < 1 || items.length > 1000) return fail("Pilih item untuk stock opname.", 422, origin);
    const cleanItems = items.map((item: any) => ({ inventory_item_id: safeText(item?.inventory_item_id, 80) }));
    if (cleanItems.some((item: any) => !item.inventory_item_id) || new Set(cleanItems.map((item: any) => item.inventory_item_id)).size !== cleanItems.length) return fail("Item opname tidak valid atau duplikat.", 422, origin);
    const idempotencyKey = safeText(body.idempotency_key, 160);
    if (idempotencyKey.length < 8) return fail("Kunci idempotensi opname tidak valid.", 422, origin);
    const countNumber = safeText(body.count_number, 60) || "CNT-" + new Date().toISOString().slice(0, 10).replace(/-/g, "") + "-" + crypto.randomUUID().slice(0, 8).toUpperCase();
    const { data, error } = await admin.rpc("erp_create_stock_count", { p_count_number: countNumber, p_branch_id: branchId, p_items: cleanItems, p_actor_user_id: actor.user.id, p_idempotency_key: idempotencyKey, p_notes: safeText(body.notes, 500) || null });
    if (error) return fail(error.message.includes("inactive_or_missing_branch") ? "Stock opname hanya dapat dimulai pada cabang aktif." : "Stock opname gagal dibuat.", 409, origin);
    await admin.from("admin_audit_logs").insert({ actor_user_id: actor.user.id, action: "stock_count_created", entity_type: "stock_count", entity_id: data?.id, metadata: { branch_id: branchId, item_count: cleanItems.length } });
    return json({ ok: true, count: data }, 201, origin);
  }

  if (action === "erp-update-stock-count-item") {
    const countId = safeText(body.count_id, 80), itemId = safeText(body.item_id, 80), quantity = Number(body.counted_quantity);
    if (!countId || !itemId || !Number.isFinite(quantity) || quantity < 0 || quantity > 100000000) return fail("Jumlah hasil hitung tidak valid.", 422, origin);
    const { data: count } = await admin.from("stock_counts").select("id,branch_id,status").eq("id", countId).maybeSingle();
    if (!count) return fail("Stock opname tidak ditemukan.", 404, origin);
    if (!await branchAccess(count.branch_id)) return fail("Akses cabang tidak diizinkan.", 403, origin);
    if (count.status !== "draft") return fail("Stock opname yang sudah diposting tidak dapat diubah.", 409, origin);
    const { data, error } = await admin.rpc("erp_update_stock_count_item", { p_count_id: countId, p_item_id: itemId, p_counted_quantity: quantity });
    if (error || data !== true) return fail("Jumlah hasil hitung gagal disimpan.", 409, origin);
    await admin.from("admin_audit_logs").insert({ actor_user_id: actor.user.id, action: "stock_count_item_updated", entity_type: "stock_count", entity_id: countId, metadata: { item_id: itemId, counted_quantity: quantity } });
    return json({ ok: true }, 200, origin);
  }

  if (action === "erp-post-stock-count") {
    const countId = safeText(body.count_id, 80);
    const { data: count } = await admin.from("stock_counts").select("id,branch_id,status").eq("id", countId).maybeSingle();
    if (!count) return fail("Stock opname tidak ditemukan.", 404, origin);
    if (!await branchAccess(count.branch_id)) return fail("Akses cabang tidak diizinkan.", 403, origin);
    if (count.status !== "draft") return fail("Stock opname sudah diposting atau tidak lagi berstatus draft.", 409, origin);
    const { data, error } = await admin.rpc("erp_post_stock_count", { p_count_id: countId, p_actor_user_id: actor.user.id });
    if (error) return fail(error.message.includes("stock_count_items_incomplete") ? "Isi semua jumlah aktual sebelum posting opname." : "Posting stock opname gagal.", 409, origin);
    await admin.from("admin_audit_logs").insert({ actor_user_id: actor.user.id, action: "stock_count_posted", entity_type: "stock_count", entity_id: countId, metadata: { branch_id: count.branch_id } });
    return json({ ok: true, result: data }, 200, origin);
  }

  if (action === "erp-list-shifts") {
    const branchId=safeText(body.branch_id,80),ids=await branchIdsForActor().catch(()=>[]);
    let q=admin.from("pos_shifts").select("id,branch_id,opened_by,closed_by,opening_cash_idr,expected_cash_idr,counted_cash_idr,cash_variance_idr,status,opened_at,closed_at,notes,branches(code,name),admin_profiles!pos_shifts_opened_by_fkey(username,display_name)").order("opened_at",{ascending:false}).limit(100);
    if(branchId&&!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(branchId)q=q.eq("branch_id",branchId);else q=ids?.length?q.in("branch_id",ids):q.eq("branch_id","00000000-0000-0000-0000-000000000000");
    const {data,error}=await q;if(error)return fail("Daftar shift gagal dimuat.",500,origin);
    return json({shifts:data||[]},200,origin);
  }

  if (action === "erp-open-shift") {
    const branchId=safeText(body.branch_id,80),cash=Number(body.opening_cash_idr||0);
    if(!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(!Number.isFinite(cash)||cash<0||cash>1000000000)return fail("Saldo awal kas tidak valid.",422,origin);
    const {data,error}=await admin.from("pos_shifts").insert({branch_id:branchId,opened_by:actor.user.id,opening_cash_idr:Math.round(cash),expected_cash_idr:Math.round(cash),status:"open"}).select("*").single();
    if(error||!data)return fail("Shift gagal dibuka. Pastikan cabang aktif dan tidak ada shift terbuka milik Anda.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"pos_shift_opened",entity_type:"pos_shift",entity_id:data.id,metadata:{branch_id:branchId,opening_cash_idr:cash}});
    return json({ok:true,shift:data},201,origin);
  }

  if (action === "erp-close-shift") {
    const shiftId=safeText(body.shift_id,80),counted=Number(body.counted_cash_idr),note=safeText(body.notes,500);
    if(!Number.isFinite(counted)||counted<0||counted>1000000000)return fail("Kas hasil hitung tidak valid.",422,origin);
    const {data:old,error:oldError}=await admin.from("pos_shifts").select("*").eq("id",shiftId).maybeSingle();
    if(oldError||!old)return fail("Shift tidak ditemukan.",404,origin);
    if(!isOwner&&old.opened_by!==actor.user.id&&!hasPerm("branches"))return fail("Hanya pembuka shift atau Owner yang dapat menutup shift ini.",403,origin);
    if(!await branchAccess(old.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(old.status!=="open")return fail("Shift sudah ditutup.",409,origin);
    const variance=Math.round(counted)-Number(old.expected_cash_idr);
    const {data,error}=await admin.from("pos_shifts").update({status:"closed",counted_cash_idr:Math.round(counted),cash_variance_idr:variance,closed_by:actor.user.id,closed_at:new Date().toISOString(),notes:note}).eq("id",shiftId).eq("status","open").select("*").maybeSingle();
    if(error||!data)return fail("Shift berubah saat proses berlangsung; muat ulang.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"pos_shift_closed",entity_type:"pos_shift",entity_id:shiftId,metadata:{expected_cash_idr:old.expected_cash_idr,counted_cash_idr:counted,cash_variance_idr:variance}});
    return json({ok:true,shift:data},200,origin);
  }

  if (action === "erp-create-pos-sale") {
    const branchId=safeText(body.branch_id,80),shiftId=safeText(body.shift_id,80),items=body.items;
    const method=safeText(body.payment_method,20),discount=Number(body.discount_idr||0);
    if(!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(!Array.isArray(items)||!items.length||items.length>50)return fail("Pilih minimal satu menu.",422,origin);
    if(!Number.isFinite(discount)||discount<0||(!isOwner&&discount>0))return fail("Diskon hanya dapat diberikan Owner sampai alur persetujuan diskon diaktifkan.",403,origin);
    const cleanItems=items.map((x:any)=>({
      slug:safeText(x?.slug,80),quantity:Number(x?.quantity),
      modifiers:Array.isArray(x?.modifiers)?x.modifiers.map((m:any)=>({code:safeText(m?.code,40)})) : [],
      substitutions:Array.isArray(x?.substitutions)?x.substitutions.map((sub:any)=>({recipe_ingredient_id:safeText(sub?.recipe_ingredient_id,80),substitute_inventory_item_id:safeText(sub?.substitute_inventory_item_id,80)})) : []
    }));
    if(cleanItems.some((x:any)=>!/^[a-z0-9-]+$/.test(x.slug)||!Number.isInteger(x.quantity)||x.quantity<1||x.quantity>1000||x.modifiers.length>20||x.substitutions.length>100))return fail("Item, modifier, substitusi, atau jumlah tidak valid.",422,origin);
    const idempotencyKey=safeText(body.idempotency_key,120)||crypto.randomUUID();
    const {data,error}=await admin.rpc("erp_create_pos_sale_idempotent",{p_branch_id:branchId,p_shift_id:shiftId,p_items:cleanItems,p_payment_method:method,p_discount_idr:Math.round(discount),p_customer_reference:safeText(body.customer_reference,120),p_notes:safeText(body.notes,500),p_actor_user_id:actor.user.id,p_idempotency_key:idempotencyKey});
    if(error)return fail(error.message.includes("open_shift_required")?"Buka shift kasir terlebih dahulu.":error.message.includes("product_unavailable")?"Menu tidak aktif atau harga belum ditetapkan.":error.message.includes("insufficient_stock")?"Stok bahan tidak mencukupi; transaksi dibatalkan.":error.message.includes("active_recipe_required")?"Aktifkan resep sebelum mengaktifkan pelacakan stok.":error.message.includes("idempotency_key_payload_mismatch")?"Kunci transaksi sudah digunakan untuk isi transaksi yang berbeda.":error.message.includes("invalid_modifier")?"Modifier tidak aktif atau tidak sesuai dengan menu.":error.message.includes("invalid_recipe_substitution")?"Substitusi bahan belum disetujui untuk resep aktif.":"Transaksi POS gagal. Periksa shift, resep, stok, dan item.",409,origin);
    return json({...data,idempotency_key:idempotencyKey},data?.idempotent_replay?200:201,origin);
  }


  if (action === "erp-list-kitchen-tickets") {
    if(!hasPerm("production")&&!hasPerm("pos")&&!hasPerm("orders"))return fail("Izin KDS tidak diizinkan.",403,origin);
    const branchId=safeText(body.branch_id,80),status=safeText(body.status,20),ids=await branchIdsForActor().catch(()=>[]);
    if(branchId&&!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    let q=admin.from("kitchen_tickets").select("id,ticket_number,branch_id,order_id,pos_sale_id,status,version,priority,notes,created_at,accepted_at,started_at,ready_at,served_at,branches(code,name),kitchen_ticket_items(id,product_id,product_name_snapshot,quantity,modifier_snapshot,substitution_snapshot,notes,status)").order("priority").order("created_at").limit(300);
    if(branchId)q=q.eq("branch_id",branchId);else q=ids?.length?q.in("branch_id",ids):q.eq("branch_id","00000000-0000-0000-0000-000000000000");
    if(status){if(!["queued","accepted","preparing","ready","served","cancelled","blocked"].includes(status))return fail("Status KDS tidak valid.",422,origin);q=q.eq("status",status);}
    const {data,error}=await q;if(error)return fail("Antrean kitchen belum dapat dimuat. Pastikan migrasi KDS sudah diterapkan.",503,origin);
    return json({tickets:data||[]},200,origin);
  }

  if (action === "erp-transition-kitchen-ticket") {
    if(!hasPerm("production")&&!hasPerm("orders")&&!hasPerm("pos"))return fail("Izin KDS tidak diizinkan.",403,origin);
    const ticketId=safeText(body.ticket_id,80),next=safeText(body.status,20),note=safeText(body.notes,500);
    if(!ticketId||!["accepted","preparing","ready","served","cancelled","blocked"].includes(next))return fail("Perubahan status KDS tidak valid.",422,origin);
    const {data:ticket,error:ticketError}=await admin.from("kitchen_tickets").select("id,branch_id,status,version").eq("id",ticketId).maybeSingle();
    if(ticketError)return fail("KDS belum siap. Pastikan migrasi KDS sudah diterapkan.",503,origin);
    if(!ticket)return fail("Tiket kitchen tidak ditemukan.",404,origin);
    if(!await branchAccess(ticket.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);
    const {data,error}=await admin.rpc("erp_transition_kitchen_ticket",{p_ticket_id:ticketId,p_next_status:next,p_actor_user_id:actor.user.id,p_notes:note||null});
    if(error)return fail(error.message.includes("kitchen_ticket_transition_invalid")?"Perubahan status KDS tidak diizinkan dari status saat ini.":"Status tiket kitchen gagal disimpan.",409,origin);
    return json(data,200,origin);
  }

  if (action === "erp-sync-offline-operation") {
    if(!hasPerm("pos"))return fail("Izin POS diperlukan untuk sinkronisasi offline.",403,origin);
    const deviceId=safeText(body.device_id,120),operationId=safeText(body.client_operation_id,120),operation=body.operation as Record<string,unknown>;
    if(!deviceId||operationId.length<8||operationId.length>120||!operation||typeof operation!=="object"||Array.isArray(operation))return fail("Data sinkronisasi offline tidak valid.",422,origin);
    if(safeText(operation.type,30)!=="pos-sale")return fail("Jenis operasi offline belum didukung.",422,origin);
    const branchId=safeText(operation.branch_id,80),shiftId=safeText(operation.shift_id,80);
    if(!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    const fingerprint=await sha256(JSON.stringify(operation));
    const {data:prior,error:priorError}=await admin.from("offline_sync_receipts").select("id,branch_id,actor_user_id,client_operation_id,payload_fingerprint,result").eq("device_id",deviceId).eq("client_operation_id",operationId).maybeSingle();
    if(priorError)return fail("Penerimaan sinkronisasi offline belum tersedia. Pastikan migrasi sudah diterapkan.",503,origin);
    if(prior){
      if(prior.actor_user_id!==actor.user.id||prior.branch_id!==branchId||prior.payload_fingerprint!==fingerprint)return fail("ID operasi offline sudah dipakai untuk payload berbeda.",409,origin);
      return json({ok:true,replayed:true,result:prior.result},200,origin);
    }
    const items=Array.isArray(operation.items)?(operation.items as any[]).map((x:any)=>({slug:safeText(x?.slug,80),quantity:Number(x?.quantity),modifiers:Array.isArray(x?.modifiers)?x.modifiers:[],substitutions:Array.isArray(x?.substitutions)?x.substitutions:[]})): [];
    if(!items.length||items.some((x:any)=>!/^[a-z0-9-]+$/.test(x.slug)||!Number.isInteger(x.quantity)||x.quantity<1||x.quantity>1000))return fail("Item transaksi offline tidak valid.",422,origin);
    const key=operationId;
    const {data:result,error}=await admin.rpc("erp_create_pos_sale_idempotent",{p_branch_id:branchId,p_shift_id:shiftId,p_items:items,p_payment_method:safeText(operation.payment_method,20),p_discount_idr:Math.round(Number(operation.discount_idr||0)),p_customer_reference:safeText(operation.customer_reference,120),p_notes:safeText(operation.notes,500),p_actor_user_id:actor.user.id,p_idempotency_key:key});
    if(error)return fail(error.message.includes("insufficient_stock")?"Sinkronisasi ditolak karena stok tidak mencukupi.":error.message.includes("open_shift_required")?"Shift terkait tidak lagi terbuka; minta supervisor menyelesaikan transaksi.":"Operasi offline gagal divalidasi. Transaksi belum disinkronkan.",409,origin);
    const {data:receipt,error:receiptError}=await admin.from("offline_sync_receipts").insert({branch_id:branchId,actor_user_id:actor.user.id,device_id:deviceId,client_operation_id:operationId,operation_type:"pos-sale",payload_fingerprint:fingerprint,result}).select("id,client_operation_id,synced_at").single();
    if(receiptError){
      const {data:retry}=await admin.from("offline_sync_receipts").select("actor_user_id,branch_id,payload_fingerprint,result").eq("device_id",deviceId).eq("client_operation_id",operationId).maybeSingle();
      if(retry&&retry.actor_user_id===actor.user.id&&retry.branch_id===branchId&&retry.payload_fingerprint===fingerprint)return json({ok:true,replayed:true,result:retry.result},200,origin);
      return fail("Transaksi diproses dengan kunci idempoten, tetapi tanda terima sinkronisasi perlu diulang.",503,origin);
    }
    return json({ok:true,replayed:false,receipt,result},201,origin);
  }


  if (action === "erp-reconcile-pos-sale") {
    if(!isOwner&&!hasPerm("reports"))return fail("Izin laporan/reconciliaton POS diperlukan.",403,origin);
    const saleId=safeText(body.sale_id,80),branchId=safeText(body.branch_id,80);
    if(!saleId||!branchId)return fail("ID transaksi dan cabang wajib diisi.",422,origin);
    if(!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    const {data:sale,error:saleError}=await admin.from("pos_sales").select("id,transaction_code,branch_id,shift_id,cashier_user_id,subtotal_idr,discount_idr,total_idr,payment_method,payment_status,customer_reference,notes,created_at").eq("id",saleId).eq("branch_id",branchId).maybeSingle();
    if(saleError)return fail("Rekonsiliasi transaksi POS gagal dimuat.",503,origin);
    if(!sale)return fail("Transaksi POS tidak ditemukan di cabang ini.",404,origin);
    const [itemsResult,ticketResult,movementsResult]=await Promise.all([
      admin.from("pos_sale_items").select("id,product_id,product_name_snapshot,quantity,unit_price_idr,line_total_idr,modifier_snapshot,substitution_snapshot").eq("sale_id",saleId).order("id"),
      admin.from("kitchen_tickets").select("id,ticket_number,branch_id,status,version,created_at,served_at,kitchen_ticket_items(id,product_name_snapshot,quantity,modifier_snapshot,substitution_snapshot,status)").eq("pos_sale_id",saleId).maybeSingle(),
      admin.from("stock_movements").select("id,inventory_item_id,movement_type,quantity,reference_type,reference_id,notes,created_at").eq("branch_id",branchId).eq("reference_type","pos_sale").eq("reference_id",saleId).order("created_at")
    ]);
    if(itemsResult.error||ticketResult.error||movementsResult.error)return fail("Detail rekonsiliasi POS/KDS/stok gagal dimuat.",503,origin);
    const entityIds=[saleId,...(ticketResult.data?.id?[ticketResult.data.id]:[])];
    const {data:audit,error:auditError}=await admin.from("admin_audit_logs").select("actor_user_id,action,entity_type,entity_id,metadata,created_at").in("entity_id",entityIds).order("created_at");
    if(auditError)return fail("Audit trail rekonsiliasi tidak tersedia.",503,origin);
    const {data:balances,error:balanceError}=await admin.from("branch_inventory").select("inventory_item_id,on_hand,updated_at").eq("branch_id",branchId);
    if(balanceError)return fail("Saldo stok rekonsiliasi tidak tersedia.",503,origin);
    return json({ok:true,sale,items:itemsResult.data||[],kitchen_ticket:ticketResult.data||null,stock_movements:movementsResult.data||[],stock_balances:balances||[],audit_events:audit||[]},200,origin);
  }

  if (action === "erp-list-sales") {
    if(!hasPerm("pos")&&!hasPerm("reports"))return fail("Izin laporan POS tidak diizinkan.",403,origin);
    const branchId=safeText(body.branch_id,80),since=safeText(body.since,10),ids=await branchIdsForActor().catch(()=>[]);
    let q=admin.from("pos_sales").select("id,transaction_code,branch_id,shift_id,cashier_user_id,subtotal_idr,discount_idr,total_idr,payment_method,payment_status,customer_reference,notes,created_at,branches(code,name),pos_sale_items(product_name_snapshot,quantity,unit_price_idr,line_total_idr)").order("created_at",{ascending:false}).limit(200);
    if(branchId&&!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(branchId)q=q.eq("branch_id",branchId);else q=ids?.length?q.in("branch_id",ids):q.eq("branch_id","00000000-0000-0000-0000-000000000000");
    if(since)q=q.gte("created_at",since+"T00:00:00");
    const {data,error}=await q;if(error)return fail("Laporan POS gagal dimuat.",500,origin);
    return json({sales:data||[]},200,origin);
  }

  if (action === "erp-list-expenses") {
    const branchId=safeText(body.branch_id,80),ids=await branchIdsForActor().catch(()=>[]);
    let q=admin.from("branch_expenses").select("id,expense_code,branch_id,category,description,amount_idr,payment_method,status,receipt_reference,created_by,reviewed_by,reviewed_at,created_at,branches(code,name),admin_profiles!branch_expenses_created_by_fkey(username,display_name)").order("created_at",{ascending:false}).limit(200);
    if(branchId&&!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(branchId)q=q.eq("branch_id",branchId);else q=ids?.length?q.in("branch_id",ids):q.eq("branch_id","00000000-0000-0000-0000-000000000000");
    const {data,error}=await q;if(error)return fail("Daftar biaya gagal dimuat.",500,origin);
    return json({expenses:data||[]},200,origin);
  }

  if (action === "erp-create-expense") {
    const branchId=safeText(body.branch_id,80),category=safeText(body.category,60),description=safeText(body.description,240),amount=Number(body.amount_idr),method=safeText(body.payment_method,20);
    if(!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(!category||!description||!Number.isFinite(amount)||amount<=0||amount>1000000000||!["cash","bank_transfer","qris","other"].includes(method))return fail("Data biaya tidak valid.",422,origin);
    const code="EXP-"+new Date().toISOString().slice(0,10).replaceAll("-","")+"-"+crypto.randomUUID().slice(0,6).toUpperCase();
    const {data,error}=await admin.from("branch_expenses").insert({expense_code:code,branch_id:branchId,category,description,amount_idr:Math.round(amount),payment_method:method,status:"pending_approval",receipt_reference:safeText(body.receipt_reference,120)||null,created_by:actor.user.id}).select("*").single();
    if(error||!data)return fail("Biaya gagal dicatat.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"erp_expense_submitted",entity_type:"branch_expense",entity_id:data.id,metadata:{amount_idr:amount,branch_id:branchId}});
    return json({ok:true,expense:data},201,origin);
  }

  if (action === "erp-review-expense") {
    if(!isOwner&&!hasPerm("finance"))return fail("Izin Finance diperlukan.",403,origin);
    const id=safeText(body.id,80),next=safeText(body.status,20),note=safeText(body.note,500);
    if(!["approved","rejected","paid"].includes(next))return fail("Status persetujuan tidak valid.",422,origin);
    const {data:old}=await admin.from("branch_expenses").select("id,created_by,status,branch_id,amount_idr").eq("id",id).maybeSingle();
    if(!old)return fail("Biaya tidak ditemukan.",404,origin);
    if(old.created_by===actor.user.id)return fail("Pemisahan tugas: pembuat biaya tidak boleh menyetujui biaya sendiri.",403,origin);
    if(!await branchAccess(old.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(next==="paid"&&old.status!=="approved")return fail("Biaya harus disetujui sebelum dibayar.",409,origin);
    if(next==="approved"&&old.status!=="pending_approval")return fail("Hanya biaya yang menunggu persetujuan yang dapat disetujui.",409,origin);
    if(next==="rejected"&&old.status!=="pending_approval")return fail("Hanya biaya yang menunggu persetujuan yang dapat ditolak.",409,origin);
    const {data,error}=await admin.from("branch_expenses").update({status:next,reviewed_by:actor.user.id,reviewed_at:new Date().toISOString()}).eq("id",id).eq("status",old.status).select("*").maybeSingle();
    if(error||!data)return fail("Status biaya berubah; muat ulang.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"erp_expense_"+next,entity_type:"branch_expense",entity_id:id,metadata:{amount_idr:old.amount_idr,note}});
    return json({ok:true,expense:data},200,origin);
  }

  if (action === "erp-reconcile-purchase-requisition") {
    if (!isOwner) return fail("Rekonsiliasi requisition hanya dapat diakses Owner.", 403, origin);
    const id = safeText(body.id, 80);
    if (!id) return fail("ID requisition wajib diisi.", 422, origin);
    const { data: requisition, error: reqError } = await admin.from("purchase_requisitions")
      .select("id,requisition_number,branch_id,status,purpose,needed_by,notes,estimated_total_idr,requested_by,approved_by,rejected_by,converted_purchase_order_id,submitted_at,approved_at,rejected_at,converted_at,created_at,updated_at")
      .eq("id", id).maybeSingle();
    if (reqError || !requisition) return fail("Purchase requisition tidak ditemukan.", 404, origin);
    if (!await branchAccess(requisition.branch_id)) return fail("Akses cabang tidak diizinkan.", 403, origin);
    const [lines, audit] = await Promise.all([
      admin.from("purchase_requisition_items")
        .select("id,requisition_id,inventory_item_id,item_name_snapshot,quantity,estimated_unit_cost_idr,estimated_line_total_idr,notes")
        .eq("requisition_id", requisition.id).order("created_at", { ascending: true }),
      admin.from("admin_audit_logs")
        .select("id,action,entity_type,entity_id,metadata,created_at")
        .eq("entity_type", "purchase_requisition").eq("entity_id", requisition.id)
        .order("created_at", { ascending: true }),
    ]);
    if (lines.error || audit.error) return fail("Rekonsiliasi requisition/audit gagal dimuat.", 500, origin);
    let purchaseOrder = null;
    let purchaseOrderItems = [];
    if (requisition.converted_purchase_order_id) {
      const { data: po, error: poError } = await admin.from("purchase_orders")
        .select("id,po_number,branch_id,supplier_id,status,subtotal_idr,requested_by,approved_by,notes,created_at")
        .eq("id", requisition.converted_purchase_order_id).maybeSingle();
      if (poError || !po) return fail("PO hasil konversi tidak ditemukan.", 409, origin);
      const { data: poLines, error: poLinesError } = await admin.from("purchase_order_items")
        .select("id,purchase_order_id,inventory_item_id,item_name_snapshot,quantity,unit_cost_idr,line_total_idr")
        .eq("purchase_order_id", po.id).order("id", { ascending: true });
      if (poLinesError) return fail("Detail PO hasil konversi gagal dimuat.", 500, origin);
      purchaseOrder = po;
      purchaseOrderItems = poLines || [];
    }
    return json({
      requisition,
      items: lines.data || [],
      purchase_order: purchaseOrder,
      purchase_order_items: purchaseOrderItems,
      audit_events: audit.data || [],
    }, 200, origin);
  }

  if (action === "erp-list-purchase-requisitions") {
    const branchId = safeText(body.branch_id, 80);
    const ids = await branchIdsForActor().catch(() => []);
    let q = admin.from("purchase_requisitions")
      .select("id,requisition_number,branch_id,status,purpose,needed_by,notes,estimated_total_idr,requested_by,approved_by,rejected_by,converted_purchase_order_id,submitted_at,approved_at,rejected_at,converted_at,created_at,updated_at,branches(code,name),purchase_requisition_items(id,inventory_item_id,item_name_snapshot,quantity,estimated_unit_cost_idr,estimated_line_total_idr,notes)")
      .order("created_at", { ascending: false }).limit(200);
    if (branchId && !await branchAccess(branchId)) return fail("Akses cabang tidak diizinkan.", 403, origin);
    if (branchId) q = q.eq("branch_id", branchId);
    else q = ids?.length ? q.in("branch_id", ids) : q.eq("branch_id", "00000000-0000-0000-0000-000000000000");
    const { data, error } = await q;
    if (error) return fail("Purchase requisition gagal dimuat.", 500, origin);
    return json({ purchase_requisitions: data || [] }, 200, origin);
  }

  if (action === "erp-create-purchase-requisition") {
    const branchId = safeText(body.branch_id, 80);
    const purpose = safeText(body.purpose, 200);
    const neededBy = safeText(body.needed_by, 10);
    const items = body.items;
    if (!branchId || !await branchAccess(branchId)) return fail("Akses cabang tidak diizinkan.", 403, origin);
    if (purpose.length < 3) return fail("Tujuan pembelian minimal 3 karakter.", 422, origin);
    if (neededBy && !/^\d{4}-\d{2}-\d{2}$/.test(neededBy)) return fail("Tanggal kebutuhan tidak valid.", 422, origin);
    if (!Array.isArray(items) || items.length < 1 || items.length > 100) return fail("Tambahkan 1–100 item kebutuhan.", 422, origin);
    const cleaned = [];
    for (const item of items) {
      const inventoryItemId = safeText(item?.inventory_item_id, 80);
      const quantity = Number(item?.quantity);
      const unitCost = Number(item?.estimated_unit_cost_idr ?? 0);
      if (!inventoryItemId || !Number.isFinite(quantity) || quantity <= 0 || quantity > 100000 ||
          !Number.isFinite(unitCost) || unitCost < 0 || unitCost > 1000000000) {
        return fail("Item, jumlah, atau estimasi harga tidak valid.", 422, origin);
      }
      cleaned.push({
        inventory_item_id: inventoryItemId,
        quantity,
        estimated_unit_cost_idr: Math.round(unitCost),
        notes: safeText(item?.notes, 250) || null,
      });
    }
    const { data, error } = await admin.rpc("erp_create_purchase_requisition", {
      p_branch_id: branchId,
      p_items: cleaned,
      p_requested_by: actor.user.id,
      p_purpose: purpose,
      p_needed_by: neededBy || null,
      p_notes: safeText(body.notes, 500) || null,
    });
    if (error) {
      const message = error.message || "";
      const status = /not_found|not_active|invalid_requisition|invalid_purchase_requisition/i.test(message) ? 422 : 409;
      return fail("Purchase requisition gagal dibuat. Periksa cabang, item, dan jumlah.", status, origin);
    }
    return json(data, 201, origin);
  }

  if (action === "erp-transition-purchase-requisition") {
    const id = safeText(body.id, 80);
    const next = safeText(body.status, 20);
    const supplierId = safeText(body.supplier_id, 80) || null;
    if (!id || !["submitted", "approved", "rejected", "converted", "cancelled"].includes(next)) {
      return fail("ID atau status requisition tidak valid.", 422, origin);
    }
    const { data: old, error: oldError } = await admin.from("purchase_requisitions")
      .select("id,status,branch_id,requested_by,requisition_number")
      .eq("id", id).maybeSingle();
    if (oldError || !old) return fail("Purchase requisition tidak ditemukan.", 404, origin);
    if (!await branchAccess(old.branch_id)) return fail("Akses cabang tidak diizinkan.", 403, origin);
    if (["approved", "rejected", "converted"].includes(next) && !isOwner) {
      return fail("Persetujuan, penolakan, dan konversi requisition hanya dapat dilakukan Owner.", 403, origin);
    }
    if (["approved", "rejected"].includes(next) && old.requested_by === actor.user.id) {
      return fail("Pembuat requisition tidak boleh menyetujui atau menolak requisition sendiri.", 403, origin);
    }
    if (next === "cancelled" && !isOwner && old.requested_by !== actor.user.id) {
      return fail("Hanya pembuat requisition atau Owner yang dapat membatalkan.", 403, origin);
    }
    if (supplierId) {
      const { data: supplier } = await admin.from("suppliers").select("id").eq("id", supplierId).eq("is_active", true).maybeSingle();
      if (!supplier) return fail("Supplier tidak ditemukan atau tidak aktif.", 404, origin);
    }
    const { data, error } = await admin.rpc("erp_transition_purchase_requisition", {
      p_requisition_id: id,
      p_next_status: next,
      p_actor_user_id: actor.user.id,
      p_supplier_id: supplierId,
    });
    if (error) {
      const message = error.message || "";
      const status = /not_found/i.test(message) ? 404 : /not_allowed|invalid_requisition_transition/i.test(message) ? 409 : 422;
      return fail("Transisi purchase requisition gagal. Muat ulang dan periksa statusnya.", status, origin);
    }
    return json({ ok: true, ...data }, 200, origin);
  }

  if (action === "erp-list-purchase-orders") {
    const branchId=safeText(body.branch_id,80),ids=await branchIdsForActor().catch(()=>[]);
    let q=admin.from("purchase_orders").select("id,po_number,branch_id,supplier_id,status,subtotal_idr,requested_by,approved_by,notes,created_at,branches(code,name),purchase_order_items(id,inventory_item_id,item_name_snapshot,quantity,unit_cost_idr,line_total_idr)").order("created_at",{ascending:false}).limit(200);
    if(branchId&&!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(branchId)q=q.eq("branch_id",branchId);else q=ids?.length?q.in("branch_id",ids):q.eq("branch_id","00000000-0000-0000-0000-000000000000");
    const {data,error}=await q;if(error)return fail("Purchase order gagal dimuat.",500,origin);
    return json({purchase_orders:data||[]},200,origin);
  }

  if (action === "erp-create-purchase-order") {
    const branchId=safeText(body.branch_id,80),items=body.items;
    if(!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(!Array.isArray(items)||!items.length||items.length>100)return fail("Tambahkan minimal satu item pembelian.",422,origin);
    let subtotal=0;const cleaned=[];
    for(const x of items){
      const itemId=safeText(x?.inventory_item_id,80),qty=Number(x?.quantity),unitCost=Number(x?.unit_cost_idr);
      if(!Number.isFinite(qty)||qty<=0||qty>100000||!Number.isFinite(unitCost)||unitCost<0||unitCost>1000000000)return fail("Jumlah atau biaya satuan tidak valid.",422,origin);
      const {data:it}=await admin.from("inventory_items").select("id,name").eq("id",itemId).eq("is_active",true).maybeSingle();
      if(!it)return fail("Item persediaan tidak ditemukan.",404,origin);
      subtotal+=Math.round(qty*unitCost);cleaned.push({inventory_item_id:itemId,item_name_snapshot:it.name,quantity:qty,unit_cost_idr:Math.round(unitCost)});
    }
    const code="PO-"+new Date().toISOString().slice(0,10).replaceAll("-","")+"-"+crypto.randomUUID().slice(0,6).toUpperCase();
    const {data:po,error}=await admin.from("purchase_orders").insert({po_number:code,branch_id:branchId,status:"draft",subtotal_idr:subtotal,requested_by:actor.user.id,notes:safeText(body.notes,500)||null}).select("*").single();
    if(error||!po)return fail("Purchase order gagal dibuat.",409,origin);
    const {error:itemsError}=await admin.from("purchase_order_items").insert(cleaned.map(x=>({...x,purchase_order_id:po.id})));
    if(itemsError){await admin.from("purchase_orders").delete().eq("id",po.id);return fail("Detail purchase order gagal disimpan.",500,origin);}
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"erp_purchase_order_created",entity_type:"purchase_order",entity_id:po.id,metadata:{po_number:code,subtotal_idr:subtotal}});
    return json({ok:true,purchase_order:{...po,items:cleaned}},201,origin);
  }

  if (action === "erp-update-purchase-order") {
    const id=safeText(body.id,80),next=safeText(body.status,20);
    if(!["submitted","approved","ordered","cancelled"].includes(next))return fail("Status purchase order tidak valid.",422,origin);
    const {data:old}=await admin.from("purchase_orders").select("id,status,branch_id,requested_by").eq("id",id).maybeSingle();
    if(!old)return fail("Purchase order tidak ditemukan.",404,origin);
    if(!await branchAccess(old.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(next==="approved"&&!isOwner)return fail("Hanya Owner dapat menyetujui purchase order pada tahap ini.",403,origin);
    const valid=(old.status==="draft"&&["submitted","cancelled"].includes(next))||(old.status==="submitted"&&["approved","cancelled"].includes(next))||(old.status==="approved"&&["ordered","cancelled"].includes(next));
    if(!valid)return fail("Perubahan status tidak diizinkan dari status saat ini.",409,origin);
    const {data,error}=await admin.from("purchase_orders").update({status:next,approved_by:next==="approved"?actor.user.id:undefined,updated_at:new Date().toISOString()}).eq("id",id).eq("status",old.status).select("*").maybeSingle();
    if(error||!data)return fail("Purchase order berubah; muat ulang.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"erp_purchase_order_"+next,entity_type:"purchase_order",entity_id:id,metadata:{previous_status:old.status}});
    return json({ok:true,purchase_order:data},200,origin);
  }


  if (action === "erp-transition-delivery-dispatch") {
    if(!hasPerm("orders")&&!hasPerm("pos"))return fail("Izin perubahan status pengiriman tidak diizinkan.",403,origin);
    const dispatchId=safeText(body.dispatch_id,64),next=safeText(body.next_status,30),note=safeText(body.note,500)||"";
    if(!/^[0-9a-f-]{36}$/i.test(dispatchId)||!["picked_up","in_transit","delivered","failed","cancelled"].includes(next))return fail("Perintah status pengiriman tidak valid.",422,origin);
    const {data:dispatch,error:dispatchError}=await admin.from("delivery_dispatches").select("id,branch_id,status").eq("id",dispatchId).maybeSingle();
    if(dispatchError)return fail("Pengiriman belum dapat diverifikasi.",503,origin);
    if(!dispatch)return fail("Pengiriman tidak ditemukan.",404,origin);
    if(!await branchAccess(dispatch.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);
    const eventId=crypto.randomUUID(),payload=JSON.stringify({dispatch_id:dispatchId,next_status:next,note,actor_id:actor.user.id,event_id:eventId});
    const digest=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(payload));
    const payloadHash=[...new Uint8Array(digest)].map(x=>x.toString(16).padStart(2,"0")).join("");
    const {data,error}=await admin.rpc("delivery_transition_dispatch",{p_dispatch_id:dispatchId,p_next_status:next,p_event_id:eventId,p_payload_hash:payloadHash,p_actor_user_id:actor.user.id,p_note:note});
    if(error){
      const duplicate=error.code==="23505",pod=String(error.message||"").includes("DELIVERY_PROOF_REQUIRED");
      return fail(duplicate?"Event pengiriman sudah pernah dicatat.":pod?"Proof of delivery wajib diverifikasi sebelum status delivered.":"Transisi status pengiriman tidak diizinkan.",duplicate||pod?409:422,origin);
    }
    return json({dispatch:data},200,origin);
  }

  if (action === "erp-list-delivery-dispatches") {
    if(!hasPerm("orders")&&!hasPerm("pos")&&!hasPerm("reports"))return fail("Izin delivery tidak diizinkan.",403,origin);
    const branchId=safeText(body.branch_id,80),orderId=safeText(body.order_id,80);
    if(branchId&&!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    let q=admin.from("delivery_dispatches").select("id,tenant_id,branch_id,order_id,provider,provider_service,tracking_number,tracking_url,delivery_fee_idr,cod_amount_idr,status,booked_at,delivered_at,failed_at,created_at,orders(order_number,customer_name,delivery_address)").order("created_at",{ascending:false}).limit(100);
    if(branchId)q=q.eq("branch_id",branchId);
    if(orderId)q=q.eq("order_id",orderId);
    if(!branchId&&!orderId){const ids=await branchIdsForActor().catch(()=>[]);q=ids?.length?q.in("branch_id",ids):q.eq("branch_id","00000000-0000-0000-0000-000000000000");}
    const {data,error}=await q;
    if(error)return fail("Data pengiriman belum tersedia. Pastikan migrasi Delivery diterapkan pada batch final.",503,origin);
    return json({dispatches:data||[]},200,origin);
  }

  if (action === "erp-book-delivery-dispatch") {
    if(!hasPerm("orders")&&!hasPerm("pos"))return fail("Izin booking delivery tidak diizinkan.",403,origin);
    const orderId=safeText(body.order_id,80),provider=safeText(body.provider,40);
    const providerService=safeText(body.provider_service,80)||null;
    const trackingNumber=safeText(body.tracking_number,120)||null;
    const trackingUrl=safeText(body.tracking_url,500)||null;
    const deliveryFee=Number(body.delivery_fee_idr),codAmount=Number(body.cod_amount_idr||0);
    const idempotencyKey=safeText(body.idempotency_key,120);
    if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(orderId)||
       provider.length<2||!Number.isSafeInteger(deliveryFee)||deliveryFee<0||
       !Number.isSafeInteger(codAmount)||codAmount<0||idempotencyKey.length<8) {
      return fail("Data booking pengiriman tidak valid.",422,origin);
    }
    if(trackingUrl){try{const u=new URL(trackingUrl);if(u.protocol!=="https:")return fail("Tracking URL wajib HTTPS.",422,origin);}catch{return fail("Tracking URL tidak valid.",422,origin);}}
    const {data:order,error:orderError}=await admin.from("orders").select("id,branch_id,fulfillment_status,payment_status").eq("id",orderId).maybeSingle();
    if(orderError)return fail("Pesanan belum dapat diverifikasi.",503,origin);
    if(!order)return fail("Pesanan tidak ditemukan.",404,origin);
    if(!order.branch_id||!await branchAccess(order.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);
    const {data,error}=await admin.rpc("delivery_book_dispatch",{
      p_order_id:orderId,p_provider:provider,p_provider_service:providerService,
      p_tracking_number:trackingNumber,p_tracking_url:trackingUrl,p_delivery_fee_idr:deliveryFee,
      p_cod_amount_idr:codAmount,p_idempotency_key:idempotencyKey,p_actor_user_id:actor.user.id
    });
    if(error){
      const duplicate=error.code==="23505",notReady=String(error.message||"").includes("ORDER_NOT_READY"),
        unpaid=String(error.message||"").includes("ORDER_PAYMENT_NOT_SETTLED");
      return fail(duplicate?"Pengiriman aktif atau idempotency key sudah digunakan.":notReady?"Pesanan harus berstatus siap sebelum dikirim.":unpaid?"Pembayaran pesanan belum diselesaikan.":"Booking pengiriman ditolak.",duplicate||notReady||unpaid?409:422,origin);
    }
    return json({dispatch:data},201,origin);
  }

  if (action === "erp-list-fulfillment-orders") {
    if(!hasPerm("orders")&&!hasPerm("pos")&&!hasPerm("reports"))return fail("Izin fulfillment tidak diizinkan.",403,origin);
    const branchId=safeText(body.branch_id,80),ids=await branchIdsForActor().catch(()=>[]);
    if(branchId&&!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    let q=admin.from("orders").select("id,order_number,created_at,timezone,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,delivery_address,product_subtotal_idr,payment_status,operational_status,fulfillment_status,branch_id,branch_selection_source,branches(code,name),order_items(product_name_snapshot,quantity,line_total_idr)").order("created_at",{ascending:false}).limit(200);
    if(branchId)q=q.eq("branch_id",branchId);else q=ids?.length?q.in("branch_id",ids):q.eq("branch_id","00000000-0000-0000-0000-000000000000");
    const {data,error}=await q;if(error)return fail("Daftar fulfillment gagal dimuat.",500,origin);
    return json({orders:data||[]},200,origin);
  }

  if (action === "erp-update-fulfillment") {
    if(!hasPerm("orders")&&!hasPerm("pos"))return fail("Izin fulfillment tidak diizinkan.",403,origin);
    const id=safeText(body.order_id,80),next=safeText(body.fulfillment_status,30),note=safeText(body.notes,500);
    const allowed=["accepted","preparing","ready","dispatched","fulfilled","failed","cancelled"];
    if(!allowed.includes(next))return fail("Status fulfillment tidak valid.",422,origin);
    const {data:old}=await admin.from("orders").select("id,branch_id,fulfillment_status,operational_status,payment_status").eq("id",id).maybeSingle();
    if(!old)return fail("Pesanan tidak ditemukan.",404,origin);
    if(!old.branch_id||!await branchAccess(old.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);
    const transitions:Record<string,string[]>={unassigned:["accepted","cancelled"],queued:["accepted","cancelled"],accepted:["preparing","cancelled","failed"],preparing:["ready","failed"],ready:["dispatched","fulfilled","cancelled"],dispatched:["fulfilled","failed"],failed:["accepted","cancelled"],fulfilled:[],cancelled:[]};
    if(!(transitions[old.fulfillment_status]||[]).includes(next))return fail("Perubahan status fulfillment tidak diizinkan.",409,origin);
    if(next==="fulfilled"&&!["paid","verified","settled"].includes(String(old.payment_status)))return fail("Pesanan belum memiliki status pembayaran yang disetujui.",409,origin);
    const values:any={fulfillment_status:next,fulfillment_notes:note||null,updated_at:new Date().toISOString()};
    if(next==="fulfilled")values.fulfilled_at=new Date().toISOString();
    const {data,error}=await admin.from("orders").update(values).eq("id",id).eq("fulfillment_status",old.fulfillment_status).select("id,fulfillment_status,branch_id,fulfilled_at").maybeSingle();
    if(error||!data)return fail("Status berubah atau gagal disimpan. Muat ulang.",409,origin);
    await admin.from("order_status_history").insert({order_id:id,status_type:"operational",old_status:old.fulfillment_status,new_status:next,note:note||"Fulfillment status updated"});
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"order_fulfillment_"+next,entity_type:"order",entity_id:id,metadata:{branch_id:old.branch_id,previous_status:old.fulfillment_status}});
    return json({ok:true,order:data},200,origin);
  }

  if (action === "erp-receive-purchase-order") {
    if(!hasPerm("procurement")&&!hasPerm("inventory"))return fail("Izin penerimaan barang tidak diizinkan.",403,origin);
    const id=safeText(body.purchase_order_id,80),receipt=safeText(body.receipt_number,60),items=body.items;
    const {data:po}=await admin.from("purchase_orders").select("id,branch_id,status").eq("id",id).maybeSingle();
    if(!po)return fail("Purchase order tidak ditemukan.",404,origin);
    if(!await branchAccess(po.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);
    const {data,error}=await admin.rpc("erp_receive_purchase_order",{p_purchase_order_id:id,p_receipt_number:receipt,p_items:items,p_actor_user_id:actor.user.id,p_supplier_delivery_reference:safeText(body.supplier_delivery_reference,120)||null,p_notes:safeText(body.notes,500)||null});
    if(error)return fail(error.message.includes("over_receipt")?"Jumlah penerimaan melebihi sisa PO.":error.message.includes("purchase_order_not_receivable")?"PO belum berstatus ordered atau partially received.":"Penerimaan gagal. Periksa item dan jumlah.",409,origin);
    return json(data,201,origin);
  }

  if (action === "erp-reconcile-purchase-receipt") {
    if (!isOwner) return fail("Rekonsiliasi penerimaan hanya dapat diakses Owner.",403,origin);
    const receiptId=safeText(body.receipt_id,80),purchaseOrderId=safeText(body.purchase_order_id,80);
    if(!receiptId||!purchaseOrderId)return fail("ID receipt dan purchase order wajib diisi.",422,origin);
    const {data:receipt,error:receiptError}=await admin.from("purchase_receipts")
      .select("id,receipt_number,purchase_order_id,branch_id,status,received_by,created_at")
      .eq("id",receiptId).eq("purchase_order_id",purchaseOrderId).maybeSingle();
    if(receiptError||!receipt)return fail("Receipt tidak ditemukan untuk purchase order ini.",404,origin);
    if(!await branchAccess(receipt.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);
    const [lines,audit]=await Promise.all([
      admin.from("purchase_receipt_items").select("id,receipt_id,purchase_order_item_id,inventory_item_id,quantity_received,unit_cost_idr").eq("receipt_id",receipt.id),
      admin.from("admin_audit_logs").select("id,action,entity_type,entity_id,metadata,created_at").eq("entity_type","purchase_receipt").eq("entity_id",receipt.id).eq("action","erp_purchase_receipt_posted")
    ]);
    if(lines.error||audit.error)return fail("Rekonsiliasi receipt/audit gagal dimuat.",500,origin);
    const itemIds=[...new Set((lines.data||[]).map((x:any)=>x.inventory_item_id))];
    let movements:any[]=[];
    if(itemIds.length){
      const {data,error}=await admin.from("stock_movements")
        .select("id,branch_id,inventory_item_id,movement_type,quantity,notes,created_by,created_at")
        .eq("branch_id",receipt.branch_id).eq("movement_type","receipt").in("inventory_item_id",itemIds)
        .ilike("notes", "%receipt "+receipt.receipt_number+"%");
      if(error)return fail("Rekonsiliasi stock movement gagal dimuat.",500,origin);
      movements=data||[];
    }
    return json({receipt,receipt_items:lines.data||[],stock_movements:movements,audit_events:audit.data||[]},200,origin);
  }



  if (action === "erp-set-product-stock-tracking") {
    if(!await hasHQPermission("production"))return fail("Akses Production Head Office diperlukan untuk mengubah pelacakan stok.",403,origin);
    const productId=safeText(body.product_id,80),enabled=body.enabled===true;
    if(!productId)return fail("Produk wajib dipilih.",422,origin);
    const {data:product}=await admin.from("products").select("id,slug,stock_tracking_enabled").eq("id",productId).maybeSingle();
    if(!product)return fail("Produk tidak ditemukan.",404,origin);
    if(enabled){
      const {data:recipe}=await admin.from("recipes").select("id").eq("product_id",productId).eq("status","active").limit(1).maybeSingle();
      if(!recipe)return fail("Aktifkan dan validasi resep terlebih dahulu sebelum pelacakan stok dinyalakan.",409,origin);
      const {data:ingredients}=await admin.from("recipe_ingredients").select("id").eq("recipe_id",recipe.id);
      if(!ingredients?.length)return fail("Resep aktif belum memiliki bahan.",409,origin);
    }
    const {data:updated,error}=await admin.from("products").update({stock_tracking_enabled:enabled,updated_at:new Date().toISOString()}).eq("id",productId).select("id,slug,stock_tracking_enabled").single();
    if(error||!updated)return fail("Konfigurasi pelacakan stok gagal disimpan.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"product_stock_tracking_changed",entity_type:"product",entity_id:productId,metadata:{stock_tracking_enabled:enabled}});
    return json({ok:true,product:updated},200,origin);
  }

  if (action === "erp-list-product-modifiers") {
    if(!await hasHQPermission("production"))return fail("Akses Production Head Office diperlukan untuk modifier menu.",403,origin);
    const productId=safeText(body.product_id,80);
    let q=admin.from("product_modifiers").select("*,products(name,slug)").order("product_id").order("modifier_group").order("name").limit(500);
    if(productId)q=q.eq("product_id",productId);
    const {data,error}=await q;if(error)return fail("Modifier menu belum tersedia. Pastikan migrasi modifier sudah diterapkan.",503,origin);
    return json({modifiers:data||[]},200,origin);
  }

  if (action === "erp-save-product-modifier") {
    if(!await hasHQPermission("production"))return fail("Akses Production Head Office diperlukan untuk mengubah modifier.",403,origin);
    const id=safeText(body.modifier_id,80),productId=safeText(body.product_id,80),group=safeText(body.modifier_group,60),code=safeText(body.modifier_code,40).toLowerCase(),name=safeText(body.name,100),delta=Number(body.price_delta_idr||0);
    if(!productId||!group||!name||!/^[a-z0-9][a-z0-9_-]{0,39}$/.test(code)||!Number.isSafeInteger(delta)||delta < -100000000||delta > 100000000)return fail("Data modifier tidak valid.",422,origin);
    const {data:product}=await admin.from("products").select("id").eq("id",productId).maybeSingle();if(!product)return fail("Produk tidak ditemukan.",404,origin);
    const values={product_id:productId,modifier_group:group,modifier_code:code,name,price_delta_idr:delta,is_required:body.is_required===true,is_active:body.is_active!==false,updated_at:new Date().toISOString()};
    const result=id?await admin.from("product_modifiers").update(values).eq("id",id).select("*").maybeSingle():await admin.from("product_modifiers").insert(values).select("*").single();
    if(result.error||!result.data)return fail("Modifier gagal disimpan; periksa duplikasi kode dalam grup.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:id?"erp_product_modifier_updated":"erp_product_modifier_created",entity_type:"product_modifier",entity_id:result.data.id,metadata:{product_id:productId,modifier_group:group,modifier_code:code,is_active:values.is_active}});
    return json({ok:true,modifier:result.data},id?200:201,origin);
  }

  if (action === "erp-list-recipe-substitutions") {
    if(!hasHQPermission("production"))return fail("Akses Production Head Office diperlukan untuk substitusi resep.",403,origin);
    const ingredientId=safeText(body.recipe_ingredient_id,80);
    let q=admin.from("recipe_substitutions").select("*,recipe_ingredients(recipe_id,inventory_item_id,unit,inventory_items(name,sku))").order("created_at",{ascending:false}).limit(500);
    if(ingredientId)q=q.eq("recipe_ingredient_id",ingredientId);
    const {data,error}=await q;if(error)return fail("Daftar substitusi belum tersedia. Pastikan migrasi sudah diterapkan.",503,origin);
    return json({substitutions:data||[]},200,origin);
  }

  if (action === "erp-save-recipe-substitution") {
    if(!await hasHQPermission("production"))return fail("Hanya Production Head Office yang dapat menyetujui substitusi bahan.",403,origin);
    const ingredientId=safeText(body.recipe_ingredient_id,80),substituteId=safeText(body.substitute_inventory_item_id,80),factor=Number(body.quantity_factor||1),active=body.is_active!==false;
    if(!ingredientId||!substituteId||!Number.isFinite(factor)||factor<=0||factor>1000)return fail("Data substitusi tidak valid.",422,origin);
    const {data:ingredient}=await admin.from("recipe_ingredients").select("id,inventory_item_id,unit,recipes!inner(status)").eq("id",ingredientId).maybeSingle();
    if(!ingredient)return fail("Bahan resep tidak ditemukan.",404,origin);
    const {data:base}=await admin.from("inventory_items").select("id,unit,is_active").eq("id",ingredient.inventory_item_id).maybeSingle();
    const {data:sub}=await admin.from("inventory_items").select("id,unit,is_active").eq("id",substituteId).maybeSingle();
    if(!base?.is_active||!sub?.is_active||base.id===sub.id)return fail("Bahan pengganti tidak valid atau tidak aktif.",422,origin);
    if(base.unit!==sub.unit||ingredient.unit!==base.unit)return fail("Satuan bahan dan pengganti harus sama; konversi satuan perlu didefinisikan sebelum aktivasi.",422,origin);
    const values={recipe_ingredient_id:ingredientId,substitute_inventory_item_id:substituteId,quantity_factor:factor,is_active:active,approved_by:actor.user.id,approved_at:new Date().toISOString()};
    const result=await admin.from("recipe_substitutions").upsert(values,{onConflict:"recipe_ingredient_id,substitute_inventory_item_id"}).select("*").single();
    if(result.error||!result.data)return fail("Substitusi resep gagal disimpan.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"erp_recipe_substitution_approved",entity_type:"recipe_substitution",entity_id:result.data.id,metadata:{recipe_ingredient_id:ingredientId,substitute_inventory_item_id:substituteId,quantity_factor:factor,is_active:active}});
    return json({ok:true,substitution:result.data},200,origin);
  }

  if (action === "erp-list-recipes") {
    if(!hasPerm("production")&&!hasPerm("inventory")&&!hasPerm("reports"))return fail("Izin resep/produksi tidak diizinkan.",403,origin);
    const {data,error}=await admin.from("recipes").select("id,product_id,version,yield_quantity,yield_unit,status,effective_from,effective_to,instructions,approved_by,approved_at,products(name,slug),recipe_ingredients(id,inventory_item_id,quantity_per_yield,unit,is_optional,inventory_items(name,sku))").order("product_id").order("version",{ascending:false}).limit(300);
    if(error)return fail("Daftar resep gagal dimuat.",500,origin);
    return json({recipes:data||[]},200,origin);
  }

  if (action === "erp-save-recipe") {
    if(!await hasHQPermission("production"))return fail("Pembuatan resep global memerlukan izin Production Head Office.",403,origin);
    const productId=safeText(body.product_id,80),yieldQty=Number(body.yield_quantity),yieldUnit=safeText(body.yield_unit,20),ingredients=body.ingredients;
    if(!productId||!Number.isFinite(yieldQty)||yieldQty<=0||!yieldUnit||!Array.isArray(ingredients)||!ingredients.length||ingredients.length>100)return fail("Data resep tidak valid.",422,origin);
    const {data:product}=await admin.from("products").select("id").eq("id",productId).maybeSingle();if(!product)return fail("Produk tidak ditemukan.",404,origin);
    const cleaned=ingredients.map((x:any)=>({inventory_item_id:safeText(x?.inventory_item_id,80),quantity_per_yield:Number(x?.quantity_per_yield),unit:safeText(x?.unit,20),is_optional:x?.is_optional===true}));
    if(cleaned.some((x:any)=>!x.inventory_item_id||!Number.isFinite(x.quantity_per_yield)||x.quantity_per_yield<=0||!x.unit)||new Set(cleaned.map((x:any)=>x.inventory_item_id)).size!==cleaned.length)return fail("Bahan resep duplikat atau jumlah tidak valid.",422,origin);
    const {data:items}=await admin.from("inventory_items").select("id").in("id",cleaned.map((x:any)=>x.inventory_item_id)).eq("is_active",true);
    if((items||[]).length!==cleaned.length)return fail("Ada bahan yang tidak aktif/tidak ditemukan.",422,origin);
    const {data:latest}=await admin.from("recipes").select("version").eq("product_id",productId).order("version",{ascending:false}).limit(1).maybeSingle();
    const {data:recipe,error}=await admin.from("recipes").insert({product_id:productId,version:Number(latest?.version||0)+1,yield_quantity:yieldQty,yield_unit:yieldUnit,status:"draft",instructions:safeText(body.instructions,2000)||null,created_by:actor.user.id}).select("*").single();
    if(error||!recipe)return fail("Draft resep gagal dibuat.",409,origin);
    const {error:ie}=await admin.from("recipe_ingredients").insert(cleaned.map((x:any)=>({...x,recipe_id:recipe.id})));
    if(ie){await admin.from("recipes").delete().eq("id",recipe.id);return fail("Detail bahan resep gagal disimpan.",409,origin);}
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"erp_recipe_draft_created",entity_type:"recipe",entity_id:recipe.id,metadata:{product_id:productId,version:recipe.version}});
    return json({ok:true,recipe},201,origin);
  }

  if (action === "erp-retire-recipe") {
    if(!await hasHQPermission("production"))return fail("Retiring a recipe requires Production Head Office permission.",403,origin);
    const id=safeText(body.recipe_id,80);
    if(!id)return fail("Recipe ID is required.",422,origin);
    const {data:recipe,error:recipeError}=await admin.from("recipes").select("id,product_id,status").eq("id",id).maybeSingle();
    if(recipeError||!recipe)return fail("Recipe not found.",404,origin);
    if(recipe.status==="retired")return json({ok:true,recipe_id:id,status:"retired",unchanged:true},200,origin);
    if(recipe.status==="draft")return json({ok:true,recipe_id:id,status:"draft",unchanged:true},200,origin);
    if(recipe.status!=="active")return fail("Only an active recipe can be retired.",409,origin);
    const {data:product,error:productError}=await admin.from("products").select("is_active,stock_tracking_enabled").eq("id",recipe.product_id).maybeSingle();
    if(productError||!product)return fail("Recipe product not found.",404,origin);
    if(product.is_active||product.stock_tracking_enabled)return fail("Deactivate the product and disable stock tracking before retiring its recipe.",409,origin);
    const {data:retired,error:retireError}=await admin.from("recipes").update({status:"retired"}).eq("id",id).eq("status","active").select("id,status").maybeSingle();
    if(retireError||!retired)return fail("Recipe retirement failed; refresh and reconcile its state.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"erp_recipe_retired",entity_type:"recipe",entity_id:id,metadata:{product_id:recipe.product_id,reason:"qa_fixture_cleanup"}});
    return json({ok:true,recipe_id:id,status:"retired"},200,origin);
  }

  if (action === "erp-activate-recipe") {
    if(!await hasHQPermission("production"))return fail("Aktivasi resep global memerlukan izin Production Head Office.",403,origin);
    const id=safeText(body.recipe_id,80);
    const {data,error}=await admin.rpc("erp_activate_recipe",{p_recipe_id:id,p_actor_user_id:actor.user.id});
    if(error)return fail(error.message.includes("recipe_has_no_ingredients")?"Resep tanpa bahan tidak dapat diaktifkan.":error.message.includes("recipe_not_draft")?"Hanya draft resep yang dapat diaktifkan.":"Aktivasi resep gagal.",409,origin);
    return json({ok:true,recipe:data},200,origin);
  }

  if (action === "erp-list-production-batches") {
    if(!hasPerm("production")&&!hasPerm("inventory")&&!hasPerm("reports"))return fail("Izin produksi tidak diizinkan.",403,origin);
    const branchId=safeText(body.branch_id,80),ids=await branchIdsForActor().catch(()=>[]);
    if(branchId&&!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    let q=admin.from("production_batches").select("*,branches(code,name),recipes(version,yield_quantity,yield_unit,products(name)),production_consumptions(inventory_item_id,planned_quantity,actual_quantity,unit,inventory_items(name,sku))").order("created_at",{ascending:false}).limit(200);
    if(branchId)q=q.eq("branch_id",branchId);else q=ids?.length?q.in("branch_id",ids):q.eq("branch_id","00000000-0000-0000-0000-000000000000");
    const {data,error}=await q;if(error)return fail("Batch produksi gagal dimuat.",500,origin);
    return json({batches:data||[]},200,origin);
  }

  if (action === "erp-create-production-batch") {
    if(!hasPerm("production"))return fail("Izin produksi diperlukan.",403,origin);
    const branchId=safeText(body.branch_id,80),recipeId=safeText(body.recipe_id,80),qty=Number(body.planned_quantity);
    if(!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(!Number.isFinite(qty)||qty<=0||qty>100000)return fail("Jumlah produksi tidak valid.",422,origin);
    const {data:recipe}=await admin.from("recipes").select("id").eq("id",recipeId).eq("status","active").maybeSingle();if(!recipe)return fail("Pilih resep aktif.",409,origin);
    const batchNo="BATCH-"+new Date().toISOString().slice(0,10).replaceAll("-","")+"-"+crypto.randomUUID().slice(0,8).toUpperCase();
    const {data,error}=await admin.from("production_batches").insert({batch_number:batchNo,branch_id:branchId,recipe_id:recipeId,planned_quantity:qty,status:"planned",notes:safeText(body.notes,500)||null}).select("*").single();
    if(error||!data)return fail("Batch produksi gagal dibuat.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"erp_production_batch_created",entity_type:"production_batch",entity_id:data.id,metadata:{branch_id:branchId,recipe_id:recipeId,planned_quantity:qty}});
    return json({ok:true,batch:data},201,origin);
  }

  if (action === "erp-start-production-batch") {
    if(!hasPerm("production"))return fail("Izin produksi diperlukan.",403,origin);
    const id=safeText(body.batch_id,80),{data:old}=await admin.from("production_batches").select("id,branch_id,status").eq("id",id).maybeSingle();
    if(!old)return fail("Batch tidak ditemukan.",404,origin);if(!await branchAccess(old.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);
    const {data,error}=await admin.from("production_batches").update({status:"in_progress",started_by:actor.user.id,started_at:new Date().toISOString()}).eq("id",id).eq("status","planned").select("*").maybeSingle();
    if(error||!data)return fail("Batch sudah berubah status atau gagal dimulai.",409,origin);
    return json({ok:true,batch:data},200,origin);
  }

  if (action === "erp-complete-production-batch") {
    if(!hasPerm("production"))return fail("Izin produksi diperlukan.",403,origin);
    const id=safeText(body.batch_id,80),good=Number(body.actual_good_quantity),waste=Number(body.waste_quantity||0),consumptions=body.actual_consumptions;
    const {data:batch}=await admin.from("production_batches").select("id,branch_id").eq("id",id).maybeSingle();
    if(!batch)return fail("Batch tidak ditemukan.",404,origin);if(!await branchAccess(batch.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);
    const {data,error}=await admin.rpc("erp_complete_production_batch",{p_batch_id:id,p_actual_good_quantity:good,p_waste_quantity:waste,p_actual_consumptions:consumptions,p_actor_user_id:actor.user.id});
    if(error)return fail(error.message.includes("insufficient_stock")?"Stok bahan baku tidak mencukupi.":error.message.includes("active_recipe_required")?"Resep aktif diperlukan.":"Penyelesaian batch gagal. Periksa konsumsi aktual dan status batch.",409,origin);
    return json(data,200,origin);
  }

  if (action === "erp-list-settlements") {
    if(!await hasFinanceHQ())return fail("Akses Finance Head Office diperlukan.",403,origin);
    const {data,error}=await admin.from("payment_settlements").select("*,payment_settlement_items(id,payment_record_id,pos_sale_id,amount_idr)").order("settlement_date",{ascending:false}).limit(300);
    if(error)return fail("Settlement belum dapat dimuat.",500,origin);return json({settlements:data||[]},200,origin);
  }

  if (action === "erp-create-settlement") {
    if(!await hasFinanceHQ())return fail("Akses Finance Head Office diperlukan.",403,origin);
    const code=safeText(body.settlement_code,60),method=safeText(body.payment_method,30),date=safeText(body.settlement_date,10),gross=Number(body.gross_amount_idr),fee=Number(body.fee_amount_idr||0);
    if(!code||!["bank_transfer","qris"].includes(method)||!/^\d{4}-\d{2}-\d{2}$/.test(date)||!Number.isSafeInteger(gross)||gross<0||!Number.isSafeInteger(fee)||fee<0||fee>gross)return fail("Data settlement tidak valid.",422,origin);
    const {data,error}=await admin.from("payment_settlements").insert({settlement_code:code,payment_method:method,provider_reference:safeText(body.provider_reference,120)||null,settlement_date:date,gross_amount_idr:gross,fee_amount_idr:fee,received_amount_idr:body.received_amount_idr==null?null:Number(body.received_amount_idr),notes:safeText(body.notes,500)||null}).select("*").single();
    if(error||!data)return fail("Settlement gagal dibuat; kode mungkin sudah digunakan.",409,origin);
    return json({ok:true,settlement:data},201,origin);
  }

  if (action === "erp-match-settlement") {
    if(!await hasFinanceHQ())return fail("Akses Finance Head Office diperlukan.",403,origin);
    const id=safeText(body.settlement_id,80),items=body.items;
    if(!Array.isArray(items)||!items.length||items.length>500)return fail("Pilih transaksi untuk dicocokkan.",422,origin);
    const {data,error}=await admin.rpc("erp_match_payment_settlement",{p_settlement_id:id,p_items:items,p_actor_user_id:actor.user.id});
    if(error){const msg=error.message||"";return fail(msg.includes("settlement_gross_mismatch")?"Total transaksi tidak sama dengan bruto settlement.":msg.includes("settlement_amount_mismatch")?"Nominal transaksi berbeda dari catatan sumber.":msg.includes("payment_not_verified")?"Pembayaran online belum terverifikasi.":msg.includes("pos_sale_not_paid")?"Penjualan POS belum berstatus lunas.":msg.includes("duplicate key")?"Transaksi sudah dicocokkan di settlement lain.":"Pencocokan settlement gagal. Periksa transaksi dan statusnya.",409,origin);}
    return json(data,200,origin);
  }

  if (action === "erp-list-refunds") {
    if(!hasPerm("finance"))return fail("Izin Finance diperlukan.",403,origin);
    const hq=await hasFinanceHQ(),ids=await branchIdsForActor().catch(()=>[]);
    let q=admin.from("refund_records").select("*,branches(code,name),orders(order_number,customer_name),payment_records(method,status),pos_sales(transaction_code,total_idr)").order("requested_at",{ascending:false}).limit(300);
    if(!hq)q=ids?.length?q.in("branch_id",ids):q.eq("branch_id","00000000-0000-0000-0000-000000000000");
    const {data,error}=await q;if(error)return fail("Daftar refund gagal dimuat.",500,origin);
    return json({refunds:data||[]},200,origin);
  }

  if (action === "erp-create-refund") {
    if(!hasPerm("finance"))return fail("Izin Finance diperlukan.",403,origin);
    const orderId=safeText(body.order_id,80)||null,paymentId=safeText(body.payment_record_id,80)||null,posId=safeText(body.pos_sale_id,80)||null,amount=Number(body.amount_idr),reason=safeText(body.reason,500);
    if([orderId,paymentId,posId].filter(Boolean).length!==1||!Number.isSafeInteger(amount)||amount<=0||!reason)return fail("Pilih tepat satu sumber transaksi, jumlah, dan alasan refund.",422,origin);
    let sourceBranchId:string|null=null;
    if(orderId){const {data:o}=await admin.from("orders").select("id,branch_id").eq("id",orderId).maybeSingle();if(!o)return fail("Order sumber tidak ditemukan.",404,origin);sourceBranchId=o.branch_id;}
    if(paymentId){const {data:p}=await admin.from("payment_records").select("id,order_id").eq("id",paymentId).maybeSingle();if(!p?.order_id)return fail("Payment record sumber tidak ditemukan atau bukan pembayaran order.",404,origin);if(orderId&&orderId!==p.order_id)return fail("Referensi order dan pembayaran tidak cocok.",422,origin);const {data:o}=await admin.from("orders").select("branch_id").eq("id",p.order_id).maybeSingle();sourceBranchId=o?.branch_id||null;}
    if(posId){const {data:s}=await admin.from("pos_sales").select("id,branch_id,payment_status").eq("id",posId).maybeSingle();if(!s||s.payment_status!=="paid")return fail("Penjualan POS sumber tidak ditemukan atau belum lunas.",409,origin);sourceBranchId=s.branch_id;}
    if(!sourceBranchId)return fail("Transaksi sumber belum memiliki cabang.",409,origin);
    const suppliedBranch=safeText(body.branch_id,80);if(suppliedBranch&&suppliedBranch!==sourceBranchId)return fail("Cabang refund harus sama dengan cabang transaksi sumber.",422,origin);
    if(!await hasFinanceHQ()&&!await branchAccess(sourceBranchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    const code="RFD-"+new Date().toISOString().slice(0,10).replaceAll("-","")+"-"+crypto.randomUUID().slice(0,8).toUpperCase();
    const {data,error}=await admin.from("refund_records").insert({refund_code:code,order_id:orderId,payment_record_id:paymentId,pos_sale_id:posId,branch_id:sourceBranchId,amount_idr:amount,reason,status:"requested",requested_by:actor.user.id}).select("*").single();
    if(error||!data)return fail(error?.message?.includes("refund_exceeds_remaining_balance")?"Jumlah refund melebihi sisa nilai transaksi.":"Permintaan refund gagal dibuat.",409,origin);
    return json({ok:true,refund:data},201,origin);
  }

  if (action === "erp-review-refund") {
    if(!hasPerm("finance")&&!isOwner)return fail("Izin Finance diperlukan.",403,origin);
    const id=safeText(body.refund_id,80),next=safeText(body.status,20),note=safeText(body.external_reference,120);
    if(!["approved","rejected"].includes(next))return fail("Keputusan refund tidak valid.",422,origin);
    const {data:old}=await admin.from("refund_records").select("*").eq("id",id).maybeSingle();
    if(!old)return fail("Refund tidak ditemukan.",404,origin);
    if(old.requested_by===actor.user.id)return fail("Pemisahan tugas: pembuat refund tidak boleh menyetujui sendiri.",403,origin);
    if(old.branch_id&&!await hasFinanceHQ()&&!await branchAccess(old.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(old.status!=="requested")return fail("Refund bukan lagi menunggu keputusan.",409,origin);
    const {data,error}=await admin.from("refund_records").update({status:next,reviewed_by:actor.user.id,reviewed_at:new Date().toISOString(),external_reference:note||null}).eq("id",id).eq("status","requested").select("*").maybeSingle();
    if(error||!data)return fail("Refund berubah saat diproses.",409,origin);
    return json({ok:true,refund:data},200,origin);
  }

  if (action === "erp-process-refund") {
    if(!hasPerm("finance")&&!isOwner)return fail("Izin Finance diperlukan.",403,origin);
    const id=safeText(body.refund_id,80),reference=safeText(body.external_reference,120);
    if(!reference)return fail("Referensi refund dari penyedia pembayaran wajib diisi.",422,origin);
    const {data:old}=await admin.from("refund_records").select("*").eq("id",id).maybeSingle();
    if(!old)return fail("Refund tidak ditemukan.",404,origin);
    if(old.status!=="approved")return fail("Refund harus disetujui sebelum diproses.",409,origin);
    // Fail closed: a non-HQ finance actor must never process an unscoped refund.
    const financeHQ = await hasFinanceHQ();
    if(!old.branch_id&&!financeHQ)return fail("Refund tanpa cabang hanya dapat diproses oleh Finance Head Office.",403,origin);
    if(old.branch_id&&!financeHQ&&!await actorCanAccessBranch(old.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(old.requested_by===actor.user.id||old.reviewed_by===actor.user.id)return fail("Pemisahan tugas: pemohon atau penyetuju tidak boleh memproses refund sendiri.",403,origin);
    const {data,error}=await admin.from("refund_records").update({status:"processed",processed_by:actor.user.id,processed_at:new Date().toISOString(),external_reference:reference}).eq("id",id).eq("status","approved").select("*").maybeSingle();
    if(error||!data)return fail("Refund berubah saat diproses.",409,origin);
    return json({ok:true,refund:data},200,origin);
  }

  if (action === "erp-create-cash-reconciliation") {
    if(!hasPerm("finance"))return fail("Izin Finance diperlukan.",403,origin);
    const branchId=safeText(body.branch_id,80),date=safeText(body.business_date,10),shiftId=safeText(body.shift_id,80)||null;
    if(!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(!/^\d{4}-\d{2}-\d{2}$/.test(date))return fail("Tanggal rekonsiliasi tidak valid.",422,origin);
    const fields=["cash_expected_idr","cash_counted_idr","bank_expected_idr","bank_received_idr","qris_expected_idr","qris_received_idr"];
    const values:any={};for(const key of fields){const n=Number(body[key]||0);if(!Number.isSafeInteger(n)||n<0)return fail("Nilai rekonsiliasi tidak valid.",422,origin);values[key]=n;}
    const code="REC-"+date.replaceAll("-","")+"-"+crypto.randomUUID().slice(0,8).toUpperCase();
    const {data,error}=await admin.from("cash_reconciliations").insert({reconciliation_code:code,branch_id:branchId,shift_id,business_date:date,...values,status:"submitted",prepared_by:actor.user.id,notes:safeText(body.notes,500)||null}).select("*").single();
    if(error||!data)return fail("Rekonsiliasi gagal disimpan. Periksa duplikasi cabang/tanggal/shift.",409,origin);
    return json({ok:true,reconciliation:data},201,origin);
  }

  if (action === "erp-list-cash-reconciliations") {
    if(!hasPerm("finance")&&!hasPerm("reports"))return fail("Izin Finance diperlukan.",403,origin);
    const branchId=safeText(body.branch_id,80),ids=await branchIdsForActor().catch(()=>[]);
    if(branchId&&!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    let q=admin.from("cash_reconciliations").select("*,branches(code,name),pos_shifts(opened_at,closed_at,status)").order("business_date",{ascending:false}).limit(300);
    if(branchId)q=q.eq("branch_id",branchId);else q=ids?.length?q.in("branch_id",ids):q.eq("branch_id","00000000-0000-0000-0000-000000000000");
    const {data,error}=await q;if(error)return fail("Daftar rekonsiliasi gagal dimuat.",500,origin);return json({reconciliations:data||[]},200,origin);
  }

  if (action === "erp-review-cash-reconciliation") {
    if(!hasPerm("finance")&&!isOwner)return fail("Izin Finance diperlukan.",403,origin);
    const id=safeText(body.id,80),decision=safeText(body.status,20);
    if(!["approved","exception"].includes(decision))return fail("Status rekonsiliasi tidak valid.",422,origin);
    const {data:old}=await admin.from("cash_reconciliations").select("id,branch_id,prepared_by,status").eq("id",id).maybeSingle();
    if(!old)return fail("Rekonsiliasi tidak ditemukan.",404,origin);
    if(old.prepared_by===actor.user.id)return fail("Pemisahan tugas: pembuat tidak boleh meninjau rekonsiliasi sendiri.",403,origin);
    if(!await branchAccess(old.branch_id))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(old.status!=="submitted")return fail("Rekonsiliasi tidak menunggu tinjauan.",409,origin);
    const {data,error}=await admin.from("cash_reconciliations").update({status:decision,reviewed_by:actor.user.id,reviewed_at:new Date().toISOString()}).eq("id",id).eq("status","submitted").select("*").maybeSingle();
    if(error||!data)return fail("Rekonsiliasi berubah saat ditinjau.",409,origin);
    return json({ok:true,reconciliation:data},200,origin);
  }

  if (action === "erp-list-fiscal-periods") {
    if(!await hasFinanceHQ())return fail("Akses Finance Head Office diperlukan.",403,origin);
    const {data,error}=await admin.from("fiscal_periods").select("*").order("starts_on",{ascending:false}).limit(100);
    if(error)return fail("Periode fiskal gagal dimuat.",500,origin);return json({periods:data||[]},200,origin);
  }

  if (action === "erp-create-fiscal-period") {
    if(!await hasFinanceHQ())return fail("Akses Finance Head Office diperlukan.",403,origin);
    const code=safeText(body.period_code,40),start=safeText(body.starts_on,10),end=safeText(body.ends_on,10);
    if(!code||!/^\d{4}-\d{2}-\d{2}$/.test(start)||!/^\d{4}-\d{2}-\d{2}$/.test(end)||end<start)return fail("Periode fiskal tidak valid.",422,origin);
    const {data,error}=await admin.from("fiscal_periods").insert({period_code:code,starts_on:start,ends_on:end,status:"open"}).select("*").single();
    if(error||!data)return fail("Periode fiskal gagal dibuat atau kode sudah dipakai.",409,origin);return json({ok:true,period:data},201,origin);
  }

  if (action === "erp-close-fiscal-period" || action === "erp-reopen-fiscal-period") {
    if(!isOwner)return fail("Hanya Owner yang dapat menutup atau membuka kembali periode fiskal.",403,origin);
    const id=safeText(body.period_id,80),note=safeText(body.notes,500);
    const {data:old}=await admin.from("fiscal_periods").select("*").eq("id",id).maybeSingle();if(!old)return fail("Periode fiskal tidak ditemukan.",404,origin);
    const reopening=action==="erp-reopen-fiscal-period";
    if(reopening&&old.status!=="closed")return fail("Hanya periode closed yang dapat dibuka kembali.",409,origin);
    if(!reopening&&old.status!=="open")return fail("Hanya periode open yang dapat ditutup.",409,origin);
    const values:any=reopening?{status:"reopened",reopened_by:actor.user.id,reopened_at:new Date().toISOString(),closing_notes:note||null}:{status:"closed",closed_by:actor.user.id,closed_at:new Date().toISOString(),closing_notes:note||null};
    const {data,error}=await admin.from("fiscal_periods").update(values).eq("id",id).eq("status",old.status).select("*").maybeSingle();
    if(error||!data)return fail("Periode fiskal berubah saat diproses.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:reopening?"erp_fiscal_period_reopened":"erp_fiscal_period_closed",entity_type:"fiscal_period",entity_id:id,metadata:{previous_status:old.status,notes:note}});
    return json({ok:true,period:data},200,origin);
  }

  if (action === "erp-list-tax-settings") {
    if(!await hasFinanceHQ())return fail("Akses Finance Head Office diperlukan.",403,origin);
    const {data,error}=await admin.from("tax_settings").select("*").order("effective_from",{ascending:false}).limit(200);
    if(error)return fail("Pengaturan pajak gagal dimuat.",500,origin);return json({tax_settings:data||[]},200,origin);
  }

  if (action === "erp-save-tax-setting") {
    if(!await hasFinanceHQ())return fail("Akses Finance Head Office diperlukan.",403,origin);
    const code=safeText(body.tax_code,40),name=safeText(body.name,120),rate=Number(body.rate),from=safeText(body.effective_from,10),to=safeText(body.effective_to,10)||null,applies=safeText(body.applies_to,20);
    if(!code||!name||!Number.isFinite(rate)||rate<0||rate>100||!/^\d{4}-\d{2}-\d{2}$/.test(from)||(to&&(!/^\d{4}-\d{2}-\d{2}$/.test(to)||to<from))||!["sales","purchase","both"].includes(applies))return fail("Konfigurasi pajak tidak valid.",422,origin);
    const {data,error}=await admin.from("tax_settings").insert({tax_code:code,name,rate,inclusive:body.inclusive===true,applies_to:applies,effective_from:from,effective_to:to,is_active:true,created_by:actor.user.id}).select("*").single();
    if(error||!data)return fail("Pengaturan pajak gagal disimpan; kode mungkin sudah ada.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"erp_tax_setting_created",entity_type:"tax_setting",entity_id:data.id,metadata:{tax_code:code,rate,effective_from:from}});
    return json({ok:true,tax_setting:data},201,origin);
  }

  if (action === "erp-save-branch-capacity") {
    if(!isOwner&&!hasPerm("inventory"))return fail("Izin Owner/Inventory diperlukan.",403,origin);
    const branchId=safeText(body.branch_id,80),productId=safeText(body.product_id,80),date=safeText(body.service_date,10),capacity=Number(body.capacity);
    if(!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||!Number.isInteger(capacity)||capacity<0||capacity>100000)return fail("Tanggal atau kapasitas tidak valid.",422,origin);
    const {data:old}=await admin.from("branch_product_capacity").select("id,reserved_quantity").eq("branch_id",branchId).eq("product_id",productId).eq("service_date",date).maybeSingle();
    if(old&&capacity<Number(old.reserved_quantity||0))return fail("Kapasitas tidak boleh lebih rendah dari jumlah reserved yang tersimpan.",409,origin);
    const result=old?await admin.from("branch_product_capacity").update({capacity,updated_at:new Date().toISOString()}).eq("id",old.id).select("*").single():await admin.from("branch_product_capacity").insert({branch_id:branchId,product_id:productId,service_date:date,capacity,reserved_quantity:0}).select("*").single();
    if(result.error||!result.data)return fail("Kapasitas cabang gagal disimpan.",409,origin);
    await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"erp_branch_capacity_saved",entity_type:"branch_product_capacity",entity_id:result.data.id,metadata:{branch_id:branchId,product_id:productId,service_date:date,capacity}});
    return json({ok:true,capacity:result.data},200,origin);
  }
  if (action === "erp-list-branch-capacity") {
    if(!hasPerm("branches")&&!hasPerm("inventory")&&!hasPerm("reports"))return fail("Izin kapasitas cabang tidak diizinkan.",403,origin);
    const branchId=safeText(body.branch_id,80),date=safeText(body.service_date,10);
    if(branchId&&!await branchAccess(branchId))return fail("Akses cabang tidak diizinkan.",403,origin);
    let q=admin.from("branch_product_capacity").select("*,branches(code,name),products(name,slug)").order("service_date",{ascending:true}).limit(500);
    if(branchId) q=q.eq("branch_id",branchId);
    else if(!isOwner){let ids:string[];try{ids=await actorBranchIds();}catch{return fail("Penugasan cabang gagal dimuat.",503,origin);}q=ids.length?q.in("branch_id",ids):q.eq("branch_id","00000000-0000-0000-0000-000000000000");}
    if(date)q=q.eq("service_date",date);
    const {data,error}=await q;if(error)return fail("Kapasitas cabang gagal dimuat.",500,origin);return json({capacities:data||[]},200,origin);
  }

  return fail("Aksi tidak dikenal.", 400, origin);
});
