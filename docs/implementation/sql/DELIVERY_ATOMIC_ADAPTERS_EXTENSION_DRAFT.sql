-- DESIGN DRAFT ONLY — apply after DELIVERY_FULFILLMENT_SCHEMA_DRAFT.sql
-- and DELIVERY_PROVIDER_STORAGE_SCHEMA_DRAFT.sql.
-- Provider network I/O is performed by an injected worker. This file owns
-- idempotent state transitions, queue claims, webhook application and reconciliation.

alter table public.delivery_dispatches
 add column if not exists provider_booking_status text not null default 'confirmed'
 check(provider_booking_status in ('pending','confirmed','failed'));
alter table public.delivery_provider_quotes add column if not exists idempotency_key text null;
create unique index if not exists delivery_provider_quotes_idempotency_uq
 on public.delivery_provider_quotes(tenant_id,idempotency_key) where idempotency_key is not null;
alter table public.delivery_outbox add column if not exists claimed_by text null;
alter table public.delivery_outbox add column if not exists claimed_at timestamptz null;

alter table public.delivery_cost_reconciliations alter column finance_source_reconciliation_id drop not null;
alter table public.delivery_cost_reconciliations drop constraint if exists delivery_cost_reconciled_requires_finance_fk;
alter table public.delivery_cost_reconciliations add constraint delivery_cost_reconciled_requires_finance_fk
 check(status<>'reconciled' or finance_source_reconciliation_id is not null);
do $$ begin
 if not exists(select 1 from pg_constraint where conname='delivery_cost_finance_journal_fk'
   and conrelid='public.delivery_cost_reconciliations'::regclass) then
  alter table public.delivery_cost_reconciliations add constraint delivery_cost_finance_journal_fk
   foreign key(finance_source_reconciliation_id) references public.finance_journal_entries(id) on delete restrict;
 end if;
end $$;

create or replace function public.delivery_reject_evidence_mutation()
returns trigger language plpgsql security invoker set search_path=''
as $$ begin raise exception using errcode='55000',message='DELIVERY_EVIDENCE_APPEND_ONLY'; end $$;
revoke all on function public.delivery_reject_evidence_mutation() from public,anon,authenticated;
drop trigger if exists delivery_provider_events_append_only on public.delivery_provider_events;
create trigger delivery_provider_events_append_only before update or delete on public.delivery_provider_events
 for each row execute function public.delivery_reject_evidence_mutation();
drop trigger if exists delivery_cost_reconciliations_append_only on public.delivery_cost_reconciliations;
create trigger delivery_cost_reconciliations_append_only before update or delete on public.delivery_cost_reconciliations
 for each row execute function public.delivery_reject_evidence_mutation();
drop trigger if exists delivery_storage_evidence_append_only on public.delivery_storage_evidence;
create trigger delivery_storage_evidence_append_only before update or delete on public.delivery_storage_evidence
 for each row execute function public.delivery_reject_evidence_mutation();

create or replace function public.delivery_request_provider_config(
 p_tenant_id uuid,p_branch_id uuid,p_provider_key text,p_display_name text,
 p_secret_reference text,p_integration_mode text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.delivery_provider_configs%rowtype;
begin
 if length(btrim(coalesce(p_provider_key,''))) not between 2 and 60
  or length(btrim(coalesce(p_display_name,''))) not between 2 and 100
  or p_secret_reference !~ '^[A-Z][A-Z0-9_]{2,119}$'
  or p_integration_mode not in ('manual','api') then
  raise exception using errcode='22023',message='INVALID_DELIVERY_PROVIDER_CONFIG';
 end if;
 if not exists(select 1 from public.branches where tenant_id=p_tenant_id and id=p_branch_id) then
  raise exception using errcode='23503',message='DELIVERY_PROVIDER_BRANCH_NOT_IN_TENANT';
 end if;
 insert into public.delivery_provider_configs(tenant_id,branch_id,provider_key,display_name,
  credential_secret_reference,integration_mode,status,created_by)
 values(p_tenant_id,p_branch_id,lower(btrim(p_provider_key)),btrim(p_display_name),
  p_secret_reference,p_integration_mode,'pending',p_actor_user_id) returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'delivery.provider_config.requested','delivery_provider_config',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'provider_key',v.provider_key,
   'integration_mode',v.integration_mode,'secret_reference',v.credential_secret_reference));
 return jsonb_build_object('provider_config_id',v.id,'status',v.status,'provider_key',v.provider_key);
