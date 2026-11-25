-- DESIGN DRAFT ONLY — payroll payout Finance clearing and bank evidence.
-- Depends on HR_PAYROLL_FINANCE_SCHEMA_DRAFT.sql and
-- HR_PAYROLL_PAYMENT_ADAPTERS_DRAFT.sql. Not a migration.
--
-- Accounting lifecycle:
-- 1. Provider-confirmed beneficiary credit: Dr payroll payable / Cr payout clearing.
-- 2. Independently imported bank debit: Dr payout clearing / Cr bank cash.
-- 3. Provider reversal: immutable Finance exception; do not rewrite posted journals.
-- Apply only after disposable replay, source/account compatibility review,
-- pgTAP, RLS/ACL checks, and separate staging approval.

create table if not exists public.hr_payroll_payment_finance_mappings (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 provider_config_id uuid not null,
 payroll_payable_account text not null check(length(btrim(payroll_payable_account)) between 1 and 80),
 payout_clearing_account text not null check(length(btrim(payout_clearing_account)) between 1 and 80),
 bank_cash_account text not null check(length(btrim(bank_cash_account)) between 1 and 80),
 bank_account_fingerprint_sha256 text not null check(bank_account_fingerprint_sha256 ~ '^[0-9a-f]{64}$'),
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

create unique index if not exists hr_payroll_one_statement_line_per_clearing_uq
 on public.hr_payroll_payment_finance_clearings(tenant_id,bank_statement_line_id)
 where bank_statement_line_id is not null;
create index if not exists hr_payroll_payment_clearing_status_idx
 on public.hr_payroll_payment_finance_clearings(tenant_id,status,created_at);
create index if not exists hr_payroll_bank_statement_unmatched_idx
 on public.hr_payroll_bank_statement_lines(tenant_id,branch_id,provider_payout_reference);

create table if not exists public.hr_payroll_payment_bank_reconciliations (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 payment_batch_id uuid not null,
 expected_amount_idr bigint not null check(expected_amount_idr>0),
 provider_cleared_amount_idr bigint not null check(provider_cleared_amount_idr>=0),
 bank_matched_amount_idr bigint not null check(bank_matched_amount_idr>=0),
 item_count integer not null check(item_count>0),
 statement_line_ids uuid[] not null,
 evidence_sha256 text not null check(evidence_sha256 ~ '^[0-9a-f]{64}$'),
 reconciled_by uuid not null references auth.users(id) on delete restrict,
 reconciled_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,payment_batch_id),
 foreign key(tenant_id,payment_batch_id) references public.hr_payroll_payment_batches(tenant_id,id) on delete restrict,
 check(expected_amount_idr=provider_cleared_amount_idr and expected_amount_idr=bank_matched_amount_idr),
 check(cardinality(statement_line_ids)=item_count)
);

create table if not exists public.hr_payroll_payment_reversal_exceptions (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 payment_item_id uuid not null,
 provider_event_id uuid not null,
 clearing_id uuid null,
 reason_code text not null check(reason_code in ('provider_reversal_after_bank_match','provider_reversal_before_bank_match')),
 payload_sha256 text not null check(payload_sha256 ~ '^[0-9a-f]{64}$'),
 recorded_by uuid not null references auth.users(id) on delete restrict,
 recorded_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,provider_event_id),
 foreign key(tenant_id,payment_item_id) references public.hr_payroll_payment_items(tenant_id,id) on delete restrict,
 foreign key(tenant_id,provider_event_id) references public.hr_payroll_provider_events(tenant_id,id) on delete restrict,
 foreign key(tenant_id,clearing_id) references public.hr_payroll_payment_finance_clearings(tenant_id,id) on delete restrict
);

