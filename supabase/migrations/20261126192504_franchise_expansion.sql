-- D'Lice FnB OS official migration generated from reviewed domain SQL drafts.
-- Source files:
--   docs/implementation/sql/FRANCHISE_EXPANSION_SCHEMA_DRAFT.sql

create table if not exists public.franchise_applications (
 id uuid primary key default gen_random_uuid(),
 applicant_name text not null check(length(btrim(applicant_name)) between 2 and 160),
 applicant_email text not null,
 applicant_phone text not null,
 proposed_region text not null,
 proposed_city text not null,
 investment_capacity_idr bigint not null check(investment_capacity_idr>=0),
 experience_summary text null,
 status text not null default 'submitted' check(status in ('submitted','screening','due_diligence','approved','rejected','withdrawn')),
 assigned_reviewer uuid null references auth.users(id) on delete restrict,
 submitted_at timestamptz not null default now(),
 reviewed_at timestamptz null,
 created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists franchise_applications_status_idx on public.franchise_applications(status,submitted_at);

create table if not exists public.franchise_due_diligence_checks (
 id uuid primary key default gen_random_uuid(),
 application_id uuid not null references public.franchise_applications(id) on delete restrict,
 check_key text not null check(check_key in ('identity','financial','legal','operational_experience','territory_conflict','reputation')),
 status text not null default 'pending' check(status in ('pending','passed','failed','waived')),
 evidence_reference text null,
 reviewer_user_id uuid null references auth.users(id) on delete restrict,
 reviewed_at timestamptz null,
 notes text null,
 created_at timestamptz not null default now(),
 unique(application_id,check_key),
 check(status not in ('passed','waived') or (reviewer_user_id is not null and reviewed_at is not null))
);

create table if not exists public.franchise_sites (
 id uuid primary key default gen_random_uuid(),
 application_id uuid not null references public.franchise_applications(id) on delete restrict,
 proposed_address text not null,
 city text not null,
 province text not null,
 latitude numeric(9,6) null,
 longitude numeric(9,6) null,
 floor_area_sqm numeric(10,2) null check(floor_area_sqm is null or floor_area_sqm>0),
 feasibility_status text not null default 'pending' check(feasibility_status in ('pending','assessing','approved','rejected')),
 feasibility_score numeric(5,2) null check(feasibility_score is null or feasibility_score between 0 and 100),
 evidence_reference text null,
 reviewed_by uuid null references auth.users(id) on delete restrict,
 reviewed_at timestamptz null,
 created_at timestamptz not null default now(),
 check((latitude is null)=(longitude is null)),
 check(latitude is null or latitude between -90 and 90),
 check(longitude is null or longitude between -180 and 180),
 check(feasibility_status<>'approved' or (reviewed_by is not null and reviewed_at is not null and evidence_reference is not null))
);

create table if not exists public.franchise_agreements (
 id uuid primary key default gen_random_uuid(),
 application_id uuid not null references public.franchise_applications(id) on delete restrict,
 tenant_id uuid null references public.tenants(id) on delete restrict,
 branch_id uuid null references public.branches(id) on delete restrict,
 agreement_status text not null default 'draft' check(agreement_status in ('draft','pending_signature','active','expired','terminated')),
 current_version integer not null default 1 check(current_version>0),
 signed_at timestamptz null,
 effective_from date null,
 effective_to date null,
 created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 check((tenant_id is null)=(branch_id is null)),
 check(effective_to is null or effective_from is null or effective_to>=effective_from),
 check(agreement_status<>'active' or (tenant_id is not null and branch_id is not null and signed_at is not null and effective_from is not null))
);
create table if not exists public.franchise_agreement_versions (
 id uuid primary key default gen_random_uuid(),
 agreement_id uuid not null references public.franchise_agreements(id) on delete restrict,
 version integer not null check(version>0),
 royalty_rate_bps integer not null check(royalty_rate_bps between 0 and 5000),
 marketing_fee_rate_bps integer not null default 0 check(marketing_fee_rate_bps between 0 and 2000),
 fixed_monthly_fee_idr bigint not null default 0 check(fixed_monthly_fee_idr>=0),
 effective_from date not null,
 effective_to date null,
 signed_document_reference text null,
 approved_by uuid null references auth.users(id) on delete restrict,
 approved_at timestamptz null,
 created_at timestamptz not null default now(),
 unique(agreement_id,version),
 check(effective_to is null or effective_to>=effective_from),
 check((approved_by is null)=(approved_at is null))
);
create index if not exists franchise_agreement_version_effective_idx on public.franchise_agreement_versions(agreement_id,effective_from,effective_to);

create table if not exists public.franchise_opening_gates (
 id uuid primary key default gen_random_uuid(),
 agreement_id uuid not null references public.franchise_agreements(id) on delete restrict,
 gate_key text not null check(gate_key in ('legal_signed','site_approved','permits','fitout','equipment','staffing','training','inventory','pos_ready','brand_audit')),
 status text not null default 'pending' check(status in ('pending','in_progress','passed','blocked')),
 evidence_reference text null,
 verified_by uuid null references auth.users(id) on delete restrict,
 verified_at timestamptz null,
 notes text null,
 created_at timestamptz not null default now(),
 unique(agreement_id,gate_key),
 check(status<>'passed' or (evidence_reference is not null and verified_by is not null and verified_at is not null))
);

create table if not exists public.franchise_royalty_statements (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 agreement_id uuid not null references public.franchise_agreements(id) on delete restrict,
 agreement_version_id uuid not null references public.franchise_agreement_versions(id) on delete restrict,
 period_start date not null,
 period_end date not null,
 eligible_net_sales_idr bigint not null check(eligible_net_sales_idr>=0),
 royalty_rate_bps integer not null check(royalty_rate_bps between 0 and 5000),
 royalty_amount_idr bigint generated always as ((eligible_net_sales_idr::numeric*royalty_rate_bps/10000)::bigint) stored,
 marketing_fee_rate_bps integer not null check(marketing_fee_rate_bps between 0 and 2000),
 marketing_fee_amount_idr bigint generated always as ((eligible_net_sales_idr::numeric*marketing_fee_rate_bps/10000)::bigint) stored,
 status text not null default 'draft' check(status in ('draft','reviewed','approved','invoiced','paid','disputed')),
 source_reconciliation_reference text not null,
 idempotency_key text not null,
 reviewed_by uuid null references auth.users(id) on delete restrict,
 approved_by uuid null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,branch_id,period_start,period_end),
 unique(tenant_id,idempotency_key),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 check(period_end>=period_start),
 check(length(btrim(source_reconciliation_reference))>=8),
 check(length(btrim(idempotency_key)) between 8 and 120),
 check(status not in ('approved','invoiced','paid') or (reviewed_by is not null and approved_by is not null and reviewed_by<>approved_by))
);
create index if not exists franchise_royalty_period_idx on public.franchise_royalty_statements(tenant_id,period_start,period_end,status);

