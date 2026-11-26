-- D'Lice FnB OS official migration generated from reviewed domain SQL drafts.
-- Source files:
--   docs/implementation/sql/CRM_LOYALTY_SCHEMA_DRAFT.sql
--   docs/implementation/sql/CRM_LOYALTY_ADAPTERS_EXTENSION_DRAFT.sql
--   docs/implementation/sql/CRM_FINANCIAL_CLOSE_REVIEW_EXTENSION_DRAFT.sql
--   docs/implementation/sql/CRM_LOYALTY_EXPIRY_EXTENSION_DRAFT.sql

create table if not exists public.crm_customers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid null,
  display_name text null check (display_name is null or length(btrim(display_name)) between 1 and 120),
  phone_e164 text null check (phone_e164 is null or phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  email_normalized text null check (email_normalized is null or (length(email_normalized) <= 254 and email_normalized = lower(email_normalized))),
  status text not null default 'prospect' check (status in ('prospect','active','inactive','merged','blocked')),
  marketing_status text not null default 'unknown' check (marketing_status in ('unknown','active','suppressed')),
  merged_into_customer_id uuid null,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id,id),
  foreign key (tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  foreign key (tenant_id,merged_into_customer_id) references public.crm_customers(tenant_id,id) on delete restrict,
  check (phone_e164 is not null or email_normalized is not null),
  check (merged_into_customer_id is null or merged_into_customer_id <> id)
);
create unique index if not exists crm_customers_tenant_phone_uq
  on public.crm_customers(tenant_id,phone_e164) where phone_e164 is not null and status <> 'merged';
create unique index if not exists crm_customers_tenant_email_uq
  on public.crm_customers(tenant_id,email_normalized) where email_normalized is not null and status <> 'merged';
create index if not exists crm_customers_tenant_branch_status_idx
  on public.crm_customers(tenant_id,branch_id,status,created_at desc);

create table if not exists public.crm_customer_consent_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  customer_id uuid not null,
  purpose text not null check (purpose in ('marketing_email','marketing_sms','marketing_whatsapp','personalization')),
  channel text not null check (channel in ('email','sms','whatsapp','pos','web','staff')),
  decision text not null check (decision in ('granted','withdrawn')),
  policy_version text not null check (length(btrim(policy_version)) between 1 and 80),
  idempotency_key text not null check (length(idempotency_key) between 8 and 120),
  occurred_at timestamptz not null,
  actor_user_id uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (tenant_id,id),
  unique (tenant_id,idempotency_key),
  foreign key (tenant_id,customer_id) references public.crm_customers(tenant_id,id) on delete restrict
);
create index if not exists crm_consent_customer_purpose_time_idx
  on public.crm_customer_consent_events(tenant_id,customer_id,purpose,occurred_at desc);

create table if not exists public.crm_loyalty_ledger (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  customer_id uuid not null,
  entry_kind text not null check (entry_kind in ('earn','redeem','adjustment','reversal')),
  points bigint not null check (points <> 0),
  idempotency_key text not null check (length(idempotency_key) between 8 and 120),
  source_reference text not null check (length(btrim(source_reference)) between 1 and 160),
  reverses_entry_id uuid null,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (tenant_id,id),
  unique (tenant_id,idempotency_key),
  foreign key (tenant_id,customer_id) references public.crm_customers(tenant_id,id) on delete restrict,
  foreign key (tenant_id,reverses_entry_id) references public.crm_loyalty_ledger(tenant_id,id) on delete restrict,
  check ((entry_kind='earn' and points>0 and reverses_entry_id is null)
      or (entry_kind='redeem' and points<0 and reverses_entry_id is null)
      or (entry_kind='adjustment' and reverses_entry_id is null)
      or (entry_kind='reversal' and reverses_entry_id is not null))
);
create unique index if not exists crm_loyalty_one_reversal_per_entry_uq
  on public.crm_loyalty_ledger(tenant_id,reverses_entry_id) where reverses_entry_id is not null;
create index if not exists crm_loyalty_customer_ledger_idx
  on public.crm_loyalty_ledger(tenant_id,customer_id,created_at desc);

create table if not exists public.crm_rewards (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  name text not null check (length(btrim(name)) between 1 and 120),
  description text null,
  points_cost bigint not null check (points_cost > 0),
  starts_at timestamptz not null,
  expires_at timestamptz not null,
  status text not null default 'draft' check (status in ('draft','active','paused','retired')),
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id,id),
  check (expires_at > starts_at)
);
create index if not exists crm_rewards_tenant_status_window_idx
  on public.crm_rewards(tenant_id,status,starts_at,expires_at);

create table if not exists public.crm_reward_vouchers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  customer_id uuid not null,
  reward_id uuid not null,
  code text not null check (length(btrim(code)) between 6 and 80),
  idempotency_key text not null check (length(idempotency_key) between 8 and 120),
  points_cost bigint not null check (points_cost > 0),
  status text not null default 'reserved' check (status in ('reserved','redeemed','cancelled','expired')),
  expires_at timestamptz not null,
  redeemed_at timestamptz null,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (tenant_id,id),
  unique (tenant_id,code),
  unique (tenant_id,idempotency_key),
  foreign key (tenant_id,customer_id) references public.crm_customers(tenant_id,id) on delete restrict,
  foreign key (tenant_id,reward_id) references public.crm_rewards(tenant_id,id) on delete restrict
);
create index if not exists crm_vouchers_customer_status_idx
  on public.crm_reward_vouchers(tenant_id,customer_id,status,expires_at);

create table if not exists public.crm_transaction_links (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  customer_id uuid not null,
  source_type text not null check (source_type in ('online_order','pos_sale')),
  source_id uuid not null,
  branch_id uuid not null,
  linked_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (tenant_id,source_type,source_id),
  foreign key (tenant_id,customer_id) references public.crm_customers(tenant_id,id) on delete restrict,
  foreign key (tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);

-- No direct browser access. Edge Function dlice-orders uses its service role
-- only after verifying the caller and tenant/branch membership.


create table if not exists public.crm_marketing_campaigns (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 name text not null check(length(btrim(name)) between 2 and 120),
 channel text not null check(channel in ('email','sms','whatsapp')),
 purpose text not null check(purpose in ('marketing_email','marketing_sms','marketing_whatsapp')),
 subject text null,
 message_template text not null check(length(btrim(message_template)) between 1 and 10000),
 status text not null default 'draft' check(status in ('draft','approved','audience_prepared','queued','sending','sent','paused','cancelled')),
 scheduled_at timestamptz null,
 approved_by uuid null references auth.users(id) on delete restrict,
 approved_at timestamptz null,
 created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,id),
 check((channel='email' and purpose='marketing_email') or (channel='sms' and purpose='marketing_sms') or (channel='whatsapp' and purpose='marketing_whatsapp')),
 check(status not in ('approved','audience_prepared','queued','sending','sent') or (approved_by is not null and approved_at is not null and approved_by<>created_by))
);
create table if not exists public.crm_campaign_recipients (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 campaign_id uuid not null,
 customer_id uuid not null,
 destination_snapshot text not null,
 consent_event_id uuid null,
 status text not null default 'queued' check(status in ('queued','sent','delivered','failed','suppressed','unsubscribed')),
 provider_message_id text null,
 attempted_at timestamptz null,
 delivered_at timestamptz null,
 failure_reason text null,
 idempotency_key text not null,
 created_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,campaign_id,customer_id),
 unique(tenant_id,idempotency_key),
 foreign key(tenant_id,campaign_id) references public.crm_marketing_campaigns(tenant_id,id) on delete restrict,
 foreign key(tenant_id,customer_id) references public.crm_customers(tenant_id,id) on delete restrict,
 foreign key(tenant_id,consent_event_id) references public.crm_customer_consent_events(tenant_id,id) on delete restrict
);
create index if not exists crm_campaign_recipient_queue_idx on public.crm_campaign_recipients(tenant_id,campaign_id,status);
-- Audit inserts in the same transaction as customer/consent/reward writes.
create or replace function public.crm_audit_insert_row()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row jsonb := to_jsonb(new);
  v_actor_id uuid;
  v_tenant_id uuid;
begin
  v_actor_id := nullif(coalesce(v_row->>'actor_user_id',v_row->>'created_by'),'')::uuid;
  v_tenant_id := nullif(v_row->>'tenant_id','')::uuid;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values (
    v_actor_id,
    'crm.'||tg_table_name||'.'||lower(tg_op),
    tg_table_name,
    v_row->>'id',
    jsonb_build_object('tenant_id',v_tenant_id)
  );
  return new;
end;
$$;
revoke all on function public.crm_audit_insert_row() from public,anon,authenticated;
drop trigger if exists crm_customers_audit_insert on public.crm_customers;
create trigger crm_customers_audit_insert after insert on public.crm_customers
for each row execute function public.crm_audit_insert_row();
drop trigger if exists crm_consent_audit_insert on public.crm_customer_consent_events;
create trigger crm_consent_audit_insert after insert on public.crm_customer_consent_events
for each row execute function public.crm_audit_insert_row();
drop trigger if exists crm_rewards_audit_insert on public.crm_rewards;
create trigger crm_rewards_audit_insert after insert or update on public.crm_rewards
for each row execute function public.crm_audit_insert_row();
drop trigger if exists crm_vouchers_audit_insert on public.crm_reward_vouchers;
create trigger crm_vouchers_audit_insert after insert on public.crm_reward_vouchers
for each row execute function public.crm_audit_insert_row();

-- Append-only ledger RPC. EXECUTE is granted only to service_role; callers
-- must be authenticated/authorized in the Edge Function before invoking it.
create or replace function public.crm_append_loyalty_entry(
  p_tenant_id uuid,
  p_customer_id uuid,
  p_entry_kind text,
  p_points bigint,
  p_idempotency_key text,
  p_source_reference text,
  p_reverses_entry_id uuid,
  p_actor_user_id uuid
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_balance bigint;
  v_original public.crm_loyalty_ledger%rowtype;
  v_entry public.crm_loyalty_ledger%rowtype;
begin
  if p_entry_kind not in ('earn','redeem','adjustment','reversal') or p_points=0
    or length(coalesce(p_idempotency_key,'')) not between 8 and 120
    or length(btrim(coalesce(p_source_reference,'')))=0 then
    raise exception using errcode='22023', message='INVALID_LEDGER_COMMAND';
  end if;

  perform 1 from public.crm_customers
   where tenant_id=p_tenant_id and id=p_customer_id and status in ('prospect','active')
   for update;
  if not found then raise exception using errcode='P0002', message='CUSTOMER_NOT_FOUND'; end if;

  if exists(select 1 from public.crm_loyalty_ledger where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key) then
    raise exception using errcode='23505', message='DUPLICATE_IDEMPOTENCY_KEY';
  end if;

  if (p_entry_kind='earn' and p_points<0) or (p_entry_kind='redeem' and p_points>=0)
    or (p_entry_kind='reversal' and p_reverses_entry_id is null)
    or (p_entry_kind<>'reversal' and p_reverses_entry_id is not null) then
    raise exception using errcode='22023', message='INVALID_POINTS_SIGN_OR_REVERSAL_REFERENCE';
  end if;

  if p_entry_kind='reversal' then
    select * into v_original from public.crm_loyalty_ledger
     where tenant_id=p_tenant_id and id=p_reverses_entry_id and customer_id=p_customer_id
     for update;
    if not found or v_original.entry_kind='reversal' or p_points <> -v_original.points then
      raise exception using errcode='22023', message='INVALID_REVERSAL_TARGET_OR_AMOUNT';
    end if;
    if exists(select 1 from public.crm_loyalty_ledger where tenant_id=p_tenant_id and reverses_entry_id=p_reverses_entry_id) then
      raise exception using errcode='23505', message='ENTRY_ALREADY_REVERSED';
    end if;
  end if;

  select coalesce(sum(points),0) into v_balance from public.crm_loyalty_ledger
   where tenant_id=p_tenant_id and customer_id=p_customer_id;
  if v_balance+p_points<0 then raise exception using errcode='22023', message='INSUFFICIENT_POINTS'; end if;

  insert into public.crm_loyalty_ledger
    (tenant_id,customer_id,entry_kind,points,idempotency_key,source_reference,reverses_entry_id,created_by)
  values
    (p_tenant_id,p_customer_id,p_entry_kind,p_points,p_idempotency_key,p_source_reference,p_reverses_entry_id,p_actor_user_id)
  returning * into v_entry;

  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values (p_actor_user_id,'crm.loyalty.'||p_entry_kind,'crm_loyalty_ledger',v_entry.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'customer_id',p_customer_id,'points',p_points,'source_reference',p_source_reference));

  return jsonb_build_object('entry_id',v_entry.id,'balance_after',v_balance+p_points,'entry_kind',v_entry.entry_kind);
end;
$$;
revoke all on function public.crm_append_loyalty_entry(uuid,uuid,text,bigint,text,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.crm_append_loyalty_entry(uuid,uuid,text,bigint,text,text,uuid,uuid) to service_role;

-- Atomic reward redemption: voucher reservation and points debit share one transaction.
create or replace function public.crm_redeem_reward(
  p_tenant_id uuid,
  p_customer_id uuid,
  p_reward_id uuid,
  p_idempotency_key text,
  p_actor_user_id uuid
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_reward public.crm_rewards%rowtype;
  v_voucher public.crm_reward_vouchers%rowtype;
  v_balance bigint;
begin
  if length(coalesce(p_idempotency_key,'')) not between 8 and 120 then
    raise exception using errcode='22023', message='INVALID_IDEMPOTENCY_KEY';
  end if;

  perform 1 from public.crm_customers
   where tenant_id=p_tenant_id and id=p_customer_id and status='active'
   for update;
  if not found then raise exception using errcode='P0002', message='ACTIVE_CUSTOMER_NOT_FOUND'; end if;

  select * into v_reward from public.crm_rewards
   where tenant_id=p_tenant_id and id=p_reward_id and status='active'
     and starts_at<=now() and expires_at>now()
   for update;
  if not found then raise exception using errcode='P0002', message='REWARD_NOT_ACTIVE'; end if;

  if exists(select 1 from public.crm_reward_vouchers where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key) then
    raise exception using errcode='23505', message='DUPLICATE_REDEMPTION';
  end if;

  select coalesce(sum(points),0) into v_balance from public.crm_loyalty_ledger
   where tenant_id=p_tenant_id and customer_id=p_customer_id;
  if v_balance<v_reward.points_cost then
    raise exception using errcode='22023', message='INSUFFICIENT_POINTS';
  end if;

  insert into public.crm_reward_vouchers
    (tenant_id,customer_id,reward_id,code,idempotency_key,points_cost,status,expires_at,created_by)
  values
    (p_tenant_id,p_customer_id,p_reward_id,
     upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),
     p_idempotency_key,v_reward.points_cost,'reserved',v_reward.expires_at,p_actor_user_id)
  returning * into v_voucher;

  insert into public.crm_loyalty_ledger
    (tenant_id,customer_id,entry_kind,points,idempotency_key,source_reference,created_by)
  values
    (p_tenant_id,p_customer_id,'redeem',-v_reward.points_cost,p_idempotency_key,
     'voucher:'||v_voucher.id::text,p_actor_user_id);

  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values (p_actor_user_id,'crm.loyalty.redeem','crm_loyalty_ledger',v_voucher.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'customer_id',p_customer_id,'reward_id',p_reward_id,'points',-v_reward.points_cost));

  return jsonb_build_object('voucher_id',v_voucher.id,'voucher_code',v_voucher.code,
    'points_cost',v_voucher.points_cost,'expires_at',v_voucher.expires_at,'balance_after',v_balance-v_voucher.points_cost);
