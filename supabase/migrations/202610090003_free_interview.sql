-- Versão 2: levantamento livre e referência à entrevista no Drive.
-- Atualização aditiva para a Fase 1 existente. Não exclui clientes, demandas ou respostas.
begin;
alter table kanban.demands add column if not exists technical_notes text not null default '';
alter table kanban.demands add column if not exists interview_pdf_url text not null default '';
alter table kanban.demands add column if not exists interview_pdf_name text not null default '';
alter table kanban.demands add column if not exists interview_drive_id text not null default '';
alter table kanban.demands add column if not exists survey_confirmed_at timestamptz;
alter table kanban.demands add column if not exists survey_confirmed_by uuid references kanban.profiles;
alter table kanban.demands add column if not exists survey_format int not null default 1;

create or replace function kanban.drive_reference(url text) returns text
language plpgsql immutable set search_path='' as $$
declare parts text[]; begin
if trim(coalesce(url,''))='' then return ''; end if;
parts:=regexp_match(trim(url),'^https://drive\.google\.com/file/d/([A-Za-z0-9_-]{10,200})(/(view|preview))?/?([?#][^[:space:]]*)?$');
if parts is not null then return parts[1]; end if;
parts:=regexp_match(trim(url),'^https://drive\.google\.com/open\?id=([A-Za-z0-9_-]{10,200})(&[^[:space:]]*)?$');
if parts is not null then return parts[1]; end if;
raise exception 'Use o link de um arquivo do Google Drive (https://drive.google.com/file/d/...).';
end; $$;
revoke all on function kanban.drive_reference(text) from public,anon,authenticated;

create or replace function kanban.missing(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare d kanban.demands; result jsonb:='[]'; begin
select * into d from kanban.demands where id=p_id;
if length(trim(d.technical_notes))=0 or lower(trim(d.technical_notes)) in ('pendente','a definir','não sei','n/a') then result:=result||jsonb_build_array('Registrar o levantamento técnico no campo livre'); end if;
if d.interview_drive_id='' then result:=result||jsonb_build_array('Informar o PDF da entrevista escolhido no Drive'); end if;
if not d.technical_complete or d.survey_format<>2 then result:=result||jsonb_build_array('Confirmar a conclusão do levantamento'); end if;
return result; end; $$;

create or replace function public.kb_bootstrap() returns jsonb
language plpgsql security definer set search_path='' as $$ begin
perform kanban.require_active(); return jsonb_build_object('api_version',2,
'profile',(select to_jsonb(p) from kanban.profiles p where id=auth.uid()),
'roles',(select jsonb_agg(role) from kanban.user_roles where user_id=auth.uid()),
'stages',(select jsonb_agg(to_jsonb(s) order by position) from kanban.workflow_stages s),
'products','[]'::jsonb,
'people',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'roles',(select jsonb_agg(role) from kanban.user_roles where user_id=p.id)) order by p.name),'[]') from kanban.profiles p where active)); end; $$;

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
if v_complete and (length(trim(v_notes))=0 or lower(trim(v_notes)) in ('pendente','a definir','não sei','n/a') or v_drive='') then raise exception 'Para concluir, registre o levantamento e a referência ao PDF da entrevista. Você pode salvar como rascunho.'; end if;
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

create or replace function public.kb_detail(p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$ declare d kanban.demands; begin
perform kanban.require_active(); select * into d from kanban.demands where id=p_id;
if not found or not kanban.can_read(d) then raise exception 'Orçamento indisponível.'; end if;
return to_jsonb(d)||jsonb_build_object('customer',(select legal_name from kanban.customers where id=d.customer_id),
'legacy_interview',(select jsonb_build_object('product_name',p.name,'answers',i.answers,'fields',t.fields,'version',t.version) from kanban.demand_items i join kanban.interview_templates t on t.id=i.template_id join kanban.product_types p on p.id=t.product_id where i.demand_id=p_id),
'missing',kanban.missing(p_id),'can_edit',kanban.can_edit(d),
'execution',(select to_jsonb(e) from kanban.stage_executions e where demand_id=p_id and completed_at is null)); end; $$;

-- O catálogo antigo fica somente para consulta histórica, sem edição pelo aplicativo.
revoke execute on function public.kb_set_product(text,text,boolean) from authenticated,anon,public;
revoke all on function public.kb_bootstrap(),public.kb_detail(uuid),public.kb_save_demand(uuid,int,jsonb) from public,anon;
grant execute on function public.kb_bootstrap(),public.kb_detail(uuid),public.kb_save_demand(uuid,int,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
