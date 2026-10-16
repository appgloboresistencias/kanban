-- Executar SOMENTE no projeto Globo nwxjntiysbwqwwwpazrd.
-- Limpeza autorizada pelo usuário: clientes, cards, anexos dos cards e históricos de teste.
-- Preserva contas, perfis, permissões, etapas, configurações e biblioteca de entrevistas.
-- Antes: pelo Storage, exclua os objetos de TESTE do bucket globo-documentos.
-- Nunca apague linhas de storage.objects por SQL: isso não exclui os arquivos físicos.
begin;
lock table kanban.demands,kanban.documents,kanban.customers,kanban.stage_executions in access exclusive mode;
do $$ begin
 if exists(select 1 from storage.objects where bucket_id='globo-documentos') then
  raise exception 'Existem arquivos no bucket globo-documentos. Exclua os objetos de teste pelo painel Storage e execute novamente. Nenhum registro foi removido.';
 end if;
end $$;
-- Sem CASCADE: uma dependência desconhecida interrompe a limpeza inteira.
truncate kanban.document_migrations,kanban.documents,kanban.transition_requests,
 kanban.stage_assignments,kanban.audit_events,kanban.demand_items,kanban.stage_executions,
 kanban.demands,kanban.customer_contacts,kanban.customers;
update kanban.document_settings set used_bytes=kanban.storage_usage(),checked_at=now() where id;
-- Numeração não é reutilizada para evitar confusão com documentos já exportados.
commit;
select (select count(*) from kanban.demands) as cards,
 (select count(*) from kanban.customers) as clientes,
 (select count(*) from kanban.profiles where active) as usuarios_ativos,
 (select count(*) from kanban.interview_library where status='ready') as modelos_disponiveis;
