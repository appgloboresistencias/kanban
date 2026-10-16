-- Somente para banco SEM schema kanban. Para banco existente use VERSAO-2-ATUALIZAR.sql.
begin;
-- Fase 1. Schema independente; não modifica public.profiles/orders da versão 1.

create schema kanban;
revoke all on schema kanban from public;
grant usage on schema kanban to authenticated;
create table kanban.profiles(id uuid primary key references auth.users(id), name text not null, email text not null, active boolean not null default false);
create table kanban.roles(code text primary key, label text not null);
insert into kanban.roles values ('admin','Administrador'),('manager','Gestor'),('sales','Vendas'),('design','Projeto'),('estimator','Orçamentista'),('warehouse','Almoxarifado'),('production','Produção'),('quality','Qualidade'),('delivery','Entrega');
create table kanban.user_roles(user_id uuid references kanban.profiles, role text references kanban.roles, primary key(user_id,role));
create table kanban.customers(id uuid primary key default gen_random_uuid(), legal_name text not null check(length(trim(legal_name)) between 2 and 200), trade_name text not null default '', tax_id text unique, created_by uuid not null references kanban.profiles, version int not null default 1, created_at timestamptz not null default now());
create table kanban.customer_contacts(id uuid primary key default gen_random_uuid(),customer_id uuid not null unique references kanban.customers, name text not null, email text not null default '', phone text not null default '');
create table kanban.product_types(id text primary key, name text not null, active boolean not null default true);
create table kanban.interview_templates(id uuid primary key default gen_random_uuid(), product_id text not null references kanban.product_types, version int not null, fields jsonb not null check(jsonb_typeof(fields)='array'), requires_drawing boolean not null default true, unique(product_id,version));
create table kanban.workflow_stages(code text primary key, name text not null, position int not null unique, role text not null references kanban.roles);
insert into kanban.workflow_stages values ('sales','Vendas',1,'sales'),('design','Projeto',2,'design'),('quotation','Orçamento',3,'estimator'),('approval','Aprovação',4,'sales'),('op','Gerar OP',5,'design'),('warehouse','Almoxarifado',6,'warehouse'),('production','Produção',7,'production'),('quality','Qualidade',8,'quality'),('delivery','Entrega',9,'delivery');
create table kanban.number_counters(year int primary key, last_value int not null);
create table kanban.demands(id uuid primary key, number text not null unique, title text not null check(length(trim(title)) between 3 and 200), customer_id uuid not null references kanban.customers, seller_id uuid not null references kanban.profiles, assignee_id uuid not null references kanban.profiles, stage text not null default 'sales' references kanban.workflow_stages, status text not null default 'open' check(status in ('open','rejected','completed')), description text not null default '', notes text not null default '', requested_date date, technical_complete boolean not null default false, version int not null default 1, created_by uuid not null references kanban.profiles, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table kanban.demand_items(id uuid primary key default gen_random_uuid(), demand_id uuid not null unique references kanban.demands, template_id uuid not null references kanban.interview_templates, answers jsonb not null default '{}' check(jsonb_typeof(answers)='object'));
create table kanban.stage_executions(id uuid primary key default gen_random_uuid(), demand_id uuid not null references kanban.demands, stage text not null references kanban.workflow_stages, assignee_id uuid not null references kanban.profiles, entered_at timestamptz not null default now(), started_at timestamptz, completed_at timestamptz, check(started_at is null or started_at>=entered_at),check(completed_at is null or completed_at>=coalesce(started_at,entered_at)));
create unique index one_open_execution on kanban.stage_executions(demand_id) where completed_at is null;
create table kanban.stage_assignments(id uuid primary key default gen_random_uuid(), execution_id uuid not null references kanban.stage_executions, assignee_id uuid not null references kanban.profiles, actor_id uuid not null references kanban.profiles, reason text not null, created_at timestamptz not null default now());
create table kanban.audit_events(id bigint generated always as identity primary key, demand_id uuid references kanban.demands, actor_id uuid not null references kanban.profiles, type text not null, description text not null, before_data jsonb, after_data jsonb, created_at timestamptz not null default now());
create table kanban.transition_requests(id uuid primary key, demand_id uuid not null references kanban.demands, actor_id uuid not null references kanban.profiles, target text not null, result_version int not null);
-- Metadados reservados para a Fase 2; nenhum upload fictício ou link público.
create table kanban.documents(id uuid primary key default gen_random_uuid(),demand_id uuid not null references kanban.demands,execution_id uuid references kanban.stage_executions,kind text not null,name text not null,provider_id text not null,confirmed boolean not null default false,created_at timestamptz not null default now());
create index demands_stage_page on kanban.demands(stage,created_at desc,id desc);
create index demands_seller on kanban.demands(seller_id);
create index demands_assignee on kanban.demands(assignee_id);
create index demands_customer on kanban.demands(customer_id);
create index demands_deadline on kanban.demands(requested_date) where status='open';
create index audit_page on kanban.audit_events(demand_id,id desc);
create index docs_card on kanban.documents(demand_id);

create function kanban.has_role(roles text[]) returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from kanban.profiles p join kanban.user_roles r on r.user_id=p.id where p.id=auth.uid() and p.active and r.role=any(roles)); $$;
create function kanban.can_read(d kanban.demands) returns boolean language sql stable security definer set search_path='' as $$
select kanban.has_role(array['admin','manager']) or (exists(select 1 from kanban.profiles where id=auth.uid() and active) and (d.seller_id=auth.uid() or d.assignee_id=auth.uid() or (d.stage not in ('sales','approval') and kanban.has_role(array[(select role from kanban.workflow_stages where code=d.stage)])))); $$;
create function kanban.can_edit(d kanban.demands) returns boolean language sql stable security definer set search_path='' as $$
select kanban.has_role(array['admin','manager']) or (d.assignee_id=auth.uid() and kanban.has_role(array[(select role from kanban.workflow_stages where code=d.stage)])); $$;
create function kanban.require_active() returns void language plpgsql security definer set search_path='' as $$ begin
if not exists(select 1 from kanban.profiles p join kanban.user_roles r on r.user_id=p.id where p.id=auth.uid() and p.active) then raise exception 'Acesso não autorizado ou cadastro inativo.' using errcode='42501'; end if; end; $$;
create function kanban.on_user() returns trigger language plpgsql security definer set search_path='' as $$ begin
insert into kanban.profiles(id,name,email) values(new.id,coalesce(nullif(new.raw_user_meta_data->>'name',''),split_part(coalesce(new.email,''),'@',1)),coalesce(new.email,'')); return new; end; $$;
create trigger kanban_new_user after insert on auth.users for each row execute function kanban.on_user();
insert into kanban.profiles(id,name,email) select id,coalesce(nullif(raw_user_meta_data->>'name',''),split_part(coalesce(email,''),'@',1)),coalesce(email,'') from auth.users;

