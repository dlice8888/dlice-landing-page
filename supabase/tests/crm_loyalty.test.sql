-- Disposable PostgreSQL/pgTAP contracts for CRM identity, consent, loyalty, Finance close and campaigns.
begin;
select plan(46);

select ok(to_regclass('public.crm_customers') is not null,'CRM customer identity table exists');
select ok(to_regclass('public.crm_customer_consent_events') is not null,'append-only consent event ledger exists');
select ok(to_regclass('public.crm_loyalty_ledger') is not null,'loyalty ledger exists');
select ok(to_regclass('public.crm_rewards') is not null,'rewards exist');
select ok(to_regclass('public.crm_reward_vouchers') is not null,'reward vouchers exist');
select ok(to_regclass('public.crm_transaction_links') is not null,'paid POS and Order transaction links exist');
select ok(to_regclass('public.crm_marketing_campaigns') is not null,'campaign master exists');
select ok(to_regclass('public.crm_campaign_recipients') is not null,'campaign audience recipients exist');
select ok(to_regclass('public.crm_voucher_consumptions') is not null,'voucher consumption ledger exists');
select ok(to_regclass('public.crm_financial_close_projections') is not null,'Finance close projection exists');
select ok(to_regclass('public.crm_loyalty_earning_rules') is not null,'approved loyalty earning rules exist');
select ok(to_regclass('public.crm_campaign_outbox') is not null,'campaign transactional outbox exists');
select ok(to_regclass('public.crm_campaign_provider_events') is not null,'campaign provider receipt ledger exists');
select ok(to_regclass('public.crm_campaign_attributions') is not null,'campaign attribution ledger exists');
select ok(to_regclass('public.crm_campaign_costs') is not null,'campaign cost ledger exists');
select ok(to_regclass('public.crm_campaign_provider_configs') is not null,'campaign provider configuration exists');
select ok(to_regclass('public.crm_loyalty_point_allocations') is not null,'FIFO loyalty point allocation table exists');

select ok(to_regprocedure('public.crm_link_transaction_customer(uuid,uuid,text,uuid,uuid,text,text,uuid)') is not null,'transaction customer linking RPC exists');
select ok(to_regprocedure('public.crm_build_financial_close_projection(uuid,uuid,text,uuid,uuid)') is not null,'Finance close projection RPC exists');
select ok(to_regprocedure('public.crm_reconcile_financial_close_projection(uuid,uuid,uuid)') is not null,'Finance close reconciliation RPC exists');
select ok(to_regprocedure('public.crm_award_loyalty_for_reconciled_close(uuid,uuid,text,uuid,uuid)') is not null,'reconciled POS/Order/Finance award RPC exists');
select ok(position('pos_sale_tenders' in pg_get_functiondef('public.crm_build_financial_close_projection(uuid,uuid,text,uuid,uuid)'::regprocedure))>0
  and position('POS_SPLIT_TENDER_METHOD_ALLOCATION_MISMATCH' in pg_get_functiondef('public.crm_build_financial_close_projection(uuid,uuid,text,uuid,uuid)'::regprocedure))>0,
  'POS split tender must reconcile each bank/QRIS tender with provider settlement and cash with drawer');
select ok(position('cardinality(v.settlement_ids)>0' in pg_get_functiondef('public.crm_reconcile_financial_close_projection(uuid,uuid,uuid)'::regprocedure))>0
  and position('v.shift_reconciliation_id is not null' in pg_get_functiondef('public.crm_reconcile_financial_close_projection(uuid,uuid,uuid)'::regprocedure))>0,
  'Finance review independently rechecks both settlement and cash drawer evidence for split tender');

