-- Somente leitura. Execute antes de instalar e guarde os resultados fora do Git.
select current_database() as database, version() as version;
select nspname from pg_namespace where nspname in ('public','kanban','auth');
select schemaname,tablename from pg_tables where schemaname in ('public','kanban') order by 1,2;
select schemaname,tablename,policyname,cmd from pg_policies where schemaname in ('public','kanban') order by 1,2,3;
select count(*) as contas_auth from auth.users;
select event_object_schema,event_object_table,trigger_name from information_schema.triggers where event_object_schema='auth';
-- Se já existir schema kanban ou funções public.kb_*, não execute novamente a instalação.
select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname like 'kb\_%' escape '\';