end; $$;
revoke all on function public.delivery_request_provider_config(uuid,uuid,text,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.delivery_request_provider_config(uuid,uuid,text,text,text,text,uuid) to service_role;

create or replace function public.delivery_create_provider_quote(
 p_tenant_id uuid,p_branch_id uuid,p_order_id uuid,p_provider_config_id uuid,
 p_provider_quote_id text,p_service_level text,p_quoted_cost_idr bigint,p_cod_supported boolean,
 p_expires_at timestamptz,p_payload_sha256 text,p_idempotency_key text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.delivery_provider_quotes%rowtype; v_order public.orders%rowtype; v_config public.delivery_provider_configs%rowtype;
begin
 if length(btrim(coalesce(p_provider_quote_id,''))) not between 1 and 160
  or length(btrim(coalesce(p_service_level,''))) not between 1 and 80 or p_quoted_cost_idr<0
  or p_expires_at<=now() or p_expires_at>now()+interval '2 hours'
  or p_payload_sha256 !~ '^[0-9a-f]{64}$'
  or length(coalesce(p_idempotency_key,'')) not between 8 and 120 then
  raise exception using errcode='22023',message='INVALID_DELIVERY_PROVIDER_QUOTE';
 end if;
 select * into v from public.delivery_provider_quotes where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
 if found then
  if v.branch_id<>p_branch_id or v.order_id<>p_order_id or v.provider_config_id<>p_provider_config_id
   or v.provider_quote_id<>p_provider_quote_id or v.quoted_cost_idr<>p_quoted_cost_idr
   or v.service_level<>p_service_level or v.cod_supported<>p_cod_supported or v.expires_at<>p_expires_at
   or v.provider_payload_sha256<>p_payload_sha256 then
   raise exception using errcode='23505',message='DELIVERY_QUOTE_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','quote_id',v.id);
 end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found or v_order.branch_id<>p_branch_id or v_order.payment_status not in ('paid','verified','settled')
  or v_order.fulfillment_status<>'ready' then raise exception using errcode='23514',message='DELIVERY_ORDER_NOT_QUOTE_ELIGIBLE'; end if;
 select * into v_config from public.delivery_provider_configs where tenant_id=p_tenant_id and id=p_provider_config_id
  and status='active' and (branch_id is null or branch_id=p_branch_id) for share;
 if not found then raise exception using errcode='42501',message='APPROVED_DELIVERY_PROVIDER_REQUIRED'; end if;
 insert into public.delivery_provider_quotes(tenant_id,branch_id,order_id,provider_config_id,provider_quote_id,
  service_level,quoted_cost_idr,cod_supported,expires_at,provider_payload_sha256,idempotency_key)
 values(p_tenant_id,p_branch_id,p_order_id,p_provider_config_id,p_provider_quote_id,p_service_level,
  p_quoted_cost_idr,p_cod_supported,p_expires_at,p_payload_sha256,p_idempotency_key) returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'delivery.quote.created','delivery_provider_quote',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'order_id',p_order_id,
   'provider_config_id',p_provider_config_id,'quoted_cost_idr',p_quoted_cost_idr));
 return jsonb_build_object('status','quoted','quote_id',v.id,'expires_at',v.expires_at,'quoted_cost_idr',v.quoted_cost_idr);
end; $$;
revoke all on function public.delivery_create_provider_quote(uuid,uuid,uuid,uuid,text,text,bigint,boolean,timestamptz,text,text,uuid) from public,anon,authenticated;
grant execute on function public.delivery_create_provider_quote(uuid,uuid,uuid,uuid,text,text,bigint,boolean,timestamptz,text,text,uuid) to service_role;

create or replace function public.delivery_book_dispatch_from_quote(
 p_tenant_id uuid,p_branch_id uuid,p_quote_id uuid,p_cod_amount_idr bigint,
 p_idempotency_key text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_quote public.delivery_provider_quotes%rowtype; v_config public.delivery_provider_configs%rowtype;
 v_order public.orders%rowtype; v_dispatch public.delivery_dispatches%rowtype; v_outbox public.delivery_outbox%rowtype;
begin
 if p_cod_amount_idr<0 or length(coalesce(p_idempotency_key,'')) not between 8 and 120 then
  raise exception using errcode='22023',message='INVALID_DELIVERY_DISPATCH_COMMAND';
 end if;
 select * into v_dispatch from public.delivery_dispatches where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
 if found then
  if v_dispatch.quote_id<>p_quote_id or v_dispatch.cod_amount_idr<>p_cod_amount_idr then
   raise exception using errcode='23505',message='DELIVERY_DISPATCH_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','dispatch_id',v_dispatch.id,'provider_booking_status',v_dispatch.provider_booking_status);
 end if;
 select * into v_quote from public.delivery_provider_quotes where tenant_id=p_tenant_id and branch_id=p_branch_id and id=p_quote_id for update;
 if not found or v_quote.status<>'quoted' or v_quote.expires_at<=now() then raise exception using errcode='23514',message='DELIVERY_QUOTE_NOT_SELECTABLE'; end if;
 select * into v_config from public.delivery_provider_configs where tenant_id=p_tenant_id and id=v_quote.provider_config_id
  and status='active' for share;
 if not found then raise exception using errcode='42501',message='APPROVED_DELIVERY_PROVIDER_REQUIRED'; end if;
 select * into v_order from public.orders where id=v_quote.order_id for update;
 if not found or v_order.branch_id<>p_branch_id or v_order.payment_status not in ('paid','verified','settled')
  or v_order.fulfillment_status<>'ready' then raise exception using errcode='23514',message='DELIVERY_ORDER_NOT_BOOKABLE'; end if;
 if exists(select 1 from public.delivery_dispatches where tenant_id=p_tenant_id and order_id=v_order.id and status not in ('failed','cancelled')) then
  raise exception using errcode='23505',message='ACTIVE_DISPATCH_ALREADY_EXISTS';
 end if;
 insert into public.delivery_dispatches(tenant_id,branch_id,order_id,provider,provider_service,delivery_fee_idr,
  cod_amount_idr,status,idempotency_key,booked_at,created_by,quote_id,provider_booking_status,courier_cost_expected_idr)
 values(p_tenant_id,p_branch_id,v_order.id,v_config.provider_key,v_quote.service_level,v_quote.quoted_cost_idr,
  p_cod_amount_idr,'booked',p_idempotency_key,now(),p_actor_user_id,v_quote.id,'pending',v_quote.quoted_cost_idr)
 returning * into v_dispatch;
 update public.delivery_provider_quotes set status='selected' where tenant_id=p_tenant_id and id=v_quote.id;
 update public.orders set fulfillment_status='dispatched',updated_at=now() where id=v_order.id and fulfillment_status='ready';
 if not found then raise exception using errcode='40001',message='ORDER_FULFILLMENT_RACE'; end if;
 insert into public.order_status_history(order_id,status_type,old_status,new_status,note)
 values(v_order.id,'operational','ready','dispatched','Delivery quote selected; provider booking queued');
 insert into public.delivery_outbox(tenant_id,dispatch_id,event_type,status,idempotency_key)
 values(p_tenant_id,v_dispatch.id,'book','queued','delivery-book:'||v_dispatch.id::text) returning * into v_outbox;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'delivery.dispatch.booking_queued','delivery_dispatch',v_dispatch.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'order_id',v_order.id,'quote_id',v_quote.id,'outbox_id',v_outbox.id));
 return jsonb_build_object('status','queued','dispatch_id',v_dispatch.id,'outbox_id',v_outbox.id,'provider_booking_status','pending');