end;
$$;
revoke all on function public.crm_redeem_reward(uuid,uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.crm_redeem_reward(uuid,uuid,uuid,text,uuid) to service_role;

create or replace function public.crm_approve_campaign(p_tenant_id uuid,p_campaign_id uuid,p_actor_user_id uuid)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.crm_marketing_campaigns%rowtype;
begin
 select * into v from public.crm_marketing_campaigns where tenant_id=p_tenant_id and id=p_campaign_id for update;
 if not found then raise exception using errcode='P0002',message='CRM_CAMPAIGN_NOT_FOUND'; end if;
 if v.status<>'draft' then raise exception using errcode='23514',message='CRM_CAMPAIGN_NOT_DRAFT'; end if;
 if v.created_by=p_actor_user_id then raise exception using errcode='42501',message='INDEPENDENT_CAMPAIGN_APPROVER_REQUIRED'; end if;
 update public.crm_marketing_campaigns set status='approved',approved_by=p_actor_user_id,approved_at=now(),updated_at=now() where id=p_campaign_id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'crm.campaign.approved','crm_marketing_campaign',p_campaign_id::text,jsonb_build_object('tenant_id',p_tenant_id));
 return jsonb_build_object('campaign_id',p_campaign_id,'status','approved');
end $$;
revoke all on function public.crm_approve_campaign(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.crm_approve_campaign(uuid,uuid,uuid) to service_role;

create or replace function public.crm_prepare_campaign_audience(p_tenant_id uuid,p_campaign_id uuid,p_actor_user_id uuid)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_campaign public.crm_marketing_campaigns%rowtype; v_inserted integer; v_suppressed integer;
begin
 select * into v_campaign from public.crm_marketing_campaigns where tenant_id=p_tenant_id and id=p_campaign_id for update;
 if not found then raise exception using errcode='P0002',message='CRM_CAMPAIGN_NOT_FOUND'; end if;
 if v_campaign.status not in ('approved','audience_prepared') then raise exception using errcode='23514',message='CRM_CAMPAIGN_NOT_APPROVED'; end if;
 if v_campaign.approved_by=p_actor_user_id then
  -- The approver may prepare the queue, but cannot approve their own campaign.
  null;
 end if;
 insert into public.crm_campaign_recipients(tenant_id,campaign_id,customer_id,destination_snapshot,consent_event_id,status,idempotency_key)
 select p_tenant_id,v_campaign.id,c.id,
  case v_campaign.channel when 'email' then c.email_normalized else c.phone_e164 end,
  consent.id,'queued',v_campaign.id::text||':'||c.id::text
 from public.crm_customers c
 join lateral (
  select e.id,e.decision from public.crm_customer_consent_events e
  where e.tenant_id=c.tenant_id and e.customer_id=c.id and e.purpose=v_campaign.purpose
  order by e.occurred_at desc,e.created_at desc limit 1
 ) consent on consent.decision='granted'
 where c.tenant_id=p_tenant_id and c.status='active' and c.marketing_status='active'
  and case v_campaign.channel when 'email' then c.email_normalized is not null else c.phone_e164 is not null end
 on conflict(tenant_id,campaign_id,customer_id) do nothing;
 get diagnostics v_inserted=row_count;
 select count(*) into v_suppressed from public.crm_customers c
 where c.tenant_id=p_tenant_id and c.status='active'
  and not exists(select 1 from public.crm_campaign_recipients r where r.tenant_id=p_tenant_id and r.campaign_id=p_campaign_id and r.customer_id=c.id);
 update public.crm_marketing_campaigns set status='audience_prepared',updated_at=now() where id=p_campaign_id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'crm.campaign.audience_prepared','crm_marketing_campaign',p_campaign_id::text,
 jsonb_build_object('tenant_id',p_tenant_id,'queued',v_inserted,'suppressed',v_suppressed,'purpose',v_campaign.purpose));
 return jsonb_build_object('campaign_id',p_campaign_id,'queued',v_inserted,'suppressed',v_suppressed);
end $$;
revoke all on function public.crm_prepare_campaign_audience(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.crm_prepare_campaign_audience(uuid,uuid,uuid) to service_role;

-- NOTE: transaction links must be created only after the Edge Function verifies
-- that source_id belongs to branch_id and branch_id belongs to p_tenant_id.
-- Do not add customer_id to legacy orders/POS until their tenant attribution,
-- including historical/unassigned online orders, has been reconciled.


-- POS voucher lifecycle. A voucher can be consumed only against an already
-- verified crm_transaction_links row; the Edge Function must create that
-- link only after proving the source order belongs to this tenant and branch.
create table if not exists public.crm_voucher_consumptions (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 voucher_id uuid not null,
 source_type text not null check(source_type in ('online_order','pos_sale')),
 source_id uuid not null,
 branch_id uuid not null,
 consumed_by uuid not null references auth.users(id) on delete restrict,
 consumed_at timestamptz not null default now(),
 voided_by uuid null references auth.users(id) on delete restrict,
 voided_at timestamptz null,
 void_reason text null,
 unique(tenant_id,id),
 unique(tenant_id,voucher_id),
 foreign key(tenant_id,voucher_id) references public.crm_reward_vouchers(tenant_id,id) on delete restrict,
 foreign key(tenant_id,source_type,source_id) references public.crm_transaction_links(tenant_id,source_type,source_id) on delete restrict,
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 check((voided_at is null and voided_by is null) or (voided_at is not null and voided_by is not null and length(btrim(coalesce(void_reason,'')))>=3))
);
alter table public.crm_voucher_consumptions enable row level security;
drop policy if exists service_role_only on public.crm_voucher_consumptions;
create policy service_role_only on public.crm_voucher_consumptions for all to service_role using(true) with check(true);
revoke all on public.crm_voucher_consumptions from anon,authenticated;
grant select,insert,update,delete on public.crm_voucher_consumptions to service_role;

create or replace function public.crm_consume_voucher(
 p_tenant_id uuid,p_voucher_code text,p_source_type text,p_source_id uuid,p_branch_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.crm_reward_vouchers%rowtype; v_link public.crm_transaction_links%rowtype; v_consumption public.crm_voucher_consumptions%rowtype;
begin
 if p_source_type not in ('online_order','pos_sale') or length(btrim(coalesce(p_voucher_code,''))) not between 6 and 80 then
  raise exception using errcode='22023',message='INVALID_VOUCHER_CONSUMPTION_COMMAND';
 end if;
 select * into v from public.crm_reward_vouchers where tenant_id=p_tenant_id and code=upper(btrim(p_voucher_code)) for update;
 if not found then raise exception using errcode='P0002',message='VOUCHER_NOT_FOUND'; end if;
 if v.status<>'reserved' or v.expires_at<=now() then raise exception using errcode='23514',message='VOUCHER_NOT_REDEEMABLE'; end if;
 select * into v_link from public.crm_transaction_links
  where tenant_id=p_tenant_id and source_type=p_source_type and source_id=p_source_id and branch_id=p_branch_id and customer_id=v.customer_id;
 if not found then raise exception using errcode='42501',message='VERIFIED_CUSTOMER_TRANSACTION_LINK_REQUIRED'; end if;
 insert into public.crm_voucher_consumptions(tenant_id,voucher_id,source_type,source_id,branch_id,consumed_by)
 values(p_tenant_id,v.id,p_source_type,p_source_id,p_branch_id,p_actor_user_id) returning * into v_consumption;
 update public.crm_reward_vouchers set status='redeemed',redeemed_at=now() where tenant_id=p_tenant_id and id=v.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'crm.voucher.consumed','crm_reward_voucher',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'source_type',p_source_type,'source_id',p_source_id,'branch_id',p_branch_id));
 return jsonb_build_object('voucher_id',v.id,'status','redeemed','consumption_id',v_consumption.id,'source_id',p_source_id);
end $$;
revoke all on function public.crm_consume_voucher(uuid,text,text,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.crm_consume_voucher(uuid,text,text,uuid,uuid,uuid) to service_role;

create or replace function public.crm_void_voucher(
 p_tenant_id uuid,p_voucher_id uuid,p_source_type text,p_source_id uuid,p_reason text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.crm_reward_vouchers%rowtype; c public.crm_voucher_consumptions%rowtype; l public.crm_loyalty_ledger%rowtype; v_reversal_id uuid;
begin
 select * into v from public.crm_reward_vouchers where tenant_id=p_tenant_id and id=p_voucher_id for update;
 if not found then raise exception using errcode='P0002',message='VOUCHER_NOT_FOUND'; end if;
 if v.status<>'redeemed' then raise exception using errcode='23514',message='ONLY_REDEEMED_VOUCHER_CAN_BE_VOIDED'; end if;
 select * into c from public.crm_voucher_consumptions
  where tenant_id=p_tenant_id and voucher_id=v.id and source_type=p_source_type and source_id=p_source_id for update;
 if not found or c.voided_at is not null then raise exception using errcode='23514',message='VOUCHER_CONSUMPTION_NOT_VOIDABLE'; end if;
 if length(btrim(coalesce(p_reason,'')))<3 then raise exception using errcode='22023',message='VOUCHER_VOID_REASON_REQUIRED'; end if;
 select * into l from public.crm_loyalty_ledger
  where tenant_id=p_tenant_id and customer_id=v.customer_id and source_reference='voucher:'||v.id::text and entry_kind='redeem' for update;
 if not found then raise exception using errcode='23514',message='VOUCHER_DEBIT_LEDGER_ENTRY_MISSING'; end if;
 if exists(select 1 from public.crm_loyalty_ledger where tenant_id=p_tenant_id and reverses_entry_id=l.id) then
  raise exception using errcode='23505',message='VOUCHER_DEBIT_ALREADY_REVERSED';
 end if;
 insert into public.crm_loyalty_ledger(tenant_id,customer_id,entry_kind,points,idempotency_key,source_reference,reverses_entry_id,created_by)
 values(p_tenant_id,v.customer_id,'reversal',v.points_cost,'voucher-void:'||v.id::text,'voucher-void:'||v.id::text,l.id,p_actor_user_id)
 returning id into v_reversal_id;
 update public.crm_voucher_consumptions set voided_by=p_actor_user_id,voided_at=now(),void_reason=left(p_reason,500)
  where tenant_id=p_tenant_id and id=c.id;
 update public.crm_reward_vouchers set status='cancelled' where tenant_id=p_tenant_id and id=v.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'crm.voucher.voided','crm_reward_voucher',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'source_type',p_source_type,'source_id',p_source_id,'reversal_entry_id',v_reversal_id,'reason',left(p_reason,500)));
 return jsonb_build_object('voucher_id',v.id,'status','cancelled','reversal_entry_id',v_reversal_id,'points_restored',v.points_cost);