-- Todas as tabelas têm RLS. Escritas são exclusivas das RPCs auditadas.
do $$ declare t record; begin for t in select tablename from pg_tables where schemaname='kanban' loop execute format('alter table kanban.%I enable row level security',t.tablename); end loop; end $$;
grant select on kanban.profiles,kanban.roles,kanban.user_roles,kanban.customers,kanban.customer_contacts,kanban.product_types,kanban.interview_templates,kanban.workflow_stages,kanban.demands,kanban.demand_items,kanban.stage_executions,kanban.stage_assignments,kanban.audit_events,kanban.documents to authenticated;
create policy profile_read on kanban.profiles for select to authenticated using(id=auth.uid() or kanban.has_role(array['admin','manager']));
create policy role_read on kanban.roles for select to authenticated using(true);
create policy user_role_read on kanban.user_roles for select to authenticated using(user_id=auth.uid() or kanban.has_role(array['admin','manager']));
create policy demands_read on kanban.demands for select to authenticated using(kanban.can_read(demands));
create policy customers_read on kanban.customers for select to authenticated using(kanban.has_role(array['admin','manager','sales','estimator']));
create policy contacts_read on kanban.customer_contacts for select to authenticated using(kanban.has_role(array['admin','manager','sales','estimator']));
create policy products_read on kanban.product_types for select to authenticated using(exists(select 1 from kanban.profiles where id=auth.uid() and active));
create policy template_read on kanban.interview_templates for select to authenticated using(exists(select 1 from kanban.profiles where id=auth.uid() and active));
create policy stages_read on kanban.workflow_stages for select to authenticated using(exists(select 1 from kanban.profiles where id=auth.uid() and active));
create policy items_read on kanban.demand_items for select to authenticated using(exists(select 1 from kanban.demands d where d.id=demand_id));
create policy executions_read on kanban.stage_executions for select to authenticated using(exists(select 1 from kanban.demands d where d.id=demand_id));
create policy assignments_read on kanban.stage_assignments for select to authenticated using(exists(select 1 from kanban.stage_executions e where e.id=execution_id));
create policy events_read on kanban.audit_events for select to authenticated using(exists(select 1 from kanban.demands d where d.id=demand_id));
create policy documents_read on kanban.documents for select to authenticated using(exists(select 1 from kanban.demands d where d.id=demand_id) and (kind='drawing' or kanban.has_role(array['admin','manager','sales','estimator'])));

create function public.kb_bootstrap() returns jsonb language plpgsql security definer set search_path='' as $$ begin perform kanban.require_active(); return jsonb_build_object(
'profile',(select to_jsonb(p) from kanban.profiles p where id=auth.uid()),
'roles',(select jsonb_agg(role) from kanban.user_roles where user_id=auth.uid()),
'stages',(select jsonb_agg(to_jsonb(s) order by position) from kanban.workflow_stages s),
'products',(select jsonb_agg(to_jsonb(p)||jsonb_build_object('template',(select to_jsonb(t) from kanban.interview_templates t where product_id=p.id order by version desc limit 1)) order by name) from kanban.product_types p),
'people',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'roles',(select jsonb_agg(role) from kanban.user_roles where user_id=p.id)) order by p.name),'[]') from kanban.profiles p where active)); end; $$;

