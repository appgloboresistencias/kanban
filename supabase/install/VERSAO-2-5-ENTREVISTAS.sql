begin;
create table if not exists kanban.interview_library(
 id uuid primary key default gen_random_uuid(), title text not null check(length(trim(title)) between 3 and 200),
 original_filename text not null, storage_path text not null unique, size_bytes bigint not null check(size_bytes>0),
 checksum text not null check(checksum ~ '^[a-f0-9]{64}$'), status text not null default 'pending' check(status in ('pending','ready','archived','cancelled')),
 uploaded_by uuid not null references kanban.profiles, created_at timestamptz not null default now());
alter table kanban.interview_library enable row level security;
revoke all on kanban.interview_library from public,anon,authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('globo-entrevistas','globo-entrevistas',false,52428800,array['application/pdf']) on conflict(id) do nothing;
do $$ begin if exists(select 1 from storage.buckets where id='globo-entrevistas' and public) then raise exception 'O bucket globo-entrevistas deve ser privado.';end if;end $$;

create or replace function kanban.interview_access(p_path text,p_upload boolean,p_meta jsonb default null) returns boolean
language plpgsql volatile security definer set search_path='' as $$ declare f kanban.interview_library;begin
if auth.uid() is null or not exists(select 1 from kanban.profiles where id=auth.uid() and active) then return false;end if;
if p_upload then select * into f from kanban.interview_library where storage_path=p_path for share;else select * into f from kanban.interview_library where storage_path=p_path;end if;
if not found then return false;end if;
if p_upload then return kanban.has_role(array['admin']) and f.uploaded_by=auth.uid() and f.status='pending' and coalesce(p_meta->>'size',p_meta->>'contentLength')::bigint=f.size_bytes and p_meta->>'mimetype'='application/pdf';end if;
return f.status='ready' or (kanban.has_role(array['admin']) and f.status in ('pending','archived'));end $$;
revoke all on function kanban.interview_access(text,boolean,jsonb) from public,anon;
grant execute on function kanban.interview_access(text,boolean,jsonb) to authenticated;
drop policy if exists globo_interview_read on storage.objects;
create policy globo_interview_read on storage.objects for select to authenticated using(bucket_id='globo-entrevistas' and kanban.interview_access(name,false));
drop policy if exists globo_interview_insert on storage.objects;
create policy globo_interview_insert on storage.objects for insert to authenticated with check(bucket_id='globo-entrevistas' and kanban.interview_access(name,true,metadata));
drop policy if exists globo_interview_read_guard on storage.objects;
create policy globo_interview_read_guard on storage.objects as restrictive for select to public using(bucket_id<>'globo-entrevistas' or kanban.interview_access(name,false));
drop policy if exists globo_interview_insert_guard on storage.objects;
create policy globo_interview_insert_guard on storage.objects as restrictive for insert to public with check(bucket_id<>'globo-entrevistas' or kanban.interview_access(name,true,metadata));
drop policy if exists globo_interview_update_guard on storage.objects;
create policy globo_interview_update_guard on storage.objects as restrictive for update to public using(bucket_id<>'globo-entrevistas') with check(bucket_id<>'globo-entrevistas');
drop policy if exists globo_interview_delete_guard on storage.objects;
create policy globo_interview_delete_guard on storage.objects as restrictive for delete to public using(bucket_id<>'globo-entrevistas');

create or replace function kanban.storage_usage() returns bigint language sql stable security definer set search_path='' as $$
select coalesce((select sum(coalesce(coalesce(metadata->>'size',metadata->>'contentLength')::bigint,0)) from storage.objects),0)
+coalesce((select sum(size_bytes) from kanban.documents f where f.status='pending' and not exists(select 1 from storage.objects o where o.bucket_id=f.bucket_name and o.name=f.storage_path)),0)
+coalesce((select sum(size_bytes) from kanban.interview_library f where f.status='pending' and not exists(select 1 from storage.objects o where o.bucket_id='globo-entrevistas' and o.name=f.storage_path)),0); $$;

