-- Keep stock transfers/counts exclusively behind the authenticated Edge Function.
-- RLS deny policies are defense in depth; explicit revokes prevent accidental Data API exposure.
REVOKE ALL PRIVILEGES ON TABLE
  public.stock_transfers,
  public.stock_transfer_items,
  public.stock_counts,
  public.stock_count_items
FROM PUBLIC, anon, authenticated;
