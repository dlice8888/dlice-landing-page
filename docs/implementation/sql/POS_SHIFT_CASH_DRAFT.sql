-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- D02-F01 / D02-F11: shift lifecycle, cash drawer movements and reconciliation.
-- Depends on the current POS schema inspected on staging 2026-11-28.
-- Apply only after disposable replay, exact role/RLS review, and E2E fixtures.
begin;

alter table public.branches
 add column if not exists pos_shift_variance_threshold_idr bigint not null default 5000
 check(pos_shift_variance_threshold_idr>=0);

create table if not exists public.pos_shift_cash_movements (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 shift_id uuid not null,
 actor_user_id uuid not null references auth.users(id) on delete restrict,
 movement_type text not null check(movement_type in ('cash_in','cash_out')),
 amount_idr bigint not null check(amount_idr>0),
 reason text not null check(length(btrim(reason))>=3),
 idempotency_key text not null check(length(idempotency_key) between 8 and 120),
 payload_fingerprint text not null,
 created_at timestamptz not null default now(),
 foreign key(shift_id,branch_id) references public.pos_shifts(id,branch_id) on delete restrict,
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 unique(tenant_id,branch_id,shift_id,idempotency_key)
);
create index if not exists pos_shift_cash_movements_ledger_idx
 on public.pos_shift_cash_movements(tenant_id,branch_id,shift_id,created_at);

create table if not exists public.pos_cash_reconciliation_snapshots (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 shift_id uuid not null,
 actor_user_id uuid not null references auth.users(id) on delete restrict,
 expected_cash_idr bigint not null check(expected_cash_idr>=0),
 counted_cash_idr bigint not null check(counted_cash_idr>=0),
 variance_idr bigint not null,
 ledger_snapshot jsonb not null check(jsonb_typeof(ledger_snapshot)='object'),
 reason text not null,
 created_at timestamptz not null default now(),
 foreign key(shift_id,branch_id) references public.pos_shifts(id,branch_id) on delete restrict,
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);
create index if not exists pos_cash_reconciliation_snapshot_idx
 on public.pos_cash_reconciliation_snapshots(tenant_id,branch_id,shift_id,created_at desc);

create table if not exists public.pos_shift_close_snapshots (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 shift_id uuid not null unique,
 actor_user_id uuid not null references auth.users(id) on delete restrict,
 expected_cash_idr bigint not null check(expected_cash_idr>=0),
 counted_cash_idr bigint not null check(counted_cash_idr>=0),
 variance_idr bigint not null,
 ledger_snapshot jsonb not null check(jsonb_typeof(ledger_snapshot)='object'),
 created_at timestamptz not null default now(),
 foreign key(shift_id,branch_id) references public.pos_shifts(id,branch_id) on delete restrict,
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);

do $$ declare t text; begin
 foreach t in array array['pos_shift_cash_movements','pos_cash_reconciliation_snapshots','pos_shift_close_snapshots'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('alter table public.%I force row level security',t);
  execute format('drop policy if exists service_role_only on public.%I',t);
  execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select,insert,update on public.%I to service_role',t);
 end loop;
end $$;

create or replace function public.pos_actor_can_access_branch(p_actor uuid,p_tenant uuid,p_branch uuid)
returns boolean language sql security invoker set search_path=''
as $$
 select exists(select 1 from public.tenant_memberships tm where tm.user_id=p_actor and tm.tenant_id=p_tenant and tm.status='active')
 and (
  exists(select 1 from public.tenant_memberships tm where tm.user_id=p_actor and tm.tenant_id=p_tenant and tm.status='active' and tm.role in ('tenant_owner','tenant_admin','group_hq','head_ops'))
  or exists(select 1 from public.branch_assignments ba join public.branches b on b.id=ba.branch_id
   where ba.user_id=p_actor and ba.branch_id=p_branch and b.tenant_id=p_tenant and ba.employment_status='active'
    and ba.starts_on<=current_date and (ba.ends_on is null or ba.ends_on>=current_date))
  or exists(select 1 from public.admin_profiles ap where ap.user_id=p_actor and ap.role='owner' and ap.is_active=true)
 );
$$;
revoke all on function public.pos_actor_can_access_branch(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.pos_actor_can_access_branch(uuid,uuid,uuid) to service_role;

create or replace function public.pos_open_shift_atomic(
 p_tenant_id uuid,p_branch_id uuid,p_actor_user_id uuid,p_opening_cash_idr bigint
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_branch public.branches%rowtype; v_shift public.pos_shifts%rowtype;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='POS_SERVICE_ROLE_REQUIRED'; end if;
 if p_opening_cash_idr is null or p_opening_cash_idr<0 or p_opening_cash_idr>1000000000 then raise exception 'invalid_opening_cash'; end if;
 select * into v_branch from public.branches where id=p_branch_id and tenant_id=p_tenant_id and status='active' for share;
 if not found or not public.pos_actor_can_access_branch(p_actor_user_id,p_tenant_id,p_branch_id) then raise exception using errcode='42501',message='pos_branch_access_denied'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_branch_id::text||':'||p_actor_user_id::text||':pos-shift-open',0));
 if exists(select 1 from public.pos_shifts where branch_id=p_branch_id and opened_by=p_actor_user_id and status='open') then raise exception 'pos_shift_already_open'; end if;
 insert into public.pos_shifts(branch_id,opened_by,opening_cash_idr,expected_cash_idr,status)
 values(p_branch_id,p_actor_user_id,p_opening_cash_idr,p_opening_cash_idr,'open') returning * into v_shift;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'pos_shift_opened','pos_shift',v_shift.id::text,jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'opening_cash_idr',p_opening_cash_idr));
 return jsonb_build_object('id',v_shift.id,'tenantId',p_tenant_id,'branchId',v_shift.branch_id,'openedBy',v_shift.opened_by,
  'status',v_shift.status,'openingCashIdr',v_shift.opening_cash_idr,'expectedCashIdr',v_shift.expected_cash_idr,'openedAt',v_shift.opened_at);
