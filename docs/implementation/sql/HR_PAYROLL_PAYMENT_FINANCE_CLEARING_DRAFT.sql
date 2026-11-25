-- DESIGN DRAFT ONLY — payroll payout Finance clearing + bank statement evidence.
-- Depends on HR_PAYROLL_FINANCE_SCHEMA_DRAFT.sql and
-- HR_PAYROLL_PAYMENT_ADAPTERS_DRAFT.sql. Not a migration; do not apply to
-- staging until the combined disposable replay, pgTAP, ACL and RLS gates pass.
--
-- Accounting flow:
-- 1) Provider-confirmed beneficiary settlement: Dr payroll payable / Cr payout clearing.
-- 2) Independently imported bank debit: Dr payout clearing / Cr bank cash.
-- 3) A provider reversal is an exception until an independently verified bank
--    return is matched; never silently rewrite the original posted entries.
--
-- Account codes intentionally use the existing Finance journal account fields.
-- They must be independently approved and mapped per tenant + branch + provider.

create table if not exists public.hr_payroll_payment_finance_mappings (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 provider_config_id uuid not null,
 payroll_payable_account text not null check(length(btrim(payroll_payable_account)) between 1 and 80),
 payout_clearing_account text not null check(length(btrim(payout_clearing_account)) between 1 and 80),
 bank_cash_account text not null check(length(btrim(bank_cash_account)) between 1 and 80),
 status text not null default 'pending' check(status in ('pending','approved','suspended')),
 created_by uuid not null references auth.users(id) on delete restrict,
 approved_by uuid null references auth.users(id) on delete restrict,
 approved_at timestamptz null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,branch_id,provider_config_id),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 foreign key(tenant_id,provider_config_id) references public.hr_payroll_payment_provider_configs(tenant_id,id) on delete restrict,
 check(payroll_payable_account<>payout_clearing_account),
 check(payout_clearing_account<>bank_cash_account),
 check(status<>'approved' or (approved_by is not null and approved_at is not null and approved_by<>created_by))
);

create table if not exists public.hr_payroll_payment_finance_clearings (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 payment_batch_id uuid not null,
 payment_item_id uuid not null,
 provider_event_id uuid not null,
 mapping_id uuid not null,
 payout_provider_reference text not null,
 amount_idr bigint not null check(amount_idr>0),
 payout_journal_entry_id uuid not null references public.finance_journal_entries(id) on delete restrict,
 bank_statement_line_id uuid null,
 bank_journal_entry_id uuid null references public.finance_journal_entries(id) on delete restrict,
 status text not null default 'provider_cleared' check(status in ('provider_cleared','bank_matched','reversal_exception')),
 created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 bank_matched_by uuid null references auth.users(id) on delete restrict,
 bank_matched_at timestamptz null,
 unique(tenant_id,id),
 unique(tenant_id,payment_item_id),
 unique(tenant_id,payout_provider_reference),
 foreign key(tenant_id,payment_batch_id) references public.hr_payroll_payment_batches(tenant_id,id) on delete restrict,
 foreign key(tenant_id,payment_item_id) references public.hr_payroll_payment_items(tenant_id,id) on delete restrict,
 foreign key(tenant_id,provider_event_id) references public.hr_payroll_provider_events(tenant_id,id) on delete restrict,
 foreign key(tenant_id,mapping_id) references public.hr_payroll_payment_finance_mappings(tenant_id,id) on delete restrict,
 check((status='bank_matched' and bank_statement_line_id is not null and bank_journal_entry_id is not null and bank_matched_by is not null and bank_matched_at is not null) or status<>'bank_matched')
);

-- Statement lines are imported only by a trusted server-side bank adapter.
-- No credentials, account numbers or raw statement files are stored here.
create table if not exists public.hr_payroll_bank_statement_lines (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 bank_account_fingerprint_sha256 text not null check(bank_account_fingerprint_sha256 ~ '^[0-9a-f]{64}$'),
 statement_reference text not null check(length(btrim(statement_reference)) between 1 and 180),
 provider_payout_reference text not null check(length(btrim(provider_payout_reference)) between 1 and 180),
 amount_idr bigint not null check(amount_idr>0),
 currency text not null check(currency='IDR'),
 booked_at timestamptz not null,
 line_sha256 text not null check(line_sha256 ~ '^[0-9a-f]{64}$'),
 import_batch_reference text not null,
 imported_by uuid not null references auth.users(id) on delete restrict,
 imported_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,bank_account_fingerprint_sha256,statement_reference),
 unique(tenant_id,bank_account_fingerprint_sha256,line_sha256),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);