end $$;
revoke all on function public.crm_void_voucher(uuid,uuid,text,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.crm_void_voucher(uuid,uuid,text,uuid,text,uuid) to service_role;

-- Atomic source-to-customer identity resolution and transaction linking.
-- The Edge Function must first verify the source row and tenant/branch scope.
-- This RPC makes customer creation/promotion, link idempotency and audit one
-- database transaction. It does not award loyalty points or assert financial
-- close; earning remains gated by the reconciled-close workflow.
create or replace function public.crm_link_transaction_customer(
  p_tenant_id uuid,
  p_branch_id uuid,
  p_source_type text,
  p_source_id uuid,
  p_customer_id uuid,
  p_display_name text,
  p_phone_e164 text,
  p_actor_user_id uuid
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_customer public.crm_customers%rowtype;
  v_link public.crm_transaction_links%rowtype;
  v_created boolean := false;
begin
  if p_tenant_id is null or p_branch_id is null or p_source_id is null
     or p_source_type not in ('online_order','pos_sale') then
    raise exception using errcode='22023', message='INVALID_CRM_TRANSACTION_LINK_COMMAND';
  end if;
  if p_phone_e164 is not null and p_phone_e164 !~ '^\+[1-9][0-9]{7,14}$' then
    raise exception using errcode='22023', message='INVALID_CUSTOMER_PHONE';
  end if;
  perform 1 from public.branches
   where id=p_branch_id and tenant_id=p_tenant_id;
  if not found then
    raise exception using errcode='23503', message='CRM_BRANCH_TENANT_MISMATCH';
  end if;

  if p_customer_id is not null then
    select * into v_customer from public.crm_customers
     where id=p_customer_id and tenant_id=p_tenant_id
     for update;
    if not found then
      raise exception using errcode='P0002', message='CUSTOMER_NOT_FOUND';
    end if;
    if v_customer.status in ('merged','blocked','inactive') then
      raise exception using errcode='22023', message='CUSTOMER_NOT_ACTIVE';
    end if;
    if p_phone_e164 is not null and v_customer.phone_e164 is not null
       and v_customer.phone_e164 <> p_phone_e164 then
      raise exception using errcode='22023', message='CUSTOMER_IDENTITY_MISMATCH';
    end if;
  else
    if p_phone_e164 is null then
      raise exception using errcode='22023', message='CUSTOMER_PHONE_REQUIRED';
    end if;
    insert into public.crm_customers
      (tenant_id,branch_id,display_name,phone_e164,status,marketing_status,created_by)
    values
      (p_tenant_id,p_branch_id,nullif(btrim(p_display_name),''),p_phone_e164,'active','unknown',p_actor_user_id)
    on conflict do nothing
    returning * into v_customer;
    if found then
      v_created := true;
    else
      select * into v_customer from public.crm_customers
       where tenant_id=p_tenant_id and phone_e164=p_phone_e164 and status<>'merged'
       for update;
      if not found then
        raise exception using errcode='23505', message='CUSTOMER_IDENTITY_CONFLICT';
      end if;
      if v_customer.status in ('blocked','inactive') then
        raise exception using errcode='22023', message='CUSTOMER_NOT_ACTIVE';
      end if;
    end if;
  end if;

  insert into public.crm_transaction_links
    (tenant_id,customer_id,source_type,source_id,branch_id,linked_by)
  values
    (p_tenant_id,v_customer.id,p_source_type,p_source_id,p_branch_id,p_actor_user_id)
  on conflict (tenant_id,source_type,source_id) do nothing
  returning * into v_link;

  if not found then
    select * into v_link from public.crm_transaction_links
     where tenant_id=p_tenant_id and source_type=p_source_type and source_id=p_source_id
     for update;
    if not found then
      raise exception using errcode='40001', message='CRM_TRANSACTION_LINK_RETRY_REQUIRED';
    end if;
    if v_link.customer_id <> v_customer.id then
      raise exception using errcode='23505', message='TRANSACTION_ALREADY_LINKED_TO_OTHER_CUSTOMER';
    end if;
    return jsonb_build_object('customer_id',v_customer.id,'link_id',v_link.id,'already_linked',true,'customer_created',false);
  end if;

  if v_customer.status='prospect' then
    update public.crm_customers
       set status='active', branch_id=coalesce(branch_id,p_branch_id), updated_at=now()
     where id=v_customer.id and tenant_id=p_tenant_id
     returning * into v_customer;
  end if;

  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values (p_actor_user_id,'crm.transaction.linked','crm_transaction_links',v_link.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,
      'source_type',p_source_type,'source_id',p_source_id,
      'customer_id',v_customer.id,'customer_created',v_created));

  return jsonb_build_object('customer_id',v_customer.id,'link_id',v_link.id,
    'already_linked',false,'customer_created',v_created);
end;
$$;
revoke all on function public.crm_link_transaction_customer(uuid,uuid,text,uuid,uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.crm_link_transaction_customer(uuid,uuid,text,uuid,uuid,text,text,uuid) to service_role;


do $$
declare t text;
begin
  foreach t in array array[
    'crm_customers',
    'crm_customer_consent_events',
    'crm_loyalty_ledger',
    'crm_rewards',
    'crm_reward_vouchers',
    'crm_transaction_links',
    'crm_marketing_campaigns',
    'crm_campaign_recipients'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists service_role_only on public.%I',t);
    execute format('create policy service_role_only on public.%I for all to service_role using (true) with check (true)',t);
    execute format('revoke all on public.%I from anon, authenticated',t);
    execute format('grant select,insert,update,delete on public.%I to service_role',t);
  end loop;
end $$;

create table if not exists public.crm_loyalty_earning_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  version text not null check(length(btrim(version)) between 1 and 80),
  points_per_thousand_idr bigint not null check(points_per_thousand_idr>=0),
  status text not null default 'draft' check(status in ('draft','approved','retired')),
  approved_by uuid null references auth.users(id) on delete restrict,
  approved_at timestamptz null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,version),
  check((status='approved' and approved_by is not null and approved_at is not null and approved_by<>created_by) or status<>'approved')
);
create unique index if not exists crm_loyalty_one_approved_rule_uq
  on public.crm_loyalty_earning_rules(tenant_id) where status='approved';

create table if not exists public.crm_financial_close_projections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  source_type text not null check(source_type in ('pos_sale','online_order')),
  source_id uuid not null,
  shift_reconciliation_id uuid null,
  settlement_reconciliation_id uuid null,
  settlement_ids uuid[] not null default '{}',
  finance_journal_entry_ids uuid[] not null default '{}',
  currency text not null check(currency='IDR'),
  subtotal_idr bigint not null check(subtotal_idr>=0),
  discount_idr bigint not null check(discount_idr>=0),
  processed_refunds_idr bigint not null check(processed_refunds_idr>=0),
  refund_evidence jsonb not null check(jsonb_typeof(refund_evidence)='array'),
  shift_reconciliation_status text not null check(shift_reconciliation_status in ('approved','not_required')),
  settlement_reconciliation_status text not null check(settlement_reconciliation_status in ('matched','cash_reconciled')),
  finance_journal_status text not null check(finance_journal_status in ('posted','reconciled')),
  finance_source_reconciliation_status text not null check(finance_source_reconciliation_status='reconciled'),
  status text not null check(status in ('reconciled','superseded')),
  source_snapshot_sha256 text not null check(source_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  reconciled_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,source_type,source_id,source_snapshot_sha256),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  check(discount_idr<=subtotal_idr and processed_refunds_idr<=subtotal_idr-discount_idr)
);
create index if not exists crm_financial_close_source_idx
  on public.crm_financial_close_projections(tenant_id,branch_id,source_type,source_id,reconciled_at desc);

create table if not exists public.crm_campaign_outbox (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  campaign_id uuid not null,
  recipient_id uuid not null,
  provider_id text not null check(length(btrim(provider_id)) between 1 and 100),
  channel text not null check(channel in ('email','sms','whatsapp')),
  destination_snapshot text not null,
  rendered_payload jsonb not null check(jsonb_typeof(rendered_payload)='object'),
  status text not null default 'queued' check(status in ('queued','claimed','accepted','delivered','failed','suppressed','dead_letter')),
  attempts integer not null default 0 check(attempts>=0),
  next_attempt_at timestamptz null,
  provider_message_id text null,
  last_error_code text null,
  idempotency_key text not null check(length(idempotency_key) between 8 and 160),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,idempotency_key),
  unique(provider_id,provider_message_id),
  foreign key(tenant_id,campaign_id) references public.crm_marketing_campaigns(tenant_id,id) on delete restrict,
  foreign key(tenant_id,recipient_id) references public.crm_campaign_recipients(tenant_id,id) on delete restrict
);
create index if not exists crm_campaign_outbox_due_idx
  on public.crm_campaign_outbox(status,next_attempt_at,created_at) where status in ('queued','failed');

create table if not exists public.crm_campaign_provider_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  provider_id text not null,
  provider_event_id text not null,
  provider_message_id text null,
  event_kind text not null check(event_kind in ('accepted','delivered','bounced','failed','unsubscribed')),
  body_sha256 text not null check(body_sha256 ~ '^[0-9a-f]{64}$'),
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  payload jsonb not null check(jsonb_typeof(payload)='object'),
  unique(tenant_id,id),
  unique(provider_id,provider_event_id)
);
create index if not exists crm_campaign_provider_message_idx
  on public.crm_campaign_provider_events(tenant_id,provider_id,provider_message_id);

create table if not exists public.crm_campaign_attributions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  campaign_id uuid not null,
  customer_id uuid not null,
  source_type text not null check(source_type in ('pos_sale','online_order')),
  source_id uuid not null,
  eligible_net_sales_idr bigint not null check(eligible_net_sales_idr>=0),
  finance_reconciliation_id uuid not null,
  attributed_at timestamptz not null,
  attribution_window_start timestamptz not null,
  attribution_window_end timestamptz not null,
  source_snapshot_sha256 text not null check(source_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  unique(tenant_id,id),
  unique(tenant_id,campaign_id,source_type,source_id),
  foreign key(tenant_id,campaign_id) references public.crm_marketing_campaigns(tenant_id,id) on delete restrict,
  foreign key(tenant_id,customer_id) references public.crm_customers(tenant_id,id) on delete restrict,
  check(attribution_window_end>attribution_window_start)
);
create index if not exists crm_campaign_attribution_window_idx
  on public.crm_campaign_attributions(tenant_id,campaign_id,attributed_at);

create table if not exists public.crm_campaign_costs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  campaign_id uuid not null,
  cost_type text not null check(cost_type in ('provider','creative','agency','other')),
  amount_idr bigint not null check(amount_idr>=0),
  finance_journal_batch_id uuid not null,
  status text not null check(status in ('posted','reconciled')),
  source_snapshot_sha256 text not null check(source_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  unique(tenant_id,id),
  foreign key(tenant_id,campaign_id) references public.crm_marketing_campaigns(tenant_id,id) on delete restrict
);
create index if not exists crm_campaign_costs_idx
  on public.crm_campaign_costs(tenant_id,campaign_id,status);

-- One transaction: validate close evidence, customer link and approved earning rule,
-- calculate eligible net sales after discounts/refunds, then append the award.
create or replace function public.crm_award_loyalty_for_reconciled_close(
  p_tenant_id uuid,p_branch_id uuid,p_source_type text,p_source_id uuid,p_actor_user_id uuid
) returns jsonb
language plpgsql security invoker set search_path = ''
as $$
declare
  v_close public.crm_financial_close_projections%rowtype;
  v_rule public.crm_loyalty_earning_rules%rowtype;
  v_customer_id uuid;
  v_net bigint;
  v_points bigint;
  v_key text;
  v_existing public.crm_loyalty_ledger%rowtype;
  v_entry public.crm_loyalty_ledger%rowtype;
  v_refund_sum bigint;
begin
  if p_tenant_id is null or p_branch_id is null or p_source_id is null
     or p_actor_user_id is null or p_source_type not in ('pos_sale','online_order') then
    raise exception using errcode='22023',message='INVALID_LOYALTY_CLOSE_COMMAND';
  end if;
  select * into v_close from public.crm_financial_close_projections
   where tenant_id=p_tenant_id and branch_id=p_branch_id
     and source_type=p_source_type and source_id=p_source_id and status='reconciled'
   order by reconciled_at desc limit 1 for update;
  if not found then raise exception using errcode='P0002',message='FINANCIAL_CLOSE_NOT_RECONCILED'; end if;
  if (p_source_type='pos_sale' and v_close.shift_reconciliation_status<>'approved')
     or (p_source_type='online_order' and v_close.shift_reconciliation_status<>'not_required')
     or v_close.settlement_reconciliation_status not in ('matched','cash_reconciled')
     or v_close.finance_journal_status not in ('posted','reconciled')
     or v_close.finance_source_reconciliation_status<>'reconciled' then
    raise exception using errcode='23514',message='FINANCIAL_CLOSE_EVIDENCE_INCOMPLETE';
  end if;
  select coalesce(sum((r->>'amountIdr')::bigint),0) into v_refund_sum
    from jsonb_array_elements(v_close.refund_evidence) r
   where r->>'status'='processed' and coalesce(r->>'id','')<>''
     and coalesce(r->>'amountIdr','') ~ '^[0-9]+$';
  if exists(select 1 from jsonb_array_elements(v_close.refund_evidence) r
    where r->>'status'<>'processed' or coalesce(r->>'id','')=''
      or coalesce(r->>'amountIdr','') !~ '^[0-9]+$')
     or v_refund_sum<>v_close.processed_refunds_idr then
    raise exception using errcode='23514',message='REFUND_EVIDENCE_INCOMPLETE';
  end if;
  v_net:=v_close.subtotal_idr-v_close.discount_idr-v_close.processed_refunds_idr;
  if v_net<0 then raise exception using errcode='23514',message='NEGATIVE_ELIGIBLE_NET_SALES'; end if;
  select * into v_rule from public.crm_loyalty_earning_rules
   where tenant_id=p_tenant_id and status='approved'
   order by approved_at desc limit 1 for share;
  if not found then raise exception using errcode='P0002',message='APPROVED_EARNING_RULE_REQUIRED'; end if;
  select customer_id into v_customer_id from public.crm_transaction_links
   where tenant_id=p_tenant_id and branch_id=p_branch_id
     and source_type=p_source_type and source_id=p_source_id;
  if v_customer_id is null then raise exception using errcode='P0002',message='SOURCE_CUSTOMER_IDENTITY_UNRESOLVED'; end if;
  perform 1 from public.crm_customers
   where tenant_id=p_tenant_id and id=v_customer_id and status='active' for update;
  if not found then raise exception using errcode='P0002',message='ACTIVE_CUSTOMER_NOT_FOUND'; end if;
  v_points:=floor(v_net/1000.0)::bigint*v_rule.points_per_thousand_idr;
  v_key:='crm-earn:'||p_tenant_id::text||':'||p_source_type||':'||p_source_id::text||':'||v_rule.version;
  select * into v_existing from public.crm_loyalty_ledger
   where tenant_id=p_tenant_id and idempotency_key=v_key;
  if found then
    if v_existing.customer_id<>v_customer_id or v_existing.points<>v_points or v_existing.entry_kind<>'earn' then
      raise exception using errcode='23505',message='LOYALTY_IDEMPOTENCY_COLLISION';
    end if;
    return jsonb_build_object('status','duplicate','entry_id',v_existing.id,'points',v_existing.points,'idempotency_key',v_key);
  end if;
  if v_points=0 then return jsonb_build_object('status','zero_award','points',0,'idempotency_key',v_key,'eligible_net_sales_idr',v_net); end if;
  insert into public.crm_loyalty_ledger
    (tenant_id,customer_id,entry_kind,points,idempotency_key,source_reference,created_by)
  values(p_tenant_id,v_customer_id,'earn',v_points,v_key,
    p_source_type||':'||p_source_id::text||':close:'||v_close.id::text,p_actor_user_id)
  returning * into v_entry;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'crm.loyalty.financial_close_awarded','crm_loyalty_ledger',v_entry.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'financial_close_id',v_close.id,
      'source_type',p_source_type,'source_id',p_source_id,'customer_id',v_customer_id,
      'eligible_net_sales_idr',v_net,'points',v_points,'earning_rule_version',v_rule.version));
  return jsonb_build_object('status','awarded','entry_id',v_entry.id,'points',v_points,
    'eligible_net_sales_idr',v_net,'idempotency_key',v_key);
