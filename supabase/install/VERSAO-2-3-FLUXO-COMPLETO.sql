begin;
-- Atualização aditiva: nenhum cadastro ou ciclo anterior é removido.
alter table kanban.stage_executions add column if not exists data jsonb not null default '{}';
alter table kanban.demands add column if not exists completed_at timestamptz;
alter table kanban.demands add column if not exists agreed_delivery_date date;
alter table kanban.demands add column if not exists materials_pending jsonb;
alter table kanban.demands add column if not exists rework_count int not null default 0;

create or replace function kanban.can_edit(d kanban.demands) returns boolean language sql stable security definer set search_path='' as $$
select d.status='open' and (kanban.has_role(array['admin','manager']) or (d.assignee_id=auth.uid() and kanban.has_role(array[(select role from kanban.workflow_stages where code=d.stage)]))); $$;

create or replace function kanban.stage_data(p jsonb) returns void language plpgsql set search_path='' as $$
declare k text; v jsonb; begin
if p is null or jsonb_typeof(p)<>'object' or octet_length(p::text)>32000 then raise exception 'Dados da etapa inválidos ou muito extensos.'; end if;
for k,v in select * from jsonb_each(p) loop
if jsonb_typeof(v) not in ('string','boolean') then raise exception 'Formato inválido no campo %.',k; end if;
if k in ('confirmed','sent','client_approved','internal_approved','partial_authorized','blocked') and jsonb_typeof(v)<>'boolean' then raise exception 'Confirmação inválida: %.',k; end if;
if right(k,5)='_date' and coalesce(p->>k,'')<>'' then
if (p->>k)!~'^\d{4}-\d{2}-\d{2}$' then raise exception 'Data inválida: %.',k; end if;
perform (p->>k)::date;
end if;
end loop;
end; $$;
create or replace function kanban.stage_require(p jsonb, fields text[]) returns void language plpgsql set search_path='' as $$ declare k text; begin
foreach k in array fields loop
if length(trim(coalesce(p->>k,'')))=0 then raise exception 'Preencha o campo obrigatório: %.',k; end if;
end loop; end; $$;
revoke all on function kanban.stage_data(jsonb),kanban.stage_require(jsonb,text[]) from public,anon,authenticated;

create or replace function public.kb_stage_save(p_id uuid,p_version int,p_data jsonb) returns int language plpgsql security definer set search_path='' as $$
declare d kanban.demands; old_data jsonb; v int; begin
perform kanban.require_active(); select * into d from kanban.demands where id=p_id for update;
if not found or not kanban.can_edit(d) then raise exception 'Sem permissão para editar a etapa.'; end if;
if d.version is distinct from p_version then raise exception 'Conflito de edição. Atualize o card.'; end if;
perform kanban.stage_data(p_data);
select data into old_data from kanban.stage_executions where demand_id=p_id and completed_at is null;
update kanban.stage_executions set data=p_data where demand_id=p_id and completed_at is null;
update kanban.demands set version=version+1,updated_at=now() where id=p_id returning version into v;
insert into kanban.audit_events(demand_id,actor_id,type,description,before_data,after_data) values(p_id,auth.uid(),'stage_saved','Dados da etapa atualizados',jsonb_build_object('stage',d.stage,'data',old_data),jsonb_build_object('stage',d.stage,'data',p_data));
return v; end; $$;

