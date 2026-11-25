-- DESIGN DRAFT ONLY — apply only after the base CRM schema has been reconciled.
-- Not a migration. This file completes the persistence contracts consumed by
-- fnb-transactional-workflows.mjs. It is intentionally service-role-only.
-- Order: CRM_LOYALTY_SCHEMA_DRAFT.sql, then this extension, then final reviewed migration.

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
  settlement_reconciliation_id uuid not null,
  settlement_ids uuid[] not null default '{}',
  finance_journal_entry_ids uuid[] not null default '{}',
  currency text not null check(currency='IDR'),
  subtotal_idr bigint not null check(subtotal_idr>=0),
  discount_idr bigint not null check(discount_idr>=0),
  processed_refunds_idr bigint not null check(processed_refunds_idr>=0),
  refund_evidence jsonb not null check(jsonb_typeof(refund_evidence)='array'),
  shift_reconciliation_status text not null check(shift_reconciliation_status in ('approved','not_required')),
  settlement_reconciliation_status text not null check(settlement_reconciliation_status='matched'),
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
     or v_close.settlement_reconciliation_status<>'matched'
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
 select tenant_id into v_branch_tenant from public.branches where id=p_branch_id;
 if v_branch_tenant is distinct from p_tenant_id then
  raise exception using errcode='42501',message='CRM_FINANCIAL_CLOSE_TENANT_BRANCH_MISMATCH';
 end if;

 if p_source_type='pos_sale' then
  select subtotal_idr,discount_idr,total_idr into v_subtotal,v_discount,v_gross
   from public.pos_sales where id=p_source_id and branch_id=p_branch_id and payment_status='paid';
  if not found then raise exception using errcode='P0002',message='PAID_POS_SALE_NOT_FOUND'; end if;
  select id,status into v_cash_id,v_cash_status from public.cash_reconciliations
   where branch_id=p_branch_id and shift_id=(select shift_id from public.pos_sales where id=p_source_id)
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

 -- A source is eligible only when its full payment amount is represented by
 -- matched settlement items and each batch has bank/provider receipt parity.
 if p_source_type='pos_sale' then
  select coalesce(array_agg(distinct ps.id order by ps.id),'{}'::uuid[]),
         coalesce(sum(psi.amount_idr),0)
   into v_settlement_ids,v_settled
   from public.payment_settlement_items psi
   join public.payment_settlements ps on ps.id=psi.settlement_id
   where psi.pos_sale_id=p_source_id and ps.status='matched'
     and ps.received_amount_idr=ps.net_amount_idr;
  if exists(select 1 from public.payment_settlement_items psi
    join public.payment_settlements ps on ps.id=psi.settlement_id
    where psi.pos_sale_id=p_source_id and
      (ps.status<>'matched' or ps.received_amount_idr is distinct from ps.net_amount_idr)) then
   raise exception using errcode='23514',message='POS_SETTLEMENT_BATCH_NOT_RECONCILED';
  end if;
 else
  select coalesce(array_agg(distinct ps.id order by ps.id),'{}'::uuid[]),
         coalesce(sum(psi.amount_idr),0)
   into v_settlement_ids,v_settled
   from public.payment_settlement_items psi
   join public.payment_settlements ps on ps.id=psi.settlement_id
   where psi.payment_record_id=any(v_payment_ids) and ps.status='matched'
     and ps.received_amount_idr=ps.net_amount_idr;
  if exists(select 1 from public.payment_settlement_items psi
    join public.payment_settlements ps on ps.id=psi.settlement_id
    where psi.payment_record_id=any(v_payment_ids) and
      (ps.status<>'matched' or ps.received_amount_idr is distinct from ps.net_amount_idr)) then
   raise exception using errcode='23514',message='ORDER_SETTLEMENT_BATCH_NOT_RECONCILED';
  end if;
 end if;
 if cardinality(v_settlement_ids)=0 or v_settled<>v_paid then
  raise exception using errcode='23514',message='SETTLEMENT_ITEMS_DO_NOT_RECONCILE_TO_SOURCE_PAYMENT';
 end if;

 -- Processed refunds only reduce eligible sales. An unresolved refund blocks
 -- the close rather than allowing points to be awarded prematurely.
 if p_source_type='pos_sale' then
  if exists(select 1 from public.refund_records where pos_sale_id=p_source_id
    and status in ('requested','approved')) then
   raise exception using errcode='23514',message='POS_REFUND_REVIEW_STILL_OPEN';
  end if;
  select coalesce(sum(amount_idr),0),coalesce(array_agg(id order by id),'{}'::uuid[])
   into v_refunds,v_refund_ids from public.refund_records
   where pos_sale_id=p_source_id and branch_id=p_branch_id and status='processed';
 else
  if exists(select 1 from public.refund_records r
    where (r.order_id=p_source_id or r.payment_record_id=any(v_payment_ids))
      and r.status in ('requested','approved')) then
   raise exception using errcode='23514',message='ORDER_REFUND_REVIEW_STILL_OPEN';
  end if;
  select coalesce(sum(amount_idr),0),coalesce(array_agg(id order by id),'{}'::uuid[])
   into v_refunds,v_refund_ids from public.refund_records
   where (order_id=p_source_id or payment_record_id=any(v_payment_ids))
     and branch_id=p_branch_id and status='processed';
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
   where branch_id=p_branch_id and source_id=any(v_payment_ids) and status='posted';
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
     and (source_id=any(v_payment_ids) or source_id=any(v_refund_ids));
 end if;

 v_snapshot:=jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,
  'source_type',p_source_type,'source_id',p_source_id,'payment_record_ids',v_payment_ids,
  'settlement_ids',v_settlement_ids,'finance_journal_entry_ids',v_journal_ids,
  'refund_ids',v_refund_ids,'subtotal_idr',v_subtotal,'discount_idr',v_discount,
  'processed_refunds_idr',v_refunds,'paid_amount_idr',v_paid,'settled_amount_idr',v_settled,
  'cash_reconciliation_id',v_cash_id,'cash_reconciliation_status',v_cash_status,
  'refund_evidence',v_refund_evidence,'captured_at',now());
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
  v_cash_status,'matched','posted','reconciled','reconciled',v_hash,now()
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