do $$
declare t text;
begin
 foreach t in array array['franchise_applications','franchise_due_diligence_checks','franchise_sites','franchise_agreements','franchise_agreement_versions','franchise_opening_gates','franchise_royalty_statements'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists service_role_only on public.%I',t);
  execute format('create policy service_role_only on public.%I for all to service_role using (true) with check (true)',t);
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant select,insert,update,delete on public.%I to service_role',t);
 end loop;
end $$;

-- Opening must be blocked unless all ten gates are passed; agreement version must be effective.
create or replace function public.franchise_assert_opening_ready(p_agreement_id uuid,p_opening_date date)
returns boolean language plpgsql security invoker set search_path=''
as $$
declare v_count integer; v_agreement public.franchise_agreements%rowtype;
begin
 select * into v_agreement from public.franchise_agreements where id=p_agreement_id for update;
 if not found or v_agreement.agreement_status<>'active' then raise exception using errcode='23514',message='FRANCHISE_AGREEMENT_NOT_ACTIVE'; end if;
 if not exists(select 1 from public.franchise_agreement_versions v where v.agreement_id=p_agreement_id and v.version=v_agreement.current_version and v.effective_from<=p_opening_date and (v.effective_to is null or v.effective_to>=p_opening_date)) then
  raise exception using errcode='23514',message='FRANCHISE_AGREEMENT_VERSION_NOT_EFFECTIVE';
 end if;
 select count(*) into v_count from public.franchise_opening_gates where agreement_id=p_agreement_id and status='passed';
 if v_count<>10 then raise exception using errcode='23514',message='FRANCHISE_OPENING_GATES_INCOMPLETE'; end if;
 return true;
end $$;
revoke all on function public.franchise_assert_opening_ready(uuid,date) from public,anon,authenticated;
grant execute on function public.franchise_assert_opening_ready(uuid,date) to service_role;

create or replace function public.franchise_create_application(
 p_applicant_name text,p_applicant_email text,p_applicant_phone text,p_proposed_region text,
 p_proposed_city text,p_investment_capacity_idr bigint,p_experience_summary text,p_created_by uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_app public.franchise_applications%rowtype;
begin
 if length(btrim(coalesce(p_applicant_name,''))) not between 2 and 160
  or p_applicant_email !~ '^\\S+@\\S+\\.\\S+
 p_application_id uuid,p_decision text,p_actor_user_id uuid,p_notes text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_app public.franchise_applications%rowtype; v_checks integer; v_passed integer; v_site integer; v_previous_status text;
begin
 if p_decision not in ('screening','due_diligence','approved','rejected') then
  raise exception using errcode='22023',message='INVALID_FRANCHISE_DECISION';
 end if;
 select * into v_app from public.franchise_applications where id=p_application_id for update;
 if not found then raise exception using errcode='P0002',message='FRANCHISE_APPLICATION_NOT_FOUND'; end if;
 v_previous_status:=v_app.status;
 if v_app.status in ('approved','rejected','withdrawn') then raise exception using errcode='23514',message='FRANCHISE_APPLICATION_TERMINAL'; end if;
 if p_decision='approved' and v_app.created_by=p_actor_user_id then raise exception using errcode='42501',message='INDEPENDENT_FRANCHISE_APPROVER_REQUIRED'; end if;
 if p_decision='approved' then
  if v_app.status<>'due_diligence' then raise exception using errcode='23514',message='FRANCHISE_DUE_DILIGENCE_REQUIRED'; end if;
  select count(*),count(*) filter(where status in ('passed','waived')) into v_checks,v_passed
   from public.franchise_due_diligence_checks where application_id=p_application_id;
  if v_checks<>6 or v_passed<>6 then raise exception using errcode='23514',message='FRANCHISE_DUE_DILIGENCE_INCOMPLETE'; end if;
  select count(*) into v_site from public.franchise_sites where application_id=p_application_id and feasibility_status='approved';
  if v_site=0 then raise exception using errcode='23514',message='FRANCHISE_SITE_NOT_APPROVED'; end if;
 end if;
 update public.franchise_applications set status=p_decision,assigned_reviewer=coalesce(assigned_reviewer,p_actor_user_id),
  reviewed_at=case when p_decision in ('approved','rejected') then now() else reviewed_at end,updated_at=now()
 where id=p_application_id returning * into v_app;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'franchise.application.'||p_decision,'franchise_application',v_app.id::text,
  jsonb_build_object('previous_status',v_previous_status,'notes',left(coalesce(p_notes,''),500)));
 return jsonb_build_object('application_id',v_app.id,'status',v_app.status);
end $$;
revoke all on function public.franchise_review_application(uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.franchise_review_application(uuid,text,uuid,text) to service_role;

create or replace function public.franchise_generate_royalty_statement(
 p_tenant_id uuid,p_branch_id uuid,p_agreement_id uuid,p_period_start date,p_period_end date,
 p_reconciliation_run_id uuid,p_idempotency_key text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_agreement public.franchise_agreements%rowtype; v_version public.franchise_agreement_versions%rowtype;
 v_metric_id uuid; v_sales numeric; v_recon public.bi_reconciliation_runs%rowtype; v_statement public.franchise_royalty_statements%rowtype;
begin
 if p_period_end<p_period_start or length(coalesce(p_idempotency_key,'')) not between 8 and 120 then
  raise exception using errcode='22023',message='INVALID_ROYALTY_PERIOD_OR_IDEMPOTENCY';
 end if;
 select * into v_agreement from public.franchise_agreements where id=p_agreement_id and tenant_id=p_tenant_id and branch_id=p_branch_id and agreement_status='active' for update;
 if not found then raise exception using errcode='42501',message='ACTIVE_FRANCHISE_AGREEMENT_NOT_FOUND'; end if;
 select * into v_version from public.franchise_agreement_versions where agreement_id=p_agreement_id and version=v_agreement.current_version
  and effective_from<=p_period_start and (effective_to is null or effective_to>=p_period_end);
 if not found then raise exception using errcode='23514',message='FRANCHISE_VERSION_NOT_EFFECTIVE_FOR_PERIOD'; end if;
 select * into v_recon from public.bi_reconciliation_runs where id=p_reconciliation_run_id and tenant_id=p_tenant_id
  and status='passed' and period_start<=p_period_start and period_end>=p_period_end;
 if not found then raise exception using errcode='23514',message='SALES_RECONCILIATION_REQUIRED'; end if;
 select id into v_metric_id from public.bi_metric_definitions where metric_key='net_sales' and active=true and unit='idr';
 if not found then raise exception using errcode='23514',message='NET_SALES_METRIC_NOT_CONFIGURED'; end if;
 select metric_value into v_sales from public.bi_metric_snapshots where tenant_id=p_tenant_id and metric_id=v_metric_id
  and status='published' and dimension_key='branch_id' and dimension_value=p_branch_id::text
  and period_start::date=p_period_start and period_end::date=p_period_end
  and formula_version=(select formula_version from public.bi_metric_definitions where id=v_metric_id)
  order by published_at desc limit 1;
 if not found or v_sales is null or v_sales<0 or v_sales<>trunc(v_sales) then
  raise exception using errcode='23514',message='PUBLISHED_RECONCILED_BRANCH_NET_SALES_REQUIRED';
 end if;
 insert into public.franchise_royalty_statements(tenant_id,branch_id,agreement_id,agreement_version_id,period_start,period_end,
  eligible_net_sales_idr,royalty_rate_bps,marketing_fee_rate_bps,status,source_reconciliation_reference,idempotency_key)
 values(p_tenant_id,p_branch_id,p_agreement_id,v_version.id,p_period_start,p_period_end,v_sales::bigint,
  v_version.royalty_rate_bps,v_version.marketing_fee_rate_bps,'draft',p_reconciliation_run_id::text,p_idempotency_key)
 returning * into v_statement;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'franchise.royalty_statement.generated','franchise_royalty_statement',v_statement.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'period_start',p_period_start,'period_end',p_period_end,
   'net_sales_idr',v_statement.eligible_net_sales_idr,'royalty_idr',v_statement.royalty_amount_idr,'reconciliation_id',p_reconciliation_run_id));
 return jsonb_build_object('statement_id',v_statement.id,'eligible_net_sales_idr',v_statement.eligible_net_sales_idr,
  'royalty_amount_idr',v_statement.royalty_amount_idr,'marketing_fee_amount_idr',v_statement.marketing_fee_amount_idr,'status',v_statement.status);
end $$;
revoke all on function public.franchise_generate_royalty_statement(uuid,uuid,uuid,date,date,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.franchise_generate_royalty_statement(uuid,uuid,uuid,date,date,uuid,text,uuid) to service_role;

-- Royalty statement generation must consume reconciled net sales, never raw order totals.
-- The caller supplies a signed-off reconciliation reference and the exact effective agreement version.

  or length(btrim(coalesce(p_applicant_phone,'')))<8
  or p_investment_capacity_idr<0 then
  raise exception using errcode='22023',message='INVALID_FRANCHISE_APPLICATION';
 end if;
 insert into public.franchise_applications(applicant_name,applicant_email,applicant_phone,proposed_region,proposed_city,investment_capacity_idr,experience_summary,created_by)
 values(btrim(p_applicant_name),lower(btrim(p_applicant_email)),btrim(p_applicant_phone),btrim(p_proposed_region),btrim(p_proposed_city),p_investment_capacity_idr,p_experience_summary,p_created_by)
 returning * into v_app;
 insert into public.franchise_due_diligence_checks(application_id,check_key)
 select v_app.id,k from unnest(array['identity','financial','legal','operational_experience','territory_conflict','reputation']) k;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_created_by,'franchise.application.created','franchise_application',v_app.id::text,
  jsonb_build_object('proposed_region',v_app.proposed_region,'proposed_city',v_app.proposed_city));
 return jsonb_build_object('id',v_app.id,'applicant_name',v_app.applicant_name,'status',v_app.status,'submitted_at',v_app.submitted_at);
end $$;
revoke all on function public.franchise_create_application(text,text,text,text,text,bigint,text,uuid) from public,anon,authenticated;
grant execute on function public.franchise_create_application(text,text,text,text,text,bigint,text,uuid) to service_role;

create or replace function public.franchise_review_due_diligence_check(
 p_check_id uuid,p_status text,p_evidence_reference text,p_actor_user_id uuid,p_notes text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.franchise_due_diligence_checks%rowtype; v_creator uuid;
begin
 if p_status not in ('passed','failed','waived','pending') then raise exception using errcode='22023',message='INVALID_DUE_DILIGENCE_STATUS'; end if;
 if p_status in ('passed','waived') and length(btrim(coalesce(p_evidence_reference,'')))<8 then raise exception using errcode='22023',message='DUE_DILIGENCE_EVIDENCE_REQUIRED'; end if;
 select * into v from public.franchise_due_diligence_checks where id=p_check_id for update;
 if not found then raise exception using errcode='P0002',message='DUE_DILIGENCE_CHECK_NOT_FOUND'; end if;
 select created_by into v_creator from public.franchise_applications where id=v.application_id;
 if v_creator=p_actor_user_id then raise exception using errcode='42501',message='APPLICANT_CANNOT_REVIEW_OWN_CHECK'; end if;
 update public.franchise_due_diligence_checks set status=p_status,evidence_reference=case when p_status in ('passed','waived') then p_evidence_reference else evidence_reference end,
 reviewer_user_id=p_actor_user_id,reviewed_at=now(),notes=left(coalesce(p_notes,''),1000)
 where id=p_check_id returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'franchise.due_diligence.'||p_status,'franchise_due_diligence_check',v.id::text,
 jsonb_build_object('application_id',v.application_id,'check_key',v.check_key));
 return jsonb_build_object('check_id',v.id,'check_key',v.check_key,'status',v.status);
end $$;
revoke all on function public.franchise_review_due_diligence_check(uuid,text,text,uuid,text) from public,anon,authenticated;
grant execute on function public.franchise_review_due_diligence_check(uuid,text,text,uuid,text) to service_role;

create or replace function public.franchise_review_site(
 p_site_id uuid,p_status text,p_evidence_reference text,p_actor_user_id uuid,p_notes text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_site public.franchise_sites%rowtype;
begin
 if p_status not in ('approved','rejected','assessing') then raise exception using errcode='22023',message='INVALID_SITE_DECISION'; end if;
 if p_status='approved' and length(btrim(coalesce(p_evidence_reference,'')))<8 then raise exception using errcode='22023',message='SITE_EVIDENCE_REQUIRED'; end if;
 select * into v_site from public.franchise_sites where id=p_site_id for update;
 if not found then raise exception using errcode='P0002',message='FRANCHISE_SITE_NOT_FOUND'; end if;
 if exists(select 1 from public.franchise_applications a where a.id=v_site.application_id and a.created_by=p_actor_user_id) then raise exception using errcode='42501',message='APPLICANT_CANNOT_APPROVE_OWN_SITE'; end if;
 update public.franchise_sites set feasibility_status=p_status,evidence_reference=case when p_status='approved' then p_evidence_reference else evidence_reference end,
  reviewed_by=p_actor_user_id,reviewed_at=now() where id=p_site_id returning * into v_site;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'franchise.site.'||p_status,'franchise_site',v_site.id::text,jsonb_build_object('application_id',v_site.application_id,'notes',left(coalesce(p_notes,''),500)));
 return jsonb_build_object('site_id',v_site.id,'status',v_site.feasibility_status);
end $$;
revoke all on function public.franchise_review_site(uuid,text,text,uuid,text) from public,anon,authenticated;
grant execute on function public.franchise_review_site(uuid,text,text,uuid,text) to service_role;

create or replace function public.franchise_review_application(
 p_application_id uuid,p_decision text,p_actor_user_id uuid,p_notes text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_app public.franchise_applications%rowtype; v_checks integer; v_passed integer; v_site integer; v_previous_status text;
begin
 if p_decision not in ('screening','due_diligence','approved','rejected') then
  raise exception using errcode='22023',message='INVALID_FRANCHISE_DECISION';
 end if;
 select * into v_app from public.franchise_applications where id=p_application_id for update;
 if not found then raise exception using errcode='P0002',message='FRANCHISE_APPLICATION_NOT_FOUND'; end if;
 v_previous_status:=v_app.status;
 if v_app.status in ('approved','rejected','withdrawn') then raise exception using errcode='23514',message='FRANCHISE_APPLICATION_TERMINAL'; end if;
 if p_decision='approved' then
  if v_app.status<>'due_diligence' then raise exception using errcode='23514',message='FRANCHISE_DUE_DILIGENCE_REQUIRED'; end if;
  select count(*),count(*) filter(where status in ('passed','waived')) into v_checks,v_passed
   from public.franchise_due_diligence_checks where application_id=p_application_id;
  if v_checks<>6 or v_passed<>6 then raise exception using errcode='23514',message='FRANCHISE_DUE_DILIGENCE_INCOMPLETE'; end if;
  select count(*) into v_site from public.franchise_sites where application_id=p_application_id and feasibility_status='approved';
  if v_site=0 then raise exception using errcode='23514',message='FRANCHISE_SITE_NOT_APPROVED'; end if;
 end if;
 update public.franchise_applications set status=p_decision,assigned_reviewer=coalesce(assigned_reviewer,p_actor_user_id),
  reviewed_at=case when p_decision in ('approved','rejected') then now() else reviewed_at end,updated_at=now()
 where id=p_application_id returning * into v_app;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'franchise.application.'||p_decision,'franchise_application',v_app.id::text,
  jsonb_build_object('previous_status',v_previous_status,'notes',left(coalesce(p_notes,''),500)));
 return jsonb_build_object('application_id',v_app.id,'status',v_app.status);
end $$;
revoke all on function public.franchise_review_application(uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.franchise_review_application(uuid,text,uuid,text) to service_role;

-- Royalty statement generation must consume reconciled net sales, never raw order totals.
-- The caller supplies a signed-off reconciliation reference and the exact effective agreement version.


-- Append-only agreement lifecycle evidence. Signature proof is a controlled
-- document reference; this RPC does not pretend to cryptographically verify
-- an external e-signature provider.
create table if not exists public.franchise_agreement_events (
 id uuid primary key default gen_random_uuid(),
 agreement_id uuid not null references public.franchise_agreements(id) on delete restrict,
 event_type text not null check(event_type in ('submitted_for_signature','version_approved','signature_recorded','activated','expired','terminated','amended')),
 actor_user_id uuid not null references auth.users(id) on delete restrict,
 document_reference text null,
 occurred_at timestamptz not null default now(),
 metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object')
);
create index if not exists franchise_agreement_events_timeline_idx
 on public.franchise_agreement_events(agreement_id,occurred_at,id);
alter table public.franchise_agreement_events enable row level security;
drop policy if exists service_role_only on public.franchise_agreement_events;
create policy service_role_only on public.franchise_agreement_events for all to service_role using(true) with check(true);
revoke all on public.franchise_agreement_events from anon,authenticated;
grant select,insert,update,delete on public.franchise_agreement_events to service_role;

create or replace function public.franchise_submit_agreement_for_signature(
 p_agreement_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.franchise_agreements%rowtype; v_version public.franchise_agreement_versions%rowtype;
begin
 select * into v from public.franchise_agreements where id=p_agreement_id for update;
 if not found then raise exception using errcode='P0002',message='FRANCHISE_AGREEMENT_NOT_FOUND'; end if;
 if v.agreement_status<>'draft' then raise exception using errcode='23514',message='FRANCHISE_AGREEMENT_NOT_DRAFT'; end if;
 if p_actor_user_id=v.created_by then raise exception using errcode='42501',message='INDEPENDENT_AGREEMENT_SUBMITTER_REQUIRED'; end if;
 select * into v_version from public.franchise_agreement_versions
  where agreement_id=v.id and version=v.current_version for update;
 if not found or v_version.approved_by is null or v_version.approved_by=p_actor_user_id or v_version.effective_from is null then
  raise exception using errcode='23514',message='APPROVED_EFFECTIVE_AGREEMENT_VERSION_REQUIRED';
 end if;
 update public.franchise_agreements set agreement_status='pending_signature' where id=v.id;
 insert into public.franchise_agreement_events(agreement_id,event_type,actor_user_id,document_reference,metadata)
 values(v.id,'submitted_for_signature',p_actor_user_id,v_version.signed_document_reference,
  jsonb_build_object('version',v.current_version));
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'franchise.agreement.submitted_for_signature','franchise_agreement',v.id::text,
  jsonb_build_object('version',v.current_version));
 return jsonb_build_object('agreement_id',v.id,'status','pending_signature','version',v.current_version);
end $$;
revoke all on function public.franchise_submit_agreement_for_signature(uuid,uuid) from public,anon,authenticated;
grant execute on function public.franchise_submit_agreement_for_signature(uuid,uuid) to service_role;

create or replace function public.franchise_record_agreement_signature(
 p_agreement_id uuid,p_actor_user_id uuid,p_signed_at timestamptz,
 p_signed_document_reference text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.franchise_agreements%rowtype; v_version public.franchise_agreement_versions%rowtype;
begin
 select * into v from public.franchise_agreements where id=p_agreement_id for update;
 if not found then raise exception using errcode='P0002',message='FRANCHISE_AGREEMENT_NOT_FOUND'; end if;
 if v.agreement_status<>'pending_signature' then raise exception using errcode='23514',message='FRANCHISE_AGREEMENT_NOT_PENDING_SIGNATURE'; end if;
 if p_signed_at is null or p_signed_at>now()+interval '5 minutes' or length(btrim(coalesce(p_signed_document_reference,'')))<8 then
  raise exception using errcode='22023',message='SIGNED_DOCUMENT_EVIDENCE_REQUIRED';
 end if;
 select * into v_version from public.franchise_agreement_versions
  where agreement_id=v.id and version=v.current_version for update;
 if not found or p_actor_user_id in (v.created_by,v_version.approved_by) then
  raise exception using errcode='42501',message='INDEPENDENT_SIGNATURE_REVIEWER_REQUIRED';
 end if;
 if v.tenant_id is null or v.branch_id is null or
    not exists(select 1 from public.branches where id=v.branch_id and tenant_id=v.tenant_id) then
  raise exception using errcode='23514',message='FRANCHISE_TENANT_BRANCH_PROVISIONING_REQUIRED';
 end if;
 if p_signed_at::date<v_version.effective_from or
    (v_version.effective_to is not null and p_signed_at::date>v_version.effective_to) then
  raise exception using errcode='23514',message='AGREEMENT_VERSION_NOT_EFFECTIVE_AT_SIGNATURE';
 end if;
 update public.franchise_agreement_versions set signed_document_reference=p_signed_document_reference
  where id=v_version.id;
 update public.franchise_agreements set agreement_status='active',signed_at=p_signed_at,
  effective_from=v_version.effective_from,effective_to=v_version.effective_to where id=v.id;
 insert into public.franchise_agreement_events(agreement_id,event_type,actor_user_id,document_reference,metadata)
 values(v.id,'signature_recorded',p_actor_user_id,p_signed_document_reference,
  jsonb_build_object('version',v.current_version,'signed_at',p_signed_at));
 insert into public.franchise_agreement_events(agreement_id,event_type,actor_user_id,document_reference,metadata)
 values(v.id,'activated',p_actor_user_id,p_signed_document_reference,
  jsonb_build_object('version',v.current_version,'tenant_id',v.tenant_id,'branch_id',v.branch_id));
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'franchise.agreement.activated','franchise_agreement',v.id::text,
  jsonb_build_object('version',v.current_version,'tenant_id',v.tenant_id,'branch_id',v.branch_id));
 return jsonb_build_object('agreement_id',v.id,'status','active','version',v.current_version,
  'signed_at',p_signed_at,'document_reference',p_signed_document_reference);
end $$;
revoke all on function public.franchise_record_agreement_signature(uuid,uuid,timestamptz,text) from public,anon,authenticated;
grant execute on function public.franchise_record_agreement_signature(uuid,uuid,timestamptz,text) to service_role;

create or replace function public.franchise_reject_agreement_event_mutation()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
 raise exception using errcode='42501',message='FRANCHISE_AGREEMENT_EVENTS_APPEND_ONLY';
end $$;
revoke all on function public.franchise_reject_agreement_event_mutation() from public,anon,authenticated;
drop trigger if exists franchise_agreement_events_immutable on public.franchise_agreement_events;
create trigger franchise_agreement_events_immutable before update or delete on public.franchise_agreement_events
for each row execute function public.franchise_reject_agreement_event_mutation();


-- Create a controlled draft agreement only after application, due diligence,
-- and site assessment are approved. The creator cannot submit their own
-- agreement for signature.
create or replace function public.franchise_create_agreement_draft(
 p_application_id uuid,p_royalty_rate_bps integer,p_marketing_fee_rate_bps integer,
 p_fixed_monthly_fee_idr bigint,p_effective_from date,p_effective_to date,
 p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_app public.franchise_applications%rowtype; v_agreement public.franchise_agreements%rowtype;
 v_version public.franchise_agreement_versions%rowtype;
begin
 select * into v_app from public.franchise_applications where id=p_application_id for update;
 if not found or v_app.status<>'approved' then raise exception using errcode='23514',message='APPROVED_FRANCHISE_APPLICATION_REQUIRED'; end if;
 if not exists(select 1 from public.franchise_due_diligence_checks
   where application_id=v_app.id and status in ('passed','waived') group by application_id having count(*)=6) then
  raise exception using errcode='23514',message='FRANCHISE_DUE_DILIGENCE_INCOMPLETE';
 end if;
 if not exists(select 1 from public.franchise_sites where application_id=v_app.id and feasibility_status='approved') then
  raise exception using errcode='23514',message='APPROVED_FRANCHISE_SITE_REQUIRED';
 end if;
 if p_royalty_rate_bps not between 0 and 5000 or p_marketing_fee_rate_bps not between 0 and 2000
   or p_fixed_monthly_fee_idr<0 or p_effective_from is null
   or (p_effective_to is not null and p_effective_to<p_effective_from) then
  raise exception using errcode='22023',message='INVALID_FRANCHISE_AGREEMENT_TERMS';
 end if;
 insert into public.franchise_agreements(application_id,agreement_status,current_version,created_by)
 values(v_app.id,'draft',1,p_actor_user_id) returning * into v_agreement;
 insert into public.franchise_agreement_versions(
  agreement_id,version,royalty_rate_bps,marketing_fee_rate_bps,fixed_monthly_fee_idr,
  effective_from,effective_to
 ) values(v_agreement.id,1,p_royalty_rate_bps,p_marketing_fee_rate_bps,
  p_fixed_monthly_fee_idr,p_effective_from,p_effective_to)
 returning * into v_version;
 insert into public.franchise_opening_gates(agreement_id,gate_key)
 select v_agreement.id,k from unnest(array[
  'legal_signed','site_approved','permits','fitout','equipment','staffing','training','inventory','pos_ready','brand_audit'
 ]) k;
 insert into public.franchise_agreement_events(agreement_id,event_type,actor_user_id,metadata)
 values(v_agreement.id,'amended',p_actor_user_id,jsonb_build_object('version',1,'initial_draft',true));
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'franchise.agreement.draft_created','franchise_agreement',v_agreement.id::text,
  jsonb_build_object('application_id',v_app.id,'version',1));
 return jsonb_build_object('agreement_id',v_agreement.id,'version_id',v_version.id,'status','draft');
end $$;
revoke all on function public.franchise_create_agreement_draft(uuid,integer,integer,bigint,date,date,uuid) from public,anon,authenticated;
grant execute on function public.franchise_create_agreement_draft(uuid,integer,integer,bigint,date,date,uuid) to service_role;

-- Record externally signed document evidence before tenant/branch activation.
create or replace function public.franchise_record_agreement_signature(
 p_agreement_id uuid,p_actor_user_id uuid,p_signed_at timestamptz,
 p_signed_document_reference text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.franchise_agreements%rowtype; v_version public.franchise_agreement_versions%rowtype;
begin
 select * into v from public.franchise_agreements where id=p_agreement_id for update;
 if not found then raise exception using errcode='P0002',message='FRANCHISE_AGREEMENT_NOT_FOUND'; end if;
 if v.agreement_status<>'pending_signature' then raise exception using errcode='23514',message='FRANCHISE_AGREEMENT_NOT_PENDING_SIGNATURE'; end if;
 if p_signed_at is null or p_signed_at>now()+interval '5 minutes' or length(btrim(coalesce(p_signed_document_reference,'')))<8 then
  raise exception using errcode='22023',message='SIGNED_DOCUMENT_EVIDENCE_REQUIRED';
 end if;
 select * into v_version from public.franchise_agreement_versions
  where agreement_id=v.id and version=v.current_version for update;
 if not found or p_actor_user_id in (v.created_by,v_version.approved_by) then
  raise exception using errcode='42501',message='INDEPENDENT_SIGNATURE_REVIEWER_REQUIRED';
 end if;
 if p_signed_at::date<v_version.effective_from or
    (v_version.effective_to is not null and p_signed_at::date>v_version.effective_to) then
  raise exception using errcode='23514',message='AGREEMENT_VERSION_NOT_EFFECTIVE_AT_SIGNATURE';
 end if;
 update public.franchise_agreement_versions set signed_document_reference=p_signed_document_reference
  where id=v_version.id;
 update public.franchise_agreements set signed_at=p_signed_at,
  effective_from=v_version.effective_from,effective_to=v_version.effective_to where id=v.id;
 insert into public.franchise_agreement_events(agreement_id,event_type,actor_user_id,document_reference,metadata)
 values(v.id,'signature_recorded',p_actor_user_id,p_signed_document_reference,
  jsonb_build_object('version',v.current_version,'signed_at',p_signed_at));
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'franchise.agreement.signature_recorded','franchise_agreement',v.id::text,
  jsonb_build_object('version',v.current_version,'signed_at',p_signed_at));
 return jsonb_build_object('agreement_id',v.id,'status','signed_pending_provisioning',
  'version',v.current_version,'signed_at',p_signed_at);
end $$;
revoke all on function public.franchise_record_agreement_signature(uuid,uuid,timestamptz,text) from public,anon,authenticated;
grant execute on function public.franchise_record_agreement_signature(uuid,uuid,timestamptz,text) to service_role;


create or replace function public.franchise_review_opening_gate(
 p_agreement_id uuid,p_gate_key text,p_status text,p_evidence_reference text,
 p_actor_user_id uuid,p_notes text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.franchise_agreements%rowtype; g public.franchise_opening_gates%rowtype;
 v_approver uuid;
begin
 if p_status not in ('in_progress','passed','blocked') then
  raise exception using errcode='22023',message='INVALID_FRANCHISE_OPENING_GATE_STATUS';
 end if;
 if p_status='passed' and length(btrim(coalesce(p_evidence_reference,'')))<8 then
  raise exception using errcode='22023',message='FRANCHISE_OPENING_GATE_EVIDENCE_REQUIRED';
 end if;
 select * into v from public.franchise_agreements where id=p_agreement_id for update;
 if not found or v.signed_at is null or v.agreement_status not in ('pending_signature','active') then
  raise exception using errcode='23514',message='SIGNED_FRANCHISE_AGREEMENT_REQUIRED_FOR_OPENING_GATE';
 end if;
 select approved_by into v_approver from public.franchise_agreement_versions
  where agreement_id=v.id and version=v.current_version;
 if p_status='passed' and p_actor_user_id in (v.created_by,v_approver) then
  raise exception using errcode='42501',message='INDEPENDENT_FRANCHISE_GATE_VERIFIER_REQUIRED';
 end if;
 select * into g from public.franchise_opening_gates
  where agreement_id=v.id and gate_key=p_gate_key for update;
 if not found then raise exception using errcode='P0002',message='FRANCHISE_OPENING_GATE_NOT_FOUND'; end if;
 if g.status='passed' and p_status<>'passed' then
  raise exception using errcode='23514',message='PASSED_FRANCHISE_OPENING_GATE_IS_FINAL';
 end if;
 update public.franchise_opening_gates set status=p_status,
  evidence_reference=case when p_status='passed' then p_evidence_reference else evidence_reference end,
  verified_by=case when p_status='passed' then p_actor_user_id else null end,
  verified_at=case when p_status='passed' then now() else null end,
  notes=left(coalesce(p_notes,''),1000)
 where id=g.id returning * into g;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'franchise.opening_gate.'||p_status,'franchise_opening_gate',g.id::text,
  jsonb_build_object('agreement_id',v.id,'gate_key',g.gate_key,'evidence_reference',g.evidence_reference));
 return jsonb_build_object('agreement_id',v.id,'gate_key',g.gate_key,'status',g.status,
  'verified_by',g.verified_by,'verified_at',g.verified_at);
end $$;
revoke all on function public.franchise_review_opening_gate(uuid,text,text,text,uuid,text) from public,anon,authenticated;
grant execute on function public.franchise_review_opening_gate(uuid,text,text,text,uuid,text) to service_role;

create or replace function public.franchise_activate_signed_agreement(
 p_agreement_id uuid,p_tenant_id uuid,p_branch_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.franchise_agreements%rowtype; v_version public.franchise_agreement_versions%rowtype;
begin
 select * into v from public.franchise_agreements where id=p_agreement_id for update;
 if not found then raise exception using errcode='P0002',message='FRANCHISE_AGREEMENT_NOT_FOUND'; end if;
 if v.agreement_status<>'pending_signature' or v.signed_at is null then
  raise exception using errcode='23514',message='SIGNED_AGREEMENT_REQUIRED';
 end if;
 if v.tenant_id is not null or v.branch_id is not null then
  raise exception using errcode='23514',message='FRANCHISE_AGREEMENT_ALREADY_PROVISIONED';
 end if;
 if not exists(select 1 from public.branches where id=p_branch_id and tenant_id=p_tenant_id) then
  raise exception using errcode='42501',message='FRANCHISE_BRANCH_TENANT_MISMATCH';
 end if;
 select * into v_version from public.franchise_agreement_versions
  where agreement_id=v.id and version=v.current_version for update;
 if not found or v_version.signed_document_reference is null or
   v_version.effective_from>current_date or
   (v_version.effective_to is not null and v_version.effective_to<current_date) then
  raise exception using errcode='23514',message='SIGNED_EFFECTIVE_AGREEMENT_VERSION_REQUIRED';
 end if;
 if p_actor_user_id in (v.created_by,v_version.approved_by) then
  raise exception using errcode='42501',message='INDEPENDENT_AGREEMENT_ACTIVATOR_REQUIRED';
 end if;
 update public.franchise_agreements set tenant_id=p_tenant_id,branch_id=p_branch_id,
  agreement_status='active' where id=v.id;
 perform public.franchise_assert_opening_ready(v.id,current_date);
 insert into public.franchise_agreement_events(agreement_id,event_type,actor_user_id,document_reference,metadata)
 values(v.id,'activated',p_actor_user_id,v_version.signed_document_reference,
  jsonb_build_object('version',v.current_version,'tenant_id',p_tenant_id,'branch_id',p_branch_id));
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'franchise.agreement.activated','franchise_agreement',v.id::text,
  jsonb_build_object('version',v.current_version,'tenant_id',p_tenant_id,'branch_id',p_branch_id));
 return jsonb_build_object('agreement_id',v.id,'status','active','tenant_id',p_tenant_id,'branch_id',p_branch_id);
end $$;
revoke all on function public.franchise_activate_signed_agreement(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.franchise_activate_signed_agreement(uuid,uuid,uuid,uuid) to service_role;


create or replace function public.franchise_approve_agreement_version(
 p_agreement_id uuid,p_version integer,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.franchise_agreements%rowtype; vv public.franchise_agreement_versions%rowtype;
begin
 select * into v from public.franchise_agreements where id=p_agreement_id for update;
 if not found or v.agreement_status<>'draft' or v.current_version<>p_version then
  raise exception using errcode='23514',message='FRANCHISE_AGREEMENT_DRAFT_VERSION_REQUIRED';
 end if;
 if p_actor_user_id=v.created_by then raise exception using errcode='42501',message='INDEPENDENT_AGREEMENT_VERSION_APPROVER_REQUIRED'; end if;
 select * into vv from public.franchise_agreement_versions
  where agreement_id=v.id and version=p_version for update;
 if not found or vv.approved_by is not null then
  raise exception using errcode='23514',message='AGREEMENT_VERSION_ALREADY_APPROVED_OR_MISSING';
 end if;
 update public.franchise_agreement_versions set approved_by=p_actor_user_id,approved_at=now()
  where id=vv.id returning * into vv;
 insert into public.franchise_agreement_events(agreement_id,event_type,actor_user_id,metadata)
 values(v.id,'version_approved',p_actor_user_id,jsonb_build_object('version',p_version));
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'franchise.agreement.version_approved','franchise_agreement_version',vv.id::text,
  jsonb_build_object('agreement_id',v.id,'version',p_version));
 return jsonb_build_object('agreement_id',v.id,'version_id',vv.id,'version',p_version,'approved_by',p_actor_user_id);
end $$;
revoke all on function public.franchise_approve_agreement_version(uuid,integer,uuid) from public,anon,authenticated;
grant execute on function public.franchise_approve_agreement_version(uuid,integer,uuid) to service_role;
