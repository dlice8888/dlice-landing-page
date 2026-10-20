-- Applied to staging as migration 20261020202449.
CREATE OR REPLACE FUNCTION public.erp_match_payment_settlement(p_settlement_id uuid, p_items jsonb, p_actor_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare s public.payment_settlements%rowtype; x jsonb; pid uuid; sid uuid; amt bigint; actual_amt bigint; total bigint:=0; n integer:=0; next_status text;
begin
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>500 then raise exception 'invalid_settlement_items'; end if;
 select * into s from public.payment_settlements where id=p_settlement_id for update;
 if not found then raise exception 'settlement_not_found'; end if;
 if s.status not in ('pending','disputed') then raise exception 'settlement_not_matchable'; end if;
 for x in select value from jsonb_array_elements(p_items) loop
  pid:=nullif(x->>'payment_record_id','')::uuid; sid:=nullif(x->>'pos_sale_id','')::uuid; amt:=nullif(x->>'amount_idr','')::bigint;
  if (pid is null)=(sid is null) or amt is null or amt<0 then raise exception 'invalid_settlement_item'; end if;
  if pid is not null then
   select amount_idr into actual_amt from public.payment_records where id=pid and status='paid' for update;
   if not found then raise exception 'payment_not_verified'; end if;
  else
   select total_idr into actual_amt from public.pos_sales where id=sid and payment_status='paid' for update;
   if not found then raise exception 'pos_sale_not_paid'; end if;
  end if;
  if actual_amt<>amt then raise exception 'settlement_amount_mismatch'; end if;
  total:=total+amt; n:=n+1;
  insert into public.payment_settlement_items(settlement_id,payment_record_id,pos_sale_id,amount_idr) values(p_settlement_id,pid,sid,amt);
 end loop;
 if total<>s.gross_amount_idr then raise exception 'settlement_gross_mismatch'; end if;
 next_status:=case when s.received_amount_idr is null then 'pending' when s.received_amount_idr=s.net_amount_idr then 'matched' else 'disputed' end;
 update public.payment_settlements set status=next_status,reconciled_by=p_actor_user_id,reconciled_at=now() where id=s.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'erp_settlement_matched','payment_settlement',s.id::text,jsonb_build_object('gross_amount_idr',total,'matched_items',n,'status',next_status));
 return jsonb_build_object('ok',true,'settlement_id',s.id,'status',next_status,'gross_matched_idr',total,'matched_items',n);
end $function$
;
revoke all on function public.erp_match_payment_settlement(uuid,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.erp_match_payment_settlement(uuid,jsonb,uuid) to service_role;
