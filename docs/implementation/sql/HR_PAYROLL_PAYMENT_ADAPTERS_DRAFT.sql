-- DESIGN DRAFT ONLY — provider-neutral payroll payment lifecycle.
-- Apply after HR_WORKFORCE_SCHEMA_DRAFT.sql and
-- HR_PAYROLL_FINANCE_SCHEMA_DRAFT.sql. No provider is assumed or enabled.
--
-- Canonical source: hr_payroll_runs + hr_payroll_lines.
-- Payment is allowed only after the run AND its Finance posting are reconciled.
-- Beneficiary details never enter these tables: only a secret reference and
-- SHA-256 fingerprint are persisted. Provider events are accepted only after
-- the Edge adapter verifies the provider's exact signature over raw bytes.

create table if not exists public.hr_payroll_payment_provider_configs (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 provider_id text not null check(length(btrim(provider_id)) between 2 and 100),
 credential_secret_reference text not null check(credential_secret_reference ~ '^[A-Z][A-Z0-9_]{2,119}$'),
 status text not null default 'pending' check(status in ('pending','active','suspended','revoked')),
 created_by uuid not null references auth.users(id) on delete restrict,
 approved_by uuid null references auth.users(id) on delete restrict,
 approved_at timestamptz null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,provider_id),
 check(status<>'active' or (approved_by is not null and approved_at is not null and approved_by<>created_by))
);

create table if not exists public.hr_payroll_beneficiary_profiles (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 employee_user_id uuid not null references auth.users(id) on delete restrict,
 beneficiary_secret_reference text not null check(beneficiary_secret_reference ~ '^[A-Z][A-Z0-9_]{2,119}$'),
 beneficiary_fingerprint_sha256 text not null check(beneficiary_fingerprint_sha256 ~ '^[0-9a-f]{64}$'),
 currency text not null default 'IDR' check(currency='IDR'),
 status text not null default 'pending' check(status in ('pending','active','suspended','revoked')),
 created_by uuid not null references auth.users(id) on delete restrict,
 approved_by uuid null references auth.users(id) on delete restrict,
 approved_at timestamptz null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,id),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 check(status<>'active' or (approved_by is not null and approved_at is not null and approved_by<>created_by))
);
create unique index if not exists hr_payroll_one_active_beneficiary_per_employee_uq
 on public.hr_payroll_beneficiary_profiles(tenant_id,branch_id,employee_user_id)
 where status='active';

create table if not exists public.hr_payroll_payment_batches (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 payroll_run_id uuid not null,
 finance_posting_id uuid not null,
 provider_config_id uuid not null,
 status text not null default 'draft' check(status in ('draft','approved','processing','reconciled','exception','cancelled')),
 amount_idr bigint not null check(amount_idr>0),
 item_count integer not null check(item_count>0),
 idempotency_key text not null check(length(idempotency_key) between 8 and 160),
 created_by uuid not null references auth.users(id) on delete restrict,
 approved_by uuid null references auth.users(id) on delete restrict,
 approved_at timestamptz null,
 reconciled_by uuid null references auth.users(id) on delete restrict,
 reconciled_at timestamptz null,
 reconciliation_sha256 text null check(reconciliation_sha256 is null or reconciliation_sha256 ~ '^[0-9a-f]{64}$'),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,payroll_run_id),
 unique(tenant_id,idempotency_key),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 foreign key(tenant_id,payroll_run_id) references public.hr_payroll_runs(tenant_id,id) on delete restrict,
 foreign key(tenant_id,finance_posting_id) references public.hr_payroll_finance_postings(tenant_id,id) on delete restrict,
 foreign key(tenant_id,provider_config_id) references public.hr_payroll_payment_provider_configs(tenant_id,id) on delete restrict,
 check((status in ('approved','processing','reconciled') and approved_by is not null and approved_at is not null and approved_by<>created_by) or status not in ('approved','processing','reconciled')),
 check((status='reconciled' and reconciled_by is not null and reconciled_at is not null and reconciliation_sha256 is not null) or status<>'reconciled')
);

