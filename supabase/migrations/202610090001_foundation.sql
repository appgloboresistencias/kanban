-- Fase 1. Schema independente; não modifica public.profiles/orders da versão 1.
begin;
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
commit;