create or replace function public.hr_approve_payroll_payment_finance_mapping(
 p_tenant_id uuid,p_mapping_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_payroll_payment_finance_mappings%rowtype;
begin
 select * into v from public.hr_payroll_payment_finance_mappings
  where tenant_id=p_tenant_id and id=p_mapping_id for update;
 if not found or v.status<>'pending' then
  raise exception using errcode='23514',message='PENDING_PAYROLL_PAYMENT_FINANCE_MAPPING_REQUIRED';
 end if;
 if p_actor_user_id in (v.created_by,
  (select created_by from public.hr_payroll_payment_provider_configs where tenant_id=p_tenant_id and id=v.provider_config_id),
  (select approved_by from public.hr_payroll_payment_provider_configs where tenant_id=p_tenant_id and id=v.provider_config_id)) then
  raise exception using errcode='42501',message='INDEPENDENT_PAYMENT_FINANCE_MAPPING_APPROVER_REQUIRED';
 end if;
 update public.hr_payroll_payment_finance_mappings
  set status='approved',approved_by=p_actor_user_id,approved_at=now(),updated_at=now()
  where id=v.id returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.payment_finance_mapping_approved',
  'hr_payroll_payment_finance_mappings',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',v.branch_id,
   'provider_config_id',v.provider_config_id,'payout_clearing_account',v.payout_clearing_account,
   'bank_cash_account',v.bank_cash_account,'bank_account_fingerprint_sha256',v.bank_account_fingerprint_sha256));
 return jsonb_build_object('mapping_id',v.id,'status',v.status);