end; $$;
revoke all on function public.delivery_book_dispatch_from_quote(uuid,uuid,uuid,bigint,text,uuid) from public,anon,authenticated;
grant execute on function public.delivery_book_dispatch_from_quote(uuid,uuid,uuid,bigint,text,uuid) to service_role;

create or replace function public.delivery_confirm_provider_booking(
 p_tenant_id uuid,p_dispatch_id uuid,p_provider_booking_reference text,p_tracking_number text,
 p_tracking_url text,p_succeeded boolean,p_error_code text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.delivery_dispatches%rowtype;
begin
 select * into v from public.delivery_dispatches where tenant_id=p_tenant_id and id=p_dispatch_id for update;
 if not found then raise exception using errcode='P0002',message='DELIVERY_DISPATCH_NOT_FOUND'; end if;
 if v.provider_booking_status='confirmed' and p_succeeded and v.provider_booking_reference=p_provider_booking_reference then
  return jsonb_build_object('status','duplicate','dispatch_id',v.id);
 end if;
 if v.provider_booking_status='failed' and not p_succeeded and v.failure_reason=left(coalesce(p_error_code,'PROVIDER_BOOKING_FAILED'),500) then
  return jsonb_build_object('status','duplicate','dispatch_id',v.id);
 end if;
 if v.provider_booking_status<>'pending' then raise exception using errcode='23514',message='DELIVERY_BOOKING_RESULT_ALREADY_FINAL'; end if;
 if p_succeeded then
  if length(btrim(coalesce(p_provider_booking_reference,'')))<2 then raise exception using errcode='22023',message='PROVIDER_BOOKING_REFERENCE_REQUIRED'; end if;
  update public.delivery_dispatches set provider_booking_status='confirmed',provider_booking_reference=p_provider_booking_reference,
   tracking_number=p_tracking_number,tracking_url=p_tracking_url,updated_by=p_actor_user_id,updated_at=now()
   where tenant_id=p_tenant_id and id=p_dispatch_id returning * into v;
 else
  update public.delivery_dispatches set provider_booking_status='failed',status='failed',failed_at=now(),
   failure_reason=left(coalesce(p_error_code,'PROVIDER_BOOKING_FAILED'),500),updated_by=p_actor_user_id,updated_at=now()
   where tenant_id=p_tenant_id and id=p_dispatch_id returning * into v;
  update public.orders set fulfillment_status='failed',updated_at=now() where id=v.order_id and fulfillment_status='dispatched';
  if found then
   insert into public.order_status_history(order_id,status_type,old_status,new_status,note)
   values(v.order_id,'operational','dispatched','failed','Provider booking failed: '||left(coalesce(p_error_code,''),300));
  end if;
 end if;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,case when p_succeeded then 'delivery.provider_booking.confirmed' else 'delivery.provider_booking.failed' end,
  'delivery_dispatch',v.id::text,jsonb_build_object('tenant_id',p_tenant_id,'provider_booking_reference',v.provider_booking_reference,'error_code',p_error_code));
 return jsonb_build_object('dispatch_id',v.id,'provider_booking_status',v.provider_booking_status,'status',v.status);
end; $$;
revoke all on function public.delivery_confirm_provider_booking(uuid,uuid,text,text,text,boolean,text,uuid) from public,anon,authenticated;
grant execute on function public.delivery_confirm_provider_booking(uuid,uuid,text,text,text,boolean,text,uuid) to service_role;

