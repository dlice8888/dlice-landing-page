-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- Food-safety thresholds and allergen policy are explicitly tenant-approved; no universal limits are hard-coded.
create table if not exists public.food_safety_policies (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 policy_version integer not null check(policy_version>0),
 product_class text not null,
 min_temp_c numeric(7,3) not null,
 max_temp_c numeric(7,3) not null,
 required_allergens text[] not null default '{}',
 effective_from timestamptz not null,
 effective_until timestamptz null,
 status text not null default 'draft' check(status in ('draft','pending_approval','approved','retired')),
 created_by uuid not null references auth.users(id) on delete restrict,
 approved_by uuid null references auth.users(id) on delete restrict,
 approved_at timestamptz null,
 created_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,branch_id,product_class,policy_version),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 check(min_temp_c<=max_temp_c),
 check(status<>'approved' or (approved_by is not null and approved_at is not null)),
 check(approved_by is null or approved_by<>created_by),
 check(effective_until is null or effective_until>effective_from)
);
create table if not exists public.food_safety_inspections (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 policy_id uuid not null,
 source_type text not null check(source_type in ('receipt_item','production_batch','branch_check')),
 source_id uuid not null,
 lot_code text not null,
 measured_temp_c numeric(7,3) not null,
 min_temp_c_snapshot numeric(7,3) not null,
 max_temp_c_snapshot numeric(7,3) not null,
 declared_allergens text[] not null default '{}',
 missing_allergens text[] not null default '{}',
 temperature_in_range boolean not null,
 disposition text not null check(disposition in ('accepted','quarantined')),
 idempotency_key text not null,
 inspected_by uuid not null references auth.users(id) on delete restrict,
 inspected_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,idempotency_key),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 foreign key(tenant_id,policy_id) references public.food_safety_policies(tenant_id,id) on delete restrict
);
create table if not exists public.food_lot_quarantines (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 lot_code text not null,
 inspection_id uuid null,
 recall_id uuid null,
 reason_codes text[] not null,
 status text not null default 'held' check(status in ('held','release_pending','released','destroyed')),
 idempotency_key text not null,
 created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 released_by uuid null references auth.users(id) on delete restrict,
 released_at timestamptz null,
 unique(tenant_id,id),
 unique(tenant_id,idempotency_key),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 foreign key(tenant_id,inspection_id) references public.food_safety_inspections(tenant_id,id) on delete restrict,
 check(status<>'released' or (released_by is not null and released_at is not null))
);
create table if not exists public.food_recalls (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 lot_code text not null,
 reason text not null,
 severity text not null check(severity in ('low','medium','high','critical')),
 status text not null default 'initiated' check(status in ('initiated','in_progress','contained','closed')),
 affected_branch_count integer not null check(affected_branch_count>=0),
 affected_order_count integer not null check(affected_order_count>=0),
 idempotency_key text not null,
 created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,idempotency_key),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);
