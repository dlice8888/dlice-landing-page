# D’Lice backend setup and release checklist

## What is implemented in this branch
- Public Edge Function `dlice-orders` validates checkout input and delegates price/capacity validation to a transactional database function.
- Orders and item price snapshots are stored in Supabase; checkout reserves capacity for 15 minutes.
- Payment declarations and private proof uploads set `pending_verification`; they never mark an order as paid.
- Admin panel at `/admin.html` supports authenticated order review, private proof links, payment review, operational status changes, and price/capacity setup.
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

To add a sales admin, create their Auth user and insert a row in `admin_profiles` with role `sales_admin`. Only the owner can change menu prices/capacities through the panel.

## Release/testing notes
- The current landing page is static HTML. The checkout now calls the Edge Function but no live order can be accepted until prices and date capacities are configured.
- Confirm Supabase Edge Function secrets are present: the deployed function reads `SUPABASE_SECRET_KEYS` (preferred) or legacy `SUPABASE_SERVICE_ROLE_KEY`, and `SUPABASE_PUBLISHABLE_KEYS` (preferred) or legacy `SUPABASE_ANON_KEY`. These are platform-provided function secrets; never commit them.
- Public function JWT verification is disabled so unauthenticated customers can submit checkout. The function performs validation itself; run abuse/rate-limit testing before production promotion.
- The admin UI requires Supabase Auth and an active `admin_profiles` row.
- WhatsApp confirmations are currently a deliberate manual action via a generated `wa.me` link. Fully automatic messages require approved WhatsApp Business API provider credentials, templates, and webhook/retry setup.
- Before promotion, test valid and invalid checkout, price tampering, simultaneous checkout near capacity, expired reservations, on-time/late payment declaration, proof upload MIME/size, unauthorized admin calls, owner vs sales-admin access, duplicate payment verification, and notification retries.
- Do not claim production-ready until the above QA passes and actual business prices, capacity, payment details, and admin account are configured.
