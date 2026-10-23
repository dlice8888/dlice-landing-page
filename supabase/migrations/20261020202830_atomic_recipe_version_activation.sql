-- Applied to staging as migration 20261020202830.
CREATE OR REPLACE FUNCTION public.erp_activate_recipe(p_recipe_id uuid, p_actor_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare r public.recipes%rowtype; n integer;
begin
 select * into r from public.recipes where id=p_recipe_id for update;
 if not found then raise exception 'recipe_not_found'; end if;
 if r.status<>'draft' then raise exception 'recipe_not_draft'; end if;
 perform 1 from public.products where id=r.product_id for update;
 select count(*) into n from public.recipe_ingredients where recipe_id=r.id;
 if n<1 then raise exception 'recipe_has_no_ingredients'; end if;
 update public.recipes set status='retired' where product_id=r.product_id and status='active';
 update public.recipes set status='active',approved_by=p_actor_user_id,approved_at=now() where id=r.id and status='draft';
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'erp_recipe_activated','recipe',r.id::text,jsonb_build_object('product_id',r.product_id,'version',r.version));
 return jsonb_build_object('ok',true,'recipe_id',r.id,'product_id',r.product_id,'version',r.version,'status','active');
end $function$
;
revoke all on function public.erp_activate_recipe(uuid,uuid) from public,anon,authenticated;
grant execute on function public.erp_activate_recipe(uuid,uuid) to service_role;