create table if not exists public.food_recall_impacts (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 recall_id uuid not null,
 impact_type text not null check(impact_type in ('branch','order','receipt','production_batch')),
 impact_entity_id uuid not null,
 quantity numeric(14,3) null check(quantity is null or quantity>=0),
 created_at timestamptz not null default now(),
 foreign key(tenant_id,recall_id) references public.food_recalls(tenant_id,id) on delete restrict,
 unique(tenant_id,recall_id,impact_type,impact_entity_id)
);
create table if not exists public.supplier_quality_policies (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 supplier_id uuid not null references public.suppliers(id) on delete restrict,
 policy_version integer not null check(policy_version>0),
 critical_finding_codes text[] not null default '{}',
 effective_from timestamptz not null,
 effective_until timestamptz null,
 status text not null default 'draft' check(status in ('draft','pending_approval','approved','retired')),
 created_by uuid not null references auth.users(id) on delete restrict,
 approved_by uuid null references auth.users(id) on delete restrict,
 approved_at timestamptz null,
 created_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,branch_id,supplier_id,policy_version),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 check(status<>'approved' or (approved_by is not null and approved_at is not null)),
 check(approved_by is null or approved_by<>created_by),
 check(effective_until is null or effective_until>effective_from)
);
create table if not exists public.supplier_quality_inspections (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 supplier_id uuid not null references public.suppliers(id) on delete restrict,
 receipt_item_id uuid not null references public.purchase_receipt_items(id) on delete restrict,
 policy_id uuid not null,
 findings jsonb not null check(jsonb_typeof(findings)='array' and jsonb_array_length(findings)>0),
 disposition text not null check(disposition in ('accepted_with_observation','quarantined')),
 idempotency_key text not null,
 inspected_by uuid not null references auth.users(id) on delete restrict,
 inspected_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,idempotency_key),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 foreign key(tenant_id,policy_id) references public.supplier_quality_policies(tenant_id,id) on delete restrict
);
create table if not exists public.supplier_quality_quarantines (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 receipt_item_id uuid not null references public.purchase_receipt_items(id) on delete restrict,
 inspection_id uuid not null,
 quantity numeric(14,3) not null check(quantity>0),
 reason_codes text[] not null,
 status text not null default 'held' check(status in ('held','release_pending','released','returned','destroyed')),
 idempotency_key text not null,
 created_at timestamptz not null default now(),
 released_by uuid null references auth.users(id) on delete restrict,
 released_at timestamptz null,
 unique(tenant_id,id),
 unique(tenant_id,idempotency_key),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 foreign key(tenant_id,inspection_id) references public.supplier_quality_inspections(tenant_id,id) on delete restrict,
 check(status<>'released' or (released_by is not null and released_at is not null))
);
create table if not exists public.supplier_corrective_actions (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 supplier_id uuid not null references public.suppliers(id) on delete restrict,
 inspection_id uuid not null,
 status text not null default 'open' check(status in ('open','in_progress','submitted','verified','rejected','closed')),
 root_cause text null,
 corrective_action text null,
 preventive_action text null,
 evidence_reference text null,
 created_by uuid not null references auth.users(id) on delete restrict,
 submitted_by uuid null references auth.users(id) on delete restrict,
 verified_by uuid null references auth.users(id) on delete restrict,
 verified_at timestamptz null,
 idempotency_key text not null,
 created_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,idempotency_key),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 foreign key(tenant_id,inspection_id) references public.supplier_quality_inspections(tenant_id,id) on delete restrict,
 check(submitted_by is null or submitted_by<>created_by),
 check(verified_by is null or (verified_by<>created_by and verified_by<>submitted_by)),
 check(status not in ('verified','closed') or (verified_by is not null and verified_at is not null))
);
create table if not exists public.quality_compliance_events (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 entity_type text not null check(entity_type in ('food_safety_inspection','food_recall','food_lot_quarantine','supplier_quality_inspection','supplier_quarantine','supplier_capa')),
 entity_id uuid not null,
 action text not null,
 actor_user_id uuid not null references auth.users(id) on delete restrict,
 idempotency_key text not null,
 evidence jsonb not null default '{}'::jsonb check(jsonb_typeof(evidence)='object'),
 created_at timestamptz not null default now(),
 unique(tenant_id,idempotency_key),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);
create index if not exists food_safety_inspections_lot_idx on public.food_safety_inspections(tenant_id,branch_id,lot_code,inspected_at desc);
create index if not exists food_recalls_lot_idx on public.food_recalls(tenant_id,lot_code,created_at desc);
create index if not exists supplier_quality_inspections_supplier_idx on public.supplier_quality_inspections(tenant_id,branch_id,supplier_id,inspected_at desc);
create index if not exists supplier_capa_status_idx on public.supplier_corrective_actions(tenant_id,branch_id,status,created_at);
do $$
declare t text;
begin
 foreach t in array array['food_safety_policies','food_safety_inspections','food_lot_quarantines','food_recalls','food_recall_impacts','supplier_quality_policies','supplier_quality_inspections','supplier_quality_quarantines','supplier_corrective_actions','quality_compliance_events'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists service_role_only on public.%I',t);
  execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant select,insert,update,delete on public.%I to service_role',t);
 end loop;
end $$;
