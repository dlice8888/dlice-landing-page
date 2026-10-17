# D’Lice staging acceptance test plan

**Environment:** Vercel Preview branch `feat/staging-order-receipt-gates` + Supabase staging project `higoadrzxnhzbbwhdbmh`.

**Production guard:** Do not merge this branch or deploy the function to `gdjlkrmlsurcdbwnmqgg` until all mandatory checks below pass and the owner approves.

## Before testing
- [ ] Open the Preview URL from the latest deployment for this branch (not `dlice.vercel.app`).
- [ ] Sign in to `admin.html` using the existing Owner username account.
- [ ] In Owner > Instruksi pembayaran, enter the correct bank display name, account owner and account number, then enable bank transfer.
- [ ] Upload the correct QRIS image, inspect it, then enable QRIS. Do not use fake account details or make a real transfer during a test.
- [ ] Create a dedicated test staff account and grant only the permissions needed for the staff test.
- [ ] Choose a future service date and configure product capacity for each test menu.
- [ ] Use a clearly identifiable test order/customer; do not delete historical staging orders.

## Tracking and operations navigation
- [ ] Open `track.html` using the private tracking link from a test order; verify invalid/missing tokens do not reveal order data.
- [ ] Verify the tracking page displays the correct DLC transaction code, payment status, requested date/time, receiving method, item quantities, subtotal and localized status history.
- [ ] Change an operational status in the staging Owner/staff page and confirm tracking reflects the latest status after manual refresh or the 45-second auto-refresh.
- [ ] Verify desktop operations page uses a sidebar and mobile uses a horizontally scrollable compact menu; each menu opens the matching section.
- [ ] Verify the dashboard counts match the staging order list; payment menu filters orders requiring payment action and operations menu filters active orders.
- [ ] Sign in as staff with only `orders`; verify catalog, capacity, payment settings and staff management are hidden/unavailable as applicable.
- [ ] Sign in as staff with only `catalog`; verify catalog access works but order/payment operations are not available.
- [ ] Sign in as staff with `settings`; verify capacity menu is available only if the backend authorizes the related action.
- [ ] Verify Owner can manage staff permissions and payment settings, while direct API calls by unauthorized staff are rejected (UI hiding alone is not sufficient).

## Customer checkout
- [ ] Menu quantity changes update the summary and estimated total immediately.
- [ ] Submit an order with multiple products; server response uses authoritative product prices and ID format `DLC-dd/mm/yyyy-xxxxx` in WITA.
- [ ] A receipt modal appears before payment instructions; confirm is required.
- [ ] Transfer selection shows the active bank display name, account owner, account number and instructions.
- [ ] QRIS selection shows the active QR image and instructions.
- [ ] A second receipt modal appears before proof upload and includes selected payment method, item quantities, unit prices, line subtotals and total.
- [ ] Changing quantity before proof upload updates the server order, increments receipt version, invalidates the prior approval and requires a new receipt confirmation.
- [ ] Changing quantity after proof upload is blocked; staff must handle the correction.
- [ ] Upload an allowed proof file; then upload a replacement proof and verify the existing pending payment record is reused rather than duplicated.
- [ ] Upload unsupported file type or file over 5 MB; verify a clear rejection.
- [ ] The bottom WhatsApp button is hidden before proof upload and appears after successful upload. The message contains order code, customer contact, items, quantities, prices, total, schedule, receiving method, delivery address, notes and proof status.
- [ ] Click final WhatsApp handoff; verify message opens for admin `6285397710002`. Confirm sending in WhatsApp. A failed/closed WhatsApp window must not delete the order.

## Staff and Owner workflow
- [ ] Owner can save bank settings, upload/replace QRIS and enable/disable each method.
- [ ] A staff account without `settings` permission cannot read or change payment settings.
- [ ] A staff account without `orders` permission cannot list orders, view proof, verify payment or change status.
- [ ] Payment cannot be marked paid without an uploaded proof.
- [ ] After payment verification, a customer WhatsApp confirmation is prepared with verified amount/method, order details, private tracking link and tutorial.
- [ ] Open the WhatsApp message and mark it sent only after confirming it was actually sent.
- [ ] Attempt an operational status update before marking payment confirmation sent; server must reject it.
- [ ] After marking sent, status change asks for confirmation; cancellation/delivery issue also requires a reason.
- [ ] Status history and audit log record actor, time, before/after state and reason.
- [ ] Legacy paid orders without a notification log show a retry/create confirmation action; pending orders without proof cannot be approved.

## Security and data integrity
- [ ] Direct anonymous REST access to order/payment/settings tables remains denied.
- [ ] Invalid tracking token cannot retrieve order data.
- [ ] Tracking page only shows order summary, payment status, operational status and timeline; it does not expose phone number or internal notes.
- [ ] Old receipt version cannot be used to upload proof or finalize WhatsApp message.
- [ ] Two simultaneous checkouts for the same product/date cannot exceed configured capacity.
- [ ] Same-day orders after 18:00 WITA are rejected.
- [ ] Review Supabase security advisors and function logs after test runs.

## Current staging baseline (do not delete automatically)
- There are 5 existing staging orders and 6 payment records.
- 2 payment records are pending verification without proof; they must not be approved.
- Existing historical orders predate receipt snapshots; keep them intact and use the legacy notification retry action where appropriate.
- Bank transfer and QRIS are seeded but disabled until Owner configures real payment details.

## Pass criteria
All mandatory checks above pass in Preview and staging, no unexpected duplicate payment records are created, no unhandled runtime errors appear, and the Owner explicitly approves production promotion.
