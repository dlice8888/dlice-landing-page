-- Privacy-preserving funnel metrics: aggregate counts only, no cookies, IPs, phone numbers, or order IDs.
create table if not exists public.funnel_daily_metrics (
  metric_date date not null default (now() at time zone 'UTC')::date,
  event_name text not null check (event_name in ('page_view','menu_view','add_to_order','checkout_start','order_created','proof_uploaded','whatsapp_click')),
  event_count bigint not null default 0 check (event_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (metric_date, event_name)
);
alter table public.funnel_daily_metrics enable row level security;
revoke all on table public.funnel_daily_metrics from public, anon, authenticated;
grant select, insert, update, delete on table public.funnel_daily_metrics to service_role;

create or replace function public.record_funnel_event(p_event text)
returns boolean
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if p_event not in ('page_view','menu_view','add_to_order','checkout_start','order_created','proof_uploaded','whatsapp_click') then
    return false;
  end if;
  insert into public.funnel_daily_metrics (metric_date, event_name, event_count, updated_at)
  values ((now() at time zone 'UTC')::date, p_event, 1, now())
  on conflict (metric_date, event_name) do update
    set event_count = public.funnel_daily_metrics.event_count + 1,
        updated_at = now();
  return true;
end;
$$;
revoke all on function public.record_funnel_event(text) from public, anon, authenticated;
grant execute on function public.record_funnel_event(text) to service_role;