create table if not exists public.hr_payroll_payment_items (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 payment_batch_id uuid not null,
 payroll_line_id uuid not null,
 beneficiary_profile_id uuid not null,
 beneficiary_fingerprint_sha256 text not null check(beneficiary_fingerprint_sha256 ~ '^[0-9a-f]{64}$'),
 amount_idr bigint not null check(amount_idr>0),
 status text not null default 'pending' check(status in ('pending','accepted','settled','failed','reversed')),
 provider_reference text null,
 settled_at timestamptz null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,payment_batch_id,payroll_line_id),
 foreign key(tenant_id,payment_batch_id) references public.hr_payroll_payment_batches(tenant_id,id) on delete restrict,
 foreign key(tenant_id,payroll_line_id) references public.hr_payroll_lines(tenant_id,id) on delete restrict,
 foreign key(tenant_id,beneficiary_profile_id) references public.hr_payroll_beneficiary_profiles(tenant_id,id) on delete restrict,
 check((status='settled' and settled_at is not null and provider_reference is not null) or status<>'settled')
);

create table if not exists public.hr_payroll_provider_events (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 payment_batch_id uuid not null,
 payment_item_id uuid not null,
 provider_config_id uuid not null,
 provider_event_id text not null check(length(btrim(provider_event_id)) between 1 and 180),
 event_kind text not null check(event_kind in ('accepted','settled','failed','reversed')),
 amount_idr bigint not null check(amount_idr>0),
 provider_reference text null,
 payload_sha256 text not null check(payload_sha256 ~ '^[0-9a-f]{64}$'),
 signature_verified boolean not null check(signature_verified=true),
 occurred_at timestamptz not null,
 received_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(provider_config_id,provider_event_id),
 foreign key(tenant_id,payment_batch_id) references public.hr_payroll_payment_batches(tenant_id,id) on delete restrict,
 foreign key(tenant_id,payment_item_id) references public.hr_payroll_payment_items(tenant_id,id) on delete restrict,
 foreign key(tenant_id,provider_config_id) references public.hr_payroll_payment_provider_configs(tenant_id,id) on delete restrict
);

create table if not exists public.hr_payroll_payment_reconciliations (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 payment_batch_id uuid not null,
 expected_amount_idr bigint not null check(expected_amount_idr>0),
 settled_amount_idr bigint not null check(settled_amount_idr>=0),
 item_count integer not null check(item_count>0),
 event_ids uuid[] not null default '{}',
 evidence_sha256 text not null check(evidence_sha256 ~ '^[0-9a-f]{64}$'),
 status text not null check(status in ('reconciled','exception')),
 reconciled_by uuid not null references auth.users(id) on delete restrict,
 reconciled_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,payment_batch_id),
 foreign key(tenant_id,payment_batch_id) references public.hr_payroll_payment_batches(tenant_id,id) on delete restrict,
 check(status<>'reconciled' or (expected_amount_idr=settled_amount_idr and cardinality(event_ids)>0))
);