create or replace function public.delivery_ingest_verified_provider_event(
 p_tenant_id uuid,p_branch_id uuid,p_dispatch_id uuid,p_provider_event_id text,p_next_status text,
 p_occurred_at timestamptz,p_payload_sha256 text,p_signature_key_version text,p_signature_verified boolean,
 p_actor_user_id uuid,p_note text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.delivery_dispatches%rowtype; v_event public.delivery_provider_events%rowtype;
begin
 if not p_signature_verified or length(btrim(coalesce(p_provider_event_id,''))) not between 8 and 160
  or p_next_status not in ('picked_up','in_transit','delivered','failed','cancelled')
  or p_payload_sha256 !~ '^[0-9a-f]{64}$' then
  raise exception using errcode='22023',message='INVALID_OR_UNVERIFIED_DELIVERY_WEBHOOK';
 end if;
 select * into v from public.delivery_dispatches where tenant_id=p_tenant_id and branch_id=p_branch_id and id=p_dispatch_id for update;
 if not found or v.provider_booking_status<>'confirmed' then raise exception using errcode='23514',message='CONFIRMED_DISPATCH_REQUIRED'; end if;
 if not exists(select 1 from public.delivery_provider_configs c where c.tenant_id=p_tenant_id and c.provider_key=v.provider
  and c.status='active' and (c.branch_id is null or c.branch_id=p_branch_id)) then
  raise exception using errcode='42501',message='ACTIVE_PROVIDER_CONFIG_REQUIRED';
 end if;
 select * into v_event from public.delivery_provider_events where tenant_id=p_tenant_id and provider=v.provider and provider_event_id=p_provider_event_id;
 if found then
  if v_event.payload_hash<>p_payload_sha256 or v_event.dispatch_id<>p_dispatch_id then
   raise exception using errcode='23505',message='DELIVERY_PROVIDER_EVENT_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','dispatch_id',v.id,'event_id',v_event.id);
 end if;
 if not ((v.status='booked' and p_next_status in ('picked_up','failed','cancelled')) or
  (v.status='picked_up' and p_next_status in ('in_transit','failed')) or
  (v.status='in_transit' and p_next_status in ('delivered','failed'))) then
  raise exception using errcode='23514',message='INVALID_DELIVERY_TRANSITION';
 end if;
 if p_next_status='delivered' and not exists(select 1 from public.delivery_proof_of_delivery where tenant_id=p_tenant_id and dispatch_id=v.id) then
  raise exception using errcode='23514',message='DELIVERY_PROOF_REQUIRED';
 end if;
 insert into public.delivery_provider_events(tenant_id,dispatch_id,provider,provider_event_id,event_type,provider_status,
  occurred_at,payload_hash,processed_at,processing_status,processing_note,signature_verified_at,signature_key_version)
 values(p_tenant_id,v.id,v.provider,p_provider_event_id,'provider_webhook',p_next_status,p_occurred_at,p_payload_sha256,
  now(),'processed',left(coalesce(p_note,''),500),now(),p_signature_key_version) returning * into v_event;
 update public.delivery_dispatches set status=p_next_status,
  delivered_at=case when p_next_status='delivered' then now() else delivered_at end,
  failed_at=case when p_next_status='failed' then now() else failed_at end,
  failure_reason=case when p_next_status='failed' then left(coalesce(p_note,''),500) else failure_reason end,
  updated_by=p_actor_user_id,updated_at=now() where tenant_id=p_tenant_id and id=v.id returning * into v;
 if p_next_status='delivered' then
  update public.orders set fulfillment_status='fulfilled',fulfilled_at=now(),updated_at=now()
   where id=v.order_id and fulfillment_status='dispatched';
  if not found then raise exception using errcode='40001',message='ORDER_FULFILLMENT_STATE_MISMATCH'; end if;
  insert into public.order_status_history(order_id,status_type,old_status,new_status,note)
   values(v.order_id,'operational','dispatched','fulfilled','Provider webhook confirmed delivery with proof');
 elsif p_next_status='failed' then
  update public.orders set fulfillment_status='failed',updated_at=now() where id=v.order_id and fulfillment_status='dispatched';
  if found then insert into public.order_status_history(order_id,status_type,old_status,new_status,note)
   values(v.order_id,'operational','dispatched','failed','Provider webhook: '||left(coalesce(p_note,''),300)); end if;
 elsif p_next_status='cancelled' then
  update public.orders set fulfillment_status='ready',updated_at=now() where id=v.order_id and fulfillment_status='dispatched';
  if found then insert into public.order_status_history(order_id,status_type,old_status,new_status,note)
   values(v.order_id,'operational','dispatched','ready','Provider dispatch cancelled'); end if;
 end if;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'delivery.provider_webhook.'||p_next_status,'delivery_dispatch',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'event_id',p_provider_event_id,'payload_sha256',p_payload_sha256));
 return jsonb_build_object('status','processed','dispatch_id',v.id,'event_id',v_event.id,'dispatch_status',v.status);
end; $$;
revoke all on function public.delivery_ingest_verified_provider_event(uuid,uuid,uuid,text,text,timestamptz,text,text,boolean,uuid,text) from public,anon,authenticated;
grant execute on function public.delivery_ingest_verified_provider_event(uuid,uuid,uuid,text,text,timestamptz,text,text,boolean,uuid,text) to service_role;

