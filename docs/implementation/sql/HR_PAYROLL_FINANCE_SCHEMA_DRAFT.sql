-- DESIGN DRAFT ONLY — canonical HR payroll + existing Finance journal integration.
-- This file deliberately EXTENDS hr_payroll_runs/hr_payroll_lines from
-- HR_WORKFORCE_SCHEMA_DRAFT.sql. It does not create hr_employees,
-- hr_payroll_run_lines, finance_journal_batches, or a shadow payroll model.
-- Finance source of truth is the existing finance_journal_entries table.
-- Do not apply until the combined HR + Finance migration has been reviewed.

create table if not exists public.hr_payroll_finance_account_mappings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  payroll_expense_account text not null check(length(btrim(payroll_expense_account)) between 1 and 80),
  payroll_payable_account text not null check(length(btrim(payroll_payable_account)) between 1 and 80),
  payroll_deduction_account text not null check(length(btrim(payroll_deduction_account)) between 1 and 80),
  status text not null default 'pending' check(status in ('pending','approved','suspended')),
  created_by uuid not null references auth.users(id) on delete restrict,
  approved_by uuid null references auth.users(id) on delete restrict,
  approved_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,branch_id),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  check((status='approved' and approved_by is not null and approved_at is not null and approved_by<>created_by) or status<>'approved')
);

create table if not exists public.hr_payroll_finance_postings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  payroll_run_id uuid not null,
  fiscal_period_id uuid not null references public.fiscal_periods(id) on delete restrict,
  status text not null default 'draft' check(status in ('draft','posted','reconciled','exception')),
  gross_amount_idr bigint not null check(gross_amount_idr>0),
  deductions_amount_idr bigint not null check(deductions_amount_idr>=0),
  net_amount_idr bigint not null check(net_amount_idr>=0),
  finance_entry_ids uuid[] not null default '{}',
  idempotency_key text not null check(length(idempotency_key) between 8 and 160),
  created_by uuid not null references auth.users(id) on delete restrict,
  posted_by uuid null references auth.users(id) on delete restrict,
  posted_at timestamptz null,
  reconciled_by uuid null references auth.users(id) on delete restrict,
  reconciled_at timestamptz null,
  reconciliation_sha256 text null check(reconciliation_sha256 is null or reconciliation_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,payroll_run_id),
  unique(tenant_id,idempotency_key),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  foreign key(tenant_id,payroll_run_id) references public.hr_payroll_runs(tenant_id,id) on delete restrict,
  check(gross_amount_idr-deductions_amount_idr=net_amount_idr),
  check((status in ('posted','reconciled') and posted_by is not null and posted_at is not null and cardinality(finance_entry_ids)>0) or status not in ('posted','reconciled')),
  check((status='reconciled' and reconciled_by is not null and reconciled_at is not null and reconciliation_sha256 is not null) or status<>'reconciled')
);

alter table public.hr_payroll_runs
  add column if not exists finance_journal_id uuid;
alter table public.hr_payroll_runs drop constraint if exists hr_payroll_runs_finance_posting_fk;
alter table public.hr_payroll_runs add constraint hr_payroll_runs_finance_posting_fk
  foreign key(tenant_id,finance_journal_id)
  references public.hr_payroll_finance_postings(tenant_id,id) on delete restrict;

create index if not exists hr_payroll_finance_posting_period_idx
  on public.hr_payroll_finance_postings(tenant_id,branch_id,status,created_at desc);
create index if not exists hr_payroll_finance_entry_source_idx
  on public.finance_journal_entries(source_type,source_id,status)
  where source_type='hr_payroll_run';

create or replace function public.hr_approve_payroll_finance_mapping(
  p_tenant_id uuid,p_mapping_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_payroll_finance_account_mappings%rowtype;
begin
  select * into v from public.hr_payroll_finance_account_mappings
   where tenant_id=p_tenant_id and id=p_mapping_id for update;
  if not found then raise exception using errcode='P0002',message='PAYROLL_FINANCE_MAPPING_NOT_FOUND'; end if;
  if v.status<>'pending' or v.created_by=p_actor_user_id then
    raise exception using errcode='42501',message='INDEPENDENT_PAYROLL_FINANCE_MAPPING_APPROVAL_REQUIRED';
  end if;
  update public.hr_payroll_finance_account_mappings
    set status='approved',approved_by=p_actor_user_id,approved_at=now(),updated_at=now()
    where id=v.id returning * into v;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'hr.payroll.finance_mapping_approved','hr_payroll_finance_account_mappings',v.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'branch_id',v.branch_id));
  return jsonb_build_object('mapping_id',v.id,'status',v.status);