end $$;
revoke all on function public.pos_open_shift_atomic(uuid,uuid,uuid,bigint) from public,anon,authenticated;
grant execute on function public.pos_open_shift_atomic(uuid,uuid,uuid,bigint) to service_role;

create or replace function public.pos_record_cash_movement_atomic(
 p_tenant_id uuid,p_branch_id uuid,p_actor_user_id uuid,p_shift_id uuid,p_idempotency_key text,
 p_movement_type text,p_amount_idr bigint,p_reason text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_shift public.pos_shifts%rowtype; v_prior public.pos_shift_cash_movements%rowtype; v_fingerprint text; v_row public.pos_shift_cash_movements%rowtype; v_next bigint;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='POS_SERVICE_ROLE_REQUIRED'; end if;
 if p_movement_type not in ('cash_in','cash_out') or p_amount_idr<=0 or length(btrim(coalesce(p_reason,'')))<3
  or length(coalesce(p_idempotency_key,''))<8 then raise exception 'invalid_cash_movement'; end if;
 if not public.pos_actor_can_access_branch(p_actor_user_id,p_tenant_id,p_branch_id) then raise exception using errcode='42501',message='pos_branch_access_denied'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_shift_id::text||':'||p_idempotency_key,0));
 select * into v_shift from public.pos_shifts where id=p_shift_id and branch_id=p_branch_id and status='open' for update;
 if not found then raise exception 'open_shift_required'; end if;
 v_fingerprint:=encode(extensions.digest(jsonb_build_object('movement_type',p_movement_type,'amount_idr',p_amount_idr,'reason',p_reason)::text,'sha256'),'hex');
 select * into v_prior from public.pos_shift_cash_movements where tenant_id=p_tenant_id and branch_id=p_branch_id and shift_id=p_shift_id and idempotency_key=p_idempotency_key;
 if found then
  if v_prior.payload_fingerprint<>v_fingerprint then raise exception 'cash_movement_idempotency_mismatch'; end if;
  return jsonb_build_object('movementId',v_prior.id,'tenantId',p_tenant_id,'branchId',p_branch_id,'shiftId',p_shift_id,'amountIdr',v_prior.amount_idr,'replayed',true);
 end if;
 v_next:=case when p_movement_type='cash_in' then v_shift.expected_cash_idr+p_amount_idr else v_shift.expected_cash_idr-p_amount_idr end;
 if v_next<0 then raise exception 'cash_drawer_insufficient_balance'; end if;
 insert into public.pos_shift_cash_movements(tenant_id,branch_id,shift_id,actor_user_id,movement_type,amount_idr,reason,idempotency_key,payload_fingerprint)
 values(p_tenant_id,p_branch_id,p_shift_id,p_actor_user_id,p_movement_type,p_amount_idr,left(p_reason,500),p_idempotency_key,v_fingerprint)
 returning * into v_row;
 update public.pos_shifts set expected_cash_idr=v_next where id=p_shift_id and status='open';
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'pos_cash_'||p_movement_type,'pos_shift_cash_movement',v_row.id::text,jsonb_build_object('shift_id',p_shift_id,'amount_idr',p_amount_idr,'reason',p_reason,'expected_cash_idr',v_next));
 return jsonb_build_object('movementId',v_row.id,'tenantId',p_tenant_id,'branchId',p_branch_id,'shiftId',p_shift_id,'amountIdr',p_amount_idr,'expectedCashIdr',v_next,'replayed',false);