create or replace function public.kb_interviews(p_action text default 'list',p_id uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare f kanban.interview_library;c kanban.document_settings;meta jsonb;fid uuid:=gen_random_uuid();sz bigint;used bigint;begin
perform kanban.require_active();
if p_action='list' then
return (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select * from kanban.interview_library where (status='ready' or (kanban.has_role(array['admin']) and status in ('pending','archived'))) and (p_id is null or id>p_id) order by id limit 31)x);end if;
if not kanban.has_role(array['admin']) then raise exception 'Somente administrador gerencia modelos de entrevista.';end if;
perform 1 from kanban.document_settings where id for update;
if p_action='reserve' then
select * into c from kanban.document_settings where id;
sz:=(p_data->>'size')::bigint;
if sz is null or sz<=0 or sz>least(c.pdf_limit,52428800) or lower(coalesce(p_data->>'filename','')) !~ '\.pdf$' or length(p_data->>'filename')>200 or coalesce(p_data->>'checksum','') !~ '^[a-f0-9]{64}$' or length(trim(coalesce(p_data->>'title',''))) not between 3 and 200 then raise exception 'Informe título, arquivo PDF válido e tamanho dentro do limite.';end if;
select * into f from kanban.interview_library where checksum=p_data->>'checksum' and status in ('pending','ready') order by created_at limit 1;
if found then if f.status='pending' and f.uploaded_by<>auth.uid() then raise exception 'Outro administrador está enviando este PDF.';end if;return to_jsonb(f);end if;
used:=kanban.storage_usage();if used+sz>c.capacity_bytes then raise exception 'Espaço insuficiente no armazenamento.';end if;
insert into kanban.interview_library(id,title,original_filename,storage_path,size_bytes,checksum,uploaded_by) values(fid,trim(p_data->>'title'),p_data->>'filename','modelos/'||fid||'.pdf',sz,p_data->>'checksum',auth.uid()) returning * into f;
elsif p_action in ('finish','archive','cancel') then
select * into f from kanban.interview_library where id=p_id for update;if not found then raise exception 'Modelo não encontrado.';end if;
if p_action='finish' then
if f.status='ready' then return to_jsonb(f);end if;
if f.status<>'pending' then raise exception 'Modelo não está pendente.';end if;
select metadata into meta from storage.objects where bucket_id='globo-entrevistas' and name=f.storage_path;
if not found or coalesce(meta->>'size',meta->>'contentLength')::bigint is distinct from f.size_bytes or meta->>'mimetype' is distinct from 'application/pdf' then raise exception 'PDF ainda não foi armazenado ou diverge da reserva.';end if;
update kanban.interview_library set status='ready' where id=p_id returning * into f;
elsif p_action='archive' then
if f.status<>'ready' then raise exception 'Somente modelos disponíveis podem ser arquivados.';end if;
update kanban.interview_library set status='archived' where id=p_id returning * into f;
else
if f.status<>'pending' or exists(select 1 from storage.objects where bucket_id='globo-entrevistas' and name=f.storage_path) then raise exception 'Confirme o upload existente; somente reservas vazias podem ser canceladas.';end if;
update kanban.interview_library set status='cancelled' where id=p_id returning * into f;
end if;
else raise exception 'Operação inválida.';end if;
update kanban.document_settings set used_bytes=kanban.storage_usage(),checked_at=now() where id;
insert into kanban.audit_events(actor_id,type,description,after_data) values(auth.uid(),'interview_'||p_action,'Biblioteca de entrevistas: '||p_action,to_jsonb(f));
return to_jsonb(f);end $$;
revoke all on function public.kb_interviews(text,uuid,jsonb) from public,anon;
grant execute on function public.kb_interviews(text,uuid,jsonb) to authenticated;

