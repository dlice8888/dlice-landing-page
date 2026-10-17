# D’Lice backend setup and release checklist

## What is implemented in this branch
- Public Edge Function `dlice-orders` validates checkout input and delegates price/capacity validation to a transactional database function.
- Orders and item price snapshots are stored in Supabase; checkout reserves capacity for 15 minutes.
- Payment declarations and private proof uploads set `pending_verification`; they never mark an order as paid.
- Admin panel at `/admin.html` supports authenticated order review, private proof links, payment review, operational status changes, price/capacity setup, and owner-only per-admin permission management.
- Owner has full access. Non-owner profiles default to the `orders` permission only; the Edge Function checks permissions before protected actions. Available sections: `orders`, `catalog`, `finance`, `reports`, `settings`, and `staff`.
- Payment verification creates an idempotent notification-log record and returns a WhatsApp deep link for a human to send. Automated WhatsApp Business API delivery is not enabled because no provider credentials were supplied.
- Menu prices and date-specific capacities are intentionally blank until the owner enters real business values.

## One-time owner/admin setup
1. In Supabase Dashboard > Authentication > Users, create the intended owner account using an email controlled by D’Lice.
2. Copy that user's UUID.
3. In SQL Editor, run the following after replacing the UUID and display name. Never put this UUID in frontend code.

```sql
insert into public.admin_profiles(user_id, role, display_name, is_active)
values ('REPLACE_WITH_AUTH_USER_UUID'::uuid, 'owner', 'D’Lice Owner', true)
on conflict (user_id) do update
set role = 'owner', display_name = excluded.display_name, is_active = true;
```

4. Open `https://dlice.vercel.app/admin.html`, sign in, and set each product's actual unit price and capacity for each date before accepting orders.
5. Configure bank-transfer instructions and the official D’Lice QRIS in the business process before directing customers to pay. Do not accept proof as payment confirmation.

To add an admin, create their Auth user and insert a row in `admin_profiles` with a non-owner role, `is_active = true`, and `permissions = '["orders"]'::jsonb`. Apply migration `20261018004000_admin_role_permissions.sql` before deploying the updated Edge Function. Sign in as owner, open “Hak akses admin”, and grant only the required sections. Catalog permission allows price/capacity configuration; finance/reports/settings/staff are permission keys for future protected modules. Owners cannot be restricted through the admin permission panel.

## Release/testing notes
- The current landing page is static HTML. The checkout now calls the Edge Function but no live order can be accepted until prices and date capacities are configured.
- Confirm Supabase Edge Function secrets are present: the deployed function reads `SUPABASE_SECRET_KEYS` (preferred) or legacy `SUPABASE_SERVICE_ROLE_KEY`, and `SUPABASE_PUBLISHABLE_KEYS` (preferred) or legacy `SUPABASE_ANON_KEY`. These are platform-provided function secrets; never commit them.
- Public function JWT verification is disabled so unauthenticated customers can submit checkout. The function performs validation itself; run abuse/rate-limit testing before production promotion.
- The admin UI requires Supabase Auth and an active `admin_profiles` row.
- WhatsApp confirmations are currently a deliberate manual action via a generated `wa.me` link. Fully automatic messages require approved WhatsApp Business API provider credentials, templates, and webhook/retry setup.
- Before promotion, test valid and invalid checkout, price tampering, simultaneous checkout near capacity, expired reservations, on-time/late payment declaration, proof upload MIME/size, unauthorized admin calls, owner vs sales-admin access, duplicate payment verification, and notification retries.
- Do not claim production-ready until the above QA passes and actual business prices, capacity, payment details, and admin account are configured.

## Katalog produk dan foto Supabase

Branch `feat/supabase-product-catalog` menyiapkan katalog yang dibaca website dari aksi publik `list-products`, beserta panel owner untuk mengelola produk. Migrasi `20261018005000_product_catalog_storage.sql` menambah metadata katalog tanpa mengubah atau menghapus tabel pesanan dan membuat bucket publik `dlice-product-photos` (JPG/PNG/WebP, maksimal 5 MB).

Kolom katalog:
- `image_path`: path objek dalam bucket foto produk; URL publik dibuat dari Storage.
- `category`: `fresh`, `pastry`, atau `other`.
- `display_order`: urutan menaik pada halaman menu.
- `badge`: label opsional pada kartu produk.

Panel admin menyediakan aksi `admin-list-products`, `admin-save-product`, dan `admin-upload-product-photo`. Semua aksi membutuhkan sesi admin yang valid dan izin `catalog`; owner selalu mendapat akses penuh. Unggah foto menggunakan Edge Function agar kunci service-role tidak pernah dikirim ke browser. Foto yang diunggah baru dipakai website setelah produk disimpan dengan `image_path` tersebut.

### Prosedur staging

1. Gunakan proyek Supabase staging terpisah untuk menguji migrasi dan Edge Function. Jangan deploy versi fungsi katalog ke proyek yang melayani produksi sebelum pengujian selesai, karena fungsi `dlice-orders` yang sama melayani checkout produksi.
2. Terapkan migrasi dalam urutan setelah migrasi ordering/permissions yang sudah ada di branch.
3. Deploy Edge Function `dlice-orders` dari branch ini ke proyek staging.
4. Buka preview Vercel, masuk sebagai owner, unggah foto tiap produk, lalu simpan katalog.
5. Verifikasi menu, filter, harga, checkout multi-menu, izin akun admin, dan order snapshot. Pastikan data order lama tetap ada.
6. Setelah lulus, rencanakan rollout produksi secara terpisah. Jangan hapus foto lama di GitHub sampai semua foto yang diperlukan telah diunggah ke Storage dan halaman produksi diverifikasi.

Catatan: migrasi hanya menambahkan kolom dan bucket; foto lama tidak otomatis dipindahkan oleh SQL. Foto perlu diunggah melalui panel admin agar file benar-benar berada di Supabase Storage.
