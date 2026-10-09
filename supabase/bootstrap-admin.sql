-- Execute apenas no SQL Editor administrativo depois da instalação.
-- Substitua o e-mail abaixo pelo da conta administradora já criada no Supabase Auth.
begin;
do $$ declare target uuid; begin
select id into target from kanban.profiles where lower(email)=lower('SUBSTITUA_PELO_EMAIL_DO_ADMIN');
if target is null then raise exception 'Conta não encontrada. Corrija o e-mail antes de executar.'; end if;
update kanban.profiles set active=true where id=target;
insert into kanban.user_roles(user_id,role) values(target,'admin') on conflict do nothing;
insert into kanban.audit_events(actor_id,type,description,after_data) values(target,'admin_bootstrap','Administrador inicial habilitado no SQL Editor',jsonb_build_object('id',target));
end $$;
commit;