create or replace function public.kb_finish(p_id uuid,p_version int,p_target text,p_assignee uuid,p_reason text,p_request uuid,p_data jsonb) returns int language plpgsql security definer set search_path='' as $$
declare d kanban.demands; r kanban.transition_requests; v int; valid boolean; terminal boolean; last_proposal text; begin
perform kanban.require_active(); select * into d from kanban.demands where id=p_id for update;
if not found or not kanban.can_read(d) then raise exception 'Orçamento indisponível.'; end if;
if p_request is null then raise exception 'Identificador da operação obrigatório.'; end if;
select * into r from kanban.transition_requests where id=p_request;
if found then if r.demand_id<>p_id or r.actor_id<>auth.uid() or r.target<>p_target then raise exception 'Operação inválida.'; end if; return r.result_version; end if;
if d.version is distinct from p_version then raise exception 'Conflito de edição. Atualize o card.'; end if;
if d.status='rejected' and p_target='sales' then
if not kanban.has_role(array['admin','manager']) then raise exception 'Somente gestão pode reabrir um orçamento recusado.'; end if;
else
if not kanban.can_edit(d) then raise exception 'Sem permissão para movimentar ou pedido já encerrado.'; end if;
valid:=case d.stage
when 'sales' then p_target='design'
when 'design' then p_target in ('quotation','sales','design','rejected')
when 'quotation' then p_target in ('approval','design')
when 'approval' then p_target in ('op','quotation','design','rejected')
when 'op' then p_target in ('warehouse','design')
when 'warehouse' then p_target in ('production','op')
when 'production' then p_target='quality'
when 'quality' then p_target in ('delivery','production')
when 'delivery' then p_target='completed' else false end;
if valid is distinct from true then raise exception 'Transição não permitida para a etapa atual.'; end if;
if not exists(select 1 from kanban.stage_executions where demand_id=p_id and completed_at is null and started_at is not null) then raise exception 'Inicie a atividade antes de concluir.'; end if;
end if;
if length(trim(coalesce(p_reason,'')))<5 or length(p_reason)>4000 then raise exception 'Informe justificativa de 5 a 4000 caracteres.'; end if;
perform kanban.stage_data(p_data);
if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'Confirme a conclusão ou decisão da etapa.'; end if;
terminal:=p_target in ('completed','rejected');
if not terminal and not exists(select 1 from kanban.profiles p join kanban.user_roles ur on ur.user_id=p.id where p.id=p_assignee and p.active and ur.role in ('admin','manager',(select role from kanban.workflow_stages where code=p_target))) then raise exception 'Responsável não habilitado para a etapa.'; end if;
if d.status='open' then
if d.stage='sales' and jsonb_array_length(kanban.missing(d.id))>0 then raise exception 'Conclua as pendências do levantamento.'; end if;
if d.stage='quotation' and p_target='approval' then
perform kanban.stage_require(p_data,array['proposal_version','sent_date','valid_until_date']);
if p_data->'sent' is distinct from 'true'::jsonb then raise exception 'Confirme o envio da proposta ao cliente.'; end if;
if (p_data->>'sent_date')::date>current_date or (p_data->>'valid_until_date')::date<(p_data->>'sent_date')::date then raise exception 'Confira as datas de envio e validade.'; end if;
end if;
if d.stage='approval' and p_target='op' then
perform kanban.stage_require(p_data,array['approved_version','approval_date','approval_channel','approval_reference','delivery_date']);
if p_data->'client_approved' is distinct from 'true'::jsonb or p_data->'internal_approved' is distinct from 'true'::jsonb then raise exception 'Registre aprovação do cliente e aprovação interna.'; end if;
select data->>'proposal_version' into last_proposal from kanban.stage_executions where demand_id=p_id and stage='quotation' and completed_at is not null order by entered_at desc,id desc limit 1;
if last_proposal is not null and last_proposal<>p_data->>'approved_version' then raise exception 'A versão aprovada deve corresponder à última proposta enviada.'; end if;
if (p_data->>'approval_date')::date>current_date or (p_data->>'delivery_date')::date<(p_data->>'approval_date')::date then raise exception 'Confira as datas de aprovação e entrega.'; end if;
end if;
if p_target='rejected' then perform kanban.stage_require(p_data,array['decision_date']); if (p_data->>'decision_date')::date>current_date then raise exception 'A recusa não pode ter data futura.'; end if; end if;
if d.stage='op' and p_target='warehouse' then perform kanban.stage_require(p_data,array['op_number','issue_date','materials']); end if;
if d.stage='warehouse' and p_target='production' then
if p_data->>'material_status' not in ('total','partial') or p_data->>'material_status' is null then raise exception 'Informe a situação dos materiais.'; end if;
if p_data->>'material_status'='partial' then
perform kanban.stage_require(p_data,array['missing_materials','expected_date']);
if p_data->'partial_authorized' is distinct from 'true'::jsonb or not kanban.has_role(array['admin','manager']) then raise exception 'Material parcial exige autorização de Gestor ou Administrador ao concluir.'; end if;
update kanban.demands set materials_pending=jsonb_build_object('description',p_data->>'missing_materials','expected_date',p_data->>'expected_date','authorized_by',auth.uid(),'authorized_at',now()) where id=p_id;
else update kanban.demands set materials_pending=null where id=p_id; end if;
end if;
if d.stage='production' then
if p_data->'blocked' is distinct from 'false'::jsonb then raise exception 'Confirme que não há problemas bloqueantes em aberto.'; end if;
perform kanban.stage_require(p_data,array['work_done']);
end if;
if d.stage='quality' then
perform kanban.stage_require(p_data,array['inspection']);
if p_target='delivery' and d.materials_pending is not null then raise exception 'Regularize os materiais pendentes antes de liberar a entrega.'; end if;
end if;
if d.stage='delivery' then
perform kanban.stage_require(p_data,array['delivered_date','received_by','delivery_reference']);
if (p_data->>'delivered_date')::date>current_date then raise exception 'Entrega efetiva não pode ter data futura.'; end if;
end if;
end if;
update kanban.stage_executions set data=p_data,completed_at=now() where demand_id=p_id and completed_at is null;
if not terminal then insert into kanban.stage_executions(demand_id,stage,assignee_id) values(p_id,p_target,p_assignee); end if;
update kanban.demands set stage=case when terminal then stage else p_target end,
status=case when terminal then p_target else 'open' end,assignee_id=case when terminal then assignee_id else p_assignee end,
completed_at=case when terminal then now() else null end,version=version+1,updated_at=now(),
agreed_delivery_date=case when d.stage='approval' and p_target='op' then (p_data->>'delivery_date')::date when p_target in ('sales','design','quotation') then null else agreed_delivery_date end,
rework_count=rework_count+case when d.stage='quality' and p_target='production' then 1 else 0 end,
technical_complete=case when p_target='sales' then false else technical_complete end where id=p_id returning version into v;
insert into kanban.audit_events(demand_id,actor_id,type,description,before_data,after_data) values(p_id,auth.uid(),case when terminal then p_target when d.status='rejected' then 'reopened' else 'transition' end,p_reason,jsonb_build_object('stage',d.stage,'status',d.status,'assignee_id',d.assignee_id),jsonb_build_object('stage',p_target,'assignee_id',p_assignee,'data',p_data));
insert into kanban.transition_requests values(p_request,p_id,auth.uid(),p_target,v); return v; end; $$;

