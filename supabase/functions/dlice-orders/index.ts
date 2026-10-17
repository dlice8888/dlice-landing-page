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
    if (products.some((p) => !p.is_active || p.unit_price_idr == null)) return fail("Harga menu belum dikonfigurasi admin. Silakan hubungi D’Lice melalui WhatsApp.", 409, origin);
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
    const { data: lines } = await admin.from("order_items").select("product_name_snapshot,quantity,unit_price_idr,line_total_idr").eq("order_id", created.order_id);
    return json({
      order_id: created.order_id, order_number: created.order_id.slice(0, 8).toUpperCase(),
      tracking_token: trackingToken, subtotal_idr: created.subtotal_idr,
      reservation_expires_at: created.reservation_expires_at, items: lines ?? [],
      message: "Pesanan tersimpan. Lanjutkan pembayaran dalam 15 menit; jika Anda menyatakan sudah membayar atau mengirim bukti sebelum tenggat, kapasitas akan ditahan sampai admin memeriksa.",
    }, 201, origin);
  }

  if (action === "declare-payment" || action === "upload-proof") {
    const token = safeText(body.tracking_token, 100);
    if (token.length !== 64) return fail("Token pelacakan tidak valid.", 401, origin);
    const tokenHash = await sha256(token);
    const { data: order, error: orderError } = await admin.from("orders").select("id,payment_status,requested_date,requested_time,receiving_method,customer_whatsapp,product_subtotal_idr").eq("tracking_token_hash", tokenHash).maybeSingle();
    if (orderError || !order) return fail("Pesanan tidak ditemukan.", 404, origin);
    const { data: reservations, error: reservationError } = await admin.from("order_reservations").select("id,status,expires_at").eq("order_id", order.id);
    if (reservationError || !reservations?.length) return fail("Reservasi pesanan tidak ditemukan.", 409, origin);
    if (reservations.some((r) => r.status === "expired" || r.status === "released")) return fail("Reservasi sudah berakhir. Hubungi admin untuk memeriksa ketersediaan.", 409, origin);
    const allStillActive = reservations.every((r) => r.status === "active" && new Date(r.expires_at).getTime() > Date.now());
    if (action === "declare-payment") {
      if (!allStillActive && !reservations.every((r) => r.status === "held_for_verification")) return fail("Batas 15 menit telah lewat. Hubungi admin; jangan melakukan pembayaran baru sebelum dikonfirmasi.", 409, origin);
      const { error: updateError } = await admin.from("order_reservations").update({ status: "held_for_verification", payment_declared_at: new Date().toISOString() }).eq("order_id", order.id).eq("status", "active");
      if (updateError) return fail("Pernyataan pembayaran belum tersimpan.", 500, origin);
      await admin.from("orders").update({ payment_status: "pending_verification" }).eq("id", order.id);
      const { data: existingPayment } = await admin.from("payment_records").select("id").eq("order_id", order.id).eq("status", "pending_verification").order("created_at", { ascending: false }).limit(1).maybeSingle();
      if (existingPayment) {
        await admin.from("payment_records").update({ method: body.method === "dlice_qris" ? "dlice_qris" : "bank_transfer", amount_idr: order.product_subtotal_idr }).eq("id", existingPayment.id);
      } else {
        await admin.from("payment_records").insert({ order_id: order.id, method: body.method === "dlice_qris" ? "dlice_qris" : "bank_transfer", amount_idr: order.product_subtotal_idr, status: "pending_verification" });
      }
      await admin.from("order_status_history").insert({ order_id: order.id, status_type: "payment", old_status: order.payment_status, new_status: "pending_verification", note: "Customer declared payment via tracking token" });
      return json({ ok: true, message: "Pernyataan pembayaran tercatat. Kapasitas ditahan sambil menunggu pemeriksaan admin." }, 200, origin);
    }
    if (!allStillActive && !reservations.every((r) => r.status === "held_for_verification")) return fail("Reservasi sudah berakhir; hubungi admin sebelum mengunggah bukti.", 409, origin);
    const mime = safeText(body.mime_type, 50);
    const encoded = safeText(body.file_base64, 7_000_000);
    const extByMime: Record<string, string> = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "application/pdf": "pdf" };
    if (!extByMime[mime] || !encoded || encoded.length > 7_000_000) return fail("Format atau ukuran bukti tidak didukung (maksimal 5 MB).", 422, origin);
    const binary = Uint8Array.from(atob(encoded.replace(/^data:[^,]+,/, "")), (c) => c.charCodeAt(0));
    if (binary.byteLength > 5 * 1024 * 1024) return fail("Ukuran bukti maksimal 5 MB.", 413, origin);
    const path = `${order.id}/${crypto.randomUUID()}.${extByMime[mime]}`;
    const { error: uploadError } = await admin.storage.from("dlice-payment-proofs").upload(path, binary, { contentType: mime, upsert: false });
    if (uploadError) return fail("Unggahan bukti gagal. Coba kembali.", 500, origin);
    const { error: payError } = await admin.from("payment_records").insert({ order_id: order.id, method: body.method === "dlice_qris" ? "dlice_qris" : "bank_transfer", amount_idr: order.product_subtotal_idr, status: "pending_verification", proof_storage_path: path });
    if (payError) return fail("Bukti tersimpan tetapi pencatatan pembayaran gagal; hubungi admin dan jangan unggah ulang dulu.", 500, origin);
    await admin.from("order_reservations").update({ status: "held_for_verification", proof_received_at: new Date().toISOString() }).eq("order_id", order.id).eq("status", "active");
    await admin.from("orders").update({ payment_status: "pending_verification" }).eq("id", order.id);
    await admin.from("order_status_history").insert({ order_id: order.id, status_type: "payment", old_status: order.payment_status, new_status: "pending_verification", note: "Payment proof uploaded; awaiting admin verification" });
    return json({ ok: true, message: "Bukti tersimpan secara privat dan menunggu verifikasi admin." }, 200, origin);
  }

  if (action === "admin-bootstrap-owner") {
    const bootstrapSecret = Deno.env.get("D'LICE_OWNER_BOOTSTRAP_SECRET");
    if (!bootstrapSecret || safeText(body.bootstrap_secret, 256) !== bootstrapSecret) return fail("Bootstrap tidak diizinkan.", 403, origin);
    const { count, error: countError } = await admin.from("admin_profiles").select("user_id", { count: "exact", head: true }).eq("role", "owner");
    if (countError) return fail("Status owner tidak dapat diperiksa.", 500, origin);
    if ((count ?? 0) > 0) return fail("Akun owner sudah tersedia; bootstrap ditutup.", 409, origin);
    const username = safeText(body.username, 32);
    const password = typeof body.password === "string" ? body.password : "";
    if (!validUsername(username) || username.toLowerCase() !== "dlice8888" || password.length < 12) return fail("Username bootstrap atau password tidak memenuhi kebijakan.", 422, origin);
    const { data: created, error: createError } = await admin.auth.admin.createUser({ email: usernameEmail(username), password, email_confirm: true, user_metadata: { username } });
    if (createError || !created.user) return fail("Akun owner gagal dibuat.", 500, origin);
    const { error: profileError } = await admin.from("admin_profiles").insert({ user_id: created.user.id, username, role: "owner", display_name: "Owner D’Lice", is_active: true, permissions: ["*"] });
    if (profileError) { await admin.auth.admin.deleteUser(created.user.id); return fail("Profil owner gagal dibuat.", 500, origin); }
    await admin.from("admin_audit_logs").insert({ actor_user_id: created.user.id, action: "bootstrap_owner", entity_type: "admin_profile", entity_id: created.user.id, metadata: { username } });
    return json({ ok: true }, 201, origin);
  }

  const actor = await getAdmin(req);
  if (!actor) return fail("Login admin diperlukan.", 401, origin);

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
  };
  const requiredPermission = permissionForAction[action];
  if (requiredPermission && actor.profile.role !== "owner" && !actor.profile.permissions.includes(requiredPermission)) {
    return fail("Akses ditolak. Owner belum memberikan izin untuk bagian ini.", 403, origin);
  }

  if (action === "admin-list-staff") {
    if (actor.profile.role !== "owner") return fail("Hanya owner yang dapat mengelola izin admin.", 403, origin);
    const { data, error } = await admin.from("admin_profiles").select("user_id,username,role,display_name,is_active,permissions").order("created_at", { ascending: true });
    if (error) return fail("Daftar admin gagal dimuat.", 500, origin);
    return json({ staff: data ?? [], available_permissions: ["orders", "catalog", "finance", "reports", "settings", "staff"] }, 200, origin);
  }

  if (action === "admin-create-staff") {
    if (actor.profile.role !== "owner") return fail("Hanya owner yang dapat membuat akun admin.", 403, origin);
    const username = safeText(body.username, 32);
    const displayName = safeText(body.display_name, 120);
    const password = typeof body.password === "string" ? body.password : "";
    const permissions = body.permissions;
    const allowed = new Set(["orders", "catalog", "finance", "reports", "settings", "staff"]);
    if (!validUsername(username) || !displayName || password.length < 12 || !Array.isArray(permissions) || permissions.some((p) => typeof p !== "string" || !allowed.has(p))) return fail("Username, nama, password (minimal 12 karakter), atau izin tidak valid.", 422, origin);
    const { data: created, error: createError } = await admin.auth.admin.createUser({ email: usernameEmail(username), password, email_confirm: true, user_metadata: { username, display_name: displayName } });
    if (createError || !created.user) return fail(createError?.message?.includes("already") ? "Username sudah digunakan." : "Akun admin gagal dibuat.", 409, origin);
    const { error: profileError } = await admin.from("admin_profiles").insert({ user_id: created.user.id, username, role: "admin", display_name: displayName, is_active: true, permissions: [...new Set(permissions)] });
    if (profileError) { await admin.auth.admin.deleteUser(created.user.id); return fail(profileError.code === "23505" ? "Username sudah digunakan." : "Profil admin gagal dibuat.", 500, origin); }
    await admin.from("admin_audit_logs").insert({ actor_user_id: actor.user.id, action: "create_admin_account", entity_type: "admin_profile", entity_id: created.user.id, metadata: { username, permissions: [...new Set(permissions)] } });
    return json({ ok: true, username }, 201, origin);
  }

  if (action === "admin-set-permissions") {
    if (actor.profile.role !== "owner") return fail("Hanya owner yang dapat mengubah izin admin.", 403, origin);
    const userId = safeText(body.user_id, 80);
    const permissions = body.permissions;
    const allowed = new Set(["orders", "catalog", "finance", "reports", "settings", "staff"]);
    if (!userId || !Array.isArray(permissions) || permissions.some((p) => typeof p !== "string" || !allowed.has(p))) return fail("Daftar izin tidak valid.", 422, origin);
    const { data: target, error: targetError } = await admin.from("admin_profiles").select("user_id,role").eq("user_id", userId).maybeSingle();
    if (targetError || !target) return fail("Akun admin tidak ditemukan.", 404, origin);
    if (target.role === "owner") return fail("Izin akun owner tidak dapat dibatasi melalui panel ini.", 409, origin);
    const { error } = await admin.from("admin_profiles").update({ permissions: [...new Set(permissions)] }).eq("user_id", userId);
    if (error) return fail("Izin admin gagal disimpan.", 500, origin);
    await admin.from("admin_audit_logs").insert({ actor_user_id: actor.user.id, action: "update_admin_permissions", entity_type: "admin_profile", entity_id: userId, metadata: { permissions: [...new Set(permissions)] } });
    return json({ ok: true }, 200, origin);
  }

  if (action === "admin-list-orders") {
    const { data, error } = await admin.from("orders").select("id,order_number,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,delivery_address,customer_notes,product_subtotal_idr,payment_status,operational_status,created_at,order_items(product_name_snapshot,quantity,unit_price_idr,line_total_idr),payment_records(id,method,status,amount_idr,proof_storage_path,created_at)").order("created_at", { ascending: false }).limit(100);
    if (error) return fail("Daftar pesanan gagal dimuat.", 500, origin);
    return json({ orders: data ?? [], role: actor.profile.role, permissions: actor.profile.permissions }, 200, origin);
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
    if (name.length < 2 || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug) || !["fresh","pastry","other"].includes(category) || !Number.isInteger(displayOrder) || displayOrder < 0 || (price !== null && (!Number.isInteger(price) || price < 0 || price > 100000000))) return fail("Periksa nama, slug, kategori, urutan, dan harga produk.", 422, origin);
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
    if (!/^[a-z0-9-]+$/.test(slug) || !Number.isInteger(price) || price < 0 || !/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isInteger(capacity) || capacity < 0 || capacity > 10000) return fail("Harga/tanggal/kapasitas tidak valid.", 422, origin);
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
    if (!allowed.includes(next)) return fail("Status operasional tidak valid.", 422, origin);
    const { data: oldOrder } = await admin.from("orders").select("operational_status").eq("id", orderId).maybeSingle();
    if (!oldOrder) return fail("Pesanan tidak ditemukan.", 404, origin);
    const { error } = await admin.from("orders").update({ operational_status: next }).eq("id", orderId);
    if (error) return fail("Status gagal diperbarui.", 500, origin);
    await admin.from("order_status_history").insert({ order_id: orderId, status_type: "operational", old_status: oldOrder.operational_status, new_status: next, changed_by: actor.user.id });
    await admin.from("admin_audit_logs").insert({ actor_user_id: actor.user.id, action: "update_order_status", entity_type: "order", entity_id: orderId, metadata: { old_status: oldOrder.operational_status, new_status: next } });
    return json({ ok: true }, 200, origin);
  }

  if (action === "admin-verify-payment") {
    const orderId = safeText(body.order_id, 80);
    const result = safeText(body.result, 20);
    const note = safeText(body.note, 500);
    if (!["paid","rejected"].includes(result)) return fail("Hasil verifikasi tidak valid.", 422, origin);

    const { data: order } = await admin.from("orders").select("id,order_number,customer_name,customer_whatsapp,requested_date,requested_time,receiving_method,delivery_address,product_subtotal_idr,payment_status").eq("id", orderId).maybeSingle();
    if (!order) return fail("Pesanan tidak ditemukan.", 404, origin);
    if (order.payment_status === "paid" || order.payment_status === "refunded") return fail("Status pembayaran ini tidak dapat ditimpa.", 409, origin);
    const { data: payment } = await admin.from("payment_records").select("id").eq("order_id", orderId).eq("status","pending_verification").order("created_at",{ascending:false}).limit(1).maybeSingle();
    if (!payment) return fail("Tidak ada pembayaran yang menunggu verifikasi.", 409, origin);
    const { error: paymentError } = await admin.from("payment_records").update({ status: result, verified_by: actor.user.id, verified_at: new Date().toISOString(), admin_note: note || null }).eq("id", payment.id);
    if (paymentError) return fail("Status pembayaran gagal diperbarui.", 500, origin);
    await admin.from("orders").update({ payment_status: result }).eq("id", orderId);
    await admin.from("order_status_history").insert({ order_id: orderId, status_type: "payment", old_status: order.payment_status, new_status: result, changed_by: actor.user.id, note });
    await admin.from("admin_audit_logs").insert({ actor_user_id: actor.user.id, action: "verify_payment", entity_type: "order", entity_id: orderId, metadata: { result, payment_id: payment.id, note } });
    if (result === "paid") {
      await admin.from("order_reservations").update({ status: "consumed" }).eq("order_id", orderId).in("status", ["held_for_verification","active"]);
      const msg = `Halo ${order.customer_name}, pembayaran pesanan D’Lice #${String(order.order_number).padStart(5,"0")} sudah diverifikasi. Total produk: Rp${Number(order.product_subtotal_idr).toLocaleString("id-ID")}. Tanggal: ${order.requested_date}, waktu: ${order.requested_time}. Penerimaan: ${order.receiving_method === "delivery" ? "Delivery — " + (order.delivery_address ?? "") : "Pickup"}. Terima kasih! 💗`;
      const idempotencyKey = `payment-verified:${orderId}`;
      await admin.from("notification_log").upsert({ order_id: orderId, notification_type: "payment_verified_whatsapp", status: "manual_action_required", idempotency_key: idempotencyKey, recipient_whatsapp: order.customer_whatsapp, message_text: msg }, { onConflict: "idempotency_key", ignoreDuplicates: true });
      return json({ ok: true, whatsapp_url: `https://wa.me/${order.customer_whatsapp}?text=${encodeURIComponent(msg)}`, notification: "manual_action_required", message: "Pembayaran diverifikasi. Buka tautan WhatsApp untuk mengirim konfirmasi; pengiriman otomatis memerlukan kredensial WhatsApp Business API." }, 200, origin);
    }
    await admin.from("order_reservations").update({ status: "released", released_at: new Date().toISOString() }).eq("order_id", orderId).in("status", ["held_for_verification","active"]);
    return json({ ok: true, message: "Pembayaran ditolak; kapasitas dilepas. Hubungi pelanggan bila diperlukan." }, 200, origin);
  }

  return fail("Aksi tidak dikenal.", 400, origin);
});