end;
$$;
revoke all on function public.crm_award_loyalty_for_reconciled_close(uuid,uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.crm_award_loyalty_for_reconciled_close(uuid,uuid,text,uuid,uuid) to service_role;


-- Automatically link identifiable paid orders and paid POS sales to CRM.
-- This does not award points; points require the separate reconciled-close RPC.
-- Automatically link identifiable paid sources. Loyalty earning remains gated
-- by the reconciled financial-close projection RPC.
create or replace function public.crm_auto_link_paid_transaction_customer()
returns trigger language plpgsql security invoker set search_path=''
as $$
declare
  v_tenant_id uuid;
  v_raw_phone text;
  v_digits text;
  v_phone text;
  v_source_type text;
  v_display_name text;
begin
  if tg_table_name='orders' then
    if new.payment_status<>'paid' or new.branch_id is null then return new; end if;
    v_source_type:='online_order';
    v_raw_phone:=coalesce(new.customer_whatsapp,'');
    v_display_name:=nullif(btrim(new.customer_name),'');
  elsif tg_table_name='pos_sales' then
    if new.payment_status<>'paid' then return new; end if;
    v_source_type:='pos_sale';
    v_raw_phone:=coalesce(new.customer_reference,'');
    v_display_name:=null;
  else
    return new;
  end if;
  if v_raw_phone !~ '^[+0-9[:space:]()-]+$' then return new; end if;
  v_digits:=regexp_replace(v_raw_phone,'[^0-9]','','g');
  if v_digits='' then return new; end if;
  if left(v_digits,1)='0' then v_digits:='62'||substr(v_digits,2);
  elsif left(v_digits,1)='8' then v_digits:='62'||v_digits;
  end if;
  v_phone:='+'||v_digits;
  if v_phone !~ '^\+[1-9][0-9]{7,14}$' then return new; end if;
  select tenant_id into v_tenant_id from public.branches where id=new.branch_id;
  if v_tenant_id is null then
    raise exception using errcode='23503',message='CRM_SOURCE_BRANCH_TENANT_NOT_FOUND';
  end if;
  perform public.crm_link_transaction_customer(
    v_tenant_id,new.branch_id,v_source_type,new.id,null,v_display_name,v_phone,auth.uid()
  );
  return new;
end;
$$;
revoke all on function public.crm_auto_link_paid_transaction_customer() from public,anon,authenticated;
drop trigger if exists crm_auto_link_paid_order on public.orders;
create trigger crm_auto_link_paid_order
after insert or update of payment_status,customer_whatsapp,branch_id on public.orders
for each row execute function public.crm_auto_link_paid_transaction_customer();
drop trigger if exists crm_auto_link_paid_pos_sale on public.pos_sales;
create trigger crm_auto_link_paid_pos_sale
after insert or update of payment_status,customer_reference,branch_id on public.pos_sales
for each row execute function public.crm_auto_link_paid_transaction_customer();

create or replace function public.crm_reject_append_only_mutation()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
  raise exception using errcode='55000',message='CRM_APPEND_ONLY_RECORD_CANNOT_BE_CHANGED',
    detail=tg_table_name||' is append-only; record a compensating event instead';
end;
$$;
revoke all on function public.crm_reject_append_only_mutation() from public,anon,authenticated;
drop trigger if exists crm_consent_events_append_only on public.crm_customer_consent_events;
create trigger crm_consent_events_append_only before update or delete on public.crm_customer_consent_events
for each row execute function public.crm_reject_append_only_mutation();
drop trigger if exists crm_loyalty_ledger_append_only on public.crm_loyalty_ledger;
create trigger crm_loyalty_ledger_append_only before update or delete on public.crm_loyalty_ledger
for each row execute function public.crm_reject_append_only_mutation();
drop trigger if exists crm_campaign_provider_events_append_only on public.crm_campaign_provider_events;
create trigger crm_campaign_provider_events_append_only before update or delete on public.crm_campaign_provider_events
for each row execute function public.crm_reject_append_only_mutation();
drop trigger if exists crm_campaign_attributions_append_only on public.crm_campaign_attributions;
create trigger crm_campaign_attributions_append_only before update or delete on public.crm_campaign_attributions
for each row execute function public.crm_reject_append_only_mutation();
drop trigger if exists crm_campaign_costs_append_only on public.crm_campaign_costs;
create trigger crm_campaign_costs_append_only before update or delete on public.crm_campaign_costs
for each row execute function public.crm_reject_append_only_mutation();

do $$
declare t text;
begin
  foreach t in array array[
    'crm_loyalty_earning_rules','crm_financial_close_projections',
    'crm_campaign_outbox','crm_campaign_provider_events','crm_campaign_attributions',
    'crm_campaign_costs'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists service_role_only on public.%I',t);
    execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
    execute format('revoke all on public.%I from anon,authenticated',t);
    execute format('grant select,insert,update,delete on public.%I to service_role',t);
  end loop;
end $$;

-- Provider configuration is a secret-name reference only. A real provider
-- adapter must be explicitly approved before campaign outbox can be queued.
create table if not exists public.crm_campaign_provider_configs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  provider_id text not null check(length(btrim(provider_id)) between 2 and 100),
  channel text not null check(channel in ('email','sms','whatsapp')),
  credential_secret_reference text not null check(credential_secret_reference ~ '^[A-Z][A-Z0-9_]{2,119}$'),
  status text not null default 'pending' check(status in ('pending','active','suspended','revoked')),
  created_by uuid not null references auth.users(id) on delete restrict,
  approved_by uuid null references auth.users(id) on delete restrict,
  approved_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,provider_id,channel),
  check(status<>'active' or (approved_by is not null and approved_at is not null and approved_by<>created_by))
);

create or replace function public.crm_approve_campaign_provider_config(
  p_tenant_id uuid,p_config_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.crm_campaign_provider_configs%rowtype;
begin
  select * into v from public.crm_campaign_provider_configs
   where tenant_id=p_tenant_id and id=p_config_id for update;
  if not found then raise exception using errcode='P0002',message='CRM_CAMPAIGN_PROVIDER_CONFIG_NOT_FOUND'; end if;
  if v.status<>'pending' then raise exception using errcode='23514',message='CRM_CAMPAIGN_PROVIDER_CONFIG_NOT_PENDING'; end if;
  if v.created_by=p_actor_user_id then raise exception using errcode='42501',message='INDEPENDENT_CAMPAIGN_PROVIDER_APPROVER_REQUIRED'; end if;
  update public.crm_campaign_provider_configs set status='active',approved_by=p_actor_user_id,
   approved_at=now(),updated_at=now() where id=p_config_id returning * into v;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'crm.campaign.provider_config_approved','crm_campaign_provider_configs',v.id::text,
   jsonb_build_object('tenant_id',p_tenant_id,'provider_id',v.provider_id,'channel',v.channel,
    'credential_secret_reference',v.credential_secret_reference));
  return jsonb_build_object('config_id',v.id,'provider_id',v.provider_id,'channel',v.channel,'status',v.status);
end $$;
revoke all on function public.crm_approve_campaign_provider_config(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.crm_approve_campaign_provider_config(uuid,uuid,uuid) to service_role;

-- Convert consent-filtered recipients into durable provider-neutral outbox
-- rows. No network call occurs in this database function.
create or replace function public.crm_queue_campaign_outbox(
 p_tenant_id uuid,p_campaign_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_campaign public.crm_marketing_campaigns%rowtype;
 v_provider public.crm_campaign_provider_configs%rowtype; v_count integer;
begin
 select * into v_campaign from public.crm_marketing_campaigns
  where tenant_id=p_tenant_id and id=p_campaign_id for update;
 if not found then raise exception using errcode='P0002',message='CRM_CAMPAIGN_NOT_FOUND'; end if;
 if v_campaign.status not in ('audience_prepared','queued','sending') then
  raise exception using errcode='23514',message='CRM_CAMPAIGN_AUDIENCE_NOT_PREPARED';
 end if;
 select * into v_provider from public.crm_campaign_provider_configs
  where tenant_id=p_tenant_id and channel=v_campaign.channel and status='active'
  order by approved_at desc limit 1;
 if not found then raise exception using errcode='23514',message='APPROVED_CAMPAIGN_PROVIDER_REQUIRED'; end if;
 insert into public.crm_campaign_outbox(
  tenant_id,campaign_id,recipient_id,provider_id,channel,destination_snapshot,
  rendered_payload,status,attempts,next_attempt_at,idempotency_key
 )
 select r.tenant_id,r.campaign_id,r.id,v_provider.provider_id,v_campaign.channel,
  r.destination_snapshot,
  jsonb_build_object('campaign_id',v_campaign.id,'channel',v_campaign.channel,
   'subject',v_campaign.subject,'message',v_campaign.message_template,
   'recipient_id',r.id,'customer_id',r.customer_id),
  'queued',0,now(),v_campaign.id::text||':'||r.id::text
 from public.crm_campaign_recipients r
 where r.tenant_id=p_tenant_id and r.campaign_id=p_campaign_id and r.status='queued'
 on conflict(tenant_id,idempotency_key) do nothing;
 get diagnostics v_count=row_count;
 update public.crm_marketing_campaigns set status='queued',updated_at=now() where id=p_campaign_id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'crm.campaign.outbox_queued','crm_marketing_campaign',p_campaign_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'queued_count',v_count,'provider_id',v_provider.provider_id));
 return jsonb_build_object('campaign_id',p_campaign_id,'queued_count',v_count,'provider_id',v_provider.provider_id);