create index if not exists hr_payroll_payment_clearing_status_idx
 on public.hr_payroll_payment_finance_clearings(tenant_id,status,created_at);
create index if not exists hr_payroll_bank_statement_unmatched_idx
 on public.hr_payroll_bank_statement_lines(tenant_id,branch_id,provider_payout_reference);

create or replace function public.hr_post_payroll_payment_finance_clearing(
 p_tenant_id uuid,p_payment_batch_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare
 v_batch public.hr_payroll_payment_batches%rowtype;
 v_post public.hr_payroll_finance_postings%rowtype;
 v_map public.hr_payroll_payment_finance_mappings%rowtype;
 v_item record;
 v_event public.hr_payroll_provider_events%rowtype;
 v_entry_id uuid;
 v_entry_code text;
 v_count integer:=0;
 v_total bigint:=0;
begin
 select * into v_batch from public.hr_payroll_payment_batches
  where tenant_id=p_tenant_id and id=p_payment_batch_id for update;
 if not found or v_batch.status<>'reconciled' then
  raise exception using errcode='23514',message='RECONCILED_PROVIDER_PAYROLL_BATCH_REQUIRED';
 end if;
 select * into v_post from public.hr_payroll_finance_postings
  where tenant_id=p_tenant_id and id=v_batch.finance_posting_id and status='reconciled' for share;
 if not found or v_post.net_amount_idr<>v_batch.amount_idr then
  raise exception using errcode='23514',message='RECONCILED_PAYROLL_FINANCE_POSTING_REQUIRED';
 end if;
 if p_actor_user_id in (v_batch.created_by,v_batch.approved_by,v_batch.reconciled_by,
   v_post.created_by,v_post.posted_by,v_post.reconciled_by) then
  raise exception using errcode='42501',message='INDEPENDENT_FINANCE_CLEARING_POSTER_REQUIRED';
 end if;
 select * into v_map from public.hr_payroll_payment_finance_mappings
  where tenant_id=p_tenant_id and branch_id=v_batch.branch_id
   and provider_config_id=v_batch.provider_config_id and status='approved' for share;
 if not found then raise exception using errcode='23514',message='APPROVED_PAYROLL_PAYMENT_FINANCE_MAPPING_REQUIRED'; end if;
 for v_item in
  select i.* from public.hr_payroll_payment_items i
  where i.tenant_id=p_tenant_id and i.payment_batch_id=v_batch.id
  order by i.id for update
 loop
  if v_item.status<>'settled' or v_item.provider_reference is null then
   raise exception using errcode='23514',message='EVERY_PAYROLL_PAYMENT_ITEM_MUST_BE_PROVIDER_SETTLED';
  end if;
  if exists(select 1 from public.hr_payroll_payment_finance_clearings c
    where c.tenant_id=p_tenant_id and c.payment_item_id=v_item.id) then
   continue;
  end if;
  select * into v_event from public.hr_payroll_provider_events e
   where e.tenant_id=p_tenant_id and e.payment_batch_id=v_batch.id
    and e.payment_item_id=v_item.id and e.event_kind='settled'
    and e.provider_reference=v_item.provider_reference
   order by e.occurred_at desc,e.received_at desc limit 1;
  if not found or v_event.signature_verified is distinct from true
    or v_event.amount_idr<>v_item.amount_idr then
   raise exception using errcode='23514',message='AUTHENTICATED_SETTLEMENT_EVENT_REQUIRED_FOR_CLEARING';
  end if;
  v_entry_code:='PCL-'||replace(v_batch.id::text,'-','')||'-'||replace(v_item.id::text,'-','');
  insert into public.finance_journal_entries(
   entry_code,fiscal_period_id,branch_id,source_type,source_id,entry_date,
   debit_account,credit_account,amount_idr,description,status,created_by
  ) values(v_entry_code,v_post.fiscal_period_id,v_batch.branch_id,
   'hr_payroll_payment_clearing',v_item.id,
   (v_event.occurred_at at time zone 'UTC')::date,
   v_map.payroll_payable_account,v_map.payout_clearing_account,v_item.amount_idr,
   'Payroll provider payout clearing '||v_item.id::text,'posted',p_actor_user_id)
  returning id into v_entry_id;
  insert into public.hr_payroll_payment_finance_clearings(
   tenant_id,payment_batch_id,payment_item_id,provider_event_id,mapping_id,
   payout_provider_reference,amount_idr,payout_journal_entry_id,created_by
  ) values(p_tenant_id,v_batch.id,v_item.id,v_event.id,v_map.id,
   v_item.provider_reference,v_item.amount_idr,v_entry_id,p_actor_user_id);
  v_count:=v_count+1; v_total:=v_total+v_item.amount_idr;
 end loop;
 if v_total + coalesce((select sum(amount_idr) from public.hr_payroll_payment_finance_clearings
    where tenant_id=p_tenant_id and payment_batch_id=v_batch.id
     and payout_journal_entry_id is not null),0) < v_batch.amount_idr then
  -- The aggregate is checked below using the durable rows; this branch is only
  -- an early guard and does not mark the batch reconciled.
  null;
 end if;
 if (select count(*) from public.hr_payroll_payment_finance_clearings
     where tenant_id=p_tenant_id and payment_batch_id=v_batch.id)<>v_batch.item_count
   or (select coalesce(sum(amount_idr),0) from public.hr_payroll_payment_finance_clearings
     where tenant_id=p_tenant_id and payment_batch_id=v_batch.id)<>v_batch.amount_idr then
  raise exception using errcode='23514',message='PAYROLL_FINANCE_CLEARING_TOTAL_MISMATCH';
 end if;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.payment_finance_clearing_posted',
  'hr_payroll_payment_batches',v_batch.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'amount_idr',v_batch.amount_idr,
   'new_clearing_rows',v_count,'item_count',v_batch.item_count));
 return jsonb_build_object('status','provider_cleared','payment_batch_id',v_batch.id,
  'amount_idr',v_batch.amount_idr,'item_count',v_batch.item_count,
  'new_clearing_rows',v_count);
