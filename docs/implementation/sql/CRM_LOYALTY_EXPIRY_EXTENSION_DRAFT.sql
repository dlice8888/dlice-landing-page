-- DESIGN DRAFT ONLY — apply after CRM_LOYALTY_SCHEMA_DRAFT.sql,
-- CRM_LOYALTY_ADAPTERS_EXTENSION_DRAFT.sql and CRM_FINANCIAL_CLOSE_REVIEW_EXTENSION_DRAFT.sql.
-- Adds expiry lots and FIFO redemption allocation. All mutations execute in one
-- PostgreSQL transaction; do not split these operations into REST requests.

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
      when allocation_kind='redemption' or allocation_kind='expiry' then points_allocated
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
        when allocation_kind in ('redemption','expiry') then points_allocated
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