create function kanban.tax_valid(v text) returns boolean language plpgsql immutable set search_path='' as $$
declare n int:=length(v); acc int; digit int; i int; pass int; begin
if v is null or v='' then return true; end if;
if not ((n=11 and v~'^[0-9]{11}$') or (n=14 and v~'^[A-Z0-9]{12}[0-9]{2}$')) or v=repeat(substr(v,1,1),n) then return false; end if;
for pass in 1..2 loop acc:=0; for i in 1..(n-3+pass) loop
acc:=acc+(ascii(substr(v,i,1))-48) * case when n=11 then n-1+pass-i else ((n-3+pass-i)%8)+2 end;
end loop; digit:=(acc*10)%11; if digit=10 then digit:=0; end if;
if digit<>substr(v,n-2+pass,1)::int then return false; end if; end loop; return true; end; $$;

create function public.kb_save_customer(p_id uuid,p_version int,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare c kanban.customers; v_tax text:=nullif(regexp_replace(upper(coalesce(p_data->>'tax_id','')),'[./[:space:]-]','','g'),''); begin
perform kanban.require_active(); if not kanban.has_role(array['admin','manager','sales','estimator']) then raise exception 'Sem permissão para clientes.'; end if;
if not kanban.tax_valid(v_tax) then raise exception 'CPF/CNPJ inválido.'; end if;
if length(trim(coalesce(p_data->>'contact','')))<2 then raise exception 'Informe o contato.'; end if;
if length(coalesce(p_data->>'email',''))>0 and (p_data->>'email')!~'^[^ @]+@[^ @]+\.[^ @]+$' then raise exception 'E-mail inválido.'; end if;
if p_id is null then insert into kanban.customers(legal_name,trade_name,tax_id,created_by) values(trim(p_data->>'legal_name'),coalesce(p_data->>'trade_name',''),v_tax,auth.uid()) returning * into c;
else select * into c from kanban.customers where id=p_id for update; if not found or c.version is distinct from p_version then raise exception 'Cliente alterado. Atualize a página.'; end if;
update kanban.customers set legal_name=trim(p_data->>'legal_name'),trade_name=coalesce(p_data->>'trade_name',''),tax_id=v_tax,version=version+1 where id=p_id returning * into c; end if;
insert into kanban.customer_contacts(customer_id,name,email,phone) values(c.id,trim(p_data->>'contact'),coalesce(p_data->>'email',''),coalesce(p_data->>'phone','')) on conflict(customer_id) do update set name=excluded.name,email=excluded.email,phone=excluded.phone;
insert into kanban.audit_events(actor_id,type,description,after_data) values(auth.uid(),'customer_saved','Cadastro de cliente atualizado',jsonb_build_object('id',c.id,'version',c.version)); return c.id;
exception when unique_violation then raise exception 'Já existe cliente com este CPF/CNPJ.'; end; $$;

create function public.kb_customers(p_search text default '',p_page int default 0) returns jsonb language plpgsql security definer set search_path='' as $$ begin
perform kanban.require_active(); if not kanban.has_role(array['admin','manager','sales','estimator']) then raise exception 'Sem permissão para clientes.'; end if;
return (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select c.*,ct.name as contact,ct.email,ct.phone from kanban.customers c join kanban.customer_contacts ct on ct.customer_id=c.id where c.legal_name ilike '%'||left(p_search,100)||'%' or c.tax_id like '%'||left(p_search,100)||'%' order by c.legal_name,c.id limit 31 offset greatest(0,least(p_page,10000))*30)x); end; $$;

