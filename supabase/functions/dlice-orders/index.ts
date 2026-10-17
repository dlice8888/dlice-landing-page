import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "https://gdjlkrmlsurcdbwnmqgg.supabase.co";
const secretKeysRaw = Deno.env.get("SUPABASE_SECRET_KEYS");
const SERVICE_KEY = secretKeysRaw ? JSON.parse(secretKeysRaw)["default"] : Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const publishableKeysRaw = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
const PUBLIC_KEY = publishableKeysRaw ? JSON.parse(publishableKeysRaw)["default"] : Deno.env.get("SUPABASE_ANON_KEY");
const admin = createClient(SUPABASE_URL, SERVICE_KEY ?? "", { auth: { persistSession: false } });
const authClient = createClient(SUPABASE_URL, PUBLIC_KEY ?? "", { auth: { persistSession: false } });

const allowedOrigins = new Set(["https://dlice.vercel.app", "https://dlice-landing-page.vercel.app"]);
const isAllowedOrigin = (origin: string | null) => {
  if (!origin) return true;
  if (allowedOrigins.has(origin)) return true;
  try {
    const host = new URL(origin).hostname;
    return host.startsWith("dlice-landing-page-") && host.endsWith(".vercel.app");
  } catch { return false; }
};
const corsHeaders = (origin: string | null) => ({
  "Access-Control-Allow-Origin": origin && isAllowedOrigin(origin) ? origin : "https://dlice.vercel.app",
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
const usernameEmail = (username: string) => `${username.toLowerCase()}@accounts.dlice.internal`;
const validUsername = (username: string) => /^[a-zA-Z0-9._-]{3,32}$/.test(username);
const randomToken = () => {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return [...bytes].map((v) => v.toString(16).padStart(2, "0")).join("");
};
const normPhone = (value: string) => value.replace(/[^0-9]/g, "").replace(/^0/, "62");
const safeText = (value: unknown, max: number) => typeof value === "string" ? value.trim().slice(0, max) : "";
const formatTransactionCode = (orderNumber: number | string, createdAt: string) => {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Makassar", day: "2-digit", month: "2-digit", year: "numeric",
  }).formatToParts(new Date(createdAt));
  const part = (type: string) => parts.find((item) => item.type === type)?.value ?? "";
  return `DLC-${part("day")}/${part("month")}/${part("year")}-${String(orderNumber).padStart(5, "0")}`;
};
const getAdmin = async (req: Request) => {
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const { data: userData, error: userError } = await authClient.auth.getUser(token);
  if (userError || !userData.user) return null;
  const { data: profile, error } = await admin.from("admin_profiles").select("role,is_active,display_name,permissions,username").eq("user_id", userData.user.id).maybeSingle();
  if (error || !profile?.is_active) return null;
  return { user: userData.user, profile: { ...profile, permissions: profile.role === "owner" ? ["*"] : (Array.isArray(profile.permissions) ? profile.permissions : ["orders"]) } };
};

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(origin) });
  if (req.method !== "POST") return fail("Metode tidak didukung.", 405, origin);
  if (origin && !isAllowedOrigin(origin)) return fail("Origin tidak diizinkan.", 403, origin);
  if (!SERVICE_KEY || !PUBLIC_KEY) return fail("Konfigurasi server belum lengkap.", 500, origin);
  let body: Record<string, unknown>;
  try {
    const length = Number(req.headers.get("content-length") ?? "0");
    if (length > 7_000_000) return fail("Permintaan terlalu besar.", 413, origin);
    body = await req.json();
  } catch { return fail("Format permintaan tidak valid.", 400, origin); }
  const action = safeText(body.action, 40);

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
    const hash=await sha256(token),{data:o}=await admin.from("orders").select("id,order_number,created_at,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,delivery_address,customer_notes,product_subtotal_idr,payment_status,receipt_version").eq("tracking_token_hash",hash).maybeSingle();
    if(!o)return fail("Pesanan tidak ditemukan.",404,origin);if(version!==o.receipt_version)return fail("Struk berubah; tinjau dan konfirmasi ulang.",409,origin);if(!["unpaid","pending_verification"].includes(o.payment_status))return fail("Struk tidak dapat dikonfirmasi pada status ini.",409,origin);
    let instruction=null;if(method){if(!["bank_transfer","dlice_qris"].includes(method))return fail("Metode tidak valid.",422,origin);const {data:s}=await admin.from("payment_settings").select("method,display_name,instructions,account_name,account_number,qr_storage_path,updated_at,is_enabled").eq("method",method).eq("is_enabled",true).maybeSingle();if(!s)return fail("Metode belum diaktifkan Owner.",409,origin);if(method==="dlice_qris"&&!s.qr_storage_path)return fail("QRIS belum diunggah.",409,origin);instruction={method:s.method,display_name:s.display_name,instructions:s.instructions,account_name:s.account_name,account_number:s.account_number,qr_storage_path:s.qr_storage_path,settings_updated_at:s.updated_at};}
    const {data:items,error}=await admin.from("order_items").select("product_name_snapshot,quantity,unit_price_idr,line_total_idr").eq("order_id",o.id);if(error||!items?.length)return fail("Detail struk gagal dimuat.",500,origin);
    const receipt={transaction_code:formatTransactionCode(o.order_number,o.created_at),receipt_version:version,customer_name:o.customer_name,customer_whatsapp:o.customer_whatsapp,requested_date:o.requested_date,requested_time:o.requested_time,receiving_method:o.receiving_method,delivery_address:o.delivery_address,customer_notes:o.customer_notes,items,subtotal_idr:o.product_subtotal_idr,payment_method:method||null,payment_instruction:instruction,confirmed_at:new Date().toISOString()};
    const {error:e}=await admin.from("orders").update({receipt_confirmed_version:version,receipt_confirmed_at:new Date().toISOString(),receipt_snapshot:receipt}).eq("id",o.id).eq("receipt_version",version);if(e)return fail("Konfirmasi struk gagal disimpan.",500,origin);
    return json({ok:true,receipt},200,origin);
  }
  if (action === "update-order-items") {
    const token=safeText(body.tracking_token,100);if(token.length!==64||!Array.isArray(body.items))return fail("Perubahan pesanan tidak valid.",422,origin);const hash=await sha256(token),items=[];
    for(const x of body.items.slice(0,20)){const slug=safeText(x?.slug,80),quantity=Number(x?.quantity);if(!/^[a-z0-9-]+$/.test(slug)||!Number.isInteger(quantity)||quantity<1||quantity>100)return fail("Menu/jumlah tidak valid.",422,origin);const prev=items.find(i=>i.slug===slug);if(prev)prev.quantity+=quantity;else items.push({slug,quantity});}
    if(!items.length||items.some(i=>i.quantity>100))return fail("Pilih minimal satu menu.",422,origin);const {data:o}=await admin.from("orders").select("id").eq("tracking_token_hash",hash).maybeSingle();if(!o)return fail("Pesanan tidak ditemukan.",404,origin);
    const {data:u,error}=await admin.rpc("update_order_with_reservations",{p_order_id:o.id,p_tracking_token_hash:hash,p_items:items});if(error){const msg=error.message||"";return fail(msg.includes("capacity_exceeded")?"Kapasitas menu tidak mencukupi.":msg.includes("reservation_expired")?"Reservasi berakhir; hubungi admin.":msg.includes("proof_already_uploaded")?"Bukti sudah diunggah; hubungi admin.":"Perubahan pesanan gagal.",409,origin);}
    const {data:m}=await admin.from("orders").select("order_number,created_at,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,delivery_address,customer_notes,product_subtotal_idr,receipt_version").eq("id",o.id).single();const {data:lines}=await admin.from("order_items").select("product_name_snapshot,quantity,unit_price_idr,line_total_idr").eq("order_id",o.id);
    return json({ok:true,...u,receipt:{...m,transaction_code:formatTransactionCode(m.order_number,m.created_at),items:lines||[],subtotal_idr:m.product_subtotal_idr}},200,origin);
  }
  if (action === "finalize-order-whatsapp") {
    const token=safeText(body.tracking_token,100),version=Number(body.receipt_version);if(token.length!==64||!Number.isInteger(version))return fail("Data akhir tidak valid.",422,origin);const hash=await sha256(token);
    const {data:o}=await admin.from("orders").select("id,order_number,created_at,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,delivery_address,customer_notes,product_subtotal_idr,receipt_version,receipt_confirmed_version,receipt_snapshot").eq("tracking_token_hash",hash).maybeSingle();
    if(!o)return fail("Pesanan tidak ditemukan.",404,origin);if(o.receipt_version!==version||o.receipt_confirmed_version!==version||!o.receipt_snapshot?.payment_method||!o.receipt_snapshot?.payment_instruction)return fail("Struk/instruksi belum dikonfirmasi.",409,origin);
    const {data:p}=await admin.from("payment_records").select("method,status,proof_storage_path,receipt_version").eq("order_id",o.id).order("created_at",{ascending:false}).limit(1).maybeSingle();if(!p?.proof_storage_path||p.receipt_version!==version||p.method!==o.receipt_snapshot.payment_method)return fail("Bukti belum terhubung ke struk terbaru.",409,origin);
    const {data:lines}=await admin.from("order_items").select("product_name_snapshot,quantity,line_total_idr").eq("order_id",o.id);const code=formatTransactionCode(o.order_number,o.created_at),lineText=(lines||[]).map(i=>`• ${i.product_name_snapshot} × ${i.quantity} — Rp${Number(i.line_total_idr).toLocaleString("id-ID")}`).join("\n");
    const msg=`PESANAN BARU D’LICE — ${code}\nNama: ${o.customer_name}\nWhatsApp: ${o.customer_whatsapp}\nTanggal: ${o.requested_date} ${o.requested_time} WITA\nPenerimaan: ${o.receiving_method==="delivery"?"Delivery — "+(o.delivery_address||""):"Pickup"}\nMetode: ${p.method==="dlice_qris"?"QRIS D’Lice":"Transfer bank"}\n${lineText}\nTotal produk: Rp${Number(o.product_subtotal_idr).toLocaleString("id-ID")}\nCatatan: ${o.customer_notes||"-"}\nBukti pembayaran diunggah; menunggu verifikasi.`;
    const key=`customer-order:${o.id}:${version}`,{data:existing}=await admin.from("notification_log").select("status").eq("idempotency_key",key).maybeSingle();if(!existing){const {error}=await admin.from("notification_log").insert({order_id:o.id,notification_type:"customer_order_whatsapp",status:"manual_action_required",idempotency_key:key,recipient_whatsapp:"6285397710002",message_text:msg});if(error)return fail("Notifikasi gagal dicatat.",500,origin);}
    await admin.from("orders").update({final_whatsapp_requested_at:new Date().toISOString()}).eq("id",o.id);return json({ok:true,whatsapp_url:`https://wa.me/6285397710002?text=${encodeURIComponent(msg)}`,notification_status:existing?.status||"manual_action_required"},200,origin);
  }
  if (action === "track-order") {
    const token=safeText(body.tracking_token,100);if(token.length!==64)return fail("Token tracking tidak valid.",422,origin);const hash=await sha256(token),{data:o}=await admin.from("orders").select("id,order_number,created_at,requested_date,requested_time,receiving_method,delivery_address,payment_status,operational_status,product_subtotal_idr").eq("tracking_token_hash",hash).maybeSingle();if(!o)return fail("Pesanan tidak ditemukan.",404,origin);
    const {data:history}=await admin.from("order_status_history").select("status_type,old_status,new_status,note,created_at").eq("order_id",o.id).order("created_at",{ascending:false}).limit(30);const {data:items}=await admin.from("order_items").select("product_name_snapshot,quantity,line_total_idr").eq("order_id",o.id);
    return json({order:{transaction_code:formatTransactionCode(o.order_number,o.created_at),requested_date:o.requested_date,requested_time:o.requested_time,receiving_method:o.receiving_method,delivery_address:o.delivery_address,payment_status:o.payment_status,operational_status:o.operational_status,product_subtotal_idr:o.product_subtotal_idr,items:items||[],updated_at:history?.[0]?.created_at||o.created_at,history:history||[]}},200,origin);
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
    const items = normalized.map((item) => ({ product_id: products.find((p) => p.slug === item.slug)!.id, quantity: item.quantity }));
    const trackingToken = randomToken();
    const trackingHash = await sha256(trackingToken);
    const { data: created, error } = await admin.rpc("create_order_with_reservations", {
      p_order: {
        customer_name: customerName, customer_whatsapp: customerWhatsapp, requested_date: requestedDate,
        requested_time: requestedTime, receiving_method: receivingMethod, delivery_address: receivingMethod === "delivery" ? deliveryAddress : null,
        customer_notes: notes || null,
      },
      p_items: items,
      p_tracking_token_hash: trackingHash,
    });
    if (error) {
      const e = error.message ?? "";
      const messages: Record<string, string> = {
        capacity_exceeded: "Maaf, kapasitas salah satu menu untuk tanggal tersebut sudah tidak mencukupi.",
        capacity_not_configured: "Kapasitas menu untuk tanggal tersebut belum dibuka. Silakan hubungi admin.",
        same_day_cutoff_passed: "Batas pemesanan hari ini pukul 18.00 WITA sudah lewat.",
        date_in_past: "Tanggal pesanan tidak boleh di masa lalu.",
        product_unavailable_or_price_missing: "Harga atau ketersediaan menu belum disiapkan.",
      };
      const key = Object.keys(messages).find((k) => e.includes(k));
      return fail(messages[key ?? ""] ?? "Pesanan belum dapat dibuat. Periksa tanggal, menu, dan kapasitas.", 409, origin);
    }
    const { data: orderMeta, error: orderMetaError } = await admin.from("orders").select("order_number,created_at,receipt_version,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,delivery_address,customer_notes,product_subtotal_idr").eq("id", created.order_id).single();
    if (orderMetaError || !orderMeta) return fail("Pesanan tersimpan, tetapi kode transaksi belum dapat ditampilkan. Hubungi admin D’Lice.", 500, origin);
    const { data: lines } = await admin.from("order_items").select("product_name_snapshot,quantity,unit_price_idr,line_total_idr").eq("order_id", created.order_id);
    const transactionCode = formatTransactionCode(orderMeta.order_number, orderMeta.created_at);
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
    const binary = Uint8Array.from(atob(encoded.replace(/^data:[^,]+,/, "")), (c) => c.charCodeAt(0));
    if (binary.byteLength > 5 * 1024 * 1024) return fail("Ukuran bukti maksimal 5 MB.", 413, origin);
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
    const { data: created, error: createError } = await admin.auth.admin.createUser({ email: usernameEmail(username), password, email_confirm: true, user_metadata: { username } });
    if (createError || !created.user) return fail("Akun Pemilik gagal dibuat.", 500, origin);
    const { error: profileError } = await admin.from("admin_profiles").insert({ user_id: created.user.id, username, role: "owner", display_name: "Owner D’Lice", is_active: true, permissions: ["*"] });
    if (profileError) { await admin.auth.admin.deleteUser(created.user.id); return fail("Profil Pemilik gagal dibuat.", 500, origin); }
    await admin.from("admin_audit_logs").insert({ actor_user_id: created.user.id, action: "bootstrap_owner", entity_type: "admin_profile", entity_id: created.user.id, metadata: { username } });
    return json({ ok: true }, 201, origin);
  }

  const actor = await getAdmin(req);
  if (!actor) return fail("Silakan masuk terlebih dahulu untuk mengakses operasional.", 401, origin);

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
    "admin-payment-settings": "settings",
    "admin-save-payment-settings": "settings",
    "admin-upload-qris": "settings",
    "admin-mark-notification-sent": "orders",
  };
  const requiredPermission = permissionForAction[action];
  if (requiredPermission && actor.profile.role !== "owner" && !actor.profile.permissions.includes(requiredPermission)) {
    return fail("Akses ditolak. Pemilik belum memberikan izin untuk bagian ini.", 403, origin);
  }


  if(action==="admin-payment-settings"){if(actor.profile.role!=="owner")return fail("Hanya Owner.",403,origin);const {data,error}=await admin.from("payment_settings").select("method,display_name,instructions,account_name,account_number,qr_storage_path,is_enabled,updated_at").order("method");if(error)return fail("Pengaturan gagal dimuat.",500,origin);const settings=[];for(const s of data||[]){let qr_url=null;if(s.qr_storage_path){const {data:u}=await admin.storage.from("dlice-payment-assets").createSignedUrl(s.qr_storage_path,3600);qr_url=u?.signedUrl||null;}settings.push({...s,qr_url});}return json({settings},200,origin);}
  if(action==="admin-save-payment-settings"){if(actor.profile.role!=="owner")return fail("Hanya Owner.",403,origin);const method=safeText(body.method,30),display_name=safeText(body.display_name,100),instructions=safeText(body.instructions,1000),account_name=safeText(body.account_name,120),account_number=safeText(body.account_number,80),is_enabled=body.is_enabled===true;if(!["bank_transfer","dlice_qris"].includes(method))return fail("Metode tidak valid.",422,origin);const {data:current}=await admin.from("payment_settings").select("qr_storage_path").eq("method",method).maybeSingle();if(is_enabled&&method==="bank_transfer"&&(!display_name||!account_name||!account_number))return fail("Lengkapi bank, nama pemilik, dan nomor rekening.",422,origin);if(is_enabled&&method==="dlice_qris"&&!current?.qr_storage_path)return fail("Unggah QRIS dahulu.",422,origin);const {error}=await admin.from("payment_settings").upsert({method,display_name:display_name||(method==="dlice_qris"?"QRIS D’Lice":"Transfer bank"),instructions:instructions||null,account_name:method==="bank_transfer"?account_name||null:null,account_number:method==="bank_transfer"?account_number||null:null,is_enabled,updated_by:actor.user.id,updated_at:new Date().toISOString()},{onConflict:"method"});if(error)return fail("Pengaturan gagal disimpan.",500,origin);await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"update_payment_settings",entity_type:"payment_settings",entity_id:method,metadata:{method,is_enabled}});return json({ok:true},200,origin);}
  if(action==="admin-upload-qris"){if(actor.profile.role!=="owner")return fail("Hanya Owner.",403,origin);const mime=safeText(body.mime_type,50),encoded=safeText(body.file_base64,6500000),ext={"image/jpeg":"jpg","image/png":"png","image/webp":"webp"}[mime];if(!ext||!encoded||encoded.length>6500000)return fail("QRIS harus JPG/PNG/WebP maksimal 4,5 MB.",422,origin);const binary=Uint8Array.from(atob(encoded.replace(/^data:[^,]+,/,"")),c=>c.charCodeAt(0));if(binary.byteLength>4.5*1024*1024)return fail("Ukuran QRIS maksimal 4,5 MB.",413,origin);const path=`qris/${crypto.randomUUID()}.${ext}`;const {error:up}=await admin.storage.from("dlice-payment-assets").upload(path,binary,{contentType:mime,upsert:false});if(up)return fail("Unggahan QRIS gagal.",500,origin);const {error}=await admin.from("payment_settings").upsert({method:"dlice_qris",display_name:"QRIS D’Lice",qr_storage_path:path,is_enabled:false,updated_by:actor.user.id,updated_at:new Date().toISOString()},{onConflict:"method"});if(error)return fail("QRIS diunggah tetapi pengaturan gagal disimpan.",500,origin);return json({ok:true},200,origin);}
  if(action==="admin-mark-notification-sent"){const orderId=safeText(body.order_id,80),type=safeText(body.notification_type,60);if(!orderId||!["payment_verified_whatsapp","customer_order_whatsapp"].includes(type))return fail("Notifikasi tidak valid.",422,origin);const {data:n}=await admin.from("notification_log").select("id").eq("order_id",orderId).eq("notification_type",type).order("created_at",{ascending:false}).limit(1).maybeSingle();if(!n)return fail("Catatan notifikasi tidak ditemukan.",404,origin);const {error}=await admin.from("notification_log").update({status:"sent",sent_at:new Date().toISOString(),attempts:1,last_error:null}).eq("id",n.id);if(error)return fail("Status pengiriman gagal dicatat.",500,origin);await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"mark_whatsapp_notification_sent",entity_type:"notification",entity_id:n.id,metadata:{order_id:orderId,notification_type:type}});return json({ok:true},200,origin);}

  if (action === "admin-list-staff") {
    if (actor.profile.role !== "owner") return fail("Hanya Pemilik yang dapat mengelola izin staf.", 403, origin);
    const { data, error } = await admin.from("admin_profiles").select("user_id,username,role,display_name,is_active,permissions").order("created_at", { ascending: true });
    if (error) return fail("Daftar staf gagal dimuat.", 500, origin);
    return json({ staff: data ?? [], available_permissions: ["orders", "catalog", "finance", "reports", "settings", "staff"] }, 200, origin);
  }

  if (action === "admin-create-staff") {
    if (actor.profile.role !== "owner") return fail("Hanya Pemilik yang dapat membuat akun staf.", 403, origin);
    const username = safeText(body.username, 32);
    const displayName = safeText(body.display_name, 120);
    const password = typeof body.password === "string" ? body.password : "";
    const permissions = body.permissions;
    const allowed = new Set(["orders", "catalog", "finance", "reports", "settings", "staff"]);
    if (!validUsername(username) || !displayName || password.length < 12 || !Array.isArray(permissions) || permissions.some((p) => typeof p !== "string" || !allowed.has(p))) return fail("Nama pengguna, nama staf, kata sandi (minimal 12 karakter), atau izin akses tidak valid.", 422, origin);
    const { data: created, error: createError } = await admin.auth.admin.createUser({ email: usernameEmail(username), password, email_confirm: true, user_metadata: { username, display_name: displayName } });
    if (createError || !created.user) return fail(createError?.message?.includes("already") ? "Username sudah digunakan." : "Akun admin gagal dibuat.", 409, origin);
    const { error: profileError } = await admin.from("admin_profiles").insert({ user_id: created.user.id, username, role: "admin", display_name: displayName, is_active: true, permissions: [...new Set(permissions)] });
    if (profileError) { await admin.auth.admin.deleteUser(created.user.id); return fail(profileError.code === "23505" ? "Username sudah digunakan." : "Profil admin gagal dibuat.", 500, origin); }
    await admin.from("admin_audit_logs").insert({ actor_user_id: actor.user.id, action: "create_admin_account", entity_type: "admin_profile", entity_id: created.user.id, metadata: { username, permissions: [...new Set(permissions)] } });
    return json({ ok: true, username }, 201, origin);
  }

  if (action === "admin-set-permissions") {
    if (actor.profile.role !== "owner") return fail("Hanya Pemilik yang dapat mengubah izin akses staf.", 403, origin);
    const userId = safeText(body.user_id, 80);
    const permissions = body.permissions;
    const allowed = new Set(["orders", "catalog", "finance", "reports", "settings", "staff"]);
    if (!userId || !Array.isArray(permissions) || permissions.some((p) => typeof p !== "string" || !allowed.has(p))) return fail("Daftar izin tidak valid.", 422, origin);
    const { data: target, error: targetError } = await admin.from("admin_profiles").select("user_id,role").eq("user_id", userId).maybeSingle();
    if (targetError || !target) return fail("Akun staf tidak ditemukan.", 404, origin);
    if (target.role === "owner") return fail("Izin akun Pemilik tidak dapat dibatasi melalui panel ini.", 409, origin);
    const { error } = await admin.from("admin_profiles").update({ permissions: [...new Set(permissions)] }).eq("user_id", userId);
    if (error) return fail("Izin akses staf gagal disimpan.", 500, origin);
    await admin.from("admin_audit_logs").insert({ actor_user_id: actor.user.id, action: "update_admin_permissions", entity_type: "admin_profile", entity_id: userId, metadata: { permissions: [...new Set(permissions)] } });
    return json({ ok: true }, 200, origin);
  }

  if (action === "admin-list-orders") {
    const { data, error } = await admin.from("orders").select("id,order_number,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,delivery_address,customer_notes,product_subtotal_idr,payment_status,operational_status,created_at,order_items(product_name_snapshot,quantity,unit_price_idr,line_total_idr),payment_records(id,method,status,amount_idr,proof_storage_path,created_at),notification_log(id,notification_type,status,message_text,recipient_whatsapp,created_at)").order("created_at", { ascending: false }).limit(100);
    if (error) return fail("Daftar pesanan gagal dimuat.", 500, origin);
    const orders = (data ?? []).map((order) => ({ ...order, transaction_code: formatTransactionCode(order.order_number, order.created_at) }));
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
    const { data: oldOrder } = await admin.from("orders").select("operational_status,payment_status").eq("id", orderId).maybeSingle();
    if (!oldOrder) return fail("Pesanan tidak ditemukan.", 404, origin);
    if (["preparing","ready_for_pickup","waiting_for_courier","in_delivery","completed"].includes(next) && oldOrder.payment_status !== "paid") {
      return fail("Pesanan belum dapat diproses. Customer wajib mengunggah bukti pembayaran dan owner/admin harus memverifikasinya terlebih dahulu.", 409, origin);
    }
    if(oldOrder.payment_status==="paid"&&next!==oldOrder.operational_status){const {data:n}=await admin.from("notification_log").select("status").eq("order_id",orderId).eq("notification_type","payment_verified_whatsapp").order("created_at",{ascending:false}).limit(1).maybeSingle();if(!n||n.status!=="sent")return fail("Kirim konfirmasi pembayaran beserta tutorial tracking, lalu tandai terkirim sebelum memperbarui status.",409,origin);}
    if(["cancelled","delivery_issue"].includes(next)&&safeText(body.reason,500).length<4)return fail("Alasan wajib diisi untuk pembatalan/kendala.",422,origin);
    const { error } = await admin.from("orders").update({ operational_status: next }).eq("id", orderId);
    if (error) return fail("Status gagal diperbarui.", 500, origin);
    await admin.from("order_status_history").insert({ order_id: orderId, status_type: "operational", old_status: oldOrder.operational_status, new_status: next, changed_by: actor.user.id });
    await admin.from("admin_audit_logs").insert({ actor_user_id: actor.user.id, action: "update_order_status", entity_type: "order", entity_id: orderId, metadata: { old_status: oldOrder.operational_status, new_status: next } });
    return json({ ok: true }, 200, origin);
  }


  if (action === "admin-verify-payment") {
    const orderId=safeText(body.order_id,80),result=safeText(body.result,20),note=safeText(body.note,500);if(!["paid","rejected"].includes(result))return fail("Hasil verifikasi tidak valid.",422,origin);
    const {data:o}=await admin.from("orders").select("id,order_number,created_at,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,delivery_address,product_subtotal_idr,payment_status").eq("id",orderId).maybeSingle();if(!o)return fail("Pesanan tidak ditemukan.",404,origin);if(["paid","refunded"].includes(o.payment_status))return fail("Status pembayaran tidak dapat ditimpa.",409,origin);
    const {data:p}=await admin.from("payment_records").select("id,proof_storage_path,method").eq("order_id",orderId).eq("status","pending_verification").order("created_at",{ascending:false}).limit(1).maybeSingle();if(!p)return fail("Tidak ada pembayaran menunggu verifikasi.",409,origin);if(result==="paid"&&!p.proof_storage_path)return fail("Bukti pembayaran wajib tersedia.",409,origin);
    const {error:pe}=await admin.from("payment_records").update({status:result,verified_by:actor.user.id,verified_at:new Date().toISOString(),admin_note:note||null}).eq("id",p.id);if(pe)return fail("Status pembayaran gagal diperbarui.",500,origin);await admin.from("orders").update({payment_status:result}).eq("id",orderId);await admin.from("order_status_history").insert({order_id:orderId,status_type:"payment",old_status:o.payment_status,new_status:result,changed_by:actor.user.id,note});await admin.from("admin_audit_logs").insert({actor_user_id:actor.user.id,action:"verify_payment",entity_type:"order",entity_id:orderId,metadata:{result,payment_id:p.id,note}});
    if(result==="paid"){await admin.from("order_reservations").update({status:"consumed"}).eq("order_id",orderId).in("status",["held_for_verification","active"]);const token=randomToken(),hash=await sha256(token);await admin.from("orders").update({tracking_token_hash:hash}).eq("id",orderId);const {data:lines}=await admin.from("order_items").select("product_name_snapshot,quantity,line_total_idr").eq("order_id",orderId);const items=(lines||[]).map(i=>`• ${i.product_name_snapshot} × ${i.quantity} — Rp${Number(i.line_total_idr).toLocaleString("id-ID")}`).join("\n");const code=formatTransactionCode(o.order_number,o.created_at),track=`https://dlice.vercel.app/track.html?token=${token}`,method=p.method==="dlice_qris"?"QRIS D’Lice":"Transfer bank";const msg=`Halo ${o.customer_name}, pembayaran pesanan D’Lice ${code} sudah diverifikasi.\nTotal diterima: Rp${Number(o.product_subtotal_idr).toLocaleString("id-ID")}\nMetode: ${method}\nTanggal: ${o.requested_date}, ${o.requested_time} WITA\nPenerimaan: ${o.receiving_method==="delivery"?"Delivery — "+(o.delivery_address||""):"Pickup"}\nDetail:\n${items}\n\nTutorial cek progress seperti ojol/logistik: buka tautan pribadi berikut, lihat status terakhir dan waktu pembaruan, lalu cek riwayat status. Simpan tautan ini dan jangan bagikan ke orang lain:\n${track}\nJika bermasalah, kirim kode ${code} ke WhatsApp D’Lice. Terima kasih 💗`;const key=`payment-verified:${orderId}`;const {error:le}=await admin.from("notification_log").upsert({order_id:orderId,notification_type:"payment_verified_whatsapp",status:"manual_action_required",idempotency_key:key,recipient_whatsapp:o.customer_whatsapp,message_text:msg},{onConflict:"idempotency_key",ignoreDuplicates:true});if(le)return fail("Pembayaran sudah terverifikasi, tetapi notifikasi gagal dicatat. Retry dari panel staf.",500,origin);return json({ok:true,order_id:orderId,notification_type:"payment_verified_whatsapp",whatsapp_url:`https://wa.me/${o.customer_whatsapp}?text=${encodeURIComponent(msg)}`,notification:"manual_action_required",message:"Kirim konfirmasi beserta tautan tracking, lalu tandai pengiriman berhasil."},200,origin);}
    await admin.from("order_reservations").update({status:"released",released_at:new Date().toISOString()}).eq("order_id",orderId).in("status",["held_for_verification","active"]);return json({ok:true,message:"Pembayaran ditolak; kapasitas dilepas."},200,origin);
  }

  return fail("Aksi tidak dikenal.", 400, origin);
});