end $$;
revoke all on function public.hr_post_payroll_payment_finance_clearing(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_post_payroll_payment_finance_clearing(uuid,uuid,uuid) to service_role;

create or replace function public.hr_import_payroll_bank_statement_line(
 p_tenant_id uuid,p_branch_id uuid,p_bank_account_fingerprint_sha256 text,
 p_statement_reference text,p_provider_payout_reference text,p_amount_idr bigint,
 p_booked_at timestamptz,p_line_sha256 text,p_import_batch_reference text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_payroll_bank_statement_lines%rowtype;
begin
 if coalesce(p_bank_account_fingerprint_sha256,'') !~ '^[0-9a-f]{64}$'
  or coalesce(p_line_sha256,'') !~ '^[0-9a-f]{64}$'
  or p_amount_idr<=0 or length(btrim(coalesce(p_statement_reference,'')))=0
  or length(btrim(coalesce(p_provider_payout_reference,'')))=0 then
  raise exception using errcode='22023',message='INVALID_BANK_STATEMENT_LINE_EVIDENCE';
 end if;
 insert into public.hr_payroll_bank_statement_lines(
  tenant_id,branch_id,bank_account_fingerprint_sha256,statement_reference,
  provider_payout_reference,amount_idr,currency,booked_at,line_sha256,
  import_batch_reference,imported_by
 ) values(p_tenant_id,p_branch_id,p_bank_account_fingerprint_sha256,
  p_statement_reference,p_provider_payout_reference,p_amount_idr,'IDR',
  p_booked_at,p_line_sha256,p_import_batch_reference,p_actor_user_id)
 on conflict(tenant_id,bank_account_fingerprint_sha256,statement_reference) do nothing
 returning * into v;
 if not found then
  select * into v from public.hr_payroll_bank_statement_lines
   where tenant_id=p_tenant_id and bank_account_fingerprint_sha256=p_bank_account_fingerprint_sha256
    and statement_reference=p_statement_reference for update;
  if v.line_sha256<>p_line_sha256 or v.amount_idr<>p_amount_idr
   or v.provider_payout_reference<>p_provider_payout_reference then
   raise exception using errcode='23505',message='BANK_STATEMENT_REFERENCE_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','statement_line_id',v.id);
 end if;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.bank_statement_line_imported',
  'hr_payroll_bank_statement_lines',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,
   'provider_payout_reference',p_provider_payout_reference,'amount_idr',p_amount_idr,
   'line_sha256',p_line_sha256));
 return jsonb_build_object('status','imported','statement_line_id',v.id);