-- Somente anexos confirmados do card satisfazem o levantamento.
create or replace function kanban.missing(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d kanban.demands;result jsonb:='[]';begin select * into d from kanban.demands where id=p_id;
if length(trim(d.technical_notes))=0 or lower(trim(d.technical_notes)) in ('pendente','a definir','não sei','n/a') then result:=result||jsonb_build_array('Registrar o levantamento técnico no campo livre');end if;
if not exists(select 1 from kanban.documents where demand_id=p_id and kind='interview' and status='ready' and confirmed and storage_provider='supabase') then result:=result||jsonb_build_array('Anexar as respostas da entrevista em PDF na aba Documentos');end if;
if not d.technical_complete or d.survey_format<>2 then result:=result||jsonb_build_array('Confirmar a conclusão do levantamento');end if;return result;end $$;

update kanban.document_settings set default_provider='supabase',google_enabled=false where id;
alter table kanban.document_settings drop constraint if exists document_settings_supabase_only;
alter table kanban.document_settings add constraint document_settings_supabase_only check(default_provider='supabase' and not google_enabled);
revoke all on function public.kb_document_migration(uuid,text,uuid,uuid,text,text,bigint,text) from service_role;
create or replace function public.kb_save_demand(p_id uuid,p_version int,p_data jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare d kanban.demands; old_data jsonb; yr int:=extract(year from now() at time zone 'America/Sao_Paulo'); seq int;
v_notes text:=coalesce(p_data->>'technical_notes',''); v_url text:='';
v_name text:=''; v_drive text;
v_complete boolean:=coalesce((p_data->>'technical_complete')::boolean,false); v_changed boolean;
begin
perform kanban.require_active();
if not kanban.has_role(array['admin','manager','sales']) then raise exception 'Sem permissão para abertura de orçamento.'; end if;
if (p_data->>'form_version') is distinct from '2' then raise exception 'Atualize a aplicação para a versão 2 antes de salvar. Nenhum dado foi alterado.'; end if;
if octet_length(p_data::text)>65536 or length(v_notes)>20000 or length(v_url)>2048 or length(v_name)>200 then raise exception 'Limite excedido: levantamento até 20.000 caracteres e nome do PDF até 200.'; end if;
v_drive:='';
select * into d from kanban.demands where id=p_id for update;
if found then
if not kanban.can_edit(d) or d.stage<>'sales' or d.status<>'open' then raise exception 'Edição disponível somente em Vendas ao responsável.'; end if;
if d.version is distinct from p_version then raise exception 'Conflito de edição. Reabra o card para atualizar.'; end if;
old_data:=to_jsonb(d);
else if p_version is distinct from 0 then raise exception 'Orçamento não encontrado.'; end if; end if;
if not exists(select 1 from kanban.customers where id=(p_data->>'customer_id')::uuid) then raise exception 'Selecione um cliente.'; end if;
if v_complete and (length(trim(v_notes))=0 or lower(trim(v_notes)) in ('pendente','a definir','não sei','n/a') or (not exists(select 1 from kanban.documents where demand_id=p_id and kind='interview' and status='ready' and confirmed))) then raise exception 'Para concluir, registre o levantamento e as respostas da entrevista em PDF na aba Documentos. Você pode salvar como rascunho.'; end if;
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


create or replace function public.kb_document_archive(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$ declare f kanban.documents;d kanban.demands;begin
perform kanban.require_active();select * into f from kanban.documents where id=p_id;select * into d from kanban.demands where id=f.demand_id for update;
if not found or not kanban.can_read(d) or not (kanban.can_edit(d) or kanban.has_role(array['admin'])) then raise exception 'Sem permissão para arquivar.';end if;
if length(trim(coalesce(p_reason,'')))<5 then raise exception 'Informe o motivo do arquivamento.';end if;
if f.status not in ('ready','legacy') then raise exception 'Documento não está disponível para arquivamento.';end if;
if f.kind='interview' and d.technical_complete and not exists(select 1 from kanban.documents where demand_id=d.id and id<>f.id and kind='interview' and status='ready' and confirmed) then raise exception 'Mantenha uma entrevista válida ou revise a confirmação do levantamento antes de arquivar.';end if;
update kanban.documents set status='archived',archived_at=now() where id=p_id;
insert into kanban.audit_events(demand_id,actor_id,type,description,after_data) values(d.id,auth.uid(),'document_archived',p_reason,jsonb_build_object('document_id',p_id));end; $$;
create or replace function public.kb_document_config_save(p_capacity bigint,p_photo bigint,p_pdf bigint,p_office bigint,p_provider text) returns void language plpgsql security definer set search_path='' as $$ declare c kanban.document_settings; begin
perform kanban.require_active();if not kanban.has_role(array['admin']) then raise exception 'Apenas administrador altera limites.';end if;
select * into c from kanban.document_settings where id for update;
if p_provider is distinct from 'supabase' then raise exception 'Somente Supabase Storage está disponível nesta versão.';end if;
if p_capacity<kanban.storage_usage() then raise exception 'Capacidade inferior ao espaço já reservado ou utilizado.';end if;
update kanban.document_settings set capacity_bytes=p_capacity,photo_limit=p_photo,pdf_limit=p_pdf,office_limit=p_office,default_provider=p_provider where id;
insert into kanban.audit_events(actor_id,type,description,before_data,after_data) values(auth.uid(),'document_config','Limites documentais atualizados',to_jsonb(c),jsonb_build_object('capacity',p_capacity,'photo',p_photo,'pdf',p_pdf,'office',p_office,'provider',p_provider));end; $$;

create or replace function public.kb_document_reserve(p_card uuid,p_name text,p_mime text,p_size bigint,p_checksum text,p_kind text,p_previous uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare c kanban.document_settings; d kanban.demands; f kanban.documents; prev kanban.documents; eid uuid; ext text; expected text; lim bigint; used bigint; fid uuid:=gen_random_uuid(); path text; ver int:=1; series uuid; begin
perform kanban.require_active();select * into c from kanban.document_settings where id for update;
select * into d from kanban.demands where id=p_card for update;if not found or not kanban.can_edit(d) then raise exception 'Sem permissão para anexar neste card.';end if;
select id into eid from kanban.stage_executions where demand_id=p_card and completed_at is null;
if eid is null then raise exception 'Etapa não está aberta.';end if;
if c.default_provider<>'supabase' then raise exception 'Armazenamento indisponível. Solicite revisão ao administrador.';end if;
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

commit;