-- Clientes antigos não podem ignorar os novos registros obrigatórios.
create or replace function public.kb_transition(p_id uuid,p_version int,p_target text,p_assignee uuid,p_reason text,p_request uuid) returns int language plpgsql security definer set search_path='' as $$ begin
raise exception 'Atualize a aplicação para utilizar o fluxo completo de etapas.'; end; $$;

create or replace function public.kb_materials_resolve(p_id uuid,p_version int,p_reason text) returns void language plpgsql security definer set search_path='' as $$ declare d kanban.demands; begin
perform kanban.require_active(); if not kanban.has_role(array['admin','manager','warehouse']) then raise exception 'Apenas almoxarifado ou gestão pode regularizar materiais.'; end if;
select * into d from kanban.demands where id=p_id for update;
if not found or d.version is distinct from p_version then raise exception 'Conflito de edição. Atualize o card.'; end if;
if d.materials_pending is null or d.status<>'open' then raise exception 'Nenhuma pendência ativa.'; end if;
if length(trim(coalesce(p_reason,'')))<5 then raise exception 'Informe como os materiais foram regularizados.'; end if;
update kanban.demands set materials_pending=null,version=version+1,updated_at=now() where id=p_id;
insert into kanban.audit_events(demand_id,actor_id,type,description,before_data) values(p_id,auth.uid(),'materials_resolved',p_reason,d.materials_pending); end; $$;

create or replace function public.kb_board_v2(p_search text default '',p_stage text default null,p_cursor timestamptz default null,p_cursor_id uuid default null,p_status text default 'open') returns jsonb language plpgsql security definer set search_path='' as $$ begin
perform kanban.require_active(); if p_status not in ('open','completed','rejected') or p_status is null then raise exception 'Situação inválida.'; end if;
return jsonb_build_object('cards',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (
select d.*,c.legal_name as customer,p.name as assignee,e.entered_at,e.started_at,e.data as stage_data,kanban.missing(d.id) as missing
from kanban.demands d join kanban.customers c on c.id=d.customer_id join kanban.profiles p on p.id=d.assignee_id
left join lateral (select entered_at,started_at,data from kanban.stage_executions where demand_id=d.id order by entered_at desc,id desc limit 1)e on true
where kanban.can_read(d) and d.status=p_status and (p_stage is null or d.stage=p_stage) and (d.title ilike '%'||left(p_search,100)||'%' or d.number ilike '%'||left(p_search,100)||'%' or c.legal_name ilike '%'||left(p_search,100)||'%')
and (p_cursor is null or (d.created_at,d.id)<(p_cursor,p_cursor_id)) order by d.created_at desc,d.id desc limit 31)x),
'counts',(select coalesce(jsonb_object_agg(stage,n),'{}') from (select d.stage,count(*) n from kanban.demands d join kanban.customers c on c.id=d.customer_id where kanban.can_read(d) and status=p_status and (d.title ilike '%'||left(p_search,100)||'%' or d.number ilike '%'||left(p_search,100)||'%' or c.legal_name ilike '%'||left(p_search,100)||'%') group by stage)x)); end; $$;
revoke all on function public.kb_finish(uuid,int,text,uuid,text,uuid,jsonb),public.kb_stage_save(uuid,int,jsonb),public.kb_materials_resolve(uuid,int,text),public.kb_board_v2(text,text,timestamptz,uuid,text) from public,anon;
grant execute on function public.kb_finish(uuid,int,text,uuid,text,uuid,jsonb),public.kb_stage_save(uuid,int,jsonb),public.kb_materials_resolve(uuid,int,text),public.kb_board_v2(text,text,timestamptz,uuid,text) to authenticated;
create or replace function kanban.can_read(d kanban.demands) returns boolean language sql stable security definer set search_path='' as $$
select kanban.has_role(array['admin','manager']) or (exists(select 1 from kanban.profiles where id=auth.uid() and active) and (d.seller_id=auth.uid() or d.assignee_id=auth.uid() or exists(select 1 from kanban.stage_executions e where e.demand_id=d.id and e.assignee_id=auth.uid()) or exists(select 1 from kanban.audit_events a where a.demand_id=d.id and a.actor_id=auth.uid()) or (d.materials_pending is not null and kanban.has_role(array['warehouse'])) or (d.stage not in ('sales','approval') and kanban.has_role(array[(select role from kanban.workflow_stages where code=d.stage)])))); $$;