end $$;
revoke all on function public.hr_approve_payroll_payment_finance_mapping(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_approve_payroll_payment_finance_mapping(uuid,uuid,uuid) to service_role;

create or replace function public.hr_post_payroll_payment_finance_clearing(
 p_tenant_id uuid,p_payment_batch_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare
 b public.hr_payroll_payment_batches%rowtype;
 f public.hr_payroll_finance_postings%rowtype;
 m public.hr_payroll_payment_finance_mappings%rowtype;
 i record;
 e public.hr_payroll_provider_events%rowtype;
 v_entry uuid;
 v_period uuid;
 v_code text;
 v_new integer:=0;
begin
 select * into b from public.hr_payroll_payment_batches
  where tenant_id=p_tenant_id and id=p_payment_batch_id for update;
 if not found or b.status<>'reconciled' then
  raise exception using errcode='23514',message='RECONCILED_PROVIDER_PAYROLL_BATCH_REQUIRED';
 end if;
 select * into f from public.hr_payroll_finance_postings
  where tenant_id=p_tenant_id and id=b.finance_posting_id and status='reconciled' for share;
 if not found or f.net_amount_idr<>b.amount_idr then
  raise exception using errcode='23514',message='RECONCILED_PAYROLL_FINANCE_POSTING_REQUIRED';
 end if;
 select * into m from public.hr_payroll_payment_finance_mappings
  where tenant_id=p_tenant_id and branch_id=b.branch_id
   and provider_config_id=b.provider_config_id and status='approved' for share;
 if not found then raise exception using errcode='23514',message='APPROVED_PAYROLL_PAYMENT_FINANCE_MAPPING_REQUIRED'; end if;
 if p_actor_user_id in (b.created_by,b.approved_by,b.reconciled_by,
  f.created_by,f.posted_by,f.reconciled_by,m.created_by,m.approved_by,
  (select created_by from public.hr_payroll_payment_provider_configs where tenant_id=p_tenant_id and id=b.provider_config_id),
  (select approved_by from public.hr_payroll_payment_provider_configs where tenant_id=p_tenant_id and id=b.provider_config_id)) then
  raise exception using errcode='42501',message='INDEPENDENT_FINANCE_CLEARING_POSTER_REQUIRED';
 end if;
 for i in select * from public.hr_payroll_payment_items
  where tenant_id=p_tenant_id and payment_batch_id=b.id order by id for update
 loop
  if i.status<>'settled' or i.provider_reference is null then
   raise exception using errcode='23514',message='EVERY_PAYROLL_PAYMENT_ITEM_MUST_BE_PROVIDER_SETTLED';
  end if;
  if exists(select 1 from public.hr_payroll_payment_finance_clearings c
    where c.tenant_id=p_tenant_id and c.payment_item_id=i.id) then
   continue;
  end if;
  select * into e from public.hr_payroll_provider_events
   where tenant_id=p_tenant_id and payment_batch_id=b.id and payment_item_id=i.id
    and event_kind='settled' and provider_reference=i.provider_reference
    and signature_verified=true and amount_idr=i.amount_idr
   order by occurred_at desc,received_at desc limit 1;
  if not found then raise exception using errcode='23514',message='AUTHENTICATED_SETTLEMENT_EVENT_REQUIRED_FOR_CLEARING'; end if;
  select id into v_period from public.fiscal_periods
   where status='open' and starts_on<=(e.occurred_at at time zone 'UTC')::date
    and ends_on>=(e.occurred_at at time zone 'UTC')::date
   order by starts_on desc limit 1 for share;
  if v_period is null then raise exception using errcode='23514',message='OPEN_PAYOUT_FISCAL_PERIOD_REQUIRED'; end if;
  v_code:='PCL-'||replace(b.id::text,'-','')||'-'||replace(i.id::text,'-','');
  insert into public.finance_journal_entries(
   entry_code,fiscal_period_id,branch_id,source_type,source_id,entry_date,
   debit_account,credit_account,amount_idr,description,status,created_by
  ) values(v_code,v_period,b.branch_id,'hr_payroll_payment_clearing',i.id,
   (e.occurred_at at time zone 'UTC')::date,m.payroll_payable_account,
   m.payout_clearing_account,i.amount_idr,'Payroll payout clearing '||i.id::text,
   'posted',p_actor_user_id) returning id into v_entry;
  insert into public.hr_payroll_payment_finance_clearings(
   tenant_id,payment_batch_id,payment_item_id,provider_event_id,mapping_id,
   payout_provider_reference,amount_idr,payout_journal_entry_id,created_by
  ) values(p_tenant_id,b.id,i.id,e.id,m.id,i.provider_reference,i.amount_idr,v_entry,p_actor_user_id);
  v_new:=v_new+1;
 end loop;
 if (select count(*) from public.hr_payroll_payment_finance_clearings where tenant_id=p_tenant_id and payment_batch_id=b.id)<>b.item_count
  or (select coalesce(sum(amount_idr),0) from public.hr_payroll_payment_finance_clearings where tenant_id=p_tenant_id and payment_batch_id=b.id)<>b.amount_idr then
  raise exception using errcode='23514',message='PAYROLL_FINANCE_CLEARING_TOTAL_MISMATCH';
 end if;
 if v_new=0 then
  return jsonb_build_object('status','duplicate','payment_batch_id',b.id,'amount_idr',b.amount_idr,'item_count',b.item_count);
 end if;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.payment_finance_clearing_posted','hr_payroll_payment_batches',b.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'amount_idr',b.amount_idr,'new_clearing_rows',v_new,'item_count',b.item_count));
 return jsonb_build_object('status','provider_cleared','payment_batch_id',b.id,
  'amount_idr',b.amount_idr,'item_count',b.item_count,'new_clearing_rows',v_new);
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
  or p_amount_idr is null or p_amount_idr<=0
  or length(btrim(coalesce(p_statement_reference,'')))=0
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
 values(p_actor_user_id,'hr.payroll.bank_statement_line_imported','hr_payroll_bank_statement_lines',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,
   'provider_payout_reference',p_provider_payout_reference,'amount_idr',p_amount_idr,'line_sha256',p_line_sha256));
 return jsonb_build_object('status','imported','statement_line_id',v.id);
end $$;
revoke all on function public.hr_import_payroll_bank_statement_line(uuid,uuid,text,text,text,bigint,timestamptz,text,text,uuid) from public,anon,authenticated;
grant execute on function public.hr_import_payroll_bank_statement_line(uuid,uuid,text,text,text,bigint,timestamptz,text,text,uuid) to service_role;

create or replace function public.hr_match_payroll_payment_bank_statement(
 p_tenant_id uuid,p_clearing_id uuid,p_statement_line_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare
 c public.hr_payroll_payment_finance_clearings%rowtype;
 s public.hr_payroll_bank_statement_lines%rowtype;
 m public.hr_payroll_payment_finance_mappings%rowtype;
 b public.hr_payroll_payment_batches%rowtype;
 v_period uuid;
 v_entry uuid;
begin
 select * into c from public.hr_payroll_payment_finance_clearings
  where tenant_id=p_tenant_id and id=p_clearing_id for update;
 if not found then raise exception using errcode='23503',message='PAYROLL_PAYMENT_CLEARING_NOT_FOUND'; end if;
 if c.status='bank_matched' then
  if c.bank_statement_line_id=p_statement_line_id then
   return jsonb_build_object('status','duplicate','clearing_id',c.id,
    'statement_line_id',c.bank_statement_line_id,'bank_journal_entry_id',c.bank_journal_entry_id,'amount_idr',c.amount_idr);
  end if;
  raise exception using errcode='23505',message='PAYROLL_CLEARING_ALREADY_MATCHED_TO_ANOTHER_STATEMENT_LINE';
 end if;
 if c.status<>'provider_cleared' then raise exception using errcode='23514',message='UNMATCHED_PROVIDER_CLEARING_REQUIRED'; end if;
 select * into s from public.hr_payroll_bank_statement_lines
  where tenant_id=p_tenant_id and id=p_statement_line_id for update;
 if not found then raise exception using errcode='23503',message='BANK_STATEMENT_LINE_NOT_FOUND'; end if;
 select * into b from public.hr_payroll_payment_batches where tenant_id=p_tenant_id and id=c.payment_batch_id for share;
 select * into m from public.hr_payroll_payment_finance_mappings where tenant_id=p_tenant_id and id=c.mapping_id for share;
 if s.branch_id<>b.branch_id or s.provider_payout_reference<>c.payout_provider_reference
  or s.amount_idr<>c.amount_idr or s.currency<>'IDR'
  or s.bank_account_fingerprint_sha256<>m.bank_account_fingerprint_sha256 then
  raise exception using errcode='23514',message='BANK_STATEMENT_PAYOUT_MATCH_MISMATCH';
 end if;
 if exists(select 1 from public.hr_payroll_payment_finance_clearings
  where tenant_id=p_tenant_id and bank_statement_line_id=s.id) then
  raise exception using errcode='23505',message='BANK_STATEMENT_LINE_ALREADY_MATCHED';
 end if;
 if p_actor_user_id in (c.created_by,b.created_by,b.approved_by,b.reconciled_by,s.imported_by,m.created_by,m.approved_by) then
  raise exception using errcode='42501',message='INDEPENDENT_BANK_STATEMENT_RECONCILER_REQUIRED';
 end if;
 select id into v_period from public.fiscal_periods
  where status='open' and starts_on<=(s.booked_at at time zone 'UTC')::date
   and ends_on>=(s.booked_at at time zone 'UTC')::date
  order by starts_on desc limit 1 for share;
 if v_period is null then raise exception using errcode='23514',message='OPEN_BANK_STATEMENT_FISCAL_PERIOD_REQUIRED'; end if;
 insert into public.finance_journal_entries(
  entry_code,fiscal_period_id,branch_id,source_type,source_id,entry_date,
  debit_account,credit_account,amount_idr,description,status,created_by
 ) values('PBM-'||replace(c.id::text,'-',''),v_period,b.branch_id,
  'hr_payroll_bank_statement',s.id,(s.booked_at at time zone 'UTC')::date,
  m.payout_clearing_account,m.bank_cash_account,s.amount_idr,
  'Payroll bank statement payout match '||s.id::text,'posted',p_actor_user_id)
 returning id into v_entry;
 update public.hr_payroll_payment_finance_clearings set status='bank_matched',
  bank_statement_line_id=s.id,bank_journal_entry_id=v_entry,
  bank_matched_by=p_actor_user_id,bank_matched_at=now()
  where id=c.id returning * into c;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.payment_bank_statement_matched',
  'hr_payroll_payment_finance_clearings',c.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'statement_line_id',s.id,'bank_journal_entry_id',v_entry,'amount_idr',c.amount_idr));
 return jsonb_build_object('status','bank_matched','clearing_id',c.id,
  'statement_line_id',s.id,'bank_journal_entry_id',v_entry,'amount_idr',c.amount_idr);
