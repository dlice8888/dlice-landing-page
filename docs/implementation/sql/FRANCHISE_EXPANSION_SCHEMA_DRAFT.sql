-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- Franchise records are platform-owned until a franchisee tenant is approved/provisioned.
-- Tenant and branch IDs are resolved by server-side Owner workflows, never client assertions.

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
 approved_by uuid not null references auth.users(id) on delete restrict,
 approved_at timestamptz not null,
 created_at timestamptz not null default now(),
 unique(agreement_id,version),
 check(effective_to is null or effective_to>=effective_from)
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
 royalty_amount_idr bigint generated always as ((eligible_net_sales_idr*royalty_rate_bps)/10000) stored,
 marketing_fee_rate_bps integer not null check(marketing_fee_rate_bps between 0 and 2000),
 marketing_fee_amount_idr bigint generated always as ((eligible_net_sales_idr*marketing_fee_rate_bps)/10000) stored,
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

-- Royalty statement generation must consume reconciled net sales, never raw order totals.
-- The caller supplies a signed-off reconciliation reference and the exact effective agreement version.