create or replace function public.kb_assign(p_id uuid,p_version int,p_assignee uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$ declare d kanban.demands; eid uuid; begin
perform kanban.require_active(); if not kanban.has_role(array['admin','manager']) then raise exception 'Apenas gestão pode transferir responsabilidades.'; end if;
select * into d from kanban.demands where id=p_id for update; if not found or d.version is distinct from p_version then raise exception 'Conflito de edição. Atualize o card.'; end if;
if d.status<>'open' then raise exception 'Pedido encerrado não pode ser transferido.'; end if;
if length(trim(coalesce(p_reason,'')))<5 then raise exception 'Informe a justificativa.'; end if;
if not exists(select 1 from kanban.profiles p join kanban.user_roles r on r.user_id=p.id where p.id=p_assignee and p.active and r.role in ('admin','manager',(select role from kanban.workflow_stages where code=d.stage))) then raise exception 'Responsável não habilitado.'; end if;
update kanban.stage_executions set assignee_id=p_assignee where demand_id=p_id and completed_at is null returning id into eid;
insert into kanban.stage_assignments(execution_id,assignee_id,actor_id,reason) values(eid,p_assignee,auth.uid(),p_reason);
update kanban.demands set assignee_id=p_assignee,version=version+1,updated_at=now() where id=p_id;
insert into kanban.audit_events(demand_id,actor_id,type,description,before_data,after_data) values(p_id,auth.uid(),'assigned',p_reason,jsonb_build_object('assignee_id',d.assignee_id),jsonb_build_object('assignee_id',p_assignee)); end; $$;


create or replace function public.kb_bootstrap() returns jsonb
language plpgsql security definer set search_path='' as $$ begin
perform kanban.require_active(); return jsonb_build_object('api_version',2,'workflow_version',3,
'profile',(select to_jsonb(p) from kanban.profiles p where id=auth.uid()),
'roles',(select jsonb_agg(role) from kanban.user_roles where user_id=auth.uid()),
'stages',(select jsonb_agg(to_jsonb(s) order by position) from kanban.workflow_stages s),
'products','[]'::jsonb,
'people',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'roles',(select jsonb_agg(role) from kanban.user_roles where user_id=p.id)) order by p.name),'[]') from kanban.profiles p where active)); end; $$;


create or replace function public.kb_detail(p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$ declare d kanban.demands; begin
perform kanban.require_active(); select * into d from kanban.demands where id=p_id;
if not found or not kanban.can_read(d) then raise exception 'Orçamento indisponível.'; end if;
return to_jsonb(d)||jsonb_build_object('customer',(select legal_name from kanban.customers where id=d.customer_id),
'legacy_interview',(select jsonb_build_object('product_name',p.name,'answers',i.answers,'fields',t.fields,'version',t.version) from kanban.demand_items i join kanban.interview_templates t on t.id=i.template_id join kanban.product_types p on p.id=t.product_id where i.demand_id=p_id),
'cycles',(select coalesce(jsonb_agg(to_jsonb(e) order by entered_at,id),'[]') from kanban.stage_executions e where demand_id=p_id),'missing',kanban.missing(p_id),'can_edit',kanban.can_edit(d),
'execution',(select to_jsonb(e) from kanban.stage_executions e where demand_id=p_id and completed_at is null)); end; $$;


notify pgrst,'reload schema';
commit;
