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
  shift_reconciliation_id uuid not null,
  settlement_reconciliation_id uuid not null,
  finance_journal_batch_id uuid not null,
  currency text not null check(currency='IDR'),
  subtotal_idr bigint not null check(subtotal_idr>=0),
  discount_idr bigint not null check(discount_idr>=0),
  processed_refunds_idr bigint not null check(processed_refunds_idr>=0),
  refund_evidence jsonb not null check(jsonb_typeof(refund_evidence)='array'),
  shift_reconciliation_status text not null check(shift_reconciliation_status='approved'),
  settlement_reconciliation_status text not null check(settlement_reconciliation_status='reconciled'),
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
  if v_close.shift_reconciliation_status<>'approved'
     or v_close.settlement_reconciliation_status<>'reconciled'
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
create or replace function public.crm_auto_link_paid_transaction_customer()
returns trigger
language plpgsql
security invoker
set search_path = ''
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

  if v_raw_phone !~ '^[+0-9[:space:]()-]+
returns trigger language plpgsql security invoker set search_path = ''
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
    'crm_loyalty_earning_rules',
    'crm_financial_close_projections',
    'crm_campaign_outbox',
    'crm_campaign_provider_events',
    'crm_campaign_attributions',
    'crm_campaign_costs'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists service_role_only on public.%I',t);
    execute format('create policy service_role_only on public.%I for all to service_role using (true) with check (true)',t);
    execute format('revoke all on public.%I from anon, authenticated',t);
    execute format('grant select,insert,update,delete on public.%I to service_role',t);
  end loop;
end $$;
 then return new; end if;
  v_digits:=regexp_replace(v_raw_phone,'[^0-9]','','g');
  if v_digits='' then return new; end if;
  if left(v_digits,1)='0' then
    v_digits:='62'||substr(v_digits,2);
  elsif left(v_digits,1)='8' then
    v_digits:='62'||v_digits;
  end if;
  v_phone:='+'||v_digits;
  if v_phone !~ '^\+[1-9][0-9]{7,14}
returns trigger language plpgsql security invoker set search_path = ''
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
    'crm_loyalty_earning_rules',
    'crm_financial_close_projections',
    'crm_campaign_outbox',
    'crm_campaign_provider_events',
    'crm_campaign_attributions',
    'crm_campaign_costs'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists service_role_only on public.%I',t);
    execute format('create policy service_role_only on public.%I for all to service_role using (true) with check (true)',t);
    execute format('revoke all on public.%I from anon, authenticated',t);
    execute format('grant select,insert,update,delete on public.%I to service_role',t);
  end loop;
end $$;
 then return new; end if;

  select tenant_id into v_tenant_id from public.branches where id=new.branch_id;
  if v_tenant_id is null then
    raise exception using errcode='23503',message='CRM_SOURCE_BRANCH_TENANT_NOT_FOUND';
  end if;

  perform public.crm_link_transaction_customer(
    v_tenant_id,new.branch_id,v_source_type,new.id,null,v_display_name,v_phone,auth.uid()
  );
  return new;
end;
$;
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
returns trigger language plpgsql security invoker set search_path = ''
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
    'crm_loyalty_earning_rules',
    'crm_financial_close_projections',
    'crm_campaign_outbox',
    'crm_campaign_provider_events',
    'crm_campaign_attributions',
    'crm_campaign_costs'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists service_role_only on public.%I',t);
    execute format('create policy service_role_only on public.%I for all to service_role using (true) with check (true)',t);
    execute format('revoke all on public.%I from anon, authenticated',t);
    execute format('grant select,insert,update,delete on public.%I to service_role',t);
  end loop;
end $$;