end $$;
revoke all on function public.hr_match_payroll_payment_bank_statement(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_match_payroll_payment_bank_statement(uuid,uuid,uuid,uuid) to service_role;

create or replace function public.hr_reconcile_payroll_payment_bank_batch(
 p_tenant_id uuid,p_payment_batch_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare
 b public.hr_payroll_payment_batches%rowtype;
 n integer;
 provider_total bigint;
 bank_total bigint;
 line_ids uuid[];
 evidence jsonb;
 digest text;
 saved public.hr_payroll_payment_bank_reconciliations%rowtype;
begin
 select * into b from public.hr_payroll_payment_batches
  where tenant_id=p_tenant_id and id=p_payment_batch_id for update;
 if not found or b.status<>'reconciled' then
  raise exception using errcode='23514',message='RECONCILED_PAYROLL_PROVIDER_BATCH_REQUIRED';
 end if;
 if p_actor_user_id in (b.created_by,b.approved_by,b.reconciled_by) then
  raise exception using errcode='42501',message='INDEPENDENT_BANK_BATCH_RECONCILER_REQUIRED';
 end if;
 select count(*),coalesce(sum(amount_idr),0),
  coalesce(sum(case when status='bank_matched' then amount_idr else 0 end),0),
  coalesce(array_agg(bank_statement_line_id order by payment_item_id) filter(where bank_statement_line_id is not null),'{}'::uuid[])
 into n,provider_total,bank_total,line_ids
 from public.hr_payroll_payment_finance_clearings
 where tenant_id=p_tenant_id and payment_batch_id=b.id;
 if p_actor_user_id in (
  select c.bank_matched_by from public.hr_payroll_payment_finance_clearings c
   where c.tenant_id=p_tenant_id and c.payment_batch_id=b.id
  union
  select s.imported_by from public.hr_payroll_payment_finance_clearings c
   join public.hr_payroll_bank_statement_lines s on s.tenant_id=c.tenant_id and s.id=c.bank_statement_line_id
   where c.tenant_id=p_tenant_id and c.payment_batch_id=b.id
 ) then raise exception using errcode='42501',message='INDEPENDENT_BANK_BATCH_RECONCILER_REQUIRED'; end if;
 if n<>b.item_count or provider_total<>b.amount_idr or bank_total<>b.amount_idr
  or cardinality(line_ids)<>b.item_count
  or exists(select 1 from public.hr_payroll_payment_finance_clearings
   where tenant_id=p_tenant_id and payment_batch_id=b.id and status<>'bank_matched') then
  raise exception using errcode='23514',message='PAYROLL_PROVIDER_CLEARING_NOT_FULLY_BANK_MATCHED';
 end if;
 if exists(
  select 1 from public.hr_payroll_payment_finance_clearings c
  join public.hr_payroll_payment_finance_mappings m on m.tenant_id=c.tenant_id and m.id=c.mapping_id
  left join public.finance_journal_entries p on p.id=c.payout_journal_entry_id
  left join public.finance_journal_entries bank on bank.id=c.bank_journal_entry_id
  where c.tenant_id=p_tenant_id and c.payment_batch_id=b.id
   and (p.id is null or p.status<>'posted' or p.source_type<>'hr_payroll_payment_clearing'
    or p.source_id<>c.payment_item_id or p.amount_idr<>c.amount_idr
    or p.debit_account<>m.payroll_payable_account or p.credit_account<>m.payout_clearing_account
    or bank.id is null or bank.status<>'posted' or bank.source_type<>'hr_payroll_bank_statement'
    or bank.source_id<>c.bank_statement_line_id or bank.amount_idr<>c.amount_idr
    or bank.debit_account<>m.payout_clearing_account or bank.credit_account<>m.bank_cash_account)
 ) then raise exception using errcode='23514',message='PAYROLL_CLEARING_JOURNAL_EVIDENCE_MISMATCH'; end if;
 select * into saved from public.hr_payroll_payment_bank_reconciliations
  where tenant_id=p_tenant_id and payment_batch_id=b.id;
 if found then
  return jsonb_build_object('status','duplicate','reconciliation_id',saved.id,
   'amount_idr',saved.expected_amount_idr,'evidence_sha256',saved.evidence_sha256);
 end if;
 select jsonb_build_object('tenant_id',p_tenant_id,'payment_batch_id',b.id,'amount_idr',b.amount_idr,
  'clearings',coalesce(jsonb_agg(jsonb_build_object('clearing_id',c.id,'payment_item_id',c.payment_item_id,
   'provider_reference',c.payout_provider_reference,'amount_idr',c.amount_idr,
   'payout_journal_entry_id',c.payout_journal_entry_id,'bank_statement_line_id',c.bank_statement_line_id,
   'bank_journal_entry_id',c.bank_journal_entry_id) order by c.payment_item_id),'[]'::jsonb))
 into evidence from public.hr_payroll_payment_finance_clearings c
 where c.tenant_id=p_tenant_id and c.payment_batch_id=b.id;
 digest:=encode(pg_catalog.sha256(convert_to(evidence::text,'UTF8')),'hex');
 insert into public.hr_payroll_payment_bank_reconciliations(
  tenant_id,payment_batch_id,expected_amount_idr,provider_cleared_amount_idr,
  bank_matched_amount_idr,item_count,statement_line_ids,evidence_sha256,reconciled_by
 ) values(p_tenant_id,b.id,b.amount_idr,provider_total,bank_total,n,line_ids,digest,p_actor_user_id)
 returning * into saved;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.payment_bank_batch_reconciled',
  'hr_payroll_payment_bank_reconciliations',saved.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'payment_batch_id',b.id,'amount_idr',b.amount_idr,
   'item_count',n,'evidence_sha256',digest));
 return jsonb_build_object('status','bank_reconciled','reconciliation_id',saved.id,
  'payment_batch_id',b.id,'amount_idr',b.amount_idr,'item_count',n,'evidence_sha256',digest);