end $$;
revoke all on function public.hr_import_payroll_bank_statement_line(uuid,uuid,text,text,text,bigint,timestamptz,text,text,uuid) from public,anon,authenticated;
grant execute on function public.hr_import_payroll_bank_statement_line(uuid,uuid,text,text,text,bigint,timestamptz,text,text,uuid) to service_role;

create or replace function public.hr_match_payroll_payment_bank_statement(
 p_tenant_id uuid,p_clearing_id uuid,p_statement_line_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare
 v public.hr_payroll_payment_finance_clearings%rowtype;
 s public.hr_payroll_bank_statement_lines%rowtype;
 m public.hr_payroll_payment_finance_mappings%rowtype;
 b public.hr_payroll_payment_batches%rowtype;
 v_entry_id uuid;
 v_code text;
begin
 select * into v from public.hr_payroll_payment_finance_clearings
  where tenant_id=p_tenant_id and id=p_clearing_id for update;
 if not found or v.status<>'provider_cleared' then
  raise exception using errcode='23514',message='UNMATCHED_PROVIDER_CLEARING_REQUIRED';
 end if;
 select * into s from public.hr_payroll_bank_statement_lines
  where tenant_id=p_tenant_id and id=p_statement_line_id for update;
 if not found then raise exception using errcode='23503',message='BANK_STATEMENT_LINE_NOT_FOUND'; end if;
 select * into b from public.hr_payroll_payment_batches
  where tenant_id=p_tenant_id and id=v.payment_batch_id for share;
 select * into m from public.hr_payroll_payment_finance_mappings
  where tenant_id=p_tenant_id and id=v.mapping_id for share;
 if s.branch_id<>b.branch_id or s.provider_payout_reference<>v.payout_provider_reference
  or s.amount_idr<>v.amount_idr or s.currency<>'IDR'
  or s.bank_account_fingerprint_sha256 !~ '^[0-9a-f]{64}$' then
  raise exception using errcode='23514',message='BANK_STATEMENT_PAYOUT_MATCH_MISMATCH';
 end if;
 if exists(select 1 from public.hr_payroll_payment_finance_clearings
  where tenant_id=p_tenant_id and bank_statement_line_id=s.id) then
  raise exception using errcode='23505',message='BANK_STATEMENT_LINE_ALREADY_MATCHED';
 end if;
 if p_actor_user_id in (v.created_by,b.created_by,b.approved_by,b.reconciled_by) then
  raise exception using errcode='42501',message='INDEPENDENT_BANK_STATEMENT_RECONCILER_REQUIRED';
 end if;
 v_code:='PBM-'||replace(v.id::text,'-','');
 insert into public.finance_journal_entries(
  entry_code,fiscal_period_id,branch_id,source_type,source_id,entry_date,
  debit_account,credit_account,amount_idr,description,status,created_by
 ) select v_code,fp.id,b.branch_id,'hr_payroll_bank_statement',s.id,
   (s.booked_at at time zone 'UTC')::date,m.payout_clearing_account,m.bank_cash_account,
   s.amount_idr,'Payroll bank statement payout match '||s.id::text,'posted',p_actor_user_id
   from public.hr_payroll_finance_postings fp where fp.tenant_id=p_tenant_id and fp.id=b.finance_posting_id
 returning id into v_entry_id;
 if v_entry_id is null then raise exception using errcode='23503',message='PAYROLL_FINANCE_POSTING_NOT_FOUND'; end if;
 update public.hr_payroll_payment_finance_clearings set status='bank_matched',
  bank_statement_line_id=s.id,bank_journal_entry_id=v_entry_id,
  bank_matched_by=p_actor_user_id,bank_matched_at=now() where id=v.id returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.payment_bank_statement_matched',
  'hr_payroll_payment_finance_clearings',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'statement_line_id',s.id,
   'bank_journal_entry_id',v_entry_id,'amount_idr',v.amount_idr));
 return jsonb_build_object('status','bank_matched','clearing_id',v.id,
  'statement_line_id',s.id,'bank_journal_entry_id',v_entry_id,'amount_idr',v.amount_idr);