create or replace function public.delivery_claim_outbox_batch(p_worker_id text,p_limit integer)
returns setof public.delivery_outbox language plpgsql security invoker set search_path=''
as $$
begin
 if length(btrim(coalesce(p_worker_id,''))) not between 3 and 120 or p_limit not between 1 and 50 then
  raise exception using errcode='22023',message='INVALID_DELIVERY_WORKER_CLAIM';
 end if;
 return query
 with candidates as (
  select id from public.delivery_outbox where status in ('queued','retry') and next_attempt_at<=now()
   order by next_attempt_at,created_at for update skip locked limit p_limit
 )
 update public.delivery_outbox o set status='claimed',attempts=attempts+1,claimed_by=p_worker_id,
  claimed_at=now(),updated_at=now()
 from candidates c where o.id=c.id returning o.*;
end; $$;
revoke all on function public.delivery_claim_outbox_batch(text,integer) from public,anon,authenticated;
grant execute on function public.delivery_claim_outbox_batch(text,integer) to service_role;

create or replace function public.delivery_finish_outbox(
 p_outbox_id uuid,p_worker_id text,p_succeeded boolean,p_error_code text,p_retry_after_seconds integer
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.delivery_outbox%rowtype;
begin
 select * into v from public.delivery_outbox where id=p_outbox_id for update;
 if not found then raise exception using errcode='P0002',message='DELIVERY_OUTBOX_NOT_FOUND'; end if;
 if v.status='completed' and p_succeeded then return jsonb_build_object('outbox_id',v.id,'status','duplicate','attempts',v.attempts); end if;
 if v.status<>'claimed' or v.claimed_by<>p_worker_id then raise exception using errcode='42501',message='DELIVERY_OUTBOX_CLAIM_MISMATCH'; end if;
 if p_succeeded then
  update public.delivery_outbox set status='completed',claimed_by=null,claimed_at=null,last_error_code=null,updated_at=now()
   where id=p_outbox_id returning * into v;
 else
  update public.delivery_outbox set status=case when attempts>=5 then 'dead_letter' else 'retry' end,
   next_attempt_at=now()+make_interval(secs=>greatest(30,least(coalesce(p_retry_after_seconds,60),3600))),
   last_error_code=left(coalesce(p_error_code,'PROVIDER_REQUEST_FAILED'),120),
   claimed_by=null,claimed_at=null,updated_at=now()
   where id=p_outbox_id returning * into v;
 end if;
 return jsonb_build_object('outbox_id',v.id,'status',v.status,'attempts',v.attempts,'next_attempt_at',v.next_attempt_at);
end; $$;
revoke all on function public.delivery_finish_outbox(uuid,text,boolean,text,integer) from public,anon,authenticated;
grant execute on function public.delivery_finish_outbox(uuid,text,boolean,text,integer) to service_role;

create or replace function public.delivery_reconcile_cost(
 p_tenant_id uuid,p_branch_id uuid,p_dispatch_id uuid,p_customer_fee_idr bigint,p_merchant_subsidy_idr bigint,
 p_cod_expected_idr bigint,p_cod_collected_idr bigint,p_cod_remitted_idr bigint,
 p_courier_cost_expected_idr bigint,p_courier_cost_final_idr bigint,p_provider_settlement_idr bigint,
 p_provider_fee_idr bigint,p_finance_journal_entry_id uuid,p_evidence_sha256 text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.delivery_dispatches%rowtype; v_journal public.finance_journal_entries%rowtype;
 v_existing public.delivery_cost_reconciliations%rowtype; v_status text; v_id uuid; v_journal_found boolean;
begin
 if least(p_customer_fee_idr,p_merchant_subsidy_idr,p_cod_expected_idr,p_cod_collected_idr,p_cod_remitted_idr,
  p_courier_cost_expected_idr,p_courier_cost_final_idr,p_provider_settlement_idr,p_provider_fee_idr)<0
  or p_evidence_sha256 !~ '^[0-9a-f]{64}$' then
  raise exception using errcode='22023',message='INVALID_DELIVERY_RECONCILIATION';
 end if;
 select * into v from public.delivery_dispatches where tenant_id=p_tenant_id and branch_id=p_branch_id and id=p_dispatch_id for update;
 if not found or v.status<>'delivered' or v.provider_booking_status<>'confirmed' then
  raise exception using errcode='23514',message='DELIVERED_CONFIRMED_DISPATCH_REQUIRED';
 end if;
 if p_cod_expected_idr<>v.cod_amount_idr then raise exception using errcode='23514',message='DELIVERY_COD_EXPECTED_AMOUNT_MISMATCH'; end if;
 select * into v_existing from public.delivery_cost_reconciliations where tenant_id=p_tenant_id and dispatch_id=p_dispatch_id;
 if found then
  if v_existing.evidence_sha256<>p_evidence_sha256 or v_existing.customer_fee_idr<>p_customer_fee_idr
   or v_existing.merchant_subsidy_idr<>p_merchant_subsidy_idr or v_existing.cod_expected_idr<>p_cod_expected_idr
   or v_existing.cod_collected_idr<>p_cod_collected_idr or v_existing.cod_remitted_idr<>p_cod_remitted_idr
   or v_existing.courier_cost_expected_idr<>p_courier_cost_expected_idr or v_existing.courier_cost_final_idr<>p_courier_cost_final_idr
   or v_existing.provider_settlement_idr<>p_provider_settlement_idr or v_existing.provider_fee_idr<>p_provider_fee_idr
   or v_existing.finance_source_reconciliation_id is distinct from p_finance_journal_entry_id then
   raise exception using errcode='23505',message='DELIVERY_RECONCILIATION_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','reconciliation_id',v_existing.id,'reconciliation_status',v_existing.status);
 end if;
 select * into v_journal from public.finance_journal_entries where id=p_finance_journal_entry_id
  and branch_id=p_branch_id and source_type='delivery_dispatch' and source_id=p_dispatch_id and status='posted'
  and amount_idr=p_provider_settlement_idr;
 v_journal_found:=found;
 v_status:=case when v_journal_found and p_cod_expected_idr=p_cod_collected_idr and p_cod_collected_idr=p_cod_remitted_idr
  and p_courier_cost_final_idr=p_customer_fee_idr+p_merchant_subsidy_idr
  and p_provider_settlement_idr=p_courier_cost_final_idr-p_provider_fee_idr
  then 'reconciled' else 'exception' end;
 insert into public.delivery_cost_reconciliations(tenant_id,branch_id,dispatch_id,customer_fee_idr,merchant_subsidy_idr,
  cod_expected_idr,cod_collected_idr,cod_remitted_idr,courier_cost_expected_idr,courier_cost_final_idr,
  provider_settlement_idr,provider_fee_idr,finance_source_reconciliation_id,status,evidence_sha256,reconciled_by,reconciled_at)
 values(p_tenant_id,p_branch_id,p_dispatch_id,p_customer_fee_idr,p_merchant_subsidy_idr,p_cod_expected_idr,
  p_cod_collected_idr,p_cod_remitted_idr,p_courier_cost_expected_idr,p_courier_cost_final_idr,
  p_provider_settlement_idr,p_provider_fee_idr,case when v_journal_found then p_finance_journal_entry_id else null end,v_status,p_evidence_sha256,
  case when v_status='reconciled' then p_actor_user_id else null end,
  case when v_status='reconciled' then now() else null end) returning id into v_id;
 update public.delivery_dispatches set cod_collected_idr=p_cod_collected_idr,cod_remitted_idr=p_cod_remitted_idr,
  courier_cost_expected_idr=p_courier_cost_expected_idr,courier_cost_final_idr=p_courier_cost_final_idr,updated_at=now()
  where tenant_id=p_tenant_id and id=p_dispatch_id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'delivery.cost.'||v_status,'delivery_cost_reconciliation',v_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'dispatch_id',p_dispatch_id,
   'finance_journal_entry_id',p_finance_journal_entry_id,'evidence_sha256',p_evidence_sha256));
 return jsonb_build_object('reconciliation_id',v_id,'status',v_status,'finance_journal_entry_id',p_finance_journal_entry_id);