end $$;
revoke all on function public.crm_queue_campaign_outbox(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.crm_queue_campaign_outbox(uuid,uuid,uuid) to service_role;

-- Atomic worker claim with SKIP LOCKED prevents two workers from sending
-- the same outbox row. Provider delivery is performed outside this transaction.
create or replace function public.crm_claim_campaign_outbox(
 p_tenant_id uuid,p_provider_id text,p_limit integer
) returns setof public.crm_campaign_outbox
language plpgsql security invoker set search_path=''
as $$
begin
 if p_limit<1 or p_limit>100 then raise exception using errcode='22023',message='INVALID_CAMPAIGN_CLAIM_LIMIT'; end if;
 return query
 with picked as (
  select id from public.crm_campaign_outbox
  where tenant_id=p_tenant_id and provider_id=p_provider_id
   and status in ('queued','failed') and coalesce(next_attempt_at,now())<=now()
   and exists(select 1 from public.crm_campaign_provider_configs c
    where c.tenant_id=p_tenant_id and c.provider_id=p_provider_id
     and c.channel=public.crm_campaign_outbox.channel and c.status='active')
  order by created_at,id for update skip locked limit p_limit
 )
 update public.crm_campaign_outbox o set status='claimed',attempts=o.attempts+1,updated_at=now()
 from picked where o.id=picked.id returning o.*;
end $$;
revoke all on function public.crm_claim_campaign_outbox(uuid,text,integer) from public,anon,authenticated;
grant execute on function public.crm_claim_campaign_outbox(uuid,text,integer) to service_role;

create or replace function public.crm_finalize_campaign_outbox(
 p_tenant_id uuid,p_outbox_id uuid,p_status text,p_provider_message_id text,
 p_error_code text,p_max_attempts integer default 5
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.crm_campaign_outbox%rowtype; v_next text;
begin
 select * into v from public.crm_campaign_outbox where tenant_id=p_tenant_id and id=p_outbox_id for update;
 if not found then raise exception using errcode='P0002',message='CRM_CAMPAIGN_OUTBOX_NOT_FOUND'; end if;
 if v.status<>'claimed' then raise exception using errcode='23514',message='CRM_CAMPAIGN_OUTBOX_NOT_CLAIMED'; end if;
 if p_status='accepted' and length(btrim(coalesce(p_provider_message_id,'')))>0 then
  update public.crm_campaign_outbox set status='accepted',provider_message_id=p_provider_message_id,
   last_error_code=null,updated_at=now() where id=p_outbox_id returning * into v;
  update public.crm_campaign_recipients set status='sent',provider_message_id=p_provider_message_id,
   attempted_at=now() where tenant_id=p_tenant_id and id=v.recipient_id;
 elsif p_status='failed' then
  v_next:=case when v.attempts>=p_max_attempts then 'dead_letter' else 'failed' end;
  update public.crm_campaign_outbox set status=v_next,last_error_code=left(coalesce(p_error_code,'PROVIDER_SEND_FAILED'),100),
   next_attempt_at=case when v_next='failed' then now()+make_interval(secs=>least(3600,power(2,least(v.attempts,10))::integer*15)) else null end,
   updated_at=now() where id=p_outbox_id returning * into v;
  update public.crm_campaign_recipients set status='failed',failure_reason=v.last_error_code,
   attempted_at=now() where tenant_id=p_tenant_id and id=v.recipient_id;
 else
  raise exception using errcode='22023',message='INVALID_CAMPAIGN_OUTBOX_RESULT';
 end if;
 return jsonb_build_object('outbox_id',v.id,'status',v.status,'attempts',v.attempts,
  'provider_message_id',v.provider_message_id,'next_attempt_at',v.next_attempt_at);
end $$;
revoke all on function public.crm_finalize_campaign_outbox(uuid,uuid,text,text,text,integer) from public,anon,authenticated;
grant execute on function public.crm_finalize_campaign_outbox(uuid,uuid,text,text,text,integer) to service_role;

alter table public.crm_campaign_provider_configs enable row level security;
drop policy if exists service_role_only on public.crm_campaign_provider_configs;
create policy service_role_only on public.crm_campaign_provider_configs for all to service_role using(true) with check(true);
revoke all on public.crm_campaign_provider_configs from anon,authenticated;
grant select,insert,update,delete on public.crm_campaign_provider_configs to service_role;


-- Apply a provider receipt only after a provider-specific Edge adapter has
-- verified its signature over the exact raw request bytes and tenant mapping.
-- Event insertion, outbox transition and recipient transition are atomic.
create or replace function public.crm_apply_campaign_provider_receipt(
 p_tenant_id uuid,p_provider_id text,p_provider_event_id text,
 p_provider_message_id text,p_event_kind text,p_body_sha256 text,
 p_occurred_at timestamptz,p_payload jsonb
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_existing public.crm_campaign_provider_events%rowtype;
 v_event public.crm_campaign_provider_events%rowtype;
 v_outbox public.crm_campaign_outbox%rowtype;
 v_next text;
begin
 if length(btrim(coalesce(p_provider_id,'')))<2 or
    length(btrim(coalesce(p_provider_event_id,'')))<1 or
    length(btrim(coalesce(p_provider_message_id,'')))<1 or
    p_event_kind not in ('accepted','delivered','bounced','failed') or
    p_body_sha256 !~ '^[0-9a-f]{64}$' or p_occurred_at is null or
    jsonb_typeof(p_payload)<>'object' then
  raise exception using errcode='22023',message='INVALID_CAMPAIGN_PROVIDER_RECEIPT';
 end if;
 select * into v_existing from public.crm_campaign_provider_events
  where provider_id=p_provider_id and provider_event_id=p_provider_event_id for update;
 if found then
  if v_existing.tenant_id<>p_tenant_id or v_existing.body_sha256<>p_body_sha256 then
   raise exception using errcode='23505',message='CAMPAIGN_PROVIDER_EVENT_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','event_id',v_existing.id);
 end if;
 select * into v_outbox from public.crm_campaign_outbox
  where tenant_id=p_tenant_id and provider_id=p_provider_id
   and provider_message_id=p_provider_message_id for update;
 if not found then raise exception using errcode='P0002',message='CAMPAIGN_OUTBOX_MESSAGE_NOT_FOUND'; end if;
 if v_outbox.status not in ('accepted','delivered','failed') then
  raise exception using errcode='23514',message='CAMPAIGN_OUTBOX_NOT_ACCEPTED';
 end if;
 insert into public.crm_campaign_provider_events(
  tenant_id,provider_id,provider_event_id,provider_message_id,event_kind,
  body_sha256,occurred_at,payload
 ) values(p_tenant_id,p_provider_id,p_provider_event_id,p_provider_message_id,
  p_event_kind,p_body_sha256,p_occurred_at,p_payload)
 returning * into v_event;
 v_next:=case p_event_kind
  when 'delivered' then 'delivered'
  when 'bounced' then 'failed'
  when 'failed' then 'failed'
  else v_outbox.status end;
 update public.crm_campaign_outbox set status=v_next,updated_at=now(),
  last_error_code=case when p_event_kind in ('bounced','failed') then 'PROVIDER_'||upper(p_event_kind) else null end
  where id=v_outbox.id;
 update public.crm_campaign_recipients set
  status=case when p_event_kind='delivered' then 'delivered'
              when p_event_kind in ('bounced','failed') then 'failed'
              else status end,
  delivered_at=case when p_event_kind='delivered' then p_occurred_at else delivered_at end,
  failure_reason=case when p_event_kind in ('bounced','failed') then 'PROVIDER_'||upper(p_event_kind) else failure_reason end
  where tenant_id=p_tenant_id and id=v_outbox.recipient_id;
 return jsonb_build_object('status','applied','event_id',v_event.id,
  'outbox_id',v_outbox.id,'delivery_status',v_next);
end $$;
revoke all on function public.crm_apply_campaign_provider_receipt(uuid,text,text,text,text,text,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.crm_apply_campaign_provider_receipt(uuid,text,text,text,text,text,timestamptz,jsonb) to service_role;


-- Build a financial-close projection from the real POS/Order, settlement,
-- refund, shift-cash and Finance journal records. No caller-supplied totals or
-- evidence JSON are trusted. All reads and the immutable snapshot insert are
-- in one transaction; missing/ambiguous source evidence fails closed.
create or replace function public.crm_build_financial_close_projection(
 p_tenant_id uuid,p_branch_id uuid,p_source_type text,p_source_id uuid,p_actor_user_id uuid
) returns jsonb
language plpgsql security invoker set search_path=''
as $$
declare
 v_subtotal bigint; v_discount bigint:=0; v_gross bigint;
 v_refunds bigint:=0; v_paid bigint:=0; v_settled bigint:=0;
 v_payment_ids uuid[]:='{}'; v_settlement_ids uuid[]:='{}';
 v_payment_method text; v_settlement_status text:='matched';
 v_journal_ids uuid[]:='{}'; v_refund_ids uuid[]:='{}';
 v_refund_evidence jsonb:='[]'::jsonb; v_snapshot jsonb;
 v_hash text; v_cash_id uuid; v_cash_status text:='not_required';
 v_branch_tenant uuid; v_existing public.crm_financial_close_projections%rowtype;
 v_ref record; v_count integer; v_finance_total bigint; v_refund_finance bigint;
 v_order_payment_count integer;
begin
 if p_tenant_id is null or p_branch_id is null or p_source_id is null
   or p_source_type not in ('pos_sale','online_order') or p_actor_user_id is null then
  raise exception using errcode='22023',message='INVALID_CRM_FINANCIAL_CLOSE_COMMAND';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_source_type||':'||p_source_id::text,0));
 select tenant_id into v_branch_tenant from public.branches where id=p_branch_id;
 if v_branch_tenant is distinct from p_tenant_id then
  raise exception using errcode='42501',message='CRM_FINANCIAL_CLOSE_TENANT_BRANCH_MISMATCH';
 end if;

 if p_source_type='pos_sale' then
  select subtotal_idr,discount_idr,total_idr,payment_method into v_subtotal,v_discount,v_gross,v_payment_method
   from public.pos_sales where id=p_source_id and branch_id=p_branch_id and payment_status='paid';
  if not found then raise exception using errcode='P0002',message='PAID_POS_SALE_NOT_FOUND'; end if;
  select id,status into v_cash_id,v_cash_status from public.cash_reconciliations
   where branch_id=p_branch_id and shift_id=(select shift_id from public.pos_sales where id=p_source_id)
     and status='approved' and reviewed_by is not null and reviewed_at is not null
   order by created_at desc limit 1 for share;
  if v_cash_id is null or v_cash_status<>'approved' then
   raise exception using errcode='23514',message='APPROVED_SHIFT_CASH_RECONCILIATION_REQUIRED';
  end if;
  v_paid:=v_gross;
 else
  select product_subtotal_idr into v_subtotal from public.orders
   where id=p_source_id and branch_id=p_branch_id and payment_status='paid' and currency='IDR';
  if not found then raise exception using errcode='P0002',message='PAID_ONLINE_ORDER_NOT_FOUND'; end if;
  select coalesce(array_agg(id order by id),'{}'::uuid[]),count(*),coalesce(sum(amount_idr),0)
   into v_payment_ids,v_order_payment_count,v_paid
   from public.payment_records where order_id=p_source_id and status='paid';
  if v_order_payment_count=0 or v_paid<>v_subtotal then
   raise exception using errcode='23514',message='PAID_ORDER_PAYMENT_RECORDS_DO_NOT_RECONCILE';
  end if;
  v_gross:=v_paid;
 end if;

 -- Cash POS is reconciled by the approved shift cash count. Bank/QRIS POS
 -- must match provider settlement items; split tender remains blocked until
 -- its cash/provider allocation is represented explicitly.
 if p_source_type='pos_sale' and v_payment_method='cash' then
  v_settled:=v_paid;
  v_settlement_status:='cash_reconciled';
 elsif p_source_type='pos_sale' and v_payment_method='split' then
  raise exception using errcode='23514',message='POS_SPLIT_TENDER_ALLOCATION_EVIDENCE_REQUIRED';
 elsif p_source_type='pos_sale' then
  select coalesce(array_agg(distinct ps.id order by ps.id),'{}'::uuid[]),
         coalesce(sum(psi.amount_idr),0)
   into v_settlement_ids,v_settled
   from public.payment_settlement_items psi
   join public.payment_settlements ps on ps.id=psi.settlement_id
   where psi.pos_sale_id=p_source_id and ps.status='matched'
     and ps.received_amount_idr=ps.net_amount_idr and ps.reconciled_by is not null and ps.reconciled_at is not null;
  if exists(select 1 from public.payment_settlement_items psi
    join public.payment_settlements ps on ps.id=psi.settlement_id
    where psi.pos_sale_id=p_source_id and
      (ps.status<>'matched' or ps.received_amount_idr is distinct from ps.net_amount_idr or ps.reconciled_by is null or ps.reconciled_at is null)) then
   raise exception using errcode='23514',message='POS_SETTLEMENT_BATCH_NOT_RECONCILED';
  end if;
 else
  select coalesce(array_agg(distinct ps.id order by ps.id),'{}'::uuid[]),
         coalesce(sum(psi.amount_idr),0)
   into v_settlement_ids,v_settled
   from public.payment_settlement_items psi
   join public.payment_settlements ps on ps.id=psi.settlement_id
   where psi.payment_record_id=any(v_payment_ids) and ps.status='matched'
     and ps.received_amount_idr=ps.net_amount_idr and ps.reconciled_by is not null and ps.reconciled_at is not null;
  if exists(select 1 from public.payment_settlement_items psi
    join public.payment_settlements ps on ps.id=psi.settlement_id
    where psi.payment_record_id=any(v_payment_ids) and
      (ps.status<>'matched' or ps.received_amount_idr is distinct from ps.net_amount_idr or ps.reconciled_by is null or ps.reconciled_at is null)) then
   raise exception using errcode='23514',message='ORDER_SETTLEMENT_BATCH_NOT_RECONCILED';
  end if;
 end if;
 if (v_settlement_status='matched' and cardinality(v_settlement_ids)=0) or v_settled<>v_paid then
  raise exception using errcode='23514',message='SETTLEMENT_ITEMS_DO_NOT_RECONCILE_TO_SOURCE_PAYMENT';
 end if;

 -- Processed refunds only reduce eligible sales. An unresolved refund blocks
 -- the close rather than allowing points to be awarded prematurely.
 if p_source_type='pos_sale' then
  if exists(select 1 from public.refund_records where pos_sale_id=p_source_id and status='processed'
    and (processed_by is null or processed_at is null)) then
   raise exception using errcode='23514',message='PROCESSED_POS_REFUND_AUDIT_EVIDENCE_MISSING';
  end if;
  if exists(select 1 from public.refund_records where pos_sale_id=p_source_id
    and status in ('requested','approved')) then
   raise exception using errcode='23514',message='POS_REFUND_REVIEW_STILL_OPEN';
  end if;
  select coalesce(sum(amount_idr),0),coalesce(array_agg(id order by id),'{}'::uuid[])
   into v_refunds,v_refund_ids from public.refund_records
   where pos_sale_id=p_source_id and branch_id=p_branch_id and status='processed' and processed_by is not null and processed_at is not null;
 else
  if exists(select 1 from public.refund_records r
    where (r.order_id=p_source_id or r.payment_record_id=any(v_payment_ids)) and r.status='processed'
      and (r.processed_by is null or r.processed_at is null)) then
   raise exception using errcode='23514',message='PROCESSED_ORDER_REFUND_AUDIT_EVIDENCE_MISSING';
  end if;
  if exists(select 1 from public.refund_records r
    where (r.order_id=p_source_id or r.payment_record_id=any(v_payment_ids))
      and r.status in ('requested','approved')) then
   raise exception using errcode='23514',message='ORDER_REFUND_REVIEW_STILL_OPEN';
  end if;
  select coalesce(sum(amount_idr),0),coalesce(array_agg(id order by id),'{}'::uuid[])
   into v_refunds,v_refund_ids from public.refund_records
   where (order_id=p_source_id or payment_record_id=any(v_payment_ids))
     and branch_id=p_branch_id and status='processed' and processed_by is not null and processed_at is not null;
 end if;
 if v_refunds>v_gross-v_discount then
  raise exception using errcode='23514',message='PROCESSED_REFUNDS_EXCEED_PAID_SOURCE';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'amountIdr',amount_idr,'status',status,
   'processedAt',processed_at) order by id),'[]'::jsonb)
  into v_refund_evidence from public.refund_records where id=any(v_refund_ids);

 -- Finance entries must be posted against the actual source IDs. Refunds must
 -- each have their own posted journal source; no arbitrary caller hash can
 -- stand in for journal evidence.
 if p_source_type='pos_sale' then
  select coalesce(array_agg(id order by id),'{}'::uuid[]),coalesce(sum(amount_idr),0),count(*)
   into v_journal_ids,v_finance_total,v_count
   from public.finance_journal_entries
   where branch_id=p_branch_id and source_id=p_source_id and status='posted';
 else
  select coalesce(array_agg(id order by id),'{}'::uuid[]),coalesce(sum(amount_idr),0),count(*)
   into v_journal_ids,v_finance_total,v_count
   from public.finance_journal_entries
   where branch_id=p_branch_id and (source_id=p_source_id or source_id=any(v_payment_ids)) and status='posted';
 end if;
 if v_count=0 or v_finance_total<>v_gross then
  raise exception using errcode='23514',message='POSTED_FINANCE_SOURCE_JOURNAL_DOES_NOT_RECONCILE';
 end if;
 for v_ref in select id,amount_idr from public.refund_records where id=any(v_refund_ids) order by id loop
  select coalesce(array_agg(id order by id),'{}'::uuid[]),coalesce(sum(amount_idr),0),count(*)
   into v_journal_ids,v_refund_finance,v_count
   from public.finance_journal_entries
   where branch_id=p_branch_id and source_id=v_ref.id and status='posted';
  if v_count=0 or v_refund_finance<>v_ref.amount_idr then
   raise exception using errcode='23514',message='PROCESSED_REFUND_FINANCE_JOURNAL_DOES_NOT_RECONCILE';
  end if;
  -- v_journal_ids is expanded below from all source/refund ids in snapshot.
 end loop;

 -- Rebuild complete immutable journal ID set, including each refund posting.
 if p_source_type='pos_sale' then
  select coalesce(array_agg(id order by id),'{}'::uuid[]) into v_journal_ids
   from public.finance_journal_entries
   where branch_id=p_branch_id and status='posted'
     and (source_id=p_source_id or source_id=any(v_refund_ids));
 else
  select coalesce(array_agg(id order by id),'{}'::uuid[]) into v_journal_ids
   from public.finance_journal_entries
   where branch_id=p_branch_id and status='posted'
     and (source_id=p_source_id or source_id=any(v_payment_ids) or source_id=any(v_refund_ids));
 end if;

 v_snapshot:=jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,
  'source_type',p_source_type,'source_id',p_source_id,'payment_record_ids',v_payment_ids,
  'settlement_ids',v_settlement_ids,'finance_journal_entry_ids',v_journal_ids,
  'refund_ids',v_refund_ids,'subtotal_idr',v_subtotal,'discount_idr',v_discount,
  'processed_refunds_idr',v_refunds,'paid_amount_idr',v_paid,'settled_amount_idr',v_settled,
  'cash_reconciliation_id',v_cash_id,'cash_reconciliation_status',v_cash_status,
  'payment_method',v_payment_method,'settlement_reconciliation_status',v_settlement_status,
  'refund_evidence',v_refund_evidence);
 v_hash:=encode(pg_catalog.sha256(convert_to(v_snapshot::text,'UTF8')),'hex');

 select * into v_existing from public.crm_financial_close_projections
  where tenant_id=p_tenant_id and source_type=p_source_type and source_id=p_source_id
    and source_snapshot_sha256=v_hash for update;
 if found then
  return jsonb_build_object('status','duplicate','projection_id',v_existing.id,
    'source_snapshot_sha256',v_hash,'eligible_net_sales_idr',v_subtotal-v_discount-v_refunds);
 end if;

 insert into public.crm_financial_close_projections(
  tenant_id,branch_id,source_type,source_id,shift_reconciliation_id,
  settlement_reconciliation_id,settlement_ids,finance_journal_entry_ids,currency,
  subtotal_idr,discount_idr,processed_refunds_idr,refund_evidence,
  shift_reconciliation_status,settlement_reconciliation_status,
  finance_journal_status,finance_source_reconciliation_status,status,
  source_snapshot_sha256,reconciled_at
 ) values(
  p_tenant_id,p_branch_id,p_source_type,p_source_id,v_cash_id,
  (v_settlement_ids)[1],v_settlement_ids,v_journal_ids,'IDR',
  v_subtotal,v_discount,v_refunds,v_refund_evidence,
  v_cash_status,v_settlement_status,'posted','reconciled','reconciled',v_hash,now()
 ) returning * into v_existing;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'crm.financial_close.projected','crm_financial_close_projections',v_existing.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'source_type',p_source_type,
   'source_id',p_source_id,'source_snapshot_sha256',v_hash,'settlement_ids',v_settlement_ids,
   'finance_journal_entry_ids',v_journal_ids,'processed_refunds_idr',v_refunds));
 return jsonb_build_object('status','reconciled','projection_id',v_existing.id,
  'source_snapshot_sha256',v_hash,'eligible_net_sales_idr',v_subtotal-v_discount-v_refunds,
  'settlement_ids',v_settlement_ids,'finance_journal_entry_ids',v_journal_ids);