select ok(to_regprocedure('public.crm_expire_loyalty_points(uuid,uuid,uuid)') is not null,'idempotent points expiry RPC exists');
select ok(to_regprocedure('public.crm_redeem_reward(uuid,uuid,uuid,text,uuid)') is not null,'FIFO reward redemption RPC exists');
select ok(to_regprocedure('public.crm_append_loyalty_entry(uuid,uuid,text,bigint,text,text,uuid,uuid)') is not null,'audited adjustment and reversal RPC exists');
select ok(to_regprocedure('public.crm_approve_loyalty_earning_rule(uuid,uuid,uuid)') is not null,'independent earning rule approval RPC exists');
select ok(to_regprocedure('public.crm_approve_campaign(uuid,uuid,uuid)') is not null,'campaign approval RPC exists');
select ok(to_regprocedure('public.crm_prepare_campaign_audience(uuid,uuid,uuid)') is not null,'consent-aware audience preparation RPC exists');
select ok(to_regprocedure('public.crm_queue_campaign_outbox(uuid,uuid,uuid)') is not null,'campaign outbox queue RPC exists');
select ok(to_regprocedure('public.crm_claim_campaign_outbox(uuid,text,integer)') is not null,'campaign outbox worker claim RPC exists');
select ok(to_regprocedure('public.crm_finalize_campaign_outbox(uuid,uuid,text,text,text,integer)') is not null,'campaign outbox finalization RPC exists');
select ok(to_regprocedure('public.crm_apply_campaign_provider_receipt(uuid,text,text,text,text,text,timestamptz,jsonb)') is not null,'signed campaign provider receipt RPC exists');
select ok(to_regprocedure('public.crm_consume_voucher(uuid,text,text,uuid,uuid,uuid)') is not null,'voucher consumption RPC exists');
select ok(to_regprocedure('public.crm_void_voucher(uuid,uuid,text,uuid,text,uuid)') is not null,'voucher void/reversal RPC exists');

select ok((select relrowsecurity from pg_class where oid='public.crm_customers'::regclass),'CRM customer table has RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.crm_loyalty_ledger'::regclass),'loyalty ledger has RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.crm_campaign_outbox'::regclass),'campaign outbox has RLS enabled');
select ok(has_table_privilege('service_role','public.crm_loyalty_ledger','SELECT'),'service role can read loyalty evidence');
select ok(not has_table_privilege('anon','public.crm_loyalty_ledger','SELECT'),'anon cannot read loyalty evidence');

select ok(exists(select 1 from pg_trigger where tgname='crm_consent_events_append_only' and not tgisinternal),'consent events are append-only');
select ok(exists(select 1 from pg_trigger where tgname='crm_loyalty_ledger_append_only' and not tgisinternal),'loyalty ledger is append-only');
select ok(exists(select 1 from pg_trigger where tgname='crm_loyalty_point_allocations_append_only' and not tgisinternal),'point allocations are append-only');

select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname in ('crm_link_transaction_customer','crm_build_financial_close_projection',
 'crm_reconcile_financial_close_projection','crm_award_loyalty_for_reconciled_close','crm_expire_loyalty_points',
 'crm_redeem_reward','crm_append_loyalty_entry','crm_approve_loyalty_earning_rule','crm_approve_campaign',
 'crm_prepare_campaign_audience','crm_queue_campaign_outbox','crm_claim_campaign_outbox',
 'crm_finalize_campaign_outbox','crm_apply_campaign_provider_receipt','crm_consume_voucher','crm_void_voucher')
 and p.prosecdef),'all CRM privileged workflow RPCs use SECURITY INVOKER');

select throws_ok($$select public.crm_expire_loyalty_points(null::uuid,null::uuid,null::uuid)$$,
 '22023','INVALID_LOYALTY_EXPIRY_COMMAND','points expiry rejects missing tenant/customer/actor');
select throws_ok($$select public.crm_award_loyalty_for_reconciled_close(null::uuid,null::uuid,null::text,null::uuid,null::uuid)$$,
 '22023','INVALID_LOYALTY_CLOSE_COMMAND','loyalty award rejects missing financial-close scope');

select * from finish();
rollback;