end; $$;
revoke all on function public.delivery_reconcile_cost(uuid,uuid,uuid,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.delivery_reconcile_cost(uuid,uuid,uuid,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,uuid,text,uuid) to service_role;
create or replace function public.delivery_get_outbox_job_context(p_outbox_id uuid,p_worker_id text)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.delivery_outbox%rowtype; d public.delivery_dispatches%rowtype;
 q public.delivery_provider_quotes%rowtype; c public.delivery_provider_configs%rowtype; o public.orders%rowtype;
begin
 select * into v from public.delivery_outbox where id=p_outbox_id and status='claimed' and claimed_by=p_worker_id for update;
 if not found then raise exception using errcode='42501',message='DELIVERY_OUTBOX_CLAIM_MISMATCH'; end if;
 select * into d from public.delivery_dispatches where tenant_id=v.tenant_id and id=v.dispatch_id;
 if not found then raise exception using errcode='P0002',message='DELIVERY_DISPATCH_NOT_FOUND'; end if;
 select * into c from public.delivery_provider_configs where tenant_id=d.tenant_id and provider_key=d.provider
  and status='active' and (branch_id is null or branch_id=d.branch_id) order by branch_id nulls last limit 1;
 if not found then raise exception using errcode='42501',message='ACTIVE_DELIVERY_PROVIDER_CONFIG_NOT_FOUND'; end if;
 select * into q from public.delivery_provider_quotes where tenant_id=d.tenant_id and id=d.quote_id;
 select * into o from public.orders where id=d.order_id;
 return jsonb_build_object('outbox',to_jsonb(v),'dispatch',to_jsonb(d),'quote',case when q.id is null then null else to_jsonb(q) end,
  'provider_config',jsonb_build_object('id',c.id,'provider_key',c.provider_key,'display_name',c.display_name,
   'credential_secret_reference',c.credential_secret_reference,'integration_mode',c.integration_mode),
  'order',jsonb_build_object('id',o.id,'branch_id',o.branch_id,'delivery_address',o.delivery_address,
   'customer_name',o.customer_name,'customer_whatsapp',o.customer_whatsapp,'payment_status',o.payment_status));
end; $$;
revoke all on function public.delivery_get_outbox_job_context(uuid,text) from public,anon,authenticated;
grant execute on function public.delivery_get_outbox_job_context(uuid,text) to service_role;

create or replace function public.delivery_claim_outbox_batch(p_worker_id text,p_limit integer)
returns setof public.delivery_outbox language plpgsql security invoker set search_path=''
as $$
begin
 if length(btrim(coalesce(p_worker_id,''))) not between 3 and 120 or p_limit not between 1 and 50 then
  raise exception using errcode='22023',message='INVALID_DELIVERY_WORKER_CLAIM';
 end if;
 return query
 with candidates as (
  select id from public.delivery_outbox where status in ('queued','retry') and next_attempt_at<=now()
   order by next_attempt_at,created_at for update skip locked limit p_limit
 )
 update public.delivery_outbox o set status='claimed',attempts=attempts+1,claimed_by=p_worker_id,
  claimed_at=now(),updated_at=now()
 from candidates c where o.id=c.id returning o.*;
end; $$;
revoke all on function public.delivery_claim_outbox_batch(text,integer) from public,anon,authenticated;
grant execute on function public.delivery_claim_outbox_batch(text,integer) to service_role;

create or replace function public.delivery_finish_outbox(
 p_outbox_id uuid,p_worker_id text,p_succeeded boolean,p_error_code text,p_retry_after_seconds integer
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.delivery_outbox%rowtype;
begin
 select * into v from public.delivery_outbox where id=p_outbox_id for update;
 if not found then raise exception using errcode='P0002',message='DELIVERY_OUTBOX_NOT_FOUND'; end if;
 if v.status='completed' and p_succeeded then return jsonb_build_object('outbox_id',v.id,'status','duplicate','attempts',v.attempts); end if;
 if v.status<>'claimed' or v.claimed_by<>p_worker_id then raise exception using errcode='42501',message='DELIVERY_OUTBOX_CLAIM_MISMATCH'; end if;
 if p_succeeded then
  update public.delivery_outbox set status='completed',claimed_by=null,claimed_at=null,last_error_code=null,updated_at=now()
   where id=p_outbox_id returning * into v;
 else
  update public.delivery_outbox set status=case when attempts>=5 then 'dead_letter' else 'retry' end,
   next_attempt_at=now()+make_interval(secs=>greatest(30,least(coalesce(p_retry_after_seconds,60),3600))),
   last_error_code=left(coalesce(p_error_code,'PROVIDER_REQUEST_FAILED'),120),
   claimed_by=null,claimed_at=null,updated_at=now()
   where id=p_outbox_id returning * into v;
 end if;
 return jsonb_build_object('outbox_id',v.id,'status',v.status,'attempts',v.attempts,'next_attempt_at',v.next_attempt_at);
end; $$;
revoke all on function public.delivery_finish_outbox(uuid,text,boolean,text,integer) from public,anon,authenticated;
grant execute on function public.delivery_finish_outbox(uuid,text,boolean,text,integer) to service_role;

create or replace function public.delivery_reconcile_cost(
 p_tenant_id uuid,p_branch_id uuid,p_dispatch_id uuid,p_customer_fee_idr bigint,p_merchant_subsidy_idr bigint,
 p_cod_expected_idr bigint,p_cod_collected_idr bigint,p_cod_remitted_idr bigint,
 p_courier_cost_expected_idr bigint,p_courier_cost_final_idr bigint,p_provider_settlement_idr bigint,
 p_provider_fee_idr bigint,p_finance_journal_entry_id uuid,p_evidence_sha256 text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.delivery_dispatches%rowtype; v_journal public.finance_journal_entries%rowtype;
 v_existing public.delivery_cost_reconciliations%rowtype; v_status text; v_id uuid; v_journal_found boolean;
begin
 if least(p_customer_fee_idr,p_merchant_subsidy_idr,p_cod_expected_idr,p_cod_collected_idr,p_cod_remitted_idr,
  p_courier_cost_expected_idr,p_courier_cost_final_idr,p_provider_settlement_idr,p_provider_fee_idr)<0
  or p_evidence_sha256 !~ '^[0-9a-f]{64}$' then
  raise exception using errcode='22023',message='INVALID_DELIVERY_RECONCILIATION';
 end if;
 select * into v from public.delivery_dispatches where tenant_id=p_tenant_id and branch_id=p_branch_id and id=p_dispatch_id for update;
 if not found or v.status<>'delivered' or v.provider_booking_status<>'confirmed' then
  raise exception using errcode='23514',message='DELIVERED_CONFIRMED_DISPATCH_REQUIRED';
 end if;
 if p_cod_expected_idr<>v.cod_amount_idr then raise exception using errcode='23514',message='DELIVERY_COD_EXPECTED_AMOUNT_MISMATCH'; end if;
 select * into v_existing from public.delivery_cost_reconciliations where tenant_id=p_tenant_id and dispatch_id=p_dispatch_id;
 if found then
  if v_existing.evidence_sha256<>p_evidence_sha256 or v_existing.customer_fee_idr<>p_customer_fee_idr
   or v_existing.merchant_subsidy_idr<>p_merchant_subsidy_idr or v_existing.cod_expected_idr<>p_cod_expected_idr
   or v_existing.cod_collected_idr<>p_cod_collected_idr or v_existing.cod_remitted_idr<>p_cod_remitted_idr
   or v_existing.courier_cost_expected_idr<>p_courier_cost_expected_idr or v_existing.courier_cost_final_idr<>p_courier_cost_final_idr
   or v_existing.provider_settlement_idr<>p_provider_settlement_idr or v_existing.provider_fee_idr<>p_provider_fee_idr
   or v_existing.finance_source_reconciliation_id is distinct from p_finance_journal_entry_id then
   raise exception using errcode='23505',message='DELIVERY_RECONCILIATION_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','reconciliation_id',v_existing.id,'reconciliation_status',v_existing.status);
 end if;
 select * into v_journal from public.finance_journal_entries where id=p_finance_journal_entry_id
  and branch_id=p_branch_id and source_type='delivery_dispatch' and source_id=p_dispatch_id and status='posted'
  and amount_idr=p_provider_settlement_idr;
 v_journal_found:=found;
 v_status:=case when v_journal_found and p_cod_expected_idr=p_cod_collected_idr and p_cod_collected_idr=p_cod_remitted_idr
  and p_courier_cost_final_idr=p_customer_fee_idr+p_merchant_subsidy_idr
  and p_provider_settlement_idr=p_courier_cost_final_idr-p_provider_fee_idr
  then 'reconciled' else 'exception' end;
 insert into public.delivery_cost_reconciliations(tenant_id,branch_id,dispatch_id,customer_fee_idr,merchant_subsidy_idr,
  cod_expected_idr,cod_collected_idr,cod_remitted_idr,courier_cost_expected_idr,courier_cost_final_idr,
  provider_settlement_idr,provider_fee_idr,finance_source_reconciliation_id,status,evidence_sha256,reconciled_by,reconciled_at)
 values(p_tenant_id,p_branch_id,p_dispatch_id,p_customer_fee_idr,p_merchant_subsidy_idr,p_cod_expected_idr,
  p_cod_collected_idr,p_cod_remitted_idr,p_courier_cost_expected_idr,p_courier_cost_final_idr,
  p_provider_settlement_idr,p_provider_fee_idr,case when v_journal_found then p_finance_journal_entry_id else null end,v_status,p_evidence_sha256,
  case when v_status='reconciled' then p_actor_user_id else null end,
  case when v_status='reconciled' then now() else null end) returning id into v_id;
 update public.delivery_dispatches set cod_collected_idr=p_cod_collected_idr,cod_remitted_idr=p_cod_remitted_idr,
  courier_cost_expected_idr=p_courier_cost_expected_idr,courier_cost_final_idr=p_courier_cost_final_idr,updated_at=now()
  where tenant_id=p_tenant_id and id=p_dispatch_id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'delivery.cost.'||v_status,'delivery_cost_reconciliation',v_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'dispatch_id',p_dispatch_id,
   'finance_journal_entry_id',p_finance_journal_entry_id,'evidence_sha256',p_evidence_sha256));
 return jsonb_build_object('reconciliation_id',v_id,'status',v_status,'finance_journal_entry_id',p_finance_journal_entry_id);
