begin;
-- Incremental sobre 2.3. Dados antigos ficam intactos; objetos nunca são apagados por SQL.
do $$ begin if not exists(select 1 from information_schema.columns where table_schema='kanban' and table_name='stage_executions' and column_name='data') then raise exception 'Instale primeiro o fluxo 2.3.'; end if; end $$;
alter table kanban.documents add column if not exists original_filename text;
alter table kanban.documents add column if not exists stored_filename text;
alter table kanban.documents add column if not exists mime_type text;
alter table kanban.documents add column if not exists size_bytes bigint;
alter table kanban.documents add column if not exists storage_provider text not null default 'google_drive' check(storage_provider in ('supabase','google_drive'));
alter table kanban.documents add column if not exists bucket_name text;
alter table kanban.documents add column if not exists storage_path text;
alter table kanban.documents add column if not exists google_drive_file_id text;
alter table kanban.documents add column if not exists uploaded_by uuid references kanban.profiles;
alter table kanban.documents add column if not exists uploaded_at timestamptz;
alter table kanban.documents add column if not exists status text not null default 'legacy' check(status in ('legacy','pending','ready','archived','cancelled'));
alter table kanban.documents add column if not exists version int not null default 1;
alter table kanban.documents add column if not exists series_id uuid;
alter table kanban.documents add column if not exists checksum text;
alter table kanban.documents add column if not exists migration_status text not null default 'PENDENTE' check(migration_status in ('PENDENTE','EM_MIGRACAO','COPIADO','VALIDADO','FALHA','CONCLUIDO'));
alter table kanban.documents add column if not exists migrated_at timestamptz;
alter table kanban.documents add column if not exists archived_at timestamptz;
create unique index if not exists docs_storage_path on kanban.documents(bucket_name,storage_path) where storage_path is not null;
create unique index if not exists docs_series_version on kanban.documents(series_id,version) where series_id is not null;
create index if not exists docs_card_page on kanban.documents(demand_id,created_at desc,id desc);
create index if not exists docs_checksum on kanban.documents(demand_id,checksum,kind) where status in ('pending','ready');
create table if not exists kanban.document_settings(id boolean primary key default true check(id), default_provider text not null default 'supabase' check(default_provider in ('supabase','google_drive')), capacity_bytes bigint not null default 524288000 check(capacity_bytes between 1048576 and 1073741824), photo_limit bigint not null default 5242880 check(photo_limit between 1 and 52428800), pdf_limit bigint not null default 15728640 check(pdf_limit between 1 and 52428800), office_limit bigint not null default 10485760 check(office_limit between 1 and 52428800), used_bytes bigint not null default 0, checked_at timestamptz, google_enabled boolean not null default false);
insert into kanban.document_settings(id) values(true) on conflict do nothing;
alter table kanban.document_settings enable row level security;
revoke all on kanban.document_settings from public,anon,authenticated;
create table if not exists kanban.document_migrations(document_id uuid primary key references kanban.documents, target_id text, state text not null default 'PENDENTE', lease_until timestamptz, error text, verified_checksum text, verified_size bigint, updated_at timestamptz not null default now());
alter table kanban.document_migrations enable row level security;
revoke all on kanban.document_migrations from public,anon,authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('globo-documentos','globo-documentos',false,52428800,array['application/pdf','image/jpeg','image/png','image/webp','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']) on conflict(id) do nothing;
do $$ begin if exists(select 1 from storage.buckets where id='globo-documentos' and public) then raise exception 'O bucket globo-documentos existente é público. Corrija a configuração antes de instalar.'; end if; end $$;

