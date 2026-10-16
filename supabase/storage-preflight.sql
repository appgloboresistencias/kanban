-- Auditoria somente leitura, antes da atualização. Não altera dados.
select current_database(),version();
select table_name,column_name,data_type from information_schema.columns where table_schema='kanban' and table_name in ('documents','demands','stage_executions') order by table_name,ordinal_position;
select p.proname,md5(pg_get_functiondef(p.oid)) as definition_hash from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('kb_bootstrap','kb_finish','kb_save_demand','kb_document_reserve','kb_document_finish');
select to_regclass('supabase_migrations.schema_migrations') as migration_history_table;
select active,count(*) from kanban.profiles group by active;
select role,count(*) from kanban.user_roles group by role;
select count(*) as existing_document_records from kanban.documents;
select schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check from pg_policies where (schemaname='storage' and tablename='objects') or (schemaname='kanban' and tablename='documents');
select id,public,file_size_limit,allowed_mime_types from storage.buckets;
select bucket_id,count(*) as objects,coalesce(sum(coalesce(metadata->>'size',metadata->>'contentLength')::bigint),0) as bytes from storage.objects group by bucket_id;