end;
$$;
revoke all on function public.crm_build_financial_close_projection(uuid,uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.crm_build_financial_close_projection(uuid,uuid,text,uuid,uuid) to service_role;

alter table public.crm_financial_close_projections
 add column if not exists payment_record_ids uuid[] not null default '{}',
 add column if not exists paid_amount_idr bigint not null default 0,
 add column if not exists created_by uuid references auth.users(id) on delete restrict,
 add column if not exists reviewed_by uuid references auth.users(id) on delete restrict,
 add column if not exists reviewed_at timestamptz,
 add column if not exists finance_reconciliation_sha256 text check(finance_reconciliation_sha256 is null or finance_reconciliation_sha256 ~ '^[0-9a-f]{64}$');
alter table public.crm_financial_close_projections
 drop constraint if exists crm_financial_close_projections_finance_source_reconciliation_status_check;
alter table public.crm_financial_close_projections
 add constraint crm_financial_close_projections_finance_source_reconciliation_status_check
 check(finance_source_reconciliation_status in ('pending','reconciled'));
alter table public.crm_financial_close_projections
 drop constraint if exists crm_financial_close_projections_status_check;
alter table public.crm_financial_close_projections
 add constraint crm_financial_close_projections_status_check
 check(status in ('pending_finance_review','reconciled','superseded'));
alter table public.crm_financial_close_projections
 add constraint crm_financial_close_projections_review_trace_check
 check(status<>'reconciled' or (created_by is not null and reviewed_by is not null
   and reviewed_at is not null and reviewed_by<>created_by
   and finance_reconciliation_sha256 is not null
   and finance_source_reconciliation_status='reconciled'));

create or replace function public.crm_build_financial_close_projection(
 p_tenant_id uuid,p_branch_id uuid,p_source_type text,p_source_id uuid,p_actor_user_id uuid
) returns jsonb
language plpgsql security invoker set search_path=''
as $$
declare
 v_subtotal bigint; v_discount bigint:=0; v_gross bigint;
 v_refunds bigint:=0; v_paid bigint:=0; v_settled bigint:=0;
 v_payment_ids uuid[]:='{}'; v_settlement_ids uuid[]:='{}';
 v_payment_method text; v_settlement_status text:='matched';
 v_journal_ids uuid[]:='{}'; v_refund_ids uuid[]:='{}';
 v_refund_evidence jsonb:='[]'::jsonb; v_snapshot jsonb;
 v_hash text; v_cash_id uuid; v_cash_status text:='not_required';
 v_branch_tenant uuid; v_existing public.crm_financial_close_projections%rowtype;
 v_ref record; v_count integer; v_finance_total bigint; v_refund_finance bigint;
 v_order_payment_count integer;
begin
 if p_tenant_id is null or p_branch_id is null or p_source_id is null
   or p_source_type not in ('pos_sale','online_order') or p_actor_user_id is null then
  raise exception using errcode='22023',message='INVALID_CRM_FINANCIAL_CLOSE_COMMAND';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_source_type||':'||p_source_id::text,0));
 select tenant_id into v_branch_tenant from public.branches where id=p_branch_id;
 if v_branch_tenant is distinct from p_tenant_id then
  raise exception using errcode='42501',message='CRM_FINANCIAL_CLOSE_TENANT_BRANCH_MISMATCH';
 end if;

 if p_source_type='pos_sale' then
  select subtotal_idr,discount_idr,total_idr,payment_method into v_subtotal,v_discount,v_gross,v_payment_method
   from public.pos_sales where id=p_source_id and branch_id=p_branch_id and payment_status='paid';
  if not found then raise exception using errcode='P0002',message='PAID_POS_SALE_NOT_FOUND'; end if;
  select id,status into v_cash_id,v_cash_status from public.cash_reconciliations
   where branch_id=p_branch_id and shift_id=(select shift_id from public.pos_sales where id=p_source_id)
     and status='approved' and reviewed_by is not null and reviewed_at is not null
   order by created_at desc limit 1 for share;
  if v_cash_id is null or v_cash_status<>'approved' then
   raise exception using errcode='23514',message='APPROVED_SHIFT_CASH_RECONCILIATION_REQUIRED';
  end if;
  v_paid:=v_gross;
 else
  select product_subtotal_idr into v_subtotal from public.orders
   where id=p_source_id and branch_id=p_branch_id and payment_status='paid' and currency='IDR';
  if not found then raise exception using errcode='P0002',message='PAID_ONLINE_ORDER_NOT_FOUND'; end if;
  select coalesce(array_agg(id order by id),'{}'::uuid[]),count(*),coalesce(sum(amount_idr),0)
   into v_payment_ids,v_order_payment_count,v_paid
   from public.payment_records where order_id=p_source_id and status='paid';
  if v_order_payment_count=0 or v_paid<>v_subtotal then
   raise exception using errcode='23514',message='PAID_ORDER_PAYMENT_RECORDS_DO_NOT_RECONCILE';
  end if;
  v_gross:=v_paid;
 end if;

 -- Cash POS is reconciled by the approved shift cash count. Bank/QRIS POS
 -- must match provider settlement items; split tender remains blocked until
 -- its cash/provider allocation is represented explicitly.
 if p_source_type='pos_sale' and v_payment_method='cash' then
  v_settled:=v_paid;
  v_settlement_status:='cash_reconciled';
 elsif p_source_type='pos_sale' and v_payment_method='split' then
  raise exception using errcode='23514',message='POS_SPLIT_TENDER_ALLOCATION_EVIDENCE_REQUIRED';
 elsif p_source_type='pos_sale' then
  select coalesce(array_agg(distinct ps.id order by ps.id),'{}'::uuid[]),
         coalesce(sum(psi.amount_idr),0)
   into v_settlement_ids,v_settled
   from public.payment_settlement_items psi
   join public.payment_settlements ps on ps.id=psi.settlement_id
   where psi.pos_sale_id=p_source_id and ps.status='matched'
     and ps.received_amount_idr=ps.net_amount_idr and ps.reconciled_by is not null and ps.reconciled_at is not null;
  if exists(select 1 from public.payment_settlement_items psi
    join public.payment_settlements ps on ps.id=psi.settlement_id
    where psi.pos_sale_id=p_source_id and
      (ps.status<>'matched' or ps.received_amount_idr is distinct from ps.net_amount_idr or ps.reconciled_by is null or ps.reconciled_at is null)) then
   raise exception using errcode='23514',message='POS_SETTLEMENT_BATCH_NOT_RECONCILED';
  end if;
 else
  select coalesce(array_agg(distinct ps.id order by ps.id),'{}'::uuid[]),
         coalesce(sum(psi.amount_idr),0)
   into v_settlement_ids,v_settled
   from public.payment_settlement_items psi
   join public.payment_settlements ps on ps.id=psi.settlement_id
   where psi.payment_record_id=any(v_payment_ids) and ps.status='matched'
     and ps.received_amount_idr=ps.net_amount_idr and ps.reconciled_by is not null and ps.reconciled_at is not null;
  if exists(select 1 from public.payment_settlement_items psi
    join public.payment_settlements ps on ps.id=psi.settlement_id
    where psi.payment_record_id=any(v_payment_ids) and
      (ps.status<>'matched' or ps.received_amount_idr is distinct from ps.net_amount_idr or ps.reconciled_by is null or ps.reconciled_at is null)) then
   raise exception using errcode='23514',message='ORDER_SETTLEMENT_BATCH_NOT_RECONCILED';
  end if;
 end if;
 if (v_settlement_status='matched' and cardinality(v_settlement_ids)=0) or v_settled<>v_paid then
  raise exception using errcode='23514',message='SETTLEMENT_ITEMS_DO_NOT_RECONCILE_TO_SOURCE_PAYMENT';
 end if;

 -- Processed refunds only reduce eligible sales. An unresolved refund blocks
 -- the close rather than allowing points to be awarded prematurely.
 if p_source_type='pos_sale' then
  if exists(select 1 from public.refund_records where pos_sale_id=p_source_id and status='processed'
    and (processed_by is null or processed_at is null)) then
   raise exception using errcode='23514',message='PROCESSED_POS_REFUND_AUDIT_EVIDENCE_MISSING';
  end if;
  if exists(select 1 from public.refund_records where pos_sale_id=p_source_id
    and status in ('requested','approved')) then
   raise exception using errcode='23514',message='POS_REFUND_REVIEW_STILL_OPEN';
  end if;
  select coalesce(sum(amount_idr),0),coalesce(array_agg(id order by id),'{}'::uuid[])
   into v_refunds,v_refund_ids from public.refund_records
   where pos_sale_id=p_source_id and branch_id=p_branch_id and status='processed' and processed_by is not null and processed_at is not null;
 else
  if exists(select 1 from public.refund_records r
    where (r.order_id=p_source_id or r.payment_record_id=any(v_payment_ids)) and r.status='processed'
      and (r.processed_by is null or r.processed_at is null)) then
   raise exception using errcode='23514',message='PROCESSED_ORDER_REFUND_AUDIT_EVIDENCE_MISSING';
  end if;
  if exists(select 1 from public.refund_records r
    where (r.order_id=p_source_id or r.payment_record_id=any(v_payment_ids))
      and r.status in ('requested','approved')) then
   raise exception using errcode='23514',message='ORDER_REFUND_REVIEW_STILL_OPEN';
  end if;
  select coalesce(sum(amount_idr),0),coalesce(array_agg(id order by id),'{}'::uuid[])
   into v_refunds,v_refund_ids from public.refund_records
   where (order_id=p_source_id or payment_record_id=any(v_payment_ids))
     and branch_id=p_branch_id and status='processed' and processed_by is not null and processed_at is not null;
 end if;
 if v_refunds>v_gross-v_discount then
  raise exception using errcode='23514',message='PROCESSED_REFUNDS_EXCEED_PAID_SOURCE';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'amountIdr',amount_idr,'status',status,
   'processedAt',processed_at) order by id),'[]'::jsonb)
  into v_refund_evidence from public.refund_records where id=any(v_refund_ids);

 -- Finance entries must be posted against the actual source IDs. Refunds must
 -- each have their own posted journal source; no arbitrary caller hash can
 -- stand in for journal evidence.
 if p_source_type='pos_sale' then
  select coalesce(array_agg(id order by id),'{}'::uuid[]),coalesce(sum(amount_idr),0),count(*)
   into v_journal_ids,v_finance_total,v_count
   from public.finance_journal_entries
   where branch_id=p_branch_id and source_id=p_source_id and status='posted';
 else
  select coalesce(array_agg(id order by id),'{}'::uuid[]),coalesce(sum(amount_idr),0),count(*)
   into v_journal_ids,v_finance_total,v_count
   from public.finance_journal_entries
   where branch_id=p_branch_id and (source_id=p_source_id or source_id=any(v_payment_ids)) and status='posted';
 end if;
 if v_count=0 or v_finance_total<>v_gross then
  raise exception using errcode='23514',message='POSTED_FINANCE_SOURCE_JOURNAL_DOES_NOT_RECONCILE';
 end if;
 for v_ref in select id,amount_idr from public.refund_records where id=any(v_refund_ids) order by id loop
  select coalesce(array_agg(id order by id),'{}'::uuid[]),coalesce(sum(amount_idr),0),count(*)
   into v_journal_ids,v_refund_finance,v_count
   from public.finance_journal_entries
   where branch_id=p_branch_id and source_id=v_ref.id and status='posted';
  if v_count=0 or v_refund_finance<>v_ref.amount_idr then
   raise exception using errcode='23514',message='PROCESSED_REFUND_FINANCE_JOURNAL_DOES_NOT_RECONCILE';
  end if;
  -- v_journal_ids is expanded below from all source/refund ids in snapshot.
 end loop;

 -- Rebuild complete immutable journal ID set, including each refund posting.
 if p_source_type='pos_sale' then
  select coalesce(array_agg(id order by id),'{}'::uuid[]) into v_journal_ids
   from public.finance_journal_entries
   where branch_id=p_branch_id and status='posted'
     and (source_id=p_source_id or source_id=any(v_refund_ids));
 else
  select coalesce(array_agg(id order by id),'{}'::uuid[]) into v_journal_ids
   from public.finance_journal_entries
   where branch_id=p_branch_id and status='posted'
     and (source_id=p_source_id or source_id=any(v_payment_ids) or source_id=any(v_refund_ids));
 end if;

 v_snapshot:=jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,
  'source_type',p_source_type,'source_id',p_source_id,'payment_record_ids',v_payment_ids,
  'settlement_ids',v_settlement_ids,'finance_journal_entry_ids',v_journal_ids,
  'refund_ids',v_refund_ids,'subtotal_idr',v_subtotal,'discount_idr',v_discount,
  'processed_refunds_idr',v_refunds,'paid_amount_idr',v_paid,'settled_amount_idr',v_settled,
  'cash_reconciliation_id',v_cash_id,'cash_reconciliation_status',v_cash_status,
  'payment_method',v_payment_method,'settlement_reconciliation_status',v_settlement_status,
  'refund_evidence',v_refund_evidence);
 v_hash:=encode(pg_catalog.sha256(convert_to(v_snapshot::text,'UTF8')),'hex');

 select * into v_existing from public.crm_financial_close_projections
  where tenant_id=p_tenant_id and source_type=p_source_type and source_id=p_source_id
    and source_snapshot_sha256=v_hash for update;
 if found then
  return jsonb_build_object('status',v_existing.status,'projection_id',v_existing.id,
    'source_snapshot_sha256',v_hash,'eligible_net_sales_idr',v_subtotal-v_discount-v_refunds);
 end if;

 insert into public.crm_financial_close_projections(
  tenant_id,branch_id,source_type,source_id,shift_reconciliation_id,
  settlement_reconciliation_id,settlement_ids,payment_record_ids,finance_journal_entry_ids,
  paid_amount_idr,created_by,currency,subtotal_idr,discount_idr,processed_refunds_idr,refund_evidence,
  shift_reconciliation_status,settlement_reconciliation_status,
  finance_journal_status,finance_source_reconciliation_status,status,
  source_snapshot_sha256,reconciled_at
 ) values(
  p_tenant_id,p_branch_id,p_source_type,p_source_id,v_cash_id,
  (v_settlement_ids)[1],v_settlement_ids,v_payment_ids,v_journal_ids,
  v_paid,p_actor_user_id,'IDR',v_subtotal,v_discount,v_refunds,v_refund_evidence,
  v_cash_status,v_settlement_status,'posted','pending','pending_finance_review',v_hash,now()
 ) returning * into v_existing;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'crm.financial_close.projected','crm_financial_close_projections',v_existing.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'source_type',p_source_type,
   'source_id',p_source_id,'source_snapshot_sha256',v_hash,'settlement_ids',v_settlement_ids,
   'finance_journal_entry_ids',v_journal_ids,'processed_refunds_idr',v_refunds));
 return jsonb_build_object('status','pending_finance_review','projection_id',v_existing.id,
  'source_snapshot_sha256',v_hash,'eligible_net_sales_idr',v_subtotal-v_discount-v_refunds,
  'settlement_ids',v_settlement_ids,'finance_journal_entry_ids',v_journal_ids);