create or replace function kanban.document_access(p_path text,p_upload boolean,p_meta jsonb default null) returns boolean language plpgsql volatile security definer set search_path='' as $$
declare f kanban.documents; d kanban.demands;begin
if auth.uid() is null or not exists(select 1 from kanban.profiles where id=auth.uid() and active) then return false;end if;
if p_upload then select * into f from kanban.documents where bucket_name='globo-documentos' and storage_path=p_path for share;else select * into f from kanban.documents where bucket_name='globo-documentos' and storage_path=p_path;end if;
if not found then return false;end if;select * into d from kanban.demands where id=f.demand_id;
if p_upload then return f.status='pending' and f.uploaded_by=auth.uid() and kanban.can_edit(d) and exists(select 1 from kanban.stage_executions e where e.id=f.execution_id and e.completed_at is null) and coalesce(p_meta->>'size',p_meta->>'contentLength')::bigint=f.size_bytes and p_meta->>'mimetype'=f.mime_type;end if;
return kanban.can_read(d) and (f.status in ('ready','archived') or (f.status='pending' and (f.uploaded_by=auth.uid() or kanban.has_role(array['admin']))));end; $$;
revoke all on function kanban.document_access(text,boolean,jsonb) from public,anon;
grant execute on function kanban.document_access(text,boolean,jsonb) to authenticated;
drop policy if exists globo_doc_insert on storage.objects;
create policy globo_doc_insert on storage.objects for insert to authenticated with check(bucket_id='globo-documentos' and kanban.document_access(name,true,metadata));
drop policy if exists globo_doc_read on storage.objects;
create policy globo_doc_read on storage.objects for select to authenticated using(bucket_id='globo-documentos' and kanban.document_access(name,false));
-- Restritivas impedem que políticas permissivas de outros módulos abram este bucket.
drop policy if exists globo_doc_insert_guard on storage.objects;
create policy globo_doc_insert_guard on storage.objects as restrictive for insert to public with check(bucket_id<>'globo-documentos' or kanban.document_access(name,true,metadata));
drop policy if exists globo_doc_read_guard on storage.objects;
create policy globo_doc_read_guard on storage.objects as restrictive for select to public using(bucket_id<>'globo-documentos' or kanban.document_access(name,false));
drop policy if exists globo_doc_update_guard on storage.objects;
create policy globo_doc_update_guard on storage.objects as restrictive for update to public using(bucket_id<>'globo-documentos') with check(bucket_id<>'globo-documentos');
drop policy if exists globo_doc_delete_guard on storage.objects;
create policy globo_doc_delete_guard on storage.objects as restrictive for delete to public using(bucket_id<>'globo-documentos');

