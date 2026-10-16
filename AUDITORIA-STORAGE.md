# Auditoria — Storage temporário (16/10/2026)

- Repositório local: versão 2.3, commit base `43edbad`, árvore limpa antes da implementação. Fluxo completo e suas permissões já implementados; reaproveitados.
- GitHub público `appgloboresistencias/kanban`: `package.json` retornou versão `2.0.0-phase1`. Portanto o remoto está atrasado em relação ao código local e à publicação manual. Não foi feito push nem reset do histórico.
- Cloudflare `royal-tree-dc12.appgloboresistencias.workers.dev`: HTML aponta `index-CxBIRqby.js` e `index-88x6Gdlr.css`, os mesmos nomes de artefatos da versão 2.3 entregue. Isso confirma os artefatos anunciados pelo site; não é teste autenticado de produção.
- Supabase esperado: `nwxjntiysbwqwwwpazrd`. O conector disponível lista somente outro projeto, `apontamento-producao`. Consultas de migrations, tabelas e advisors no projeto Globo foram negadas por falta de permissão. Nenhuma alteração foi feita no outro projeto.
- Não foi possível certificar migrations realmente executadas, políticas remotas, capacidade contratada, usuários ou conteúdos do bucket. O usuário indicou que reconectaria a conta; a conexão correta continuava indisponível durante esta implementação.
- Auditoria complementar pronta em `supabase/storage-preflight.sql`, somente leitura. Antes da homologação conectada, conferir os resultados contra a versão 2.3.

## Estrutura reutilizada

`kanban.documents` já tem id, demand_id, execution_id, kind, name, provider_id, confirmed e created_at; não havia interface funcional de anexos. As políticas existentes eram de leitura por card/tipo. A nova migration acrescenta metadados e atualiza a política de leitura para os usuários autorizados ao card. Preserva as colunas e linhas existentes, marcadas como referências legadas, sem presumir que provider_id já seja um ID Google válido.

O levantamento livre exigia referência de PDF no Drive. Agora aceita também documento PDF de categoria Entrevista, com upload confirmado. As demais etapas conservam as validações já implementadas e suas referências manuais. Não foram acrescentados questionários técnicos nem cadastros de resistência.

## Documentação consultada

- [Changelog Supabase](https://supabase.com/changelog): verificado em 16/10/2026; alteração de TLS de novembro não exige mudança no navegador moderno utilizado.
- [Storage RLS](https://supabase.com/docs/guides/storage/security/access-control): políticas ligadas às permissões do card, sem bucket público nem upsert.
- [Schema do Storage](https://supabase.com/docs/guides/storage/schema/design): objetos são consultados para confirmação/consumo; não são inseridos ou apagados por SQL em produção. A API Storage faz o upload.
- [Implementação oficial do uploader](https://github.com/supabase/storage/blob/master/src/storage/uploader.ts): pré-autorização usa mimetype e contentLength; confirmação usa metadados do objeto. O cliente envia corpo binário, sem overhead de multipart, e as políticas aceitam size/contentLength.
- [IDs reservados do Google](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/generateIds): usados pelo worker futuro para retomar cópias sem duplicar.

## Segurança revisada

Bucket privado; caminhos gerados pelo servidor e associados a reservas; autorização ativa por card e etapa; INSERT apenas para o responsável autorizado; leitura de arquivos ativos/arquivados vinculada ao card; UPDATE/DELETE físicos negados a usuários. Políticas restritivas protegem o bucket mesmo se outros módulos tiverem políticas permissivas amplas.

RPCs mutáveis usam a arquitetura existente de funções com autorização explícita, search_path vazio e EXECUTE revogado de PUBLIC/anon. Worker de migração é exclusivo do service_role no backend. Tokens Google não são incluídos no frontend. SHA-256 confere bytes transferidos; não substitui antivírus nem análise do conteúdo dos documentos.

Advisors remotos não puderam ser executados sem acesso ao projeto correto. Testes locais não substituem homologação da API Storage e RLS no Supabase real.