end;
$$;
revoke all on function public.hr_approve_payroll_finance_mapping(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_approve_payroll_finance_mapping(uuid,uuid,uuid) to service_role;

-- Prepare balanced draft journal rows against the REAL finance_journal_entries
-- model. Each row is a debit/credit pair; net pay + deductions equals gross.
create or replace function public.hr_prepare_payroll_finance_posting(
  p_tenant_id uuid,p_branch_id uuid,p_payroll_run_id uuid,p_fiscal_period_id uuid,
  p_idempotency_key text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare
  v_run public.hr_payroll_runs%rowtype;
  v_period public.fiscal_periods%rowtype;
  v_map public.hr_payroll_finance_account_mappings%rowtype;
  v_post public.hr_payroll_finance_postings%rowtype;
  v_line record;
  v_gross bigint;
  v_deductions bigint;
  v_net bigint;
  v_line_no integer:=0;
  v_entry_id uuid;
  v_ids uuid[]:='{}';
  v_entry_code text;
begin
  if length(coalesce(p_idempotency_key,'')) not between 8 and 160 then
    raise exception using errcode='22023',message='INVALID_PAYROLL_FINANCE_IDEMPOTENCY_KEY';
  end if;
  select * into v_run from public.hr_payroll_runs
   where tenant_id=p_tenant_id and branch_id=p_branch_id and id=p_payroll_run_id for update;
  if not found or v_run.status<>'approved' or v_run.approved_by is null
     or v_run.approved_at is null or v_run.approved_by in (v_run.created_by,v_run.generated_by,v_run.submitted_by) then
    raise exception using errcode='23514',message='INDEPENDENTLY_APPROVED_PAYROLL_RUN_REQUIRED';
  end if;
  select * into v_period from public.fiscal_periods where id=p_fiscal_period_id for update;
  if not found or v_period.status<>'open'
     or v_period.starts_on>v_run.period_start or v_period.ends_on<v_run.period_end then
    raise exception using errcode='23514',message='OPEN_FISCAL_PERIOD_REQUIRED';
  end if;
  select * into v_map from public.hr_payroll_finance_account_mappings
   where tenant_id=p_tenant_id and branch_id=p_branch_id and status='approved' for share;
  if not found then raise exception using errcode='P0002',message='APPROVED_PAYROLL_FINANCE_ACCOUNT_MAPPING_REQUIRED'; end if;
  select coalesce(sum(gross_amount_idr),0),coalesce(sum(deductions_amount_idr),0),
         coalesce(sum(net_amount_idr),0)
    into v_gross,v_deductions,v_net
    from public.hr_payroll_lines where tenant_id=p_tenant_id and payroll_run_id=p_payroll_run_id;
  if v_gross<=0 or v_gross<>v_run.gross_amount_idr
     or v_deductions<>v_run.deductions_amount_idr
     or v_net<>v_run.net_amount_idr or v_gross-v_deductions<>v_net then
    raise exception using errcode='23514',message='PAYROLL_LINES_DO_NOT_RECONCILE_TO_RUN';
  end if;
  select * into v_post from public.hr_payroll_finance_postings
   where tenant_id=p_tenant_id and payroll_run_id=p_payroll_run_id for update;
  if found then
    if v_post.idempotency_key<>p_idempotency_key or v_post.gross_amount_idr<>v_gross then
      raise exception using errcode='23505',message='PAYROLL_FINANCE_POSTING_ALREADY_EXISTS';
    end if;
    return jsonb_build_object('status',v_post.status,'posting_id',v_post.id,'finance_entry_ids',v_post.finance_entry_ids);
  end if;
  insert into public.hr_payroll_finance_postings(
    tenant_id,branch_id,payroll_run_id,fiscal_period_id,status,gross_amount_idr,
    deductions_amount_idr,net_amount_idr,idempotency_key,created_by
  ) values(p_tenant_id,p_branch_id,p_payroll_run_id,p_fiscal_period_id,'draft',
    v_gross,v_deductions,v_net,p_idempotency_key,p_actor_user_id)
  returning * into v_post;

  for v_line in
    select id,employee_user_id,gross_amount_idr,deductions_amount_idr,net_amount_idr
      from public.hr_payroll_lines
     where tenant_id=p_tenant_id and payroll_run_id=p_payroll_run_id
     order by employee_user_id,id
  loop
    if v_line.net_amount_idr>0 then
      v_line_no:=v_line_no+1;
      v_entry_code:='PAY-'||replace(p_payroll_run_id::text,'-','')||'-'||lpad(v_line_no::text,5,'0');
      insert into public.finance_journal_entries(
        entry_code,fiscal_period_id,branch_id,source_type,source_id,entry_date,
        debit_account,credit_account,amount_idr,description,status,created_by
      ) values(v_entry_code,p_fiscal_period_id,p_branch_id,'hr_payroll_run',p_payroll_run_id,
        v_run.period_end,v_map.payroll_expense_account,v_map.payroll_payable_account,
        v_line.net_amount_idr,'Payroll net payable line '||v_line.id::text,'draft',p_actor_user_id)
      returning id into v_entry_id;
      v_ids:=array_append(v_ids,v_entry_id);
    end if;
    if v_line.deductions_amount_idr>0 then
      v_line_no:=v_line_no+1;
      v_entry_code:='PAY-'||replace(p_payroll_run_id::text,'-','')||'-'||lpad(v_line_no::text,5,'0');
      insert into public.finance_journal_entries(
        entry_code,fiscal_period_id,branch_id,source_type,source_id,entry_date,
        debit_account,credit_account,amount_idr,description,status,created_by
      ) values(v_entry_code,p_fiscal_period_id,p_branch_id,'hr_payroll_run',p_payroll_run_id,
        v_run.period_end,v_map.payroll_expense_account,v_map.payroll_deduction_account,
        v_line.deductions_amount_idr,'Payroll deductions line '||v_line.id::text,'draft',p_actor_user_id)
      returning id into v_entry_id;
      v_ids:=array_append(v_ids,v_entry_id);
    end if;
  end loop;
  if cardinality(v_ids)=0 then raise exception using errcode='23514',message='PAYROLL_JOURNAL_HAS_NO_LINES'; end if;
  update public.hr_payroll_finance_postings set finance_entry_ids=v_ids,updated_at=now() where id=v_post.id;
  update public.hr_payroll_runs set finance_journal_id=v_post.id,updated_at=now() where id=v_run.id;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'hr.payroll.finance_posting_prepared','hr_payroll_finance_postings',v_post.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'payroll_run_id',p_payroll_run_id,
      'gross_idr',v_gross,'deductions_idr',v_deductions,'net_idr',v_net,'journal_entry_count',cardinality(v_ids)));
  return jsonb_build_object('status','draft','posting_id',v_post.id,'finance_entry_ids',v_ids,
    'gross_amount_idr',v_gross,'deductions_amount_idr',v_deductions,'net_amount_idr',v_net);