create or replace function public.hr_approve_payroll_payment_provider(
 p_tenant_id uuid,p_provider_config_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_payroll_payment_provider_configs%rowtype;
begin
 select * into v from public.hr_payroll_payment_provider_configs
  where tenant_id=p_tenant_id and id=p_provider_config_id for update;
 if not found or v.status<>'pending' then raise exception using errcode='23514',message='PENDING_PAYROLL_PROVIDER_CONFIG_REQUIRED'; end if;
 if v.created_by=p_actor_user_id then raise exception using errcode='42501',message='INDEPENDENT_PAYROLL_PROVIDER_APPROVER_REQUIRED'; end if;
 update public.hr_payroll_payment_provider_configs set status='active',approved_by=p_actor_user_id,approved_at=now(),updated_at=now()
  where id=v.id returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.payment_provider_approved','hr_payroll_payment_provider_configs',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'provider_id',v.provider_id,'secret_reference',v.credential_secret_reference));
 return jsonb_build_object('provider_config_id',v.id,'status',v.status);
end $$;
revoke all on function public.hr_approve_payroll_payment_provider(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_approve_payroll_payment_provider(uuid,uuid,uuid) to service_role;

create or replace function public.hr_approve_payroll_beneficiary_profile(
 p_tenant_id uuid,p_profile_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_payroll_beneficiary_profiles%rowtype;
begin
 select * into v from public.hr_payroll_beneficiary_profiles where tenant_id=p_tenant_id and id=p_profile_id for update;
 if not found or v.status<>'pending' then raise exception using errcode='23514',message='PENDING_PAYROLL_BENEFICIARY_REQUIRED'; end if;
 if p_actor_user_id in (v.created_by,v.employee_user_id) then raise exception using errcode='42501',message='INDEPENDENT_BENEFICIARY_APPROVER_REQUIRED'; end if;
 update public.hr_payroll_beneficiary_profiles set status='active',approved_by=p_actor_user_id,approved_at=now(),updated_at=now()
  where id=v.id returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.beneficiary_approved','hr_payroll_beneficiary_profiles',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',v.branch_id,'employee_user_id',v.employee_user_id,
   'beneficiary_fingerprint_sha256',v.beneficiary_fingerprint_sha256));
 return jsonb_build_object('profile_id',v.id,'status',v.status);
end $$;
revoke all on function public.hr_approve_payroll_beneficiary_profile(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_approve_payroll_beneficiary_profile(uuid,uuid,uuid) to service_role;

-- Build the payment batch exclusively from persisted payroll lines and active,
-- independently approved beneficiary profiles. No amounts or account numbers
-- are accepted from the caller.
create or replace function public.hr_prepare_payroll_payment_batch(
 p_tenant_id uuid,p_branch_id uuid,p_payroll_run_id uuid,p_provider_config_id uuid,
 p_idempotency_key text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare
 v_run public.hr_payroll_runs%rowtype;
 v_post public.hr_payroll_finance_postings%rowtype;
 v_provider public.hr_payroll_payment_provider_configs%rowtype;
 v_batch public.hr_payroll_payment_batches%rowtype;
 v_count integer; v_amount bigint;
begin
 if length(coalesce(p_idempotency_key,'')) not between 8 and 160 then
  raise exception using errcode='22023',message='INVALID_PAYROLL_PAYMENT_IDEMPOTENCY_KEY';
 end if;
 select * into v_run from public.hr_payroll_runs
  where tenant_id=p_tenant_id and branch_id=p_branch_id and id=p_payroll_run_id for update;
 if not found or v_run.status<>'reconciled' or v_run.finance_journal_id is null then
  raise exception using errcode='23514',message='RECONCILED_PAYROLL_RUN_REQUIRED';
 end if;
 select * into v_post from public.hr_payroll_finance_postings
  where tenant_id=p_tenant_id and id=v_run.finance_journal_id and payroll_run_id=v_run.id
   and status='reconciled' for share;
 if not found or v_post.gross_amount_idr<>v_run.gross_amount_idr
   or v_post.deductions_amount_idr<>v_run.deductions_amount_idr
   or v_post.net_amount_idr<>v_run.net_amount_idr then
  raise exception using errcode='23514',message='RECONCILED_FINANCE_POSTING_REQUIRED';
 end if;
 select * into v_provider from public.hr_payroll_payment_provider_configs
  where tenant_id=p_tenant_id and id=p_provider_config_id and status='active' for share;
 if not found then raise exception using errcode='23514',message='APPROVED_PAYROLL_PAYMENT_PROVIDER_REQUIRED'; end if;
 select count(*) filter(where net_amount_idr>0),coalesce(sum(net_amount_idr),0) into v_count,v_amount
  from public.hr_payroll_lines where tenant_id=p_tenant_id and payroll_run_id=p_payroll_run_id and branch_id=p_branch_id;
 if exists(select 1 from public.hr_payroll_lines where tenant_id=p_tenant_id and payroll_run_id=p_payroll_run_id and branch_id<>p_branch_id) then
  raise exception using errcode='23514',message='PAYROLL_LINE_BRANCH_SCOPE_MISMATCH';
 end if;
 if v_count=0 or v_amount<>v_run.net_amount_idr then
  raise exception using errcode='23514',message='PAYROLL_PAYMENT_LINES_DO_NOT_RECONCILE';
 end if;
 if exists(
  select 1 from public.hr_payroll_lines l
  where l.tenant_id=p_tenant_id and l.payroll_run_id=p_payroll_run_id
   and l.net_amount_idr>0
   and not exists(select 1 from public.hr_payroll_beneficiary_profiles b
    where b.tenant_id=l.tenant_id and b.branch_id=l.branch_id and b.employee_user_id=l.employee_user_id
     and b.status='active' and b.approved_by is not null and b.approved_at is not null)
 ) then raise exception using errcode='23514',message='APPROVED_BENEFICIARY_PROFILE_REQUIRED_FOR_EVERY_PAYROLL_LINE'; end if;
 select * into v_batch from public.hr_payroll_payment_batches
  where tenant_id=p_tenant_id and payroll_run_id=p_payroll_run_id for update;
 if found then
  if v_batch.idempotency_key<>p_idempotency_key or v_batch.provider_config_id<>p_provider_config_id
   or v_batch.amount_idr<>v_amount then
   raise exception using errcode='23505',message='PAYROLL_PAYMENT_BATCH_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status',v_batch.status,'payment_batch_id',v_batch.id,'amount_idr',v_batch.amount_idr);
 end if;
 insert into public.hr_payroll_payment_batches(
  tenant_id,branch_id,payroll_run_id,finance_posting_id,provider_config_id,status,
  amount_idr,item_count,idempotency_key,created_by
 ) values(p_tenant_id,p_branch_id,p_payroll_run_id,v_post.id,v_provider.id,'draft',
  v_amount,v_count,p_idempotency_key,p_actor_user_id) returning * into v_batch;
 insert into public.hr_payroll_payment_items(
  tenant_id,payment_batch_id,payroll_line_id,beneficiary_profile_id,
  beneficiary_fingerprint_sha256,amount_idr
 )
 select p_tenant_id,v_batch.id,l.id,b.id,b.beneficiary_fingerprint_sha256,l.net_amount_idr
 from public.hr_payroll_lines l
 join public.hr_payroll_beneficiary_profiles b
  on b.tenant_id=l.tenant_id and b.branch_id=l.branch_id and b.employee_user_id=l.employee_user_id and b.status='active'
 where l.tenant_id=p_tenant_id and l.payroll_run_id=p_payroll_run_id and l.net_amount_idr>0
 order by l.employee_user_id,l.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.payment_batch_prepared','hr_payroll_payment_batches',v_batch.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'payroll_run_id',p_payroll_run_id,'finance_posting_id',v_post.id,
   'provider_id',v_provider.provider_id,'amount_idr',v_amount,'item_count',v_count));
 return jsonb_build_object('status','draft','payment_batch_id',v_batch.id,'amount_idr',v_amount,'item_count',v_count);
