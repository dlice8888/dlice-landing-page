-- DESIGN DRAFT ONLY. Apply after CRM_LOYALTY_ADAPTERS_EXTENSION_DRAFT.sql.
alter table public.crm_financial_close_projections
 add column if not exists payment_record_ids uuid[] not null default '{}',
 add column if not exists paid_amount_idr bigint not null default 0,
 add column if not exists created_by uuid references auth.users(id) on delete restrict,
 add column if not exists reviewed_by uuid references auth.users(id) on delete restrict,
 add column if not exists reviewed_at timestamptz;
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
  return jsonb_build_object('status','duplicate','projection_id',v_existing.id,
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
 if v.source_type='pos_sale' then
  v_ids:=array[v.source_id];
 else
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
      reviewed_by=p_actor_user_id,reviewed_at=now()
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