end;
$$;
revoke all on function public.hr_prepare_payroll_finance_posting(uuid,uuid,uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.hr_prepare_payroll_finance_posting(uuid,uuid,uuid,uuid,text,uuid) to service_role;

create or replace function public.hr_post_payroll_finance_posting(
  p_tenant_id uuid,p_posting_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_payroll_finance_postings%rowtype; r public.hr_payroll_runs%rowtype;
begin
  select * into v from public.hr_payroll_finance_postings
   where tenant_id=p_tenant_id and id=p_posting_id for update;
  if not found or v.status<>'draft' then raise exception using errcode='23514',message='PAYROLL_FINANCE_DRAFT_REQUIRED'; end if;
  select * into r from public.hr_payroll_runs
   where tenant_id=p_tenant_id and id=v.payroll_run_id for update;
  if not found or r.status<>'approved' or p_actor_user_id in (v.created_by,r.created_by,r.generated_by,r.submitted_by,r.approved_by) then
    raise exception using errcode='42501',message='INDEPENDENT_PAYROLL_FINANCE_POSTER_REQUIRED';
  end if;
  if exists(select 1 from public.fiscal_periods where id=v.fiscal_period_id and status<>'open') then
    raise exception using errcode='23514',message='FISCAL_PERIOD_CLOSED_BEFORE_POSTING';
  end if;
  if cardinality(v.finance_entry_ids)=0 or exists(
    select 1 from public.finance_journal_entries e
     where e.id=any(v.finance_entry_ids) and (e.status<>'draft' or e.source_type<>'hr_payroll_run' or e.source_id<>r.id)
  ) or (select count(*) from public.finance_journal_entries e where e.id=any(v.finance_entry_ids))<>cardinality(v.finance_entry_ids) then
    raise exception using errcode='23514',message='PAYROLL_FINANCE_DRAFT_ENTRIES_CHANGED';
  end if;
  update public.finance_journal_entries set status='posted' where id=any(v.finance_entry_ids);
  update public.hr_payroll_finance_postings set status='posted',posted_by=p_actor_user_id,posted_at=now(),updated_at=now()
   where id=v.id returning * into v;
  update public.hr_payroll_runs set status='posted',posted_by=p_actor_user_id,posted_at=now(),updated_at=now()
   where id=r.id;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'hr.payroll.finance_posted','hr_payroll_finance_postings',v.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'payroll_run_id',r.id,'finance_entry_ids',v.finance_entry_ids));
  return jsonb_build_object('status','posted','posting_id',v.id,'payroll_run_id',r.id,'finance_entry_ids',v.finance_entry_ids);