end $$;
revoke all on function public.hr_prepare_payroll_payment_batch(uuid,uuid,uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.hr_prepare_payroll_payment_batch(uuid,uuid,uuid,uuid,text,uuid) to service_role;

create or replace function public.hr_approve_payroll_payment_batch(
 p_tenant_id uuid,p_payment_batch_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_payroll_payment_batches%rowtype; r public.hr_payroll_runs%rowtype; f public.hr_payroll_finance_postings%rowtype;
begin
 select * into v from public.hr_payroll_payment_batches where tenant_id=p_tenant_id and id=p_payment_batch_id for update;
 if not found or v.status<>'draft' then raise exception using errcode='23514',message='PAYROLL_PAYMENT_DRAFT_REQUIRED'; end if;
 select * into r from public.hr_payroll_runs where tenant_id=p_tenant_id and id=v.payroll_run_id for share;
 select * into f from public.hr_payroll_finance_postings where tenant_id=p_tenant_id and id=v.finance_posting_id for share;
 if p_actor_user_id in (v.created_by,r.created_by,r.generated_by,r.submitted_by,r.approved_by,f.created_by,f.posted_by,f.reconciled_by) then
  raise exception using errcode='42501',message='INDEPENDENT_PAYROLL_PAYMENT_APPROVER_REQUIRED';
 end if;
 if exists(select 1 from public.hr_payroll_payment_items i
  join public.hr_payroll_beneficiary_profiles b on b.tenant_id=i.tenant_id and b.id=i.beneficiary_profile_id
  where i.tenant_id=p_tenant_id and i.payment_batch_id=v.id
   and p_actor_user_id in (b.created_by,b.approved_by,b.employee_user_id)) then
  raise exception using errcode='42501',message='PAYMENT_APPROVER_MUST_BE_INDEPENDENT_OF_BENEFICIARY_MAINTENANCE';
 end if;
 update public.hr_payroll_payment_batches set status='approved',approved_by=p_actor_user_id,approved_at=now(),updated_at=now()
  where id=v.id returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.payment_batch_approved','hr_payroll_payment_batches',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'amount_idr',v.amount_idr,'item_count',v.item_count));
 return jsonb_build_object('payment_batch_id',v.id,'status',v.status,'amount_idr',v.amount_idr);
end $$;
revoke all on function public.hr_approve_payroll_payment_batch(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_approve_payroll_payment_batch(uuid,uuid,uuid) to service_role;

-- Invoke only after the provider-specific Edge adapter verifies the raw-body
-- signature. This RPC is service-role-only; a caller cannot self-assert trust
-- through the public API.
create or replace function public.hr_apply_payroll_provider_event(
 p_tenant_id uuid,p_payment_batch_id uuid,p_payment_item_id uuid,
 p_provider_event_id text,p_event_kind text,p_amount_idr bigint,
 p_provider_reference text,p_payload_sha256 text,p_occurred_at timestamptz,
 p_signature_verified boolean,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare
 v_batch public.hr_payroll_payment_batches%rowtype;
 v_item public.hr_payroll_payment_items%rowtype;
 v_event public.hr_payroll_provider_events%rowtype;
begin
 if p_signature_verified is distinct from true or coalesce(p_payload_sha256,'') !~ '^[0-9a-f]{64}$'
  or length(btrim(coalesce(p_provider_event_id,''))) not between 1 and 180
  or p_event_kind not in ('accepted','settled','failed','reversed') then
  raise exception using errcode='42501',message='VERIFIED_PROVIDER_EVENT_REQUIRED';
 end if;
 select * into v_batch from public.hr_payroll_payment_batches
  where tenant_id=p_tenant_id and id=p_payment_batch_id for update;
 if not found or v_batch.status not in ('approved','processing') then
  raise exception using errcode='23514',message='APPROVED_PAYROLL_PAYMENT_BATCH_REQUIRED';
 end if;
 select * into v_item from public.hr_payroll_payment_items
  where tenant_id=p_tenant_id and payment_batch_id=v_batch.id and id=p_payment_item_id for update;
 if not found or p_amount_idr<>v_item.amount_idr then
  raise exception using errcode='23514',message='PAYROLL_PROVIDER_EVENT_ITEM_AMOUNT_MISMATCH';
 end if;
 if not exists(select 1 from public.hr_payroll_payment_provider_configs c
  where c.tenant_id=p_tenant_id and c.id=v_batch.provider_config_id and c.status='active') then
  raise exception using errcode='23514',message='PAYROLL_PROVIDER_CONFIG_NOT_ACTIVE';
 end if;
 select * into v_event from public.hr_payroll_provider_events
  where provider_config_id=v_batch.provider_config_id and provider_event_id=p_provider_event_id for update;
 if found then
  if v_event.payment_item_id<>v_item.id or v_event.payload_sha256<>p_payload_sha256 then
   raise exception using errcode='23505',message='PAYROLL_PROVIDER_EVENT_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','event_id',v_event.id,'payment_item_status',v_item.status);
 end if;
 if p_event_kind='settled' and (v_item.status in ('failed','reversed') or p_provider_reference is null) then
  raise exception using errcode='23514',message='PAYROLL_PAYMENT_ITEM_NOT_SETTLEABLE';
 end if;
 insert into public.hr_payroll_provider_events(
  tenant_id,payment_batch_id,payment_item_id,provider_config_id,provider_event_id,
  event_kind,amount_idr,provider_reference,payload_sha256,signature_verified,occurred_at
 ) values(p_tenant_id,v_batch.id,v_item.id,v_batch.provider_config_id,p_provider_event_id,
  p_event_kind,p_amount_idr,p_provider_reference,p_payload_sha256,true,p_occurred_at)
 returning * into v_event;
 update public.hr_payroll_payment_items set
  status=case p_event_kind when 'accepted' then 'accepted' when 'settled' then 'settled'
    when 'failed' then 'failed' when 'reversed' then 'reversed' end,
  provider_reference=coalesce(p_provider_reference,provider_reference),
  settled_at=case when p_event_kind='settled' then p_occurred_at else settled_at end,
  updated_at=now() where id=v_item.id returning * into v_item;
 update public.hr_payroll_payment_batches set status='processing',updated_at=now() where id=v_batch.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.provider_event_applied','hr_payroll_provider_events',v_event.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'payment_batch_id',v_batch.id,'payment_item_id',v_item.id,
   'event_kind',p_event_kind,'amount_idr',p_amount_idr,'payload_sha256',p_payload_sha256));
 return jsonb_build_object('status','applied','event_id',v_event.id,'payment_item_status',v_item.status);
end $$;
revoke all on function public.hr_apply_payroll_provider_event(uuid,uuid,uuid,text,text,bigint,text,text,timestamptz,boolean,uuid) from public,anon,authenticated;
grant execute on function public.hr_apply_payroll_provider_event(uuid,uuid,uuid,text,text,bigint,text,text,timestamptz,boolean,uuid) to service_role;

create or replace function public.hr_reconcile_payroll_payment_batch(
 p_tenant_id uuid,p_payment_batch_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare
 v public.hr_payroll_payment_batches%rowtype;
 r public.hr_payroll_runs%rowtype;
 v_count integer; v_settled bigint; v_event_ids uuid[]; v_event_item_count integer; v_event_amount bigint; v_evidence jsonb; v_hash text; f public.hr_payroll_finance_postings%rowtype;
begin
 select * into v from public.hr_payroll_payment_batches where tenant_id=p_tenant_id and id=p_payment_batch_id for update;
 if not found or v.status<>'processing' then raise exception using errcode='23514',message='PROCESSING_PAYROLL_PAYMENT_BATCH_REQUIRED'; end if;
 select * into r from public.hr_payroll_runs where tenant_id=p_tenant_id and id=v.payroll_run_id for share;
 select * into f from public.hr_payroll_finance_postings where tenant_id=p_tenant_id and id=v.finance_posting_id for share;
 if p_actor_user_id in (v.created_by,v.approved_by,r.created_by,r.generated_by,r.submitted_by,r.approved_by,f.created_by,f.posted_by,f.reconciled_by) then
  raise exception using errcode='42501',message='INDEPENDENT_PAYROLL_PAYMENT_RECONCILER_REQUIRED';
 end if;
 if exists(select 1 from public.hr_payroll_payment_items where tenant_id=p_tenant_id and payment_batch_id=v.id and status<>'settled') then
  raise exception using errcode='23514',message='ALL_PAYROLL_PAYMENT_ITEMS_MUST_BE_SETTLED';
 end if;
 select count(*),coalesce(sum(amount_idr),0) into v_count,v_settled
  from public.hr_payroll_payment_items where tenant_id=p_tenant_id and payment_batch_id=v.id and status='settled';
 if v_count<>v.item_count or v_settled<>v.amount_idr then
  raise exception using errcode='23514',message='PAYROLL_PAYMENT_SETTLEMENT_TOTAL_MISMATCH';
 end if;
 select coalesce(array_agg(e.id order by e.id),'{}'::uuid[]),
        count(distinct e.payment_item_id),coalesce(sum(e.amount_idr),0)
  into v_event_ids,v_event_item_count,v_event_amount
  from public.hr_payroll_provider_events e
  join public.hr_payroll_payment_items i on i.tenant_id=e.tenant_id and i.id=e.payment_item_id
  where e.tenant_id=p_tenant_id and e.payment_batch_id=v.id and e.event_kind='settled'
   and i.status='settled';
 if cardinality(v_event_ids)=0 or v_event_item_count<>v.item_count or v_event_amount<>v.amount_idr then
  raise exception using errcode='23514',message='SETTLED_PROVIDER_EVENT_MISSING_FOR_PAYMENT_ITEM';
 end if;
 select jsonb_build_object('tenant_id',p_tenant_id,'payment_batch_id',v.id,
  'payroll_run_id',v.payroll_run_id,'finance_posting_id',v.finance_posting_id,
  'provider_config_id',v.provider_config_id,'amount_idr',v.amount_idr,
  'items',coalesce((select jsonb_agg(jsonb_build_object('item_id',i.id,'payroll_line_id',i.payroll_line_id,
    'beneficiary_fingerprint_sha256',i.beneficiary_fingerprint_sha256,'amount_idr',i.amount_idr,
    'provider_reference',i.provider_reference,'settled_at',i.settled_at) order by i.id)
   from public.hr_payroll_payment_items i where i.tenant_id=p_tenant_id and i.payment_batch_id=v.id),'[]'::jsonb),
  'events',coalesce((select jsonb_agg(jsonb_build_object('event_id',e.id,'provider_event_id',e.provider_event_id,
    'event_kind',e.event_kind,'amount_idr',e.amount_idr,'payload_sha256',e.payload_sha256,
    'occurred_at',e.occurred_at) order by e.id)
   from public.hr_payroll_provider_events e where e.tenant_id=p_tenant_id and e.payment_batch_id=v.id),'[]'::jsonb)
 ) into v_evidence;
 v_hash:=encode(pg_catalog.sha256(convert_to(v_evidence::text,'UTF8')),'hex');
 insert into public.hr_payroll_payment_reconciliations(
  tenant_id,payment_batch_id,expected_amount_idr,settled_amount_idr,item_count,event_ids,
  evidence_sha256,status,reconciled_by
 ) values(p_tenant_id,v.id,v.amount_idr,v_settled,v_count,v_event_ids,v_hash,'reconciled',p_actor_user_id);
 update public.hr_payroll_payment_batches set status='reconciled',reconciled_by=p_actor_user_id,
  reconciled_at=now(),reconciliation_sha256=v_hash,updated_at=now() where id=v.id returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.payment_batch_reconciled','hr_payroll_payment_batches',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'payroll_run_id',v.payroll_run_id,'amount_idr',v.amount_idr,
   'item_count',v_count,'evidence_sha256',v_hash));
 return jsonb_build_object('status','reconciled','payment_batch_id',v.id,'amount_idr',v.amount_idr,
  'item_count',v_count,'evidence_sha256',v_hash);
