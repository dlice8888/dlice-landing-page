-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- D05-F01/F02/F03/F04/F06/F09/F10: tenant catalog, branch availability, pricing, BOM and recipe rollout.
-- Product master is currently global; tenant_product_catalog is required before tenant-specific rollout.
begin;

create table if not exists public.tenant_product_catalog (
 tenant_id uuid not null references public.tenants(id) on delete restrict,product_id uuid not null references public.products(id) on delete restrict,
 catalog_version integer not null check(catalog_version>0),is_active boolean not null default true,
 published_by uuid not null references auth.users(id) on delete restrict,published_at timestamptz not null default now(),
 primary key(tenant_id,product_id)
);
create table if not exists public.tenant_product_categories (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 category_code text not null,name text not null,parent_id uuid references public.tenant_product_categories(id) on delete restrict,
 sort_order integer not null default 0,is_active boolean not null default true,unique(tenant_id,category_code),unique(tenant_id,id),foreign key(tenant_id,parent_id) references public.tenant_product_categories(tenant_id,id) on delete restrict
);
create table if not exists public.tenant_product_modifier_options (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 product_id uuid not null references public.products(id) on delete restrict,modifier_group text not null,modifier_code text not null,
 name text not null,price_delta_idr bigint not null default 0 check(price_delta_idr>=0),is_required boolean not null default false,
 is_active boolean not null default true,unique(tenant_id,product_id,modifier_group,modifier_code),
 foreign key(tenant_id,product_id) references public.tenant_product_catalog(tenant_id,product_id) on delete restrict
);
create table if not exists public.branch_product_availability (
 tenant_id uuid not null references public.tenants(id) on delete restrict,branch_id uuid not null,product_id uuid not null,
 is_available boolean not null default true,starts_at timestamptz,ends_at timestamptz,reason text not null,
 version integer not null default 1 check(version>0),updated_by uuid not null references auth.users(id) on delete restrict,
 updated_at timestamptz not null default now(),primary key(tenant_id,branch_id,product_id),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 foreign key(tenant_id,product_id) references public.tenant_product_catalog(tenant_id,product_id) on delete restrict,
 check(ends_at is null or starts_at is null or ends_at>starts_at)
);
create table if not exists public.tenant_regions (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 region_code text not null,name text not null,is_active boolean not null default true,unique(tenant_id,region_code),unique(tenant_id,id)
);
alter table public.branches add column if not exists region_id uuid;\nalter table public.branches add constraint branches_tenant_region_fk foreign key(tenant_id,region_id) references public.tenant_regions(tenant_id,id) on delete restrict;
create table if not exists public.pricing_policies (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 scope text not null check(scope in ('central','regional','branch')),branch_id uuid,region_id uuid,
 product_id uuid not null references public.products(id) on delete restrict,price_idr bigint not null check(price_idr>=0),
 effective_from timestamptz not null,effective_to timestamptz,approval_id uuid,
 version integer not null default 1 check(version>0),created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),check(effective_to is null or effective_to>effective_from),
 check((scope='central' and branch_id is null and region_id is null) or
  (scope='regional' and branch_id is null and region_id is not null) or
  (scope='branch' and branch_id is not null and region_id is null)),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 foreign key(tenant_id,region_id) references public.tenant_regions(tenant_id,id) on delete restrict,
 foreign key(tenant_id,product_id) references public.tenant_product_catalog(tenant_id,product_id) on delete restrict
);
create index if not exists pricing_policy_resolution_idx on public.pricing_policies(tenant_id,product_id,effective_from desc);
create table if not exists public.recipe_bom_lines (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 recipe_id uuid not null,parent_line_id uuid references public.recipe_bom_lines(id) on delete restrict,
 inventory_item_id uuid references public.inventory_items(id) on delete restrict,child_recipe_id uuid references public.recipes(id) on delete restrict,
 quantity numeric(14,4) not null check(quantity>0),unit text not null,position integer not null default 0,
 created_at timestamptz not null default now(),check(num_nonnulls(inventory_item_id,child_recipe_id)=1),\n foreign key(tenant_id,recipe_id) references public.tenant_recipe_scopes(tenant_id,recipe_id) on delete restrict,\n foreign key(tenant_id,child_recipe_id) references public.tenant_recipe_scopes(tenant_id,recipe_id) on delete restrict\n);
create table if not exists public.recipe_change_requests (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,recipe_id uuid not null,
 created_by uuid not null references auth.users(id) on delete restrict,change_set jsonb not null check(jsonb_typeof(change_set)='object'),
 costing_snapshot jsonb,status text not null default 'draft' check(status in ('draft','pending_approval','approved','rejected','rolling_out','completed','failed')),
 version integer not null default 1,idempotency_key text not null,created_at timestamptz not null default now(),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,\n foreign key(tenant_id,recipe_id) references public.tenant_recipe_scopes(tenant_id,recipe_id) on delete restrict,unique(tenant_id,idempotency_key)\n);