create function kanban.missing(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d kanban.demands; t kanban.interview_templates; a jsonb; f jsonb; v text; result jsonb:='[]'; begin
select * into d from kanban.demands where id=p_id;
select tt.* into t from kanban.interview_templates tt join kanban.demand_items i on i.template_id=tt.id where i.demand_id=p_id;
select answers into a from kanban.demand_items where demand_id=p_id;
if not d.technical_complete then result:=result||jsonb_build_array('Confirmar levantamento técnico'); end if;
for f in select value from jsonb_array_elements(t.fields) loop
if f ? 'when' and (a->>(f->'when'->>0)) is distinct from (f->'when'->>1) then continue; end if;
v:=trim(coalesce(a->>(f->>'key'),''));
if v='' or lower(v) in ('a definir','pendente','n/a','não sei') then result:=result||jsonb_build_array(f->>'label');
elsif f->>'type'='number' then
if v!~'^[0-9]+(\.[0-9]+)?$' then result:=result||jsonb_build_array(f->>'label');
elsif v::numeric<(f->>'min')::numeric or (f->>'key' in ('quantity','elements') and v::numeric<>trunc(v::numeric)) then result:=result||jsonb_build_array(f->>'label'); end if;
elsif f->>'type'='select' and not (f->'options' ? v) then result:=result||jsonb_build_array(f->>'label'); end if;
end loop;
if t.product_id='cartucho' and coalesce(a->>'length','')~'^[0-9]+(\.[0-9]+)?$' and coalesce(a->>'cold','')~'^[0-9]+(\.[0-9]+)?$' then
if (a->>'length')::numeric<=(a->>'cold')::numeric then result:=result||jsonb_build_array('Comprimento maior que zona fria'); end if; end if;
if t.requires_drawing and not exists(select 1 from kanban.documents where demand_id=p_id and kind='drawing' and confirmed) then result:=result||jsonb_build_array('Desenho confirmado — integração disponível na Fase 2'); end if;
return result; end; $$;

create function public.kb_save_demand(p_id uuid,p_version int,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare d kanban.demands; old_data jsonb; yr int:=extract(year from now() at time zone 'America/Sao_Paulo'); seq int; tid uuid; begin
perform kanban.require_active();
if not kanban.has_role(array['admin','manager','sales']) then raise exception 'Sem permissão para abertura de orçamento.'; end if;
select * into d from kanban.demands where id=p_id for update;
if found then
if not kanban.can_edit(d) or d.stage<>'sales' or d.status<>'open' then raise exception 'Edição disponível somente em Vendas ao responsável.'; end if;
if d.version is distinct from p_version then raise exception 'Conflito de edição. Reabra o card para atualizar.'; end if; old_data:=to_jsonb(d)||(select jsonb_build_object('answers',answers,'template_id',template_id) from kanban.demand_items where demand_id=d.id);
else if p_version is distinct from 0 then raise exception 'Orçamento não encontrado.'; end if; end if;
if not exists(select 1 from kanban.customers where id=(p_data->>'customer_id')::uuid) then raise exception 'Selecione um cliente.'; end if;
select t.id into tid from kanban.interview_templates t join kanban.product_types p on p.id=t.product_id where p.id=p_data->>'product_id' and p.active order by t.version desc limit 1;
if tid is null then raise exception 'Tipo de produto indisponível.'; end if;
-- Fixar a versão da entrevista existente quando o produto não mudou.
if d.id is not null then select i.template_id into tid from kanban.demand_items i join kanban.interview_templates t on t.id=i.template_id where i.demand_id=d.id and t.product_id=p_data->>'product_id';
if tid is null then select id into tid from kanban.interview_templates where product_id=p_data->>'product_id' order by version desc limit 1; end if; end if;
if jsonb_typeof(coalesce(p_data->'answers','{}'))<>'object' or octet_length(p_data::text)>65536 then raise exception 'Dados técnicos inválidos ou muito extensos.'; end if;
if d.id is null then
insert into kanban.number_counters values(yr,1) on conflict(year) do update set last_value=kanban.number_counters.last_value+1 returning last_value into seq;
insert into kanban.demands(id,number,title,customer_id,seller_id,assignee_id,created_by) values(p_id,'ORC-'||yr||'-'||lpad(seq::text,greatest(6,length(seq::text)),'0'),trim(p_data->>'title'),(p_data->>'customer_id')::uuid,auth.uid(),auth.uid(),auth.uid()) returning * into d;
insert into kanban.stage_executions(demand_id,stage,assignee_id) values(d.id,'sales',auth.uid());
else update kanban.demands set version=version+1 where id=p_id; end if;
update kanban.demands set title=trim(p_data->>'title'),customer_id=(p_data->>'customer_id')::uuid,description=coalesce(p_data->>'description',''),notes=coalesce(p_data->>'notes',''),requested_date=nullif(p_data->>'requested_date','')::date,technical_complete=coalesce((p_data->>'technical_complete')::boolean,false),updated_at=now() where id=p_id returning * into d;
insert into kanban.demand_items(demand_id,template_id,answers) values(d.id,tid,coalesce(p_data->'answers','{}')) on conflict(demand_id) do update set template_id=excluded.template_id,answers=excluded.answers;
insert into kanban.audit_events(demand_id,actor_id,type,description,before_data,after_data) values(d.id,auth.uid(),case when old_data is null then 'created' else 'updated' end,case when old_data is null then 'Orçamento aberto' else 'Levantamento atualizado' end,old_data,to_jsonb(d)||jsonb_build_object('answers',p_data->'answers','template_id',tid)); return d.id;
end; $$;

create function public.kb_board(p_search text default '',p_stage text default null,p_cursor timestamptz default null,p_cursor_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$ begin
perform kanban.require_active();
return jsonb_build_object('cards',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (
select d.*,c.legal_name as customer,p.name as assignee,e.entered_at,e.started_at,kanban.missing(d.id) as missing
from kanban.demands d join kanban.customers c on c.id=d.customer_id join kanban.profiles p on p.id=d.assignee_id join kanban.stage_executions e on e.demand_id=d.id and e.completed_at is null
where kanban.can_read(d) and d.status='open' and (p_stage is null or d.stage=p_stage) and (d.title ilike '%'||left(p_search,100)||'%' or d.number ilike '%'||left(p_search,100)||'%' or c.legal_name ilike '%'||left(p_search,100)||'%')
and (p_cursor is null or (d.created_at,d.id)<(p_cursor,p_cursor_id)) order by d.created_at desc,d.id desc limit 31)x),
'counts',(select coalesce(jsonb_object_agg(stage,n),'{}') from (select d.stage,count(*) n from kanban.demands d join kanban.customers c on c.id=d.customer_id where kanban.can_read(d) and status='open' and (d.title ilike '%'||left(p_search,100)||'%' or d.number ilike '%'||left(p_search,100)||'%' or c.legal_name ilike '%'||left(p_search,100)||'%') group by stage)x)); end; $$;

create function public.kb_detail(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ declare d kanban.demands; begin
perform kanban.require_active(); select * into d from kanban.demands where id=p_id;
if not found or not kanban.can_read(d) then raise exception 'Orçamento indisponível.'; end if;
return to_jsonb(d)||jsonb_build_object('customer',(select legal_name from kanban.customers where id=d.customer_id),'item',(select to_jsonb(i)||jsonb_build_object('template',to_jsonb(t)) from kanban.demand_items i join kanban.interview_templates t on t.id=i.template_id where demand_id=p_id),'missing',kanban.missing(p_id),'can_edit',kanban.can_edit(d),'execution',(select to_jsonb(e) from kanban.stage_executions e where demand_id=p_id and completed_at is null)); end; $$;

create function public.kb_history(p_id uuid,p_before bigint default null) returns jsonb language plpgsql security definer set search_path='' as $$ begin
perform kanban.require_active(); if not exists(select 1 from kanban.demands d where id=p_id and kanban.can_read(d)) then raise exception 'Orçamento indisponível.'; end if;
return (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select a.id,a.type,a.description,a.created_at,p.name as actor,a.before_data,a.after_data from kanban.audit_events a join kanban.profiles p on p.id=a.actor_id where a.demand_id=p_id and (p_before is null or a.id<p_before) order by a.id desc limit 31)x); end; $$;

create function public.kb_start(p_id uuid,p_version int) returns void language plpgsql security definer set search_path='' as $$ declare d kanban.demands; begin
perform kanban.require_active(); select * into d from kanban.demands where id=p_id for update;
if not found or not kanban.can_edit(d) then raise exception 'Sem permissão para iniciar.'; end if;
if d.version is distinct from p_version then raise exception 'Conflito de edição. Atualize o card.'; end if;
update kanban.stage_executions set started_at=now() where demand_id=p_id and completed_at is null and started_at is null;
if found then update kanban.demands set version=version+1,updated_at=now() where id=p_id;
insert into kanban.audit_events(demand_id,actor_id,type,description) values(p_id,auth.uid(),'started','Atividade iniciada em '||d.stage); end if; end; $$;

create function public.kb_transition(p_id uuid,p_version int,p_target text,p_assignee uuid,p_reason text,p_request uuid) returns int language plpgsql security definer set search_path='' as $$
declare d kanban.demands; r kanban.transition_requests; v int; missing jsonb; begin
perform kanban.require_active(); select * into d from kanban.demands where id=p_id for update;
if not found or not kanban.can_read(d) then raise exception 'Orçamento indisponível.'; end if;
select * into r from kanban.transition_requests where id=p_request;
if found then if r.demand_id<>p_id or r.actor_id<>auth.uid() or r.target<>p_target then raise exception 'Operação inválida.'; end if; return r.result_version; end if;
if not kanban.can_edit(d) then raise exception 'Sem permissão para movimentar.'; end if;
if d.version is distinct from p_version then raise exception 'Conflito de edição. Atualize o card.'; end if;
if not ((d.stage='sales' and p_target='design') or (d.stage='design' and p_target='sales')) then raise exception 'Transição não disponível nesta fase. Os módulos seguintes permanecem bloqueados.'; end if;
if length(trim(coalesce(p_reason,'')))<5 then raise exception 'Informe a justificativa da movimentação.'; end if;
if not exists(select 1 from kanban.profiles p join kanban.user_roles ur on ur.user_id=p.id where p.id=p_assignee and p.active and ur.role in ('admin','manager',(select role from kanban.workflow_stages where code=p_target))) then raise exception 'Responsável não habilitado para a etapa.'; end if;
if d.stage='sales' then missing:=kanban.missing(d.id); if jsonb_array_length(missing)>0 then raise exception 'Pendências: %',missing; end if; end if;
if not exists(select 1 from kanban.stage_executions where demand_id=p_id and completed_at is null and started_at is not null) then raise exception 'Inicie a atividade antes de concluir.'; end if;
update kanban.stage_executions set completed_at=now() where demand_id=p_id and completed_at is null;
insert into kanban.stage_executions(demand_id,stage,assignee_id) values(p_id,p_target,p_assignee);
update kanban.demands set stage=p_target,assignee_id=p_assignee,version=version+1,technical_complete=case when p_target='sales' then false else technical_complete end,updated_at=now() where id=p_id returning version into v;
insert into kanban.audit_events(demand_id,actor_id,type,description,before_data,after_data) values(p_id,auth.uid(),'transition',p_reason,jsonb_build_object('stage',d.stage,'assignee_id',d.assignee_id),jsonb_build_object('stage',p_target,'assignee_id',p_assignee));
insert into kanban.transition_requests values(p_request,p_id,auth.uid(),p_target,v); return v; end; $$;

create function public.kb_assign(p_id uuid,p_version int,p_assignee uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$ declare d kanban.demands; eid uuid; begin
perform kanban.require_active(); if not kanban.has_role(array['admin','manager']) then raise exception 'Apenas gestão pode transferir responsabilidades.'; end if;
select * into d from kanban.demands where id=p_id for update; if not found or d.version is distinct from p_version then raise exception 'Conflito de edição. Atualize o card.'; end if;
if length(trim(coalesce(p_reason,'')))<5 then raise exception 'Informe a justificativa.'; end if;
if not exists(select 1 from kanban.profiles p join kanban.user_roles r on r.user_id=p.id where p.id=p_assignee and p.active and r.role in ('admin','manager',(select role from kanban.workflow_stages where code=d.stage))) then raise exception 'Responsável não habilitado.'; end if;
update kanban.stage_executions set assignee_id=p_assignee where demand_id=p_id and completed_at is null returning id into eid;
insert into kanban.stage_assignments(execution_id,assignee_id,actor_id,reason) values(eid,p_assignee,auth.uid(),p_reason);
update kanban.demands set assignee_id=p_assignee,version=version+1,updated_at=now() where id=p_id;
insert into kanban.audit_events(demand_id,actor_id,type,description,before_data,after_data) values(p_id,auth.uid(),'assigned',p_reason,jsonb_build_object('assignee_id',d.assignee_id),jsonb_build_object('assignee_id',p_assignee)); end; $$;

create function public.kb_users() returns jsonb language plpgsql security definer set search_path='' as $$ begin
perform kanban.require_active(); if not kanban.has_role(array['admin']) then raise exception 'Acesso administrativo necessário.'; end if;
return(select coalesce(jsonb_agg(to_jsonb(p)||jsonb_build_object('roles',(select coalesce(jsonb_agg(role),'[]') from kanban.user_roles where user_id=p.id)) order by name),'[]') from kanban.profiles p); end; $$;
create function public.kb_set_user(p_id uuid,p_active boolean,p_roles text[]) returns void language plpgsql security definer set search_path='' as $$ declare old_data jsonb; begin
perform kanban.require_active(); if not kanban.has_role(array['admin']) then raise exception 'Acesso administrativo necessário.'; end if;
-- Serializa alterações para preservar ao menos um administrador ativo.
perform pg_advisory_xact_lock(918426);
perform kanban.require_active(); if not kanban.has_role(array['admin']) then raise exception 'Acesso administrativo necessário.'; end if;
if p_id=auth.uid() then raise exception 'Seu próprio acesso deve ser alterado por outro administrador.'; end if;
if not exists(select 1 from kanban.profiles where id=p_id) or p_active is null or p_roles is null or cardinality(p_roles)=0 or exists(select 1 from unnest(p_roles) r where r is null or not exists(select 1 from kanban.roles where code=r)) then raise exception 'Usuário ou perfis inválidos.'; end if;
select to_jsonb(p) into old_data from kanban.profiles p where id=p_id;
update kanban.profiles set active=p_active where id=p_id;
delete from kanban.user_roles where user_id=p_id;
insert into kanban.user_roles select p_id,r from(select distinct unnest(p_roles) r)x;
insert into kanban.audit_events(actor_id,type,description,before_data,after_data) values(auth.uid(),'user_access','Permissões do colaborador alteradas',old_data,jsonb_build_object('id',p_id,'active',p_active,'roles',p_roles)); end; $$;
create function public.kb_set_product(p_id text,p_name text,p_active boolean) returns void language plpgsql security definer set search_path='' as $$ begin
perform kanban.require_active(); if not kanban.has_role(array['admin','manager']) then raise exception 'Acesso de gestão necessário.'; end if;
if length(trim(p_name))<3 or p_active is null then raise exception 'Nome ou situação inválida.'; end if;
update kanban.product_types set name=trim(p_name),active=p_active where id=p_id; if not found then raise exception 'Produto indisponível.'; end if;
insert into kanban.audit_events(actor_id,type,description,after_data) values(auth.uid(),'product_updated','Catálogo atualizado',jsonb_build_object('id',p_id,'name',p_name,'active',p_active)); end; $$;

-- Funções internas não são executáveis diretamente pelo cliente.
revoke all on all functions in schema kanban from public,anon,authenticated;
grant execute on function kanban.has_role(text[]),kanban.can_read(kanban.demands) to authenticated;
do $$ declare r record; begin for r in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on p.pronamespace=n.oid where n.nspname='public' and p.proname like 'kb\_%' escape '\' loop execute format('revoke all on function %s from public,anon',r.signature); execute format('grant execute on function %s to authenticated',r.signature); end loop; end $$;
notify pgrst,'reload schema';


insert into kanban.product_types(id,name) values('tubular','Tubular');
insert into kanban.interview_templates(product_id,version,fields) values('tubular',1,'[{"key":"voltage","label":"Tensão","type":"number","unit":"V","min":0.01},{"key":"power","label":"Potência","type":"number","unit":"W","min":0.01},{"key":"current","label":"Corrente informada","type":"number","unit":"A","min":0.01},{"key":"quantity","label":"Quantidade","type":"number","unit":"un.","min":1},{"key":"medium","label":"Meio de aplicação","type":"select","options":["Ar","Líquido","Seco"]},{"key":"cold","label":"Zona fria total","type":"number","unit":"mm","min":0},{"key":"application","label":"Aplicação","type":"text"},{"key":"material","label":"Material especificado","type":"text"}]'::jsonb);
insert into kanban.product_types(id,name) values('cartucho','Cartucho reto / bipartido');
insert into kanban.interview_templates(product_id,version,fields) values('cartucho',1,'[{"key":"voltage","label":"Tensão","type":"number","unit":"V","min":0.01},{"key":"power","label":"Potência","type":"number","unit":"W","min":0.01},{"key":"current","label":"Corrente informada","type":"number","unit":"A","min":0.01},{"key":"quantity","label":"Quantidade","type":"number","unit":"un.","min":1},{"key":"subtype","label":"Formato","type":"select","options":["Reto","Bipartido"]},{"key":"cold","label":"Zona fria total","type":"number","unit":"mm","min":0},{"key":"application","label":"Aplicação","type":"text"},{"key":"leadType","label":"Tipo de saída do rabicho","type":"text"},{"key":"leadLength","label":"Comprimento do rabicho","type":"number","unit":"mm","min":0.01},{"key":"length","label":"Comprimento total","type":"number","unit":"mm","min":0.01},{"key":"diameter","label":"Diâmetro","type":"number","unit":"mm","min":0.01}]'::jsonb);
insert into kanban.product_types(id,name) values('cartucho_l','Cartucho em L');
insert into kanban.interview_templates(product_id,version,fields) values('cartucho_l',1,'[{"key":"voltage","label":"Tensão","type":"number","unit":"V","min":0.01},{"key":"power","label":"Potência","type":"number","unit":"W","min":0.01},{"key":"current","label":"Corrente informada","type":"number","unit":"A","min":0.01},{"key":"quantity","label":"Quantidade","type":"number","unit":"un.","min":1},{"key":"cold","label":"Zona fria total","type":"number","unit":"mm","min":0},{"key":"application","label":"Aplicação","type":"text"},{"key":"leadType","label":"Tipo de saída do rabicho","type":"text"},{"key":"leadLength","label":"Comprimento do rabicho","type":"number","unit":"mm","min":0.01},{"key":"hotLength","label":"Comprimento da zona quente","type":"number","unit":"mm","min":0.01},{"key":"outletLength","label":"Comprimento da saída em L","type":"number","unit":"mm","min":0.01},{"key":"diameter","label":"Diâmetro","type":"number","unit":"mm","min":0.01}]'::jsonb);
insert into kanban.product_types(id,name) values('rosca','Rosca');
insert into kanban.interview_templates(product_id,version,fields) values('rosca',1,'[{"key":"voltage","label":"Tensão","type":"number","unit":"V","min":0.01},{"key":"power","label":"Potência","type":"number","unit":"W","min":0.01},{"key":"current","label":"Corrente informada","type":"number","unit":"A","min":0.01},{"key":"quantity","label":"Quantidade","type":"number","unit":"un.","min":1},{"key":"threadSize","label":"Medida da rosca","type":"text"},{"key":"threadType","label":"Padrão da rosca","type":"text"},{"key":"cold","label":"Zona fria total","type":"number","unit":"mm","min":0},{"key":"application","label":"Aplicação","type":"text"},{"key":"material","label":"Material especificado","type":"text"},{"key":"elements","label":"Número de elementos","type":"number","unit":"un.","min":1},{"key":"length","label":"Comprimento total","type":"number","unit":"mm","min":0.01},{"key":"diameter","label":"Diâmetro","type":"number","unit":"mm","min":0.01}]'::jsonb);
insert into kanban.product_types(id,name) values('aletada','Aletada');
insert into kanban.interview_templates(product_id,version,fields) values('aletada',1,'[{"key":"voltage","label":"Tensão","type":"number","unit":"V","min":0.01},{"key":"power","label":"Potência","type":"number","unit":"W","min":0.01},{"key":"current","label":"Corrente informada","type":"number","unit":"A","min":0.01},{"key":"quantity","label":"Quantidade","type":"number","unit":"un.","min":1},{"key":"cold","label":"Zona fria total","type":"number","unit":"mm","min":0},{"key":"application","label":"Aplicação","type":"text"},{"key":"material","label":"Material","type":"select","options":["Inox 304","Inox 316","Galvanizado","Outro"]},{"key":"materialOther","label":"Especificar material","type":"text","when":["material","Outro"]}]'::jsonb);
insert into kanban.product_types(id,name) values('bainha','Bainha');
insert into kanban.interview_templates(product_id,version,fields) values('bainha',1,'[{"key":"voltage","label":"Tensão","type":"number","unit":"V","min":0.01},{"key":"power","label":"Potência","type":"number","unit":"W","min":0.01},{"key":"current","label":"Corrente informada","type":"number","unit":"A","min":0.01},{"key":"quantity","label":"Quantidade","type":"number","unit":"un.","min":1},{"key":"material","label":"Material","type":"select","options":["Inox","Cerâmica","Mica"]},{"key":"dimensions","label":"Dimensões completas (mm)","type":"text"},{"key":"connection","label":"Tipo de ligação","type":"select","options":["Parafuso","Rabicho na espessura"]},{"key":"leadLength","label":"Comprimento do rabicho","type":"number","unit":"mm","min":0.01,"when":["connection","Rabicho na espessura"]}]'::jsonb);
insert into kanban.product_types(id,name) values('sobrebordas','Sobrebordas');
insert into kanban.interview_templates(product_id,version,fields) values('sobrebordas',1,'[{"key":"voltage","label":"Tensão","type":"number","unit":"V","min":0.01},{"key":"power","label":"Potência","type":"number","unit":"W","min":0.01},{"key":"current","label":"Corrente informada","type":"number","unit":"A","min":0.01},{"key":"quantity","label":"Quantidade","type":"number","unit":"un.","min":1},{"key":"material","label":"Material especificado","type":"text"},{"key":"cold","label":"Zona fria total","type":"number","unit":"mm","min":0},{"key":"dimensions","label":"Dimensões completas (mm)","type":"text"},{"key":"connection","label":"Tipo de ligação","type":"text"}]'::jsonb);
insert into kanban.product_types(id,name) values('coleira','Coleira');
insert into kanban.interview_templates(product_id,version,fields) values('coleira',1,'[{"key":"voltage","label":"Tensão","type":"number","unit":"V","min":0.01},{"key":"power","label":"Potência","type":"number","unit":"W","min":0.01},{"key":"current","label":"Corrente informada","type":"number","unit":"A","min":0.01},{"key":"quantity","label":"Quantidade","type":"number","unit":"un.","min":1},{"key":"material","label":"Material","type":"select","options":["Cerâmica","Mica"]},{"key":"length","label":"Comprimento total","type":"number","unit":"mm","min":0.01},{"key":"diameter","label":"Diâmetro","type":"number","unit":"mm","min":0.01},{"key":"closure","label":"Fechamento","type":"select","options":["Bujão","Aba","Presilha","Cinta","Outro"]},{"key":"closureOther","label":"Especificar fechamento","type":"text","when":["closure","Outro"]},{"key":"outlet","label":"Tipo de saída","type":"text"}]'::jsonb);

-- Versão 2: levantamento livre e referência à entrevista no Drive.
-- Atualização aditiva para a Fase 1 existente. Não exclui clientes, demandas ou respostas.

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


-- Correção 2.1: conclusão de Projeto encaminha para Orçamento.
create or replace function public.kb_transition(p_id uuid,p_version int,p_target text,p_assignee uuid,p_reason text,p_request uuid) returns int language plpgsql security definer set search_path='' as $$
declare d kanban.demands; r kanban.transition_requests; v int; missing jsonb; begin
perform kanban.require_active(); select * into d from kanban.demands where id=p_id for update;
if not found or not kanban.can_read(d) then raise exception 'Orçamento indisponível.'; end if;
select * into r from kanban.transition_requests where id=p_request;
if found then if r.demand_id<>p_id or r.actor_id<>auth.uid() or r.target<>p_target then raise exception 'Operação inválida.'; end if; return r.result_version; end if;
if not kanban.can_edit(d) then raise exception 'Sem permissão para movimentar.'; end if;
if d.version is distinct from p_version then raise exception 'Conflito de edição. Atualize o card.'; end if;
if not ((d.stage='sales' and p_target='design') or (d.stage='design' and p_target in ('sales','quotation'))) then raise exception 'Transição não disponível nesta fase. Os módulos seguintes permanecem bloqueados.'; end if;
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