end $$;
revoke all on function public.hr_match_payroll_payment_bank_statement(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_match_payroll_payment_bank_statement(uuid,uuid,uuid,uuid) to service_role;

-- Provider-reversed payouts are deliberately quarantined. A reversal is not
-- cleared by changing the original payout journal; require a separately
-- imported bank return line and a separately approved reversal policy before
-- posting any compensating entry.
create or replace function public.hr_mark_payroll_payment_reversal_exception(
 p_tenant_id uuid,p_payment_item_id uuid,p_provider_event_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare
 v_item public.hr_payroll_payment_items%rowtype;
 v_event public.hr_payroll_provider_events%rowtype;
 v_clear public.hr_payroll_payment_finance_clearings%rowtype;
begin
 select * into v_item from public.hr_payroll_payment_items
  where tenant_id=p_tenant_id and id=p_payment_item_id for update;
 if not found then raise exception using errcode='23503',message='PAYROLL_PAYMENT_ITEM_NOT_FOUND'; end if;
 select * into v_event from public.hr_payroll_provider_events
  where tenant_id=p_tenant_id and id=p_provider_event_id
   and payment_item_id=v_item.id and event_kind='reversed' and signature_verified=true;
 if not found then raise exception using errcode='23514',message='AUTHENTICATED_PROVIDER_REVERSAL_REQUIRED'; end if;
 select * into v_clear from public.hr_payroll_payment_finance_clearings
  where tenant_id=p_tenant_id and payment_item_id=v_item.id for update;
 if found then
  update public.hr_payroll_payment_finance_clearings set status='reversal_exception'
   where id=v_clear.id returning * into v_clear;
 end if;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.payment_reversal_quarantined',
  'hr_payroll_payment_items',v_item.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'provider_event_id',v_event.id,
   'clearing_id',v_clear.id,'requires_bank_return_evidence',true));
 return jsonb_build_object('status','reversal_exception','payment_item_id',v_item.id,
  'clearing_id',v_clear.id,'requires_bank_return_evidence',true);
end $$;
revoke all on function public.hr_mark_payroll_payment_reversal_exception(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_mark_payroll_payment_reversal_exception(uuid,uuid,uuid,uuid) to service_role;

do $$
declare t text;
begin
 foreach t in array array[
  'hr_payroll_payment_finance_mappings','hr_payroll_payment_finance_clearings',
  'hr_payroll_bank_statement_lines'
 ] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists service_role_only on public.%I',t);
  execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant select,insert,update,delete on public.%I to service_role',t);
 end loop;
end $$;

create or replace function public.hr_reject_payroll_payment_finance_evidence_mutation()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
 raise exception using errcode='55000',message='PAYROLL_PAYMENT_FINANCE_EVIDENCE_APPEND_ONLY';
end $$;
revoke all on function public.hr_reject_payroll_payment_finance_evidence_mutation() from public,anon,authenticated;
drop trigger if exists hr_payroll_bank_statement_lines_append_only on public.hr_payroll_bank_statement_lines;
create trigger hr_payroll_bank_statement_lines_append_only
 before update or delete on public.hr_payroll_bank_statement_lines
 for each row execute function public.hr_reject_payroll_payment_finance_evidence_mutation();

-- The clearings table is stateful but its journal links are immutable. Protect
-- the journal ids, amount and provider identity against later mutation.
create or replace function public.hr_guard_payroll_payment_clearing_identity()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
 if new.tenant_id<>old.tenant_id or new.payment_batch_id<>old.payment_batch_id
  or new.payment_item_id<>old.payment_item_id or new.provider_event_id<>old.provider_event_id
  or new.mapping_id<>old.mapping_id or new.payout_provider_reference<>old.payout_provider_reference
  or new.amount_idr<>old.amount_idr or new.payout_journal_entry_id<>old.payout_journal_entry_id then
  raise exception using errcode='55000',message='PAYROLL_PAYMENT_CLEARING_IDENTITY_IMMUTABLE';
 end if;
 if old.status='bank_matched' and new.status<>'bank_matched' then
  raise exception using errcode='55000',message='BANK_MATCHED_CLEARING_IS_IMMUTABLE';
 end if;
 return new;
end $$;
revoke all on function public.hr_guard_payroll_payment_clearing_identity() from public,anon,authenticated;
drop trigger if exists hr_payroll_payment_clearing_identity_guard on public.hr_payroll_payment_finance_clearings;
create trigger hr_payroll_payment_clearing_identity_guard
 before update on public.hr_payroll_payment_finance_clearings
 for each row execute function public.hr_guard_payroll_payment_clearing_identity();
