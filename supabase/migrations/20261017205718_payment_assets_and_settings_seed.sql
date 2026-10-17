begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('dlice-payment-assets','dlice-payment-assets',false,4718592,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
insert into public.payment_settings(method,display_name,is_enabled)
values('bank_transfer','Transfer bank',false),('dlice_qris','QRIS D’Lice',false)
on conflict(method) do nothing;
commit;