create table if not exists public.recipe_change_rollout_branches (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 request_id uuid not null references public.recipe_change_requests(id) on delete cascade,branch_id uuid not null,
 status text not null default 'pending' check(status in ('pending','published','acknowledged','failed')),
 error text,updated_at timestamptz not null default now(),foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 unique(request_id,branch_id)
);

do $$ declare t text; begin
 foreach t in array array['tenant_product_catalog','tenant_product_categories','tenant_product_modifier_options','branch_product_availability',
  'tenant_regions','pricing_policies','recipe_bom_lines','recipe_change_requests','recipe_change_rollout_branches'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('alter table public.%I force row level security',t);
  execute format('drop policy if exists service_role_only on public.%I',t);
  execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select,insert,update on public.%I to service_role',t);
 end loop;
end $$;

create or replace function public.resolve_effective_product_price(
 p_tenant_id uuid,p_branch_id uuid,p_actor_user_id uuid,p_product_id uuid,p_business_at timestamptz
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_branch public.branches%rowtype;v_price public.pricing_policies%rowtype;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='PRICING_SERVICE_ROLE_REQUIRED';end if;
 select * into v_branch from public.branches where id=p_branch_id and tenant_id=p_tenant_id;
 if not found or not public.pos_actor_can_access_branch(p_actor_user_id,p_tenant_id,p_branch_id) or not exists(select 1 from public.tenant_product_catalog where tenant_id=p_tenant_id and product_id=p_product_id and is_active)
  then raise exception using errcode='42501',message='PRICING_PRODUCT_SCOPE_DENIED';end if;
 select * into v_price from public.pricing_policies p where p.tenant_id=p_tenant_id and p.product_id=p_product_id
  and p.effective_from<=p_business_at and (p.effective_to is null or p.effective_to>p_business_at)
  and (p.scope='branch' and p.branch_id=p_branch_id or p.scope='regional' and p.region_id=v_branch.region_id or p.scope='central')
 order by case p.scope when 'branch' then 1 when 'regional' then 2 else 3 end,p.effective_from desc limit 1;
 if not found then raise exception 'effective_price_not_found';end if;
 return jsonb_build_object('tenantId',p_tenant_id,'branchId',p_branch_id,'productId',p_product_id,'priceIdr',v_price.price_idr,
  'scope',v_price.scope,'policyVersion',v_price.version,'effectiveFrom',v_price.effective_from);
end $$;
revoke all on function public.resolve_effective_product_price(uuid,uuid,uuid,uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.resolve_effective_product_price(uuid,uuid,uuid,timestamptz) to service_role;

create or replace function public.set_branch_product_availability(
 p_tenant_id uuid,p_branch_id uuid,p_actor_user_id uuid,p_product_id uuid,p_available boolean,p_starts_at timestamptz,p_ends_at timestamptz,p_reason text,p_expected_version integer
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_version integer;v_row public.branch_product_availability%rowtype;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='CATALOG_SERVICE_ROLE_REQUIRED';end if;
 if not public.pos_actor_can_access_branch(p_actor_user_id,p_tenant_id,p_branch_id) then raise exception using errcode='42501',message='BRANCH_PRODUCT_SCOPE_DENIED';end if;
 if not exists(select 1 from public.tenant_product_catalog where tenant_id=p_tenant_id and product_id=p_product_id and is_active) then raise exception using errcode='42501',message='TENANT_PRODUCT_SCOPE_DENIED';end if;
 select version into v_version from public.branch_product_availability where tenant_id=p_tenant_id and branch_id=p_branch_id and product_id=p_product_id for update;
 if not found then v_version:=0;end if;
 if v_version<>p_expected_version then raise exception using errcode='40001',message='BRANCH_AVAILABILITY_STALE_VERSION';end if;
 insert into public.branch_product_availability(tenant_id,branch_id,product_id,is_available,starts_at,ends_at,reason,version,updated_by)
 values(p_tenant_id,p_branch_id,p_product_id,p_available,p_starts_at,p_ends_at,left(p_reason,500),v_version+1,p_actor_user_id)
 on conflict(tenant_id,branch_id,product_id) do update set is_available=excluded.is_available,starts_at=excluded.starts_at,
  ends_at=excluded.ends_at,reason=excluded.reason,version=excluded.version,updated_by=excluded.updated_by,updated_at=now()
 returning * into v_row;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'branch_product_availability_changed','product',p_product_id::text,jsonb_build_object('branch_id',p_branch_id,'available',p_available,'version',v_row.version,'reason',p_reason));
 return jsonb_build_object('productId',v_row.product_id,'branchId',v_row.branch_id,'available',v_row.is_available,'version',v_row.version);
end $$;
revoke all on function public.set_branch_product_availability(uuid,uuid,uuid,uuid,boolean,timestamptz,timestamptz,text,integer) from public,anon,authenticated;
grant execute on function public.set_branch_product_availability(uuid,uuid,uuid,uuid,boolean,timestamptz,timestamptz,text,integer) to service_role;

rollback;