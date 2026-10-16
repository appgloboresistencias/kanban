begin;
-- Correção 2.2: conclusão de Orçamento encaminha para Aprovação.
create or replace function public.kb_transition(p_id uuid,p_version int,p_target text,p_assignee uuid,p_reason text,p_request uuid) returns int language plpgsql security definer set search_path='' as $$
declare d kanban.demands; r kanban.transition_requests; v int; missing jsonb; begin
perform kanban.require_active(); select * into d from kanban.demands where id=p_id for update;
if not found or not kanban.can_read(d) then raise exception 'Orçamento indisponível.'; end if;
select * into r from kanban.transition_requests where id=p_request;
if found then if r.demand_id<>p_id or r.actor_id<>auth.uid() or r.target<>p_target then raise exception 'Operação inválida.'; end if; return r.result_version; end if;
if not kanban.can_edit(d) then raise exception 'Sem permissão para movimentar.'; end if;
if d.version is distinct from p_version then raise exception 'Conflito de edição. Atualize o card.'; end if;
if not ((d.stage='sales' and p_target='design') or (d.stage='design' and p_target in ('sales','quotation')) or (d.stage='quotation' and p_target='approval')) then raise exception 'Transição não disponível nesta fase. Os módulos seguintes permanecem bloqueados.'; end if;
if length(trim(coalesce(p_reason,'')))<5 then raise exception 'Informe a justificativa da movimentação.'; end if;
if not exists(select 1 from kanban.profiles p join kanban.user_roles ur on ur.user_id=p.id where p.id=p_assignee and p.active and ur.role in ('admin','manager',(select role from kanban.workflow_stages where code=p_target))) then raise exception 'Responsável não habilitado para a etapa.'; end if;
if d.stage='sales' then missing:=kanban.missing(d.id); if jsonb_array_length(missing)>0 then raise exception 'Pendências: %',missing; end if; end if;
if not exists(select 1 from kanban.stage_executions where demand_id=p_id and completed_at is null and started_at is not null) then raise exception 'Inicie a atividade antes de concluir.'; end if;
update kanban.stage_executions set completed_at=now() where demand_id=p_id and completed_at is null;
insert into kanban.stage_executions(demand_id,stage,assignee_id) values(p_id,p_target,p_assignee);
update kanban.demands set stage=p_target,assignee_id=p_assignee,version=version+1,technical_complete=case when p_target='sales' then false else technical_complete end,updated_at=now() where id=p_id returning version into v;
insert into kanban.audit_events(demand_id,actor_id,type,description,before_data,after_data) values(p_id,auth.uid(),'transition',p_reason,jsonb_build_object('stage',d.stage,'assignee_id',d.assignee_id),jsonb_build_object('stage',p_target,'assignee_id',p_assignee));
insert into kanban.transition_requests values(p_request,p_id,auth.uid(),p_target,v); return v; end; $$;
notify pgrst, 'reload schema';
commit;
