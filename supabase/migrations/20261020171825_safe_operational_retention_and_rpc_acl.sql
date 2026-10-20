-- Safe retention for operational aggregates and rate-limit buckets.
-- Deliberately preserve orders, payment records/proofs, notifications, and audit logs.

create extension if not exists pg_cron with schema pg_catalog;

create or replace function public.cleanup_operational_data()
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
declare
  deleted_rate_limits bigint := 0;
  deleted_funnel_days bigint := 0;
begin
  delete from public.request_rate_limits
  where updated_at < now() - interval '30 days';
  get diagnostics deleted_rate_limits = row_count;

  delete from public.funnel_daily_metrics
  where metric_date < current_date - 730;
  get diagnostics deleted_funnel_days = row_count;

  return jsonb_build_object(
    'deleted_rate_limit_rows', deleted_rate_limits,
    'deleted_funnel_metric_days', deleted_funnel_days,
    'retention_policy', jsonb_build_object(
      'request_rate_limits_days', 30,
      'funnel_daily_metrics_days', 730,
      'orders_payment_proofs_notifications_audit_logs', 'preserved'
    )
  );
end;
$function$;

revoke all on function public.cleanup_operational_data() from public, anon, authenticated;
grant execute on function public.cleanup_operational_data() to service_role;
revoke all on function public.set_updated_at() from public, anon, authenticated;

select cron.unschedule(jobid)
from cron.job
where jobname = 'dlice-operational-retention';

select cron.schedule(
  'dlice-operational-retention',
  '17 3 * * *',
  'select public.cleanup_operational_data();'
);