end;
$$;
revoke all on function public.hr_post_payroll_finance_posting(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_post_payroll_finance_posting(uuid,uuid,uuid) to service_role;

create or replace function public.hr_reconcile_payroll_finance_posting(
  p_tenant_id uuid,p_posting_id uuid,p_actor_user_id uuid,p_evidence_sha256 text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_payroll_finance_postings%rowtype; r public.hr_payroll_runs%rowtype;
  v_count integer; v_amount bigint;
begin
  if coalesce(p_evidence_sha256,'') !~ '^[0-9a-f]{64}$' then
    raise exception using errcode='22023',message='PAYROLL_RECONCILIATION_SHA256_REQUIRED';
  end if;
  select * into v from public.hr_payroll_finance_postings
   where tenant_id=p_tenant_id and id=p_posting_id for update;
  if not found or v.status<>'posted' then raise exception using errcode='23514',message='POSTED_PAYROLL_FINANCE_REQUIRED'; end if;
  select * into r from public.hr_payroll_runs where tenant_id=p_tenant_id and id=v.payroll_run_id for update;
  if p_actor_user_id in (v.created_by,v.posted_by,r.created_by,r.generated_by,r.submitted_by,r.approved_by) then
    raise exception using errcode='42501',message='INDEPENDENT_PAYROLL_RECONCILER_REQUIRED';
  end if;
  select count(*),coalesce(sum(amount_idr),0) into v_count,v_amount
    from public.finance_journal_entries
   where id=any(v.finance_entry_ids) and source_type='hr_payroll_run'
     and source_id=r.id and branch_id=v.branch_id and status='posted';
  if v_count<>cardinality(v.finance_entry_ids) or v_amount<>v.gross_amount_idr then
    raise exception using errcode='23514',message='PAYROLL_FINANCE_POSTING_TOTAL_MISMATCH';
  end if;
  update public.hr_payroll_finance_postings
   set status='reconciled',reconciled_by=p_actor_user_id,reconciled_at=now(),
       reconciliation_sha256=p_evidence_sha256,updated_at=now()
   where id=v.id returning * into v;
  update public.hr_payroll_runs set status='reconciled',
    reconciliation_reference=p_evidence_sha256,updated_at=now() where id=r.id;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'hr.payroll.finance_reconciled','hr_payroll_finance_postings',v.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'payroll_run_id',r.id,'gross_amount_idr',v.gross_amount_idr,
      'journal_entry_count',v_count,'evidence_sha256',p_evidence_sha256));
  return jsonb_build_object('status','reconciled','posting_id',v.id,'payroll_run_id',r.id,
    'gross_amount_idr',v.gross_amount_idr,'finance_entry_count',v_count);
end;
$$;
revoke all on function public.hr_reconcile_payroll_finance_posting(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.hr_reconcile_payroll_finance_posting(uuid,uuid,uuid,text) to service_role;

do $$
declare t text;
begin
  foreach t in array array['hr_payroll_finance_account_mappings','hr_payroll_finance_postings'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists service_role_only on public.%I',t);
    execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
    execute format('revoke all on public.%I from anon,authenticated',t);
    execute format('grant select,insert,update,delete on public.%I to service_role',t);
  end loop;
end $$;
