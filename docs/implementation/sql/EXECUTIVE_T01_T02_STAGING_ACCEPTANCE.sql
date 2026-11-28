-- Read-only acceptance queries. Run only after the reviewed migration is applied to staging.
-- Never run these against production. They do not mutate records.

-- T01-A: new paid rows must carry a server-recognized timestamp and branch timezone snapshot.
select count(*) as paid_rows_missing_paid_at_or_business_date
from public.pos_sales
where payment_status='paid' and (paid_at is null or business_date is null or business_timezone is null);

-- T01-B: every stamped business date must equal the branch-local date at paid_at.
select count(*) as paid_date_timezone_mismatches
from public.pos_sales
where payment_status='paid' and paid_at is not null and business_date is not null
  and business_date <> (paid_at at time zone business_timezone)::date;

-- T01-C: source totals by branch business date, preserving gross, discount, refund and net.
select b.tenant_id,s.branch_id,s.business_date,b.timezone,
       count(*) as paid_transactions,
       sum(s.subtotal_idr) as gross_sales_idr,
       sum(s.discount_idr) as discounts_idr,
       sum(s.total_idr) as sales_net_before_refunds_idr,
       coalesce(sum(r.refund_total_idr),0) as processed_refunds_idr,
       sum(s.total_idr)-coalesce(sum(r.refund_total_idr),0) as net_sales_idr
from public.pos_sales s
join public.branches b on b.id=s.branch_id
left join lateral (
  select sum(rr.amount_idr)::bigint as refund_total_idr
  from public.refund_records rr
  where rr.pos_sale_id=s.id and rr.branch_id=s.branch_id and rr.status='processed'
) r on true
where s.payment_status='paid' and s.business_date is not null
group by b.tenant_id,s.branch_id,s.business_date,b.timezone
order by b.tenant_id,s.branch_id,s.business_date;

-- T01-D: per-sale settlement and Finance evidence; no net settlement is inferred when absent.
select * from public.executive_sales_reconciliation_v
order by tenant_id,branch_id,business_date,sale_id;

-- T02-A: inbox rows whose source entity is no longer at the submitted version must be zero.
select count(*) as stale_pending_approval_rows
from public.approval_inbox_items a
where a.status in ('pending','claimed')
  and not public.approval_source_is_current(a.id);

-- T02-B: source references and approval decisions are traceable and idempotent.
select a.tenant_id,a.branch_id,a.domain,a.source_entity_type,a.source_entity_id,
       a.source_version,a.status,a.version,a.expires_at,
       d.decision,d.actor_user_id,d.reason,d.idempotency_key,d.policy_version,d.created_at as decided_at
from public.approval_inbox_items a
left join public.approval_decisions d on d.approval_id=a.id
order by a.created_at desc;

-- T02-C: branch/tenant composite scope for approval rows must remain valid.
select count(*) as invalid_approval_tenant_branch_rows
from public.approval_inbox_items a
left join public.branches b on b.id=a.branch_id and b.tenant_id=a.tenant_id
where b.id is null;