create or replace function kanban.storage_usage() returns bigint language sql stable security definer set search_path='' as $$
select coalesce((select sum(coalesce(coalesce(metadata->>'size',metadata->>'contentLength')::bigint,0)) from storage.objects),0)+coalesce((select sum(size_bytes) from kanban.documents f where f.status='pending' and not exists(select 1 from storage.objects o where o.bucket_id=f.bucket_name and o.name=f.storage_path)),0); $$;
revoke all on function kanban.storage_usage() from public,anon,authenticated;
create or replace function public.kb_document_config(p_refresh boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$ declare c kanban.document_settings; begin
perform kanban.require_active();
if p_refresh then if not kanban.has_role(array['admin']) then raise exception 'Apenas administrador atualiza a medição.'; end if; update kanban.document_settings set used_bytes=kanban.storage_usage(),checked_at=now() where id; end if;
select * into c from kanban.document_settings where id; return to_jsonb(c)||jsonb_build_object('document_api',1); end; $$;
create or replace function public.kb_document_config_save(p_capacity bigint,p_photo bigint,p_pdf bigint,p_office bigint,p_provider text) returns void language plpgsql security definer set search_path='' as $$ declare c kanban.document_settings; begin
perform kanban.require_active();if not kanban.has_role(array['admin']) then raise exception 'Apenas administrador altera limites.';end if;
select * into c from kanban.document_settings where id for update;
if p_provider not in ('supabase','google_drive') or p_provider is null or (p_provider='google_drive' and not c.google_enabled) then raise exception 'Provedor indisponível: integração Google ainda não validada.';end if;
if p_capacity<kanban.storage_usage() then raise exception 'Capacidade inferior ao espaço já reservado ou utilizado.';end if;
update kanban.document_settings set capacity_bytes=p_capacity,photo_limit=p_photo,pdf_limit=p_pdf,office_limit=p_office,default_provider=p_provider where id;
insert into kanban.audit_events(actor_id,type,description,before_data,after_data) values(auth.uid(),'document_config','Limites documentais atualizados',to_jsonb(c),jsonb_build_object('capacity',p_capacity,'photo',p_photo,'pdf',p_pdf,'office',p_office,'provider',p_provider));end; $$;

create or replace function public.kb_document_reserve(p_card uuid,p_name text,p_mime text,p_size bigint,p_checksum text,p_kind text,p_previous uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare c kanban.document_settings; d kanban.demands; f kanban.documents; prev kanban.documents; eid uuid; ext text; expected text; lim bigint; used bigint; fid uuid:=gen_random_uuid(); path text; ver int:=1; series uuid; begin
perform kanban.require_active();select * into c from kanban.document_settings where id for update;
select * into d from kanban.demands where id=p_card for update;if not found or not kanban.can_edit(d) then raise exception 'Sem permissão para anexar neste card.';end if;
select id into eid from kanban.stage_executions where demand_id=p_card and completed_at is null;
if eid is null then raise exception 'Etapa não está aberta.';end if;
if c.default_provider<>'supabase' then raise exception 'Uploads no novo provedor exigem o backend Google configurado.';end if;
if p_name is null or length(trim(p_name)) not between 1 and 200 or p_name~'[/\\]' or p_checksum is null or p_checksum!~'^[a-f0-9]{64}$' or p_kind not in ('interview','proposal','approval','technical','materials','quality','delivery','other') or p_kind is null then raise exception 'Metadados do arquivo inválidos.';end if;
ext:=lower(substring(p_name from '\.([^.]+)$'));
expected:=case ext when 'pdf' then 'application/pdf' when 'jpg' then 'image/jpeg' when 'jpeg' then 'image/jpeg' when 'png' then 'image/png' when 'webp' then 'image/webp' when 'docx' then 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' when 'xlsx' then 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' else null end;
if expected is null or p_mime is distinct from expected then raise exception 'Extensão ou tipo não permitido. Use PDF, JPG, PNG, WEBP, DOCX ou XLSX.';end if;
lim:=case when ext='pdf' then c.pdf_limit when ext in ('docx','xlsx') then c.office_limit else c.photo_limit end;
if p_size is null or p_size<=0 or p_size>lim then raise exception 'Arquivo excede o limite de % MB para este tipo.',round(lim/1048576.0,1);end if;
if p_kind='interview' and ext<>'pdf' then raise exception 'Entrevista de referência deve ser PDF.';end if;
select * into f from kanban.documents where demand_id=p_card and kind=p_kind and checksum=p_checksum and status in ('ready','pending') order by created_at desc limit 1;
if found then if f.status='pending' and f.uploaded_by<>auth.uid() then raise exception 'Outro usuário está enviando este arquivo.';end if;return to_jsonb(f);end if;
if p_previous is not null then select * into prev from kanban.documents where id=p_previous and demand_id=p_card and status in ('ready','archived');if not found or prev.kind<>p_kind then raise exception 'Versão anterior inválida.';end if;series:=coalesce(prev.series_id,prev.id);select coalesce(max(version),0)+1 into ver from kanban.documents where series_id=series or id=series;else series:=fid;end if;
used:=kanban.storage_usage();if used+p_size>c.capacity_bytes then raise exception 'Espaço insuficiente no orçamento de armazenamento. Solicite revisão ao administrador.';end if;
path:='orcamentos/'||p_card||'/'||eid||'/'||fid||'.'||ext;
insert into kanban.documents(id,demand_id,execution_id,kind,name,provider_id,confirmed,original_filename,stored_filename,mime_type,size_bytes,storage_provider,bucket_name,storage_path,uploaded_by,status,version,series_id,checksum)
values(fid,p_card,eid,p_kind,p_name,path,false,p_name,fid||'.'||ext,p_mime,p_size,'supabase','globo-documentos',path,auth.uid(),'pending',ver,series,p_checksum) returning * into f;
update kanban.document_settings set used_bytes=used+p_size,checked_at=now() where id;
insert into kanban.audit_events(demand_id,actor_id,type,description,after_data) values(p_card,auth.uid(),'document_reserved','Upload reservado',jsonb_build_object('document_id',fid,'name',p_name,'version',ver));return to_jsonb(f);end; $$;

create or replace function public.kb_document_finish(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare f kanban.documents;d kanban.demands;meta jsonb;begin
perform kanban.require_active();select * into f from kanban.documents where id=p_id;
select * into d from kanban.demands where id=f.demand_id for update;
if not found or not kanban.can_read(d) then raise exception 'Documento indisponível.';end if;
select * into f from kanban.documents where id=p_id for update;
if f.status='ready' then return to_jsonb(f);end if;
-- Finaliza upload já aceito antes da movimentação, sem permitir novos uploads em etapa encerrada.
if f.status<>'pending' or (f.uploaded_by<>auth.uid() and not kanban.has_role(array['admin'])) then raise exception 'Sem permissão para confirmar este upload.';end if;
select metadata into meta from storage.objects where bucket_id=f.bucket_name and name=f.storage_path;
if not found then raise exception 'Upload ainda não foi armazenado. Selecione o arquivo novamente para retomar.';end if;
if coalesce(meta->>'size',meta->>'contentLength')::bigint is distinct from f.size_bytes or meta->>'mimetype' is distinct from f.mime_type then raise exception 'Tamanho ou tipo do objeto divergente. Upload não confirmado.';end if;
update kanban.documents set status='ready',confirmed=true,uploaded_at=now() where id=p_id returning * into f;
insert into kanban.audit_events(demand_id,actor_id,type,description,after_data) values(f.demand_id,auth.uid(),'document_uploaded','Documento armazenado',jsonb_build_object('document_id',f.id,'filename',f.name,'checksum',f.checksum,'version',f.version));return to_jsonb(f);end; $$;

create or replace function public.kb_document_list(p_card uuid,p_before timestamptz default null,p_before_id uuid default null,p_archived boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$ begin
perform kanban.require_active();if not exists(select 1 from kanban.demands d where id=p_card and kanban.can_read(d)) then raise exception 'Card indisponível.';end if;
return (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select f.*,p.name as uploader,e.stage from kanban.documents f left join kanban.profiles p on p.id=f.uploaded_by left join kanban.stage_executions e on e.id=f.execution_id where f.demand_id=p_card and (p_archived or f.status<>'archived') and f.status<>'cancelled' and (p_before is null or (f.created_at,f.id)<(p_before,p_before_id)) order by f.created_at desc,f.id desc limit 31)x);end; $$;
create or replace function public.kb_document_get(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ declare f kanban.documents;begin
perform kanban.require_active();select * into f from kanban.documents where id=p_id;if not found or not exists(select 1 from kanban.demands d where id=f.demand_id and kanban.can_read(d)) then raise exception 'Documento indisponível.';end if;return to_jsonb(f);end; $$;
create or replace function public.kb_document_archive(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$ declare f kanban.documents;d kanban.demands;begin
perform kanban.require_active();select * into f from kanban.documents where id=p_id;select * into d from kanban.demands where id=f.demand_id for update;
if not found or not kanban.can_read(d) or not (kanban.can_edit(d) or kanban.has_role(array['admin'])) then raise exception 'Sem permissão para arquivar.';end if;
if length(trim(coalesce(p_reason,'')))<5 then raise exception 'Informe o motivo do arquivamento.';end if;
if f.status not in ('ready','legacy') then raise exception 'Documento não está disponível para arquivamento.';end if;
if f.kind='interview' and d.interview_drive_id='' and d.technical_complete and not exists(select 1 from kanban.documents where demand_id=d.id and id<>f.id and kind='interview' and status='ready' and confirmed) then raise exception 'Mantenha uma entrevista válida ou revise a confirmação do levantamento antes de arquivar.';end if;
update kanban.documents set status='archived',archived_at=now() where id=p_id;
insert into kanban.audit_events(demand_id,actor_id,type,description,after_data) values(d.id,auth.uid(),'document_archived',p_reason,jsonb_build_object('document_id',p_id));end; $$;
create or replace function public.kb_document_cancel(p_id uuid) returns void language plpgsql security definer set search_path='' as $$ declare f kanban.documents;begin
perform kanban.require_active();perform 1 from kanban.document_settings where id for update;select * into f from kanban.documents where id=p_id for update;
if not found or f.status<>'pending' or (f.uploaded_by<>auth.uid() and not kanban.has_role(array['admin'])) then raise exception 'Reserva indisponível.';end if;
if exists(select 1 from storage.objects where bucket_id=f.bucket_name and name=f.storage_path) then raise exception 'Objeto já existe. Confirme o upload em vez de cancelar.';end if;
update kanban.documents set status='cancelled' where id=p_id;
update kanban.document_settings set used_bytes=kanban.storage_usage(),checked_at=now() where id;
insert into kanban.audit_events(demand_id,actor_id,type,description,after_data) values(f.demand_id,auth.uid(),'document_cancelled','Reserva sem arquivo cancelada',jsonb_build_object('document_id',p_id));end; $$;

-- RPCs existentes continuam usando autorização explícita. Não expor tabelas à escrita direta.
revoke all on function public.kb_document_config(boolean),public.kb_document_config_save(bigint,bigint,bigint,bigint,text),public.kb_document_reserve(uuid,text,text,bigint,text,text,uuid),public.kb_document_finish(uuid),public.kb_document_list(uuid,timestamptz,uuid,boolean),public.kb_document_get(uuid),public.kb_document_archive(uuid,text),public.kb_document_cancel(uuid) from public,anon;
grant execute on function public.kb_document_config(boolean),public.kb_document_config_save(bigint,bigint,bigint,bigint,text),public.kb_document_reserve(uuid,text,text,bigint,text,text,uuid),public.kb_document_finish(uuid),public.kb_document_list(uuid,timestamptz,uuid,boolean),public.kb_document_get(uuid),public.kb_document_archive(uuid,text),public.kb_document_cancel(uuid) to authenticated;
create or replace function kanban.missing(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare d kanban.demands; result jsonb:='[]'; begin
select * into d from kanban.demands where id=p_id;
if length(trim(d.technical_notes))=0 or lower(trim(d.technical_notes)) in ('pendente','a definir','não sei','n/a') then result:=result||jsonb_build_array('Registrar o levantamento técnico no campo livre'); end if;
if d.interview_drive_id='' and not exists(select 1 from kanban.documents where demand_id=p_id and kind='interview' and status='ready' and confirmed) then result:=result||jsonb_build_array('Anexar o PDF da entrevista ou informar sua referência externa'); end if;
if not d.technical_complete or d.survey_format<>2 then result:=result||jsonb_build_array('Confirmar a conclusão do levantamento'); end if;
return result; end; $$;


create or replace function public.kb_save_demand(p_id uuid,p_version int,p_data jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare d kanban.demands; old_data jsonb; yr int:=extract(year from now() at time zone 'America/Sao_Paulo'); seq int;
v_notes text:=coalesce(p_data->>'technical_notes',''); v_url text:=trim(coalesce(p_data->>'interview_pdf_url',''));
v_name text:=trim(coalesce(p_data->>'interview_pdf_name','')); v_drive text;
v_complete boolean:=coalesce((p_data->>'technical_complete')::boolean,false); v_changed boolean;
begin
perform kanban.require_active();
if not kanban.has_role(array['admin','manager','sales']) then raise exception 'Sem permissão para abertura de orçamento.'; end if;
if (p_data->>'form_version') is distinct from '2' then raise exception 'Atualize a aplicação para a versão 2 antes de salvar. Nenhum dado foi alterado.'; end if;
if octet_length(p_data::text)>65536 or length(v_notes)>20000 or length(v_url)>2048 or length(v_name)>200 then raise exception 'Limite excedido: levantamento até 20.000 caracteres e nome do PDF até 200.'; end if;
v_drive:=kanban.drive_reference(v_url);
select * into d from kanban.demands where id=p_id for update;
if found then
if not kanban.can_edit(d) or d.stage<>'sales' or d.status<>'open' then raise exception 'Edição disponível somente em Vendas ao responsável.'; end if;
if d.version is distinct from p_version then raise exception 'Conflito de edição. Reabra o card para atualizar.'; end if;
old_data:=to_jsonb(d);
else if p_version is distinct from 0 then raise exception 'Orçamento não encontrado.'; end if; end if;
if not exists(select 1 from kanban.customers where id=(p_data->>'customer_id')::uuid) then raise exception 'Selecione um cliente.'; end if;
if v_complete and (length(trim(v_notes))=0 or lower(trim(v_notes)) in ('pendente','a definir','não sei','n/a') or (v_drive='' and not exists(select 1 from kanban.documents where demand_id=p_id and kind='interview' and status='ready' and confirmed))) then raise exception 'Para concluir, registre o levantamento e a referência ao PDF da entrevista. Você pode salvar como rascunho.'; end if;
v_changed:=d.id is null or d.technical_notes is distinct from v_notes or d.interview_drive_id is distinct from v_drive or d.interview_pdf_name is distinct from v_name or not d.technical_complete or d.survey_format<>2;
if d.id is null then
insert into kanban.number_counters values(yr,1) on conflict(year) do update set last_value=kanban.number_counters.last_value+1 returning last_value into seq;
insert into kanban.demands(id,number,title,customer_id,seller_id,assignee_id,created_by) values(p_id,'ORC-'||yr||'-'||lpad(seq::text,greatest(6,length(seq::text)),'0'),trim(p_data->>'title'),(p_data->>'customer_id')::uuid,auth.uid(),auth.uid(),auth.uid()) returning * into d;
insert into kanban.stage_executions(demand_id,stage,assignee_id) values(d.id,'sales',auth.uid());
else update kanban.demands set version=version+1 where id=p_id; end if;
update kanban.demands set title=trim(p_data->>'title'),customer_id=(p_data->>'customer_id')::uuid,
description=coalesce(p_data->>'description',''),notes=coalesce(p_data->>'notes',''),requested_date=nullif(p_data->>'requested_date','')::date,
technical_notes=v_notes,interview_pdf_url=v_url,interview_drive_id=v_drive,interview_pdf_name=v_name,survey_format=2,technical_complete=v_complete,
survey_confirmed_at=case when not v_complete then null when v_changed then now() else survey_confirmed_at end,
survey_confirmed_by=case when not v_complete then null when v_changed then auth.uid() else survey_confirmed_by end,
updated_at=now() where id=p_id returning * into d;
-- Respostas da versão anterior permanecem intactas em demand_items.
insert into kanban.audit_events(demand_id,actor_id,type,description,before_data,after_data) values(d.id,auth.uid(),case when old_data is null then 'created' else 'updated' end,case when old_data is null then 'Orçamento aberto' else 'Levantamento livre atualizado' end,old_data,to_jsonb(d));
return d.id; end; $$;


drop policy if exists documents_read on kanban.documents;
create policy documents_read on kanban.documents for select to authenticated using(exists(select 1 from kanban.demands d where d.id=demand_id and kanban.can_read(d)));
alter table kanban.document_migrations add column if not exists lease_token uuid;
alter table kanban.document_migrations add column if not exists initiated_by uuid references kanban.profiles;
-- Somente worker confiável: esta função nunca é concedida a usuários do navegador.
create or replace function public.kb_document_migration(p_id uuid,p_action text,p_token uuid,p_actor uuid,p_target text default null,p_hash text default null,p_size bigint default null,p_error text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare f kanban.documents;m kanban.document_migrations;begin
if not exists(select 1 from kanban.profiles p join kanban.user_roles r on r.user_id=p.id where p.id=p_actor and p.active and r.role='admin') then raise exception 'Migração exige administrador ativo.';end if;
select * into f from kanban.documents where id=p_id for update;if not found or f.status not in ('ready','archived') then raise exception 'Documento não está pronto para migração.';end if;
insert into kanban.document_migrations(document_id) values(p_id) on conflict do nothing;
select * into m from kanban.document_migrations where document_id=p_id for update;
if p_action='claim' then
if f.migration_status='CONCLUIDO' then return jsonb_build_object('document',to_jsonb(f),'checkpoint',to_jsonb(m),'done',true);end if;
if f.storage_provider<>'supabase' or p_token is null then raise exception 'Origem ou operação inválida.';end if;
if m.lease_until>now() and m.lease_token is distinct from p_token then raise exception 'Migração já está em execução.';end if;
update kanban.document_migrations set lease_until=now()+interval '15 minutes',lease_token=p_token,initiated_by=p_actor,state='EM_MIGRACAO',error=null,updated_at=now() where document_id=p_id;
update kanban.documents set migration_status='EM_MIGRACAO' where id=p_id;
else
if m.lease_token is distinct from p_token or m.lease_until is null or m.lease_until<now() or m.initiated_by is distinct from p_actor then raise exception 'Reserva de migração expirada ou inválida.';end if;
if p_action='target' then
if p_target is null or p_target!~'^[A-Za-z0-9_-]{10,200}$' or (m.target_id is not null and m.target_id<>p_target) then raise exception 'Identificador destino inválido.';end if;
update kanban.document_migrations set target_id=p_target where document_id=p_id;
elsif p_action='copied' then
if m.target_id is null then raise exception 'Destino não reservado.';end if;
update kanban.document_migrations set state='COPIADO' where document_id=p_id;update kanban.documents set migration_status='COPIADO' where id=p_id;
elsif p_action='validated' then
if m.state<>'COPIADO' or p_hash is distinct from f.checksum or p_size is distinct from f.size_bytes then raise exception 'Integridade divergente.';end if;
update kanban.document_migrations set state='VALIDADO',verified_checksum=p_hash,verified_size=p_size where document_id=p_id;update kanban.documents set migration_status='VALIDADO' where id=p_id;
elsif p_action='complete' then
if m.state<>'VALIDADO' or m.verified_checksum is distinct from f.checksum or m.verified_size is distinct from f.size_bytes then raise exception 'Migração não validada.';end if;
update kanban.documents set storage_provider='google_drive',google_drive_file_id=m.target_id,migration_status='CONCLUIDO',migrated_at=now() where id=p_id;
update kanban.document_migrations set state='CONCLUIDO',lease_until=null where document_id=p_id;
insert into kanban.audit_events(demand_id,actor_id,type,description,after_data) values(f.demand_id,p_actor,'document_migrated','Documento copiado e validado no Google Drive; original mantido',jsonb_build_object('document_id',p_id,'target_id',m.target_id,'checksum',f.checksum));
elsif p_action='fail' then
update kanban.document_migrations set state='FALHA',error=left(p_error,1000),lease_until=null where document_id=p_id;update kanban.documents set migration_status='FALHA' where id=p_id;
else raise exception 'Ação inválida.';end if;
end if;
return jsonb_build_object('document',(select to_jsonb(x) from kanban.documents x where id=p_id),'checkpoint',(select to_jsonb(x) from kanban.document_migrations x where document_id=p_id),'done',false);end; $$;
revoke all on function public.kb_document_migration(uuid,text,uuid,uuid,text,text,bigint,text) from public,anon,authenticated;
grant execute on function public.kb_document_migration(uuid,text,uuid,uuid,text,text,bigint,text) to service_role;
create or replace function public.kb_document_rollback(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$ declare f kanban.documents;begin
perform kanban.require_active();if not kanban.has_role(array['admin']) then raise exception 'Somente administrador pode efetuar rollback.';end if;
select * into f from kanban.documents where id=p_id for update;if not found or f.migration_status<>'CONCLUIDO' or length(trim(coalesce(p_reason,'')))<5 then raise exception 'Documento ou justificativa inválidos.';end if;
if not exists(select 1 from storage.objects where bucket_id=f.bucket_name and name=f.storage_path and coalesce(metadata->>'size',metadata->>'contentLength')::bigint=f.size_bytes) then raise exception 'Original indisponível. Rollback interrompido.';end if;
update kanban.documents set storage_provider='supabase',migration_status='PENDENTE' where id=p_id;
update kanban.document_migrations set state='PENDENTE',lease_until=null where document_id=p_id;
insert into kanban.audit_events(demand_id,actor_id,type,description,after_data) values(f.demand_id,auth.uid(),'document_rollback',p_reason,jsonb_build_object('document_id',p_id));end; $$;
revoke all on function public.kb_document_rollback(uuid,text) from public,anon;grant execute on function public.kb_document_rollback(uuid,text) to authenticated;

notify pgrst,'reload schema';
commit;
