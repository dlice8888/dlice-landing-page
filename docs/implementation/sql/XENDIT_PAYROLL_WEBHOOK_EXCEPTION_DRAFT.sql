-- DESIGN DRAFT ONLY — authenticated provider webhook mismatches.
-- Depends on HR_PAYROLL_PAYMENT_ADAPTERS_DRAFT.sql. Never stores raw webhook
-- bodies or beneficiary PII; only provider IDs, reason codes and SHA-256 evidence.

create table if not exists public.hr_payroll_provider_event_exceptions (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 payment_batch_id uuid not null,
 payment_item_id uuid not null,
 provider_config_id uuid not null,
 provider_event_id text not null check(length(btrim(provider_event_id)) between 1 and 180),
 reason_code text not null check(reason_code in (
  'provider_reference','reference_id','amount','currency','unsupported_provider_status'
 )),
 provider_reference text null,
 payload_sha256 text not null check(payload_sha256 ~ '^[0-9a-f]{64}$'),
 signature_verified boolean not null check(signature_verified=true),
 occurred_at timestamptz not null,
 recorded_by uuid not null references auth.users(id) on delete restrict,
 recorded_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(provider_config_id,provider_event_id),
 foreign key(tenant_id,payment_batch_id) references public.hr_payroll_payment_batches(tenant_id,id) on delete restrict,
 foreign key(tenant_id,payment_item_id) references public.hr_payroll_payment_items(tenant_id,id) on delete restrict,
 foreign key(tenant_id,provider_config_id) references public.hr_payroll_payment_provider_configs(tenant_id,id) on delete restrict
);

create or replace function public.hr_record_payroll_provider_event_exception(
 p_tenant_id uuid,p_payment_batch_id uuid,p_payment_item_id uuid,
 p_provider_event_id text,p_reason_code text,p_provider_reference text,
 p_payload_sha256 text,p_occurred_at timestamptz,p_signature_verified boolean,
 p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare
 v_batch public.hr_payroll_payment_batches%rowtype;
 v_item public.hr_payroll_payment_items%rowtype;
 v_event public.hr_payroll_provider_event_exceptions%rowtype;
begin
 if p_signature_verified is distinct from true
  or coalesce(p_payload_sha256,'') !~ '^[0-9a-f]{64}$'
  or length(btrim(coalesce(p_provider_event_id,''))) not between 1 and 180
  or p_reason_code not in ('provider_reference','reference_id','amount','currency','unsupported_provider_status') then
  raise exception using errcode='42501',message='AUTHENTICATED_PROVIDER_EXCEPTION_REQUIRED';
 end if;
 select * into v_batch from public.hr_payroll_payment_batches
  where tenant_id=p_tenant_id and id=p_payment_batch_id for update;
 if not found or v_batch.status not in ('approved','processing') then
  raise exception using errcode='23514',message='APPROVED_PAYROLL_PAYMENT_BATCH_REQUIRED';
 end if;
 select * into v_item from public.hr_payroll_payment_items
  where tenant_id=p_tenant_id and payment_batch_id=v_batch.id and id=p_payment_item_id for update;
 if not found then raise exception using errcode='23503',message='PAYROLL_PAYMENT_ITEM_NOT_FOUND'; end if;
 select * into v_event from public.hr_payroll_provider_event_exceptions
  where provider_config_id=v_batch.provider_config_id and provider_event_id=p_provider_event_id for update;
 if found then
  if v_event.payment_item_id<>v_item.id or v_event.payload_sha256<>p_payload_sha256 then
   raise exception using errcode='23505',message='PAYROLL_PROVIDER_EXCEPTION_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','event_id',v_event.id);
 end if;
 insert into public.hr_payroll_provider_event_exceptions(
  tenant_id,payment_batch_id,payment_item_id,provider_config_id,provider_event_id,
  reason_code,provider_reference,payload_sha256,signature_verified,occurred_at,recorded_by
 ) values(p_tenant_id,v_batch.id,v_item.id,v_batch.provider_config_id,p_provider_event_id,
  p_reason_code,p_provider_reference,p_payload_sha256,true,p_occurred_at,p_actor_user_id)
 returning * into v_event;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.provider_event_exception_recorded',
  'hr_payroll_provider_event_exceptions',v_event.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'payment_batch_id',v_batch.id,
   'payment_item_id',v_item.id,'reason_code',p_reason_code,
   'provider_reference',p_provider_reference,'payload_sha256',p_payload_sha256));
 return jsonb_build_object('status','exception','event_id',v_event.id,'reason_code',p_reason_code);
end $$;

revoke all on function public.hr_record_payroll_provider_event_exception(uuid,uuid,uuid,text,text,text,text,timestamptz,boolean,uuid) from public,anon,authenticated;
grant execute on function public.hr_record_payroll_provider_event_exception(uuid,uuid,uuid,text,text,text,text,timestamptz,boolean,uuid) to service_role;

alter table public.hr_payroll_provider_event_exceptions enable row level security;
drop policy if exists service_role_only on public.hr_payroll_provider_event_exceptions;
create policy service_role_only on public.hr_payroll_provider_event_exceptions
 for all to service_role using(true) with check(true);
revoke all on public.hr_payroll_provider_event_exceptions from anon,authenticated;
grant select,insert on public.hr_payroll_provider_event_exceptions to service_role;

create or replace function public.hr_reject_payroll_provider_event_exception_mutation()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
 raise exception using errcode='55000',message='PAYROLL_PROVIDER_EVENT_EXCEPTIONS_APPEND_ONLY';
end $$;
revoke all on function public.hr_reject_payroll_provider_event_exception_mutation() from public,anon,authenticated;
drop trigger if exists hr_payroll_provider_event_exceptions_append_only on public.hr_payroll_provider_event_exceptions;
create trigger hr_payroll_provider_event_exceptions_append_only
 before update or delete on public.hr_payroll_provider_event_exceptions
 for each row execute function public.hr_reject_payroll_provider_event_exception_mutation();