end $$;
revoke all on function public.hr_reconcile_payroll_payment_bank_batch(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_reconcile_payroll_payment_bank_batch(uuid,uuid,uuid) to service_role;

create or replace function public.hr_mark_payroll_payment_reversal_exception(
 p_tenant_id uuid,p_payment_item_id uuid,p_provider_event_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare
 i public.hr_payroll_payment_items%rowtype;
 e public.hr_payroll_provider_events%rowtype;
 b public.hr_payroll_payment_batches%rowtype;
 c public.hr_payroll_payment_finance_clearings%rowtype;
 x public.hr_payroll_payment_reversal_exceptions%rowtype;
 reason text;
begin
 select * into i from public.hr_payroll_payment_items
  where tenant_id=p_tenant_id and id=p_payment_item_id for update;
 if not found then raise exception using errcode='23503',message='PAYROLL_PAYMENT_ITEM_NOT_FOUND'; end if;
 select * into e from public.hr_payroll_provider_events
  where tenant_id=p_tenant_id and id=p_provider_event_id and payment_item_id=i.id
   and event_kind='reversed' and signature_verified=true;
 if not found then raise exception using errcode='23514',message='AUTHENTICATED_PROVIDER_REVERSAL_REQUIRED'; end if;
 select * into b from public.hr_payroll_payment_batches
  where tenant_id=p_tenant_id and id=i.payment_batch_id for share;
 if p_actor_user_id in (b.created_by,b.approved_by,b.reconciled_by) then
  raise exception using errcode='42501',message='INDEPENDENT_REVERSAL_EXCEPTION_REVIEWER_REQUIRED';
 end if;
 select * into c from public.hr_payroll_payment_finance_clearings
  where tenant_id=p_tenant_id and payment_item_id=i.id for update;
 if found and c.status='bank_matched' then
  reason:='provider_reversal_after_bank_match';
 else
  reason:='provider_reversal_before_bank_match';
  if found then update public.hr_payroll_payment_finance_clearings
   set status='reversal_exception' where id=c.id returning * into c; end if;
 end if;
 insert into public.hr_payroll_payment_reversal_exceptions(
  tenant_id,payment_item_id,provider_event_id,clearing_id,reason_code,payload_sha256,recorded_by
 ) values(p_tenant_id,i.id,e.id,c.id,reason,e.payload_sha256,p_actor_user_id)
 on conflict(tenant_id,provider_event_id) do nothing returning * into x;
 if not found then
  select * into x from public.hr_payroll_payment_reversal_exceptions
   where tenant_id=p_tenant_id and provider_event_id=e.id;
  if x.payload_sha256<>e.payload_sha256 or x.payment_item_id<>i.id then
   raise exception using errcode='23505',message='PAYROLL_PROVIDER_REVERSAL_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','exception_id',x.id,'payment_item_id',i.id,
   'clearing_id',c.id,'bank_return_evidence_required',true);
 end if;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.payment_reversal_quarantined',
  'hr_payroll_payment_reversal_exceptions',x.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'provider_event_id',e.id,
   'clearing_id',c.id,'reason_code',reason,'bank_return_evidence_required',true));
 return jsonb_build_object('status','reversal_exception','exception_id',x.id,
  'payment_item_id',i.id,'clearing_id',c.id,'reason_code',reason,'bank_return_evidence_required',true);