end $$;
revoke all on function public.pos_record_cash_movement_atomic(uuid,uuid,uuid,uuid,text,text,bigint,text) from public,anon,authenticated;
grant execute on function public.pos_record_cash_movement_atomic(uuid,uuid,uuid,uuid,text,text,bigint,text) to service_role;

create or replace function public.pos_close_shift_atomic(
 p_tenant_id uuid,p_branch_id uuid,p_actor_user_id uuid,p_shift_id uuid,p_counted_cash_idr bigint,p_reason text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_shift public.pos_shifts%rowtype; v_branch public.branches%rowtype; v_sales bigint; v_in bigint; v_out bigint; v_refunds bigint;
 v_pending integer; v_expected bigint; v_variance bigint; v_supervisor boolean; v_ledger jsonb; v_closed public.pos_shifts%rowtype;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='POS_SERVICE_ROLE_REQUIRED'; end if;
 if p_counted_cash_idr<0 or length(btrim(coalesce(p_reason,'')))<3 then raise exception 'invalid_shift_close_input'; end if;
 if not public.pos_actor_can_access_branch(p_actor_user_id,p_tenant_id,p_branch_id) then raise exception using errcode='42501',message='pos_branch_access_denied'; end if;
 select * into v_branch from public.branches where id=p_branch_id and tenant_id=p_tenant_id for share;
 select * into v_shift from public.pos_shifts where id=p_shift_id and branch_id=p_branch_id for update;
 if not found or v_shift.status<>'open' then raise exception 'pos_shift_not_open'; end if;
 select count(*)::integer into v_pending from public.pos_sales where shift_id=p_shift_id and payment_status='pending';
 if v_pending>0 then raise exception 'pos_shift_pending_payments'; end if;
 select coalesce(sum(case when t.id is not null then case when t.payment_method='cash' then t.amount_idr else 0 end
   when s.payment_method='cash' then s.total_idr else 0 end),0)::bigint into v_sales
 from public.pos_sales s left join public.pos_sale_tenders t on t.sale_id=s.id
 where s.shift_id=p_shift_id and s.payment_status in ('paid','refunded');
 select coalesce(sum(amount_idr) filter(where movement_type='cash_in'),0)::bigint,
  coalesce(sum(amount_idr) filter(where movement_type='cash_out'),0)::bigint into v_in,v_out
 from public.pos_shift_cash_movements where shift_id=p_shift_id;
 select coalesce(sum(rr.amount_idr),0)::bigint into v_refunds
 from public.refund_records rr join public.pos_sales s on s.id=rr.pos_sale_id
 where s.shift_id=p_shift_id and s.payment_method='cash' and rr.status='processed';
 v_expected:=v_shift.opening_cash_idr+v_sales+v_in-v_out-v_refunds;
 if v_expected<0 then raise exception 'pos_cash_ledger_negative'; end if;
 v_variance:=p_counted_cash_idr-v_expected;
 select (ap.role='owner' or exists(select 1 from public.branch_assignments ba join public.job_positions jp on jp.id=ba.job_position_id
   where ba.user_id=p_actor_user_id and ba.branch_id=p_branch_id and ba.employment_status='active'
    and jp.code in ('branch_manager','supervisor','finance_manager')))
 into v_supervisor from public.admin_profiles ap where ap.user_id=p_actor_user_id and ap.is_active=true;
 if abs(v_variance)>v_branch.pos_shift_variance_threshold_idr and not coalesce(v_supervisor,false) then
  raise exception using errcode='42501',message='pos_shift_variance_approval_required'; end if;
 v_ledger:=jsonb_build_object('openingCashIdr',v_shift.opening_cash_idr,'cashSalesIdr',v_sales,'cashInIdr',v_in,
  'cashOutIdr',v_out,'cashRefundsIdr',v_refunds,'pendingPaymentCount',v_pending,'pendingOrderCount',0);
 update public.pos_shifts set status='closed',counted_cash_idr=p_counted_cash_idr,cash_variance_idr=v_variance,
  closed_by=p_actor_user_id,closed_at=now(),notes=left(p_reason,500)
 where id=p_shift_id and branch_id=p_branch_id and status='open' returning * into v_closed;
 if not found then raise exception 'pos_shift_close_race'; end if;
 insert into public.pos_shift_close_snapshots(tenant_id,branch_id,shift_id,actor_user_id,expected_cash_idr,counted_cash_idr,variance_idr,ledger_snapshot)
 values(p_tenant_id,p_branch_id,p_shift_id,p_actor_user_id,v_expected,p_counted_cash_idr,v_variance,v_ledger);
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'pos_shift_closed','pos_shift',p_shift_id::text,jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,
  'expected_cash_idr',v_expected,'counted_cash_idr',p_counted_cash_idr,'cash_variance_idr',v_variance,'ledger',v_ledger));
 return jsonb_build_object('shift',jsonb_build_object('id',v_closed.id,'status',v_closed.status,'expectedCashIdr',v_closed.expected_cash_idr,
  'countedCashIdr',v_closed.counted_cash_idr,'cashVarianceIdr',v_closed.cash_variance_idr),
  'ledger',v_ledger,'expectedCashIdr',v_expected,'cashVarianceIdr',v_variance);
