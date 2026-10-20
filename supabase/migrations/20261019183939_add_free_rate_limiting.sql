-- D'Lice free, database-backed rate limiting. Apply to STAGING first.
-- The bucket key is a SHA-256 digest; raw IP addresses/usernames are not stored.
create table if not exists public.request_rate_limits (
  bucket_key text primary key,
  window_started_at timestamptz not null default now(),
  hit_count integer not null default 0 check (hit_count >= 0),
  updated_at timestamptz not null default now()
);

create index if not exists request_rate_limits_updated_at_idx
  on public.request_rate_limits (updated_at);

alter table public.request_rate_limits enable row level security;
revoke all on table public.request_rate_limits from public, anon, authenticated;
grant select, insert, update, delete on table public.request_rate_limits to service_role;

create or replace function public.consume_rate_limit(
  p_bucket_key text,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_hits integer;
begin
  if p_bucket_key is null or length(p_bucket_key) <> 64
     or p_limit < 1 or p_limit > 1000
     or p_window_seconds < 1 or p_window_seconds > 86400 then
    raise exception 'Invalid rate limit arguments';
  end if;

  insert into public.request_rate_limits (bucket_key, window_started_at, hit_count, updated_at)
  values (p_bucket_key, now(), 1, now())
  on conflict (bucket_key) do update
  set window_started_at = case
        when public.request_rate_limits.window_started_at
             + make_interval(secs => p_window_seconds) <= now()
        then now()
        else public.request_rate_limits.window_started_at
      end,
      hit_count = case
        when public.request_rate_limits.window_started_at
             + make_interval(secs => p_window_seconds) <= now()
        then 1
        else public.request_rate_limits.hit_count + 1
      end,
      updated_at = now()
  returning hit_count into v_hits;

  -- Low-volume cleanup without a scheduled job or paid service.
  if random() < 0.02 then
    delete from public.request_rate_limits
    where updated_at < now() - interval '1 day';
  end if;

  return v_hits <= p_limit;
end;
$$;

revoke all on function public.consume_rate_limit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.consume_rate_limit(text, integer, integer) to service_role;