end; $$;
revoke all on function public.delivery_reconcile_cost(uuid,uuid,uuid,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.delivery_reconcile_cost(uuid,uuid,uuid,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,uuid,text,uuid) to service_role;
create or replace function public.delivery_get_outbox_job_context(p_outbox_id uuid,p_worker_id text)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.delivery_outbox%rowtype; d public.delivery_dispatches%rowtype;
 q public.delivery_provider_quotes%rowtype; c public.delivery_provider_configs%rowtype; o public.orders%rowtype;
begin
 select * into v from public.delivery_outbox where id=p_outbox_id and status='claimed' and claimed_by=p_worker_id for update;
 if not found then raise exception using errcode='42501',message='DELIVERY_OUTBOX_CLAIM_MISMATCH'; end if;
 select * into d from public.delivery_dispatches where tenant_id=v.tenant_id and id=v.dispatch_id;
 if not found then raise exception using errcode='P0002',message='DELIVERY_DISPATCH_NOT_FOUND'; end if;
 select * into c from public.delivery_provider_configs where tenant_id=d.tenant_id and provider_key=d.provider
  and status='active' and (branch_id is null or branch_id=d.branch_id) order by branch_id nulls last limit 1;
 if not found then raise exception using errcode='42501',message='ACTIVE_DELIVERY_PROVIDER_CONFIG_NOT_FOUND'; end if;
 select * into q from public.delivery_provider_quotes where tenant_id=d.tenant_id and id=d.quote_id;
 select * into o from public.orders where id=d.order_id;
 return jsonb_build_object('outbox',to_jsonb(v),'dispatch',to_jsonb(d),'quote',case when q.id is null then null else to_jsonb(q) end,
  'provider_config',jsonb_build_object('id',c.id,'provider_key',c.provider_key,'display_name',c.display_name,
   'credential_secret_reference',c.credential_secret_reference,'integration_mode',c.integration_mode),
  'order',jsonb_build_object('id',o.id,'branch_id',o.branch_id,'delivery_address',o.delivery_address,
   'customer_name',o.customer_name,'customer_whatsapp',o.customer_whatsapp,'payment_status',o.payment_status));
end; $$;
revoke all on function public.delivery_get_outbox_job_context(uuid,text) from public,anon,authenticated;
grant execute on function public.delivery_get_outbox_job_context(uuid,text) to service_role;

-- Keep trigger helpers unavailable to client roles; service_role retains internal EXECUTE.
grant execute on function public.delivery_reject_evidence_mutation() to service_role;