end;
$$;
revoke all on function public.crm_build_financial_close_projection(uuid,uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.crm_build_financial_close_projection(uuid,uuid,text,uuid,uuid) to service_role;

create or replace function public.crm_reconcile_financial_close_projection(
 p_tenant_id uuid,p_projection_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare
 v public.crm_financial_close_projections%rowtype;
 v_ids uuid[]:='{}'; v_total bigint:=0; v_count integer:=0;
 v_ref jsonb; v_ref_id uuid; v_ref_amount bigint; v_ref_total bigint; v_ref_count integer;
 v_hash text;
begin
 select * into v from public.crm_financial_close_projections
  where tenant_id=p_tenant_id and id=p_projection_id for update;
 if not found or v.status<>'pending_finance_review' then
  raise exception using errcode='23514',message='PENDING_CRM_FINANCIAL_CLOSE_REVIEW_REQUIRED';
 end if;
 if p_actor_user_id is null or p_actor_user_id=v.created_by then
  raise exception using errcode='42501',message='INDEPENDENT_FINANCE_CLOSE_REVIEWER_REQUIRED';
 end if;
 if v.settlement_reconciliation_status='matched' and exists(
   select 1 from public.payment_settlements
    where id=any(v.settlement_ids)
      and (status<>'matched' or received_amount_idr is distinct from net_amount_idr)
 ) then
  raise exception using errcode='23514',message='CRM_SETTLEMENT_STATE_CHANGED_AFTER_PROJECTION';
 end if;
 if v.settlement_reconciliation_status='cash_reconciled' and not exists(
   select 1 from public.cash_reconciliations
    where id=v.shift_reconciliation_id and status='approved'
      and cash_counted_idr=cash_expected_idr
      and bank_received_idr=bank_expected_idr
      and qris_received_idr=qris_expected_idr
 ) then
  raise exception using errcode='23514',message='CRM_CASH_RECONCILIATION_STATE_CHANGED';
 end if;
 if exists(
   select 1 from jsonb_array_elements(v.refund_evidence) e
   left join public.refund_records r on r.id=(e->>'id')::uuid
   where r.id is null or r.status<>'processed' or r.amount_idr<>(e->>'amountIdr')::bigint
 ) then
  raise exception using errcode='23514',message='CRM_REFUND_STATE_CHANGED_AFTER_PROJECTION';
 end if;
 if v.source_type='pos_sale' then
  if exists(select 1 from public.refund_records r where r.pos_sale_id=v.source_id and r.status in ('requested','approved'))
    or exists(select 1 from public.refund_records r where r.pos_sale_id=v.source_id and r.status='processed'
      and not exists(select 1 from jsonb_array_elements(v.refund_evidence) e where e->>'id'=r.id::text)) then
   raise exception using errcode='23514',message='CRM_NEW_OR_OPEN_REFUND_AFTER_PROJECTION';
  end if;
  v_ids:=array[v.source_id];
 else
  if exists(select 1 from public.refund_records r
    where (r.order_id=v.source_id or r.payment_record_id=any(v.payment_record_ids))
      and r.status in ('requested','approved'))
    or exists(select 1 from public.refund_records r
      where (r.order_id=v.source_id or r.payment_record_id=any(v.payment_record_ids))
       and r.status='processed'
       and not exists(select 1 from jsonb_array_elements(v.refund_evidence) e where e->>'id'=r.id::text)) then
   raise exception using errcode='23514',message='CRM_NEW_OR_OPEN_REFUND_AFTER_PROJECTION';
  end if;
  v_ids:=array_append(v.payment_record_ids,v.source_id);
 end if;
 select count(*),coalesce(sum(amount_idr),0) into v_count,v_total
  from public.finance_journal_entries
  where branch_id=v.branch_id and status='posted' and source_id=any(v_ids);
 if v_count=0 or v_total<>v.paid_amount_idr then
  raise exception using errcode='23514',message='CRM_SOURCE_FINANCE_JOURNAL_NOT_RECONCILED';
 end if;
 for v_ref in select value from jsonb_array_elements(v.refund_evidence) loop
  v_ref_id:=(v_ref->>'id')::uuid; v_ref_amount:=(v_ref->>'amountIdr')::bigint;
  select count(*),coalesce(sum(amount_idr),0) into v_ref_count,v_ref_total
   from public.finance_journal_entries
   where branch_id=v.branch_id and source_id=v_ref_id and status='posted';
  if v_ref_count=0 or v_ref_total<>v_ref_amount then
   raise exception using errcode='23514',message='CRM_REFUND_FINANCE_JOURNAL_NOT_RECONCILED';
  end if;
 end loop;
 if exists(select 1 from public.finance_journal_entries where id=any(v.finance_journal_entry_ids)
   and (status<>'posted' or branch_id<>v.branch_id))
  or (select count(*) from public.finance_journal_entries where id=any(v.finance_journal_entry_ids))<>cardinality(v.finance_journal_entry_ids) then
  raise exception using errcode='23514',message='CRM_FINANCE_EVIDENCE_ROWS_CHANGED';
 end if;
 v_hash:=encode(pg_catalog.sha256(convert_to(jsonb_build_object(
  'projection_id',v.id,'source_snapshot_sha256',v.source_snapshot_sha256,
  'finance_entry_ids',v.finance_journal_entry_ids,'source_total_idr',v_total,
  'reviewer',p_actor_user_id)::text,'UTF8')),'hex');
 update public.crm_financial_close_projections
  set status='reconciled',finance_source_reconciliation_status='reconciled',
      reviewed_by=p_actor_user_id,reviewed_at=now(),finance_reconciliation_sha256=v_hash
  where id=v.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'crm.financial_close.reconciled','crm_financial_close_projections',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',v.branch_id,
   'source_type',v.source_type,'source_id',v.source_id,'finance_reconciliation_sha256',v_hash,
   'source_amount_idr',v_total,'finance_entry_count',v_count));
 return jsonb_build_object('status','reconciled','projection_id',v.id,
  'source_snapshot_sha256',v.source_snapshot_sha256,'finance_reconciliation_sha256',v_hash);
end;
$$;
revoke all on function public.crm_reconcile_financial_close_projection(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.crm_reconcile_financial_close_projection(uuid,uuid,uuid) to service_role;

alter table public.crm_loyalty_earning_rules
  add column if not exists points_validity_days integer null
  check(points_validity_days is null or points_validity_days between 1 and 3650);

alter table public.crm_loyalty_ledger
  add column if not exists expires_at timestamptz null;

create index if not exists crm_loyalty_expiring_earn_entries_idx
  on public.crm_loyalty_ledger(tenant_id,customer_id,expires_at,id)
  where entry_kind='earn' and expires_at is not null;

create table if not exists public.crm_loyalty_point_allocations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  customer_id uuid not null,
  source_entry_id uuid not null,
  point_lot_entry_id uuid not null,
  allocation_kind text not null check(allocation_kind in ('redemption','redemption_reversal','earn_reversal','expiry')),
  points_allocated bigint not null check(points_allocated>0),
  created_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,source_entry_id,point_lot_entry_id,allocation_kind),
  foreign key(tenant_id,customer_id) references public.crm_customers(tenant_id,id) on delete restrict,
  foreign key(tenant_id,source_entry_id) references public.crm_loyalty_ledger(tenant_id,id) on delete restrict,
  foreign key(tenant_id,point_lot_entry_id) references public.crm_loyalty_ledger(tenant_id,id) on delete restrict
);
create index if not exists crm_loyalty_allocations_lot_idx
  on public.crm_loyalty_point_allocations(tenant_id,point_lot_entry_id,allocation_kind);

alter table public.crm_loyalty_point_allocations enable row level security;
drop policy if exists service_role_only on public.crm_loyalty_point_allocations;
create policy service_role_only on public.crm_loyalty_point_allocations
  for all to service_role using(true) with check(true);
revoke all on public.crm_loyalty_point_allocations from public,anon,authenticated;
grant select,insert on public.crm_loyalty_point_allocations to service_role;

create or replace function public.crm_reject_point_allocation_mutation()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
  raise exception using errcode='55000',message='CRM_LOYALTY_POINT_ALLOCATIONS_APPEND_ONLY';
end;
$$;
revoke all on function public.crm_reject_point_allocation_mutation() from public,anon,authenticated;
drop trigger if exists crm_loyalty_point_allocations_append_only on public.crm_loyalty_point_allocations;
create trigger crm_loyalty_point_allocations_append_only
  before update or delete on public.crm_loyalty_point_allocations
  for each row execute function public.crm_reject_point_allocation_mutation();

-- Only financial-close awards may create earned points; only the reward RPC may
-- debit them. The approved earning rule controls the expiry duration.
create or replace function public.crm_award_loyalty_for_reconciled_close(
  p_tenant_id uuid,p_branch_id uuid,p_source_type text,p_source_id uuid,p_actor_user_id uuid
) returns jsonb
language plpgsql security invoker set search_path=''
as $$
declare
  v_close public.crm_financial_close_projections%rowtype;
  v_rule public.crm_loyalty_earning_rules%rowtype;
  v_customer_id uuid;
  v_net bigint;
  v_points bigint;
  v_key text;
  v_existing public.crm_loyalty_ledger%rowtype;
  v_entry public.crm_loyalty_ledger%rowtype;
  v_refund_sum bigint;
  v_expires_at timestamptz;
begin
  if p_tenant_id is null or p_branch_id is null or p_source_id is null
     or p_actor_user_id is null or p_source_type not in ('pos_sale','online_order') then
    raise exception using errcode='22023',message='INVALID_LOYALTY_CLOSE_COMMAND';
  end if;
  select * into v_close from public.crm_financial_close_projections
   where tenant_id=p_tenant_id and branch_id=p_branch_id
     and source_type=p_source_type and source_id=p_source_id and status='reconciled'
   order by reconciled_at desc limit 1 for update;
  if not found then raise exception using errcode='P0002',message='FINANCIAL_CLOSE_NOT_RECONCILED'; end if;
  if (p_source_type='pos_sale' and v_close.shift_reconciliation_status<>'approved')
     or (p_source_type='online_order' and v_close.shift_reconciliation_status<>'not_required')
     or v_close.settlement_reconciliation_status not in ('matched','cash_reconciled')
     or v_close.finance_journal_status not in ('posted','reconciled')
     or v_close.finance_source_reconciliation_status<>'reconciled' then
    raise exception using errcode='23514',message='FINANCIAL_CLOSE_EVIDENCE_INCOMPLETE';
  end if;
  select coalesce(sum((r->>'amountIdr')::bigint),0) into v_refund_sum
    from jsonb_array_elements(v_close.refund_evidence) r
   where r->>'status'='processed' and coalesce(r->>'id','')<>''
     and coalesce(r->>'amountIdr','') ~ '^[0-9]+$';
  if exists(select 1 from jsonb_array_elements(v_close.refund_evidence) r
    where r->>'status'<>'processed' or coalesce(r->>'id','')=''
      or coalesce(r->>'amountIdr','') !~ '^[0-9]+$')
     or v_refund_sum<>v_close.processed_refunds_idr then
    raise exception using errcode='23514',message='REFUND_EVIDENCE_INCOMPLETE';
  end if;
  v_net:=v_close.subtotal_idr-v_close.discount_idr-v_close.processed_refunds_idr;
  if v_net<0 then raise exception using errcode='23514',message='NEGATIVE_ELIGIBLE_NET_SALES'; end if;
  select * into v_rule from public.crm_loyalty_earning_rules
   where tenant_id=p_tenant_id and status='approved'
   order by approved_at desc limit 1 for share;
  if not found or v_rule.points_validity_days is null then
    raise exception using errcode='23514',message='APPROVED_EARNING_RULE_WITH_VALIDITY_REQUIRED';
  end if;
  select customer_id into v_customer_id from public.crm_transaction_links
   where tenant_id=p_tenant_id and branch_id=p_branch_id
     and source_type=p_source_type and source_id=p_source_id;
  if v_customer_id is null then raise exception using errcode='P0002',message='SOURCE_CUSTOMER_IDENTITY_UNRESOLVED'; end if;
  perform 1 from public.crm_customers
   where tenant_id=p_tenant_id and id=v_customer_id and status='active' for update;
  if not found then raise exception using errcode='P0002',message='ACTIVE_CUSTOMER_NOT_FOUND'; end if;
  v_points:=floor(v_net/1000.0)::bigint*v_rule.points_per_thousand_idr;
  v_key:='crm-earn:'||p_tenant_id::text||':'||p_source_type||':'||p_source_id::text||':'||v_rule.version;
  if v_close.reconciled_at is null then raise exception using errcode='23514',message='FINANCIAL_CLOSE_RECONCILIATION_TIMESTAMP_REQUIRED'; end if;
  v_expires_at:=v_close.reconciled_at+make_interval(days=>v_rule.points_validity_days);
  select * into v_existing from public.crm_loyalty_ledger
   where tenant_id=p_tenant_id and idempotency_key=v_key;
  if found then
    if v_existing.customer_id<>v_customer_id or v_existing.points<>v_points
       or v_existing.entry_kind<>'earn' or v_existing.expires_at is distinct from v_expires_at then
      raise exception using errcode='23505',message='LOYALTY_IDEMPOTENCY_COLLISION';
    end if;
    return jsonb_build_object('status','duplicate','entry_id',v_existing.id,
      'points',v_existing.points,'expires_at',v_existing.expires_at,'idempotency_key',v_key);
  end if;
  if v_points=0 then return jsonb_build_object('status','zero_award','points',0,'idempotency_key',v_key,'eligible_net_sales_idr',v_net); end if;
  insert into public.crm_loyalty_ledger
    (tenant_id,customer_id,entry_kind,points,idempotency_key,source_reference,created_by,expires_at)
  values(p_tenant_id,v_customer_id,'earn',v_points,v_key,
    p_source_type||':'||p_source_id::text||':close:'||v_close.id::text,p_actor_user_id,v_expires_at)
  returning * into v_entry;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'crm.loyalty.financial_close_awarded','crm_loyalty_ledger',v_entry.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'financial_close_id',v_close.id,
      'source_type',p_source_type,'source_id',p_source_id,'customer_id',v_customer_id,
      'eligible_net_sales_idr',v_net,'points',v_points,'earning_rule_version',v_rule.version,
      'expires_at',v_expires_at));
  return jsonb_build_object('status','awarded','entry_id',v_entry.id,'points',v_points,
    'expires_at',v_expires_at,'eligible_net_sales_idr',v_net,'idempotency_key',v_key);
end;
$$;
revoke all on function public.crm_award_loyalty_for_reconciled_close(uuid,uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.crm_award_loyalty_for_reconciled_close(uuid,uuid,text,uuid,uuid) to service_role;

-- Expire only the unspent remainder of each earned lot. A customer row lock
-- serializes this worker against redemption and another expiry worker.
create or replace function public.crm_expire_loyalty_points(
  p_tenant_id uuid,p_customer_id uuid,p_actor_user_id uuid
) returns jsonb
language plpgsql security invoker set search_path=''
as $$
declare
  v_lot record;
  v_allocated bigint;
  v_remaining bigint;
  v_expiry_entry public.crm_loyalty_ledger%rowtype;
  v_expired_total bigint:=0;
  v_lot_count integer:=0;
  v_key text;
begin
  if p_tenant_id is null or p_customer_id is null or p_actor_user_id is null then
    raise exception using errcode='22023',message='INVALID_LOYALTY_EXPIRY_COMMAND';
  end if;
  perform 1 from public.crm_customers
   where tenant_id=p_tenant_id and id=p_customer_id and status='active' for update;
  if not found then raise exception using errcode='P0002',message='ACTIVE_CUSTOMER_NOT_FOUND'; end if;

  for v_lot in
    select id,points,expires_at from public.crm_loyalty_ledger
     where tenant_id=p_tenant_id and customer_id=p_customer_id
       and entry_kind='earn' and expires_at is not null and expires_at<=now()
     order by expires_at,id for update
  loop
    select coalesce(sum(case
      when allocation_kind in ('redemption','earn_reversal','expiry') then points_allocated
      when allocation_kind='redemption_reversal' then -points_allocated
      else 0 end),0)
      into v_allocated
      from public.crm_loyalty_point_allocations
     where tenant_id=p_tenant_id and point_lot_entry_id=v_lot.id;
    v_remaining:=greatest(v_lot.points-v_allocated,0);
    if v_remaining>0 then
      v_key:='crm-expire:'||v_lot.id::text;
      if not exists(select 1 from public.crm_loyalty_ledger where tenant_id=p_tenant_id and idempotency_key=v_key) then
        insert into public.crm_loyalty_ledger
          (tenant_id,customer_id,entry_kind,points,idempotency_key,source_reference,created_by)
        values(p_tenant_id,p_customer_id,'adjustment',-v_remaining,v_key,
          'expiry:'||v_lot.id::text,p_actor_user_id) returning * into v_expiry_entry;
        insert into public.crm_loyalty_point_allocations
          (tenant_id,customer_id,source_entry_id,point_lot_entry_id,allocation_kind,points_allocated)
        values(p_tenant_id,p_customer_id,v_expiry_entry.id,v_lot.id,'expiry',v_remaining);
        insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
        values(p_actor_user_id,'crm.loyalty.points_expired','crm_loyalty_ledger',v_expiry_entry.id::text,
          jsonb_build_object('tenant_id',p_tenant_id,'customer_id',p_customer_id,
            'point_lot_entry_id',v_lot.id,'points_expired',v_remaining,'expires_at',v_lot.expires_at));
        v_expired_total:=v_expired_total+v_remaining;
        v_lot_count:=v_lot_count+1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('status','completed','expired_points',v_expired_total,'expired_lots',v_lot_count);
end;
$$;
revoke all on function public.crm_expire_loyalty_points(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.crm_expire_loyalty_points(uuid,uuid,uuid) to service_role;

-- Reward redemption allocates the debit against earliest-expiring earned lots.
-- Expiry and debit rows plus allocation rows commit or roll back together.
create or replace function public.crm_redeem_reward(
  p_tenant_id uuid,p_customer_id uuid,p_reward_id uuid,p_idempotency_key text,p_actor_user_id uuid
) returns jsonb
language plpgsql security invoker set search_path=''
as $$
declare
  v_reward public.crm_rewards%rowtype;
  v_voucher public.crm_reward_vouchers%rowtype;
  v_debit public.crm_loyalty_ledger%rowtype;
  v_lot record;
  v_allocated bigint;
  v_available bigint;
  v_remaining bigint;
  v_balance bigint;
begin
  if length(coalesce(p_idempotency_key,'')) not between 8 and 120 then
    raise exception using errcode='22023',message='INVALID_IDEMPOTENCY_KEY';
  end if;
  perform 1 from public.crm_customers where tenant_id=p_tenant_id and id=p_customer_id and status='active' for update;
  if not found then raise exception using errcode='P0002',message='ACTIVE_CUSTOMER_NOT_FOUND'; end if;
  perform public.crm_expire_loyalty_points(p_tenant_id,p_customer_id,p_actor_user_id);
  select * into v_reward from public.crm_rewards where tenant_id=p_tenant_id and id=p_reward_id
    and status='active' and starts_at<=now() and expires_at>now() for update;
  if not found then raise exception using errcode='P0002',message='REWARD_NOT_ACTIVE'; end if;
  if exists(select 1 from public.crm_reward_vouchers where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key) then
    raise exception using errcode='23505',message='DUPLICATE_REDEMPTION';
  end if;
  select coalesce(sum(points),0) into v_balance from public.crm_loyalty_ledger
    where tenant_id=p_tenant_id and customer_id=p_customer_id;
  if v_balance<v_reward.points_cost then raise exception using errcode='22023',message='INSUFFICIENT_POINTS'; end if;

  insert into public.crm_reward_vouchers
    (tenant_id,customer_id,reward_id,code,idempotency_key,points_cost,status,expires_at,created_by)
  values(p_tenant_id,p_customer_id,p_reward_id,
    upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),
    p_idempotency_key,v_reward.points_cost,'reserved',v_reward.expires_at,p_actor_user_id)
  returning * into v_voucher;
  insert into public.crm_loyalty_ledger
    (tenant_id,customer_id,entry_kind,points,idempotency_key,source_reference,created_by)
  values(p_tenant_id,p_customer_id,'redeem',-v_reward.points_cost,p_idempotency_key,
    'voucher:'||v_voucher.id::text,p_actor_user_id) returning * into v_debit;

  v_remaining:=v_reward.points_cost;
  for v_lot in
    select id,points from public.crm_loyalty_ledger
     where tenant_id=p_tenant_id and customer_id=p_customer_id
       and (entry_kind='earn' or (entry_kind='adjustment' and points>0))
       and (expires_at is null or expires_at>now())
     order by expires_at nulls last,created_at,id for update
  loop
    select coalesce(sum(case
      when allocation_kind in ('redemption','earn_reversal','expiry') then points_allocated
      when allocation_kind='redemption_reversal' then -points_allocated
      else 0 end),0)
      into v_allocated from public.crm_loyalty_point_allocations
     where tenant_id=p_tenant_id and point_lot_entry_id=v_lot.id;
    v_available:=greatest(v_lot.points-v_allocated,0);
    if v_available>0 and v_remaining>0 then
      insert into public.crm_loyalty_point_allocations
        (tenant_id,customer_id,source_entry_id,point_lot_entry_id,allocation_kind,points_allocated)
      values(p_tenant_id,p_customer_id,v_debit.id,v_lot.id,'redemption',least(v_available,v_remaining));
      v_remaining:=v_remaining-least(v_available,v_remaining);
    end if;
    exit when v_remaining=0;
  end loop;
  if v_remaining<>0 then raise exception using errcode='23514',message='LOYALTY_EARN_LOT_ALLOCATION_MISMATCH'; end if;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'crm.loyalty.redeem','crm_loyalty_ledger',v_voucher.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'customer_id',p_customer_id,'reward_id',p_reward_id,
      'points',-v_reward.points_cost,'debit_entry_id',v_debit.id));
  return jsonb_build_object('voucher_id',v_voucher.id,'voucher_code',v_voucher.code,
    'points_cost',v_voucher.points_cost,'expires_at',v_voucher.expires_at,'balance_after',v_balance-v_reward.points_cost);
end;
$$;
revoke all on function public.crm_redeem_reward(uuid,uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.crm_redeem_reward(uuid,uuid,uuid,text,uuid) to service_role;

-- Generic ledger RPC is limited to audited adjustments/reversals. Earn and
-- redeem must use their source-backed RPCs so they cannot bypass expiry lots.
create or replace function public.crm_append_loyalty_entry(
  p_tenant_id uuid,p_customer_id uuid,p_entry_kind text,p_points bigint,
  p_idempotency_key text,p_source_reference text,p_reverses_entry_id uuid,p_actor_user_id uuid
) returns jsonb
language plpgsql security invoker set search_path=''
as $$
declare
  v_balance bigint;
  v_original public.crm_loyalty_ledger%rowtype;
  v_entry public.crm_loyalty_ledger%rowtype;
  v_allocation record;
  v_allocated bigint;
begin
  if p_entry_kind not in ('adjustment','reversal') or p_points=0
    or length(coalesce(p_idempotency_key,'')) not between 8 and 120
    or length(btrim(coalesce(p_source_reference,'')))=0 then
    raise exception using errcode='22023',message='USE_FINANCIAL_CLOSE_OR_REWARD_REDEMPTION_RPC';
  end if;
  perform 1 from public.crm_customers where tenant_id=p_tenant_id and id=p_customer_id and status in ('prospect','active') for update;
  if not found then raise exception using errcode='P0002',message='CUSTOMER_NOT_FOUND'; end if;
  if exists(select 1 from public.crm_loyalty_ledger where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key) then
    raise exception using errcode='23505',message='DUPLICATE_IDEMPOTENCY_KEY';
  end if;
  if p_entry_kind='reversal' then
    if p_reverses_entry_id is null then raise exception using errcode='22023',message='REVERSAL_TARGET_REQUIRED'; end if;
    select * into v_original from public.crm_loyalty_ledger
     where tenant_id=p_tenant_id and id=p_reverses_entry_id and customer_id=p_customer_id for update;
    if not found or v_original.entry_kind='reversal' or p_points<>-v_original.points then
      raise exception using errcode='22023',message='INVALID_REVERSAL_TARGET_OR_AMOUNT';
    end if;
    if exists(select 1 from public.crm_loyalty_ledger where tenant_id=p_tenant_id and reverses_entry_id=p_reverses_entry_id) then
      raise exception using errcode='23505',message='ENTRY_ALREADY_REVERSED';
    end if;
    if v_original.entry_kind='adjustment' then
      raise exception using errcode='23514',message='ADJUSTMENT_REVERSAL_REQUIRES_NEW_ADJUSTMENT';
    end if;
    if v_original.entry_kind='earn' then
      select coalesce(sum(case
        when allocation_kind in ('redemption','earn_reversal','expiry') then points_allocated
        when allocation_kind='redemption_reversal' then -points_allocated else 0 end),0)
        into v_allocated from public.crm_loyalty_point_allocations
       where tenant_id=p_tenant_id and point_lot_entry_id=v_original.id;
      if v_allocated>0 then raise exception using errcode='23514',message='EARN_ENTRY_ALREADY_CONSUMED_OR_EXPIRED'; end if;
    end if;
  elsif p_reverses_entry_id is not null then
    raise exception using errcode='22023',message='UNEXPECTED_REVERSAL_REFERENCE';
  end if;
  select coalesce(sum(points),0) into v_balance from public.crm_loyalty_ledger
   where tenant_id=p_tenant_id and customer_id=p_customer_id;
  if v_balance+p_points<0 then raise exception using errcode='22023',message='INSUFFICIENT_POINTS'; end if;
  insert into public.crm_loyalty_ledger
    (tenant_id,customer_id,entry_kind,points,idempotency_key,source_reference,reverses_entry_id,created_by)
  values(p_tenant_id,p_customer_id,p_entry_kind,p_points,p_idempotency_key,p_source_reference,p_reverses_entry_id,p_actor_user_id)
  returning * into v_entry;

  if p_entry_kind='reversal' and v_original.entry_kind='earn' then
    insert into public.crm_loyalty_point_allocations
      (tenant_id,customer_id,source_entry_id,point_lot_entry_id,allocation_kind,points_allocated)
    values(p_tenant_id,p_customer_id,v_entry.id,v_original.id,'earn_reversal',v_original.points);
  end if;

  if p_entry_kind='reversal' and v_original.entry_kind='redeem' then
    if exists(
      select 1 from public.crm_loyalty_point_allocations a
      join public.crm_loyalty_ledger lot on lot.tenant_id=a.tenant_id and lot.id=a.point_lot_entry_id
      where a.tenant_id=p_tenant_id and a.source_entry_id=v_original.id
        and a.allocation_kind='redemption' and lot.expires_at is not null and lot.expires_at<=now()
    ) then
      raise exception using errcode='23514',message='REDEMPTION_REVERSAL_AFTER_EXPIRY_BLOCKED';
    end if;
    for v_allocation in select point_lot_entry_id,points_allocated
      from public.crm_loyalty_point_allocations
     where tenant_id=p_tenant_id and source_entry_id=v_original.id and allocation_kind='redemption'
    loop
      insert into public.crm_loyalty_point_allocations
        (tenant_id,customer_id,source_entry_id,point_lot_entry_id,allocation_kind,points_allocated)
      values(p_tenant_id,p_customer_id,v_entry.id,v_allocation.point_lot_entry_id,'redemption_reversal',v_allocation.points_allocated);
    end loop;
  end if;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'crm.loyalty.'||p_entry_kind,'crm_loyalty_ledger',v_entry.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'customer_id',p_customer_id,'points',p_points,
      'source_reference',p_source_reference,'reverses_entry_id',p_reverses_entry_id));
  return jsonb_build_object('entry_id',v_entry.id,'balance_after',v_balance+p_points,'entry_kind',v_entry.entry_kind);
end;
$$;
revoke all on function public.crm_append_loyalty_entry(uuid,uuid,text,bigint,text,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.crm_append_loyalty_entry(uuid,uuid,text,bigint,text,text,uuid,uuid) to service_role;


-- Independently approve the expiry policy used by financial-close awards.
create or replace function public.crm_approve_loyalty_earning_rule(
  p_tenant_id uuid,p_rule_id uuid,p_actor_user_id uuid
) returns jsonb
language plpgsql security invoker set search_path=''
as $$
declare
  v_rule public.crm_loyalty_earning_rules%rowtype;
begin
  if p_tenant_id is null or p_rule_id is null or p_actor_user_id is null then
    raise exception using errcode='22023',message='INVALID_EARNING_RULE_APPROVAL';
  end if;
  select * into v_rule from public.crm_loyalty_earning_rules
   where tenant_id=p_tenant_id and id=p_rule_id for update;
  if not found then raise exception using errcode='P0002',message='EARNING_RULE_NOT_FOUND'; end if;
  if v_rule.status<>'draft' then raise exception using errcode='23514',message='EARNING_RULE_NOT_DRAFT'; end if;
  if v_rule.created_by=p_actor_user_id then raise exception using errcode='42501',message='INDEPENDENT_EARNING_RULE_APPROVER_REQUIRED'; end if;
  if v_rule.points_validity_days is null or v_rule.points_validity_days not between 1 and 3650
     or v_rule.points_per_thousand_idr<0 then
    raise exception using errcode='23514',message='EARNING_RULE_VALIDITY_POLICY_REQUIRED';
  end if;
  update public.crm_loyalty_earning_rules set status='retired'
   where tenant_id=p_tenant_id and status='approved';
  update public.crm_loyalty_earning_rules set status='approved',
    approved_by=p_actor_user_id,approved_at=now()
   where tenant_id=p_tenant_id and id=p_rule_id returning * into v_rule;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'crm.loyalty.earning_rule_approved','crm_loyalty_earning_rules',v_rule.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'version',v_rule.version,
      'points_per_thousand_idr',v_rule.points_per_thousand_idr,
      'points_validity_days',v_rule.points_validity_days));
  return jsonb_build_object('rule_id',v_rule.id,'status',v_rule.status,
    'version',v_rule.version,'points_validity_days',v_rule.points_validity_days);
end;
$$;
revoke all on function public.crm_approve_loyalty_earning_rule(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.crm_approve_loyalty_earning_rule(uuid,uuid,uuid) to service_role;

-- Trigger functions are non-client-callable; service_role retains internal EXECUTE for the global ACL contract.
grant execute on function public.crm_audit_insert_row() to service_role;
grant execute on function public.crm_auto_link_paid_transaction_customer() to service_role;
grant execute on function public.crm_reject_append_only_mutation() to service_role;
grant execute on function public.crm_reject_point_allocation_mutation() to service_role;
