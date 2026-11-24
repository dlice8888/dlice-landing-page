-- Remove two zero-scan single-column indexes that are fully covered by
-- existing unique composite indexes with the same leading key.
-- The composite indexes continue to support FK lookups on the leading column.
DROP INDEX IF EXISTS public.stock_count_items_count_idx;
DROP INDEX IF EXISTS public.stock_transfer_items_transfer_idx;
