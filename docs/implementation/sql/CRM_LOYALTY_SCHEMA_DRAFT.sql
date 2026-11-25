-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- Prepared from read-only staging schema reconnaissance on 2026-11-25.
-- Do not execute directly. Generate the final version with the Supabase CLI
-- migration workflow after the eight-domain design is reconciled.
--
-- Access model: exposed public tables remain RLS-enabled and service-role-only,
-- matching current private ERP tables. All client access must go through
-- dlice-orders after JWT validation and server-side tenant membership checks.

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
 consent_event_id uuid null references public.crm_customer_consent_events(id) on delete restrict,
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
 foreign key(tenant_id,customer_id) references public.crm_customers(tenant_id,id) on delete restrict
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
end $;
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
end $;
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
     or p_actor_user_id is null
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