end $$;
revoke all on function public.pos_close_shift_atomic(uuid,uuid,uuid,uuid,bigint,text) from public,anon,authenticated;
grant execute on function public.pos_close_shift_atomic(uuid,uuid,uuid,uuid,bigint,text) to service_role;

create or replace function public.pos_reconcile_cash_drawer_atomic(
 p_tenant_id uuid,p_branch_id uuid,p_actor_user_id uuid,p_shift_id uuid,p_counted_cash_idr bigint,p_reason text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_shift public.pos_shifts%rowtype; v_sales bigint; v_in bigint; v_out bigint; v_refunds bigint; v_pending integer; v_expected bigint; v_variance bigint; v_ledger jsonb; v_id uuid;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='POS_SERVICE_ROLE_REQUIRED'; end if;
 if p_counted_cash_idr<0 or length(btrim(coalesce(p_reason,'')))<3 then raise exception 'invalid_cash_reconciliation_input'; end if;
 if not public.pos_actor_can_access_branch(p_actor_user_id,p_tenant_id,p_branch_id) then raise exception using errcode='42501',message='pos_branch_access_denied'; end if;
 select * into v_shift from public.pos_shifts where id=p_shift_id and branch_id=p_branch_id and status='open' for update;
 if not found then raise exception 'open_shift_required'; end if;
 select count(*)::integer into v_pending from public.pos_sales where shift_id=p_shift_id and payment_status='pending';
 if v_pending>0 then raise exception 'pos_shift_pending_payments'; end if;
 select coalesce(sum(case when t.id is not null then case when t.payment_method='cash' then t.amount_idr else 0 end
  when s.payment_method='cash' then s.total_idr else 0 end),0)::bigint into v_sales
 from public.pos_sales s left join public.pos_sale_tenders t on t.sale_id=s.id where s.shift_id=p_shift_id and s.payment_status in ('paid','refunded');
 select coalesce(sum(amount_idr) filter(where movement_type='cash_in'),0)::bigint,coalesce(sum(amount_idr) filter(where movement_type='cash_out'),0)::bigint
 into v_in,v_out from public.pos_shift_cash_movements where shift_id=p_shift_id;
 select coalesce(sum(rr.amount_idr),0)::bigint into v_refunds from public.refund_records rr join public.pos_sales s on s.id=rr.pos_sale_id
 where s.shift_id=p_shift_id and s.payment_method='cash' and rr.status='processed';
 v_expected:=v_shift.opening_cash_idr+v_sales+v_in-v_out-v_refunds;v_variance:=p_counted_cash_idr-v_expected;
 v_ledger:=jsonb_build_object('openingCashIdr',v_shift.opening_cash_idr,'cashSalesIdr',v_sales,'cashInIdr',v_in,'cashOutIdr',v_out,
  'cashRefundsIdr',v_refunds,'pendingPaymentCount',v_pending,'pendingOrderCount',0);
 insert into public.pos_cash_reconciliation_snapshots(tenant_id,branch_id,shift_id,actor_user_id,expected_cash_idr,counted_cash_idr,variance_idr,ledger_snapshot,reason)
 values(p_tenant_id,p_branch_id,p_shift_id,p_actor_user_id,v_expected,p_counted_cash_idr,v_variance,v_ledger,left(p_reason,500)) returning id into v_id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'pos_cash_reconciled','pos_cash_reconciliation_snapshot',v_id::text,jsonb_build_object('shift_id',p_shift_id,'expected_cash_idr',v_expected,'counted_cash_idr',p_counted_cash_idr,'variance_idr',v_variance));
 return jsonb_build_object('reconciliationId',v_id,'tenantId',p_tenant_id,'branchId',p_branch_id,'shiftId',p_shift_id,
  'expectedCashIdr',v_expected,'countedCashIdr',p_counted_cash_idr,'varianceIdr',v_variance,'ledger',v_ledger);
end $$;
revoke all on function public.pos_reconcile_cash_drawer_atomic(uuid,uuid,uuid,uuid,bigint,text) from public,anon,authenticated;
grant execute on function public.pos_reconcile_cash_drawer_atomic(uuid,uuid,uuid,uuid,bigint,text) to service_role;

rollback;