end $$;
revoke all on function public.hr_mark_payroll_payment_reversal_exception(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_mark_payroll_payment_reversal_exception(uuid,uuid,uuid,uuid) to service_role;

do $$
declare t text;
begin
 foreach t in array array[
  'hr_payroll_payment_finance_mappings','hr_payroll_payment_finance_clearings',
  'hr_payroll_bank_statement_lines','hr_payroll_payment_bank_reconciliations',
  'hr_payroll_payment_reversal_exceptions'
 ] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists service_role_only on public.%I',t);
  execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant select,insert,update,delete on public.%I to service_role',t);
 end loop;
end $$;

create or replace function public.hr_reject_payroll_bank_statement_mutation()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
 raise exception using errcode='55000',message='PAYROLL_BANK_STATEMENT_LINES_APPEND_ONLY';
end $$;
revoke all on function public.hr_reject_payroll_bank_statement_mutation() from public,anon,authenticated;
drop trigger if exists hr_payroll_bank_statement_lines_append_only on public.hr_payroll_bank_statement_lines;
create trigger hr_payroll_bank_statement_lines_append_only
 before update or delete on public.hr_payroll_bank_statement_lines
 for each row execute function public.hr_reject_payroll_bank_statement_mutation();

-- Immutable imported bank evidence and reconciliation outcomes.
create or replace function public.hr_reject_payroll_finance_immutable_mutation()
returns trigger language plpgsql security invoker set search_path=''
as $
begin
 raise exception using errcode='55000',message='PAYROLL_FINANCE_EVIDENCE_IS_APPEND_ONLY';
end $;
revoke all on function public.hr_reject_payroll_finance_immutable_mutation() from public,anon,authenticated;
drop trigger if exists hr_payroll_bank_reconciliation_append_only on public.hr_payroll_payment_bank_reconciliations;
create trigger hr_payroll_bank_reconciliation_append_only
 before update or delete on public.hr_payroll_payment_bank_reconciliations
 for each row execute function public.hr_reject_payroll_finance_immutable_mutation();
drop trigger if exists hr_payroll_reversal_exception_append_only on public.hr_payroll_payment_reversal_exceptions;
create trigger hr_payroll_reversal_exception_append_only
 before update or delete on public.hr_payroll_payment_reversal_exceptions
 for each row execute function public.hr_reject_payroll_finance_immutable_mutation();

revoke update,delete on public.hr_payroll_bank_statement_lines from service_role;
revoke update,delete on public.hr_payroll_payment_bank_reconciliations from service_role;
revoke update,delete on public.hr_payroll_payment_reversal_exceptions from service_role;
grant select,insert on public.hr_payroll_bank_statement_lines to service_role;
grant select,insert on public.hr_payroll_payment_bank_reconciliations to service_role;
grant select,insert on public.hr_payroll_payment_reversal_exceptions to service_role;

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