end $$;
revoke all on function public.hr_reconcile_payroll_payment_batch(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_reconcile_payroll_payment_batch(uuid,uuid,uuid) to service_role;

create or replace function public.hr_reject_payroll_provider_event_mutation()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
 raise exception using errcode='55000',message='PAYROLL_PROVIDER_EVENTS_APPEND_ONLY';
end $$;
revoke all on function public.hr_reject_payroll_provider_event_mutation() from public,anon,authenticated;
drop trigger if exists hr_payroll_provider_events_append_only on public.hr_payroll_provider_events;
create trigger hr_payroll_provider_events_append_only before update or delete on public.hr_payroll_provider_events
for each row execute function public.hr_reject_payroll_provider_event_mutation();

do $$
declare t text;
begin
 foreach t in array array[
  'hr_payroll_payment_provider_configs','hr_payroll_beneficiary_profiles',
  'hr_payroll_payment_batches','hr_payroll_payment_items',
  'hr_payroll_provider_events','hr_payroll_payment_reconciliations'
 ] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists service_role_only on public.%I',t);
  execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant select,insert,update,delete on public.%I to service_role',t);
 end loop;
end $$;

-- External provider dispatch and raw-body signature verification remain disabled
-- until an exact provider contract and staging credentials are approved.
