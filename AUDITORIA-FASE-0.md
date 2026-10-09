# Globo Resistências — auditoria e arquitetura 2.0

Data: 09/10/2026. Estado: proposta para aprovação; implementação não iniciada.

## 1. Diagnóstico e evidências

O repositório oficial `https://github.com/appgloboresistencias/kanban` foi clonado e está vazio: nenhum commit, arquivo, migration, stack ou pipeline para inspecionar. A API pública do GitHub confirmou `size: 0`, `private: false`, branch padrão `main` e `has_pages: false`. Não foram encontrados dados de aplicação nesse repositório. Isso não demonstra ausência de dados no Supabase.

A fonte anterior está disponível em `../vendas`; a cópia publicada está em `../globo-publicacao`. Stack: HTML, CSS e JavaScript modular, build Node sem dependências de produção. Hospedagem anterior: Sites, acesso privado, URL https://globo-resistencias-vendas.eng-denysmartinez.chatgpt.site. Não há evidência de hospedagem ligada ao novo repositório. O pipeline anterior verifica sintaxe, domínio, SQL gerado e build; não implanta banco ou funções.

O código aponta para o Supabase `nwxjntiysbwqwwwpazrd`. Schema local: `profiles`, `orders`, `order_events`, `technical_fields`; payload de pedido em JSONB, perfil único por usuário, RPC `save_order`, controle otimista por versão, RLS e auditoria por snapshots. As oito entrevistas estão representadas no domínio e no catálogo SQL.

O usuário informou instalação do SQL e criação do administrador. Nesta auditoria, quatro consultas sem sessão, com `limit=0`, retornaram HTTP 401. Isso NÃO confirma existência das tabelas, políticas corretas, quantidade de pedidos ou estado das migrations. A inspeção autenticada de produção continua pendente; não foram lidos registros privados nem capturadas credenciais. Até essa verificação, tratar o banco como contendo dados reais a preservar.

Não foram executadas migrations, alterações de produção, uploads Drive ou deploy. Só houve leitura, clone e documentação local. Os testes registrados da v1 incluem 11 testes de domínio, SQL/RLS em PGlite e interface demonstrativa. Não foram reexecutados nesta fase e não constituem testes da v2.

## 2. Reutilização e lacunas

| Componente | Decisão proposta |
|---|---|
| Identidade visual e responsividade | Reaproveitar estilos e padrões de interação |
| Oito entrevistas e completude condicional | Portar catálogo e testes; conferir novamente com PDFs e versionar modelos |
| Regras de aprovação e concorrência | Reutilizar conceitos e cenários; adaptar ao modelo relacional |
| Auth Supabase | Manter provedor; revisar fluxo de sessão, recuperação, convites e SMTP |
| Banco JSONB atual | Preservar legado; não estender como modelo principal da v2 |
| Perfis únicos | Substituir na v2 por associação N:N usuário/perfil |
| Listagem de pedidos | Substituir carregamento de todas as páginas por paginação real no servidor |
| Upload antigo | Reimplementar: usa Service Account, pesquisa pasta em upload, devolve link e não tem operação idempotente persistida |
| Demonstração em memória | Restrita a testes, nunca fallback silencioso de persistência |

O uploader anterior não atende à conta Gmail proposta. Service Accounts não possuem quota própria nem podem ser proprietárias de arquivos; o Google orienta Drive compartilhado ou OAuth em nome de usuário. [Documentação Google](https://developers.google.com/workspace/drive/api/guides/about-shareddrives).

## 3. Arquitetura proposta

Frontend estático com TypeScript, React e Vite, organizado por módulos comercial, operação, documentos e administração. A complexidade de nove etapas justifica componentes tipados; não é necessário SSR. Reutilizar regras puras e aparência da v1, evitando copiar o monólito de interface.

Supabase Auth para contas individuais. PostgreSQL para dados, RLS e funções transacionais. Leitura de cards, documentos e indicadores exclusivamente no banco. Escritas críticas por RPC; não permitir atualização direta da etapa. Backend documental em Supabase Edge Functions inicialmente, com adaptador Drive isolado e limites conservadores de transferência. Contratos HTTP e SQL portáveis reduzem dependência de fornecedor.

Hospedagem proposta: Cloudflare Pages Free para frontend estático, associada ao GitHub, subdomínio gratuito. Não migrar a publicação anterior nesta fase. A oferta contempla uso empresarial, sem restrição identificada de uso exclusivamente pessoal nas páginas consultadas; revisar os termos aplicáveis à conta antes da ativação. [Produto](https://www.cloudflare.com/developer-platform/products/pages/) e [preços](https://developers.cloudflare.com/pages/functions/pricing/). GitHub fica como fonte e CI, não como hospedagem comercial.

## 4. OAuth e viabilidade do Drive

Viável para volume inicial moderado, condicionado ao espaço disponível, limites de transferência do backend e backup externo. Todos os arquivos novos serão criados em nome de `appgloboresistencias@gmail.com`; colaboradores usam suas próprias contas Supabase.

Criar projeto Google Cloud, habilitar Drive API, configurar consentimento External e cliente OAuth Web com callback HTTPS exato. Usar Authorization Code, `state` de uso único, PKCE quando suportado e acesso offline. A conexão é ação de administrador, com consentimento explícito do proprietário; conferir a identidade da conta conectada. Não solicitar a senha Google.

Priorizar `drive.file`, escopo não sensível recomendado pelo Google: acesso a arquivos criados ou explicitamente selecionados para o aplicativo. Arquivos preexistentes precisam de seleção autorizada via Picker ou importação; selecionar uma pasta não deve ser presumido como concessão irrestrita sobre toda a árvore. Não pedir `drive` amplo por conveniência. [Escopos](https://developers.google.com/workspace/drive/api/guides/api-specific-auth).

Em modo Testing, refresh tokens para esse acesso expiram em sete dias. Produção remove essa condição específica, mas não torna tokens eternos: revogação, inatividade e limites continuam possíveis. Avaliar verificação de marca e consentimento conforme configuração efetiva; não prometer isenção automática. [OAuth](https://developers.google.com/identity/protocols/oauth2).

Guardar client secret e chave de criptografia em segredos do backend. Refresh token criptografado em schema privado, sem grants para anon/authenticated, para permitir reconexão sem deploy. Access token apenas em cache temporário no servidor. Não registrar tokens, URLs de sessões retomáveis ou cabeçalhos de autorização. Reconexão substitui credencial, preserva IDs e valida que o proprietário continua correto. `invalid_grant` suspende operações de arquivo e gera alerta; Kanban continua operando. [Fluxo Web](https://developers.google.com/identity/protocols/oauth2/web-server).

## 5. Organização e serviço documental

Raiz `GLOBO_RESISTENCIAS_SISTEMA`, com `00_MODELOS_ENTREVISTAS`, `01_ORCAMENTOS/ORC-AAAA-NNNNNN/<ETAPA>` e `02_DOCUMENTOS_GERAIS`. Criar subpastas sob demanda. IDs persistidos são a referência, não os nomes.

Contrato `DocumentStorage`: criar pasta, upload, metadados, conteúdo/download, nova versão, status, arquivamento lógico, integridade e reconciliação. Componentes não chamam Google diretamente. Documentos comerciais e técnicos têm permissões distintas.

Listar anexos consulta Supabase. Abrir/download exige sessão, perfil ativo, acesso ao card, tipo documental, versão e vínculo; o backend resolve o ID, não aceita um ID arbitrário enviado pelo navegador. Conteúdo servido sem cache público, com `nosniff`; HTML/SVG executáveis não renderizados. PDFs/imagens em visualização isolada; CAD por download. Remover acesso público e não depender de links permanentes.

Upload: intenção PENDENTE no banco com UUID idempotente; autorização; reserva única de pasta; envio; persistência de ID e metadados; confirmação. Restrição UNIQUE por chave de operação e lock/lease para concorrência. Associar operação ao arquivo por `appProperties`, persistindo ID pré-gerado quando suportado. Em resposta ambígua, reconciliar por ID/operação antes de reenviar. Nunca manter transação SQL aberta durante chamada Google. Compensação é arquivamento controlado, não exclusão automática indiscriminada.

Novas versões terão arquivos próprios e vínculos imutáveis; uma versão vigente por documento. Não depender só da retenção de revisões nativa do Drive. Metadados incluem todos os campos da especificação: card, execução, classificação, IDs, nomes, MIME, bytes, hash, usuário, timestamps, versão, obrigatoriedade, vigência, upload e integridade.

Limites iniciais propostos: 10 MB por arquivo, dois uploads simultâneos por usuário, formatos PDF/JPEG/PNG/WebP/DXF/DWG. Validar conteúdo e não só extensão; arquivos CAD não executados. Não prometer antivírus com serviço não contratado. Para arquivos maiores, somente liberar após testar streaming/retomada pelo backend, mantendo URI de sessão protegida. Downloads repetidos podem consumir mais quota que armazenamento.

## 6. Cache, consumo e recuperação

Cache por versão para produtos/modelos; IDs de pastas persistentes; consultas de metadados paginadas. Nenhum `files.list` ao abrir, filtrar ou movimentar card. Reconciliação administrativa limitada a operações pendentes/IDs conhecidos. Sem varredura frequente de pastas ou polling constante.

Retry de 429 e 403 de quota com jitter, backoff e máximo inicial de quatro tentativas; 403 de permissão não tratado como quota. Falhas definitivas geram ação de reconexão/correção. Dashboard de documentos agregado do banco; uso da conta Google pode ser consultado administrativamente e armazenado com data da medição, sem consulta a cada abertura.

## 7. Modelo relacional

UUIDs e FKs; `timestamptz`; apresentação America/Sao_Paulo. JSONB apenas para respostas variáveis de entrevistas, detalhes extensíveis e diffs de auditoria.

| Grupo | Entidades e relações |
|---|---|
| Identidade | profiles → auth.users; roles ↔ user_roles; permissões por ação e setor |
| Cadastros | customers → customer_contacts; product_types → interview_templates versionados |
| Fluxo | demands → demand_items; workflow_stages; stage_executions N por demanda; stage_assignments; workflow_transitions |
| Comercial | demands → quotations → quotation_revisions; customer_approvals e internal_approvals vinculadas à revisão |
| Operação | production_orders N por demanda; material_separations → material_pending_items; production_executions; quality_inspections; rework_cycles; deliveries |
| Arquivos | document_folders; documents → document_versions; document_operations; storage_integrity_checks |
| Gestão | issues; notifications; audit_events append-only; system_settings; contadores anuais; conexão OAuth privada |

Demanda é o card único, com etapa atual, execução atual e versão de concorrência. Separar estado final recusado/concluído da etapa operacional. Numeração anual por contador atualizado atomicamente, com UNIQUE(ano,sequencial), sem `MAX+1`; admitir lacunas. OP é número emitido pelo ERP, com unicidade contextual ao ERP/empresa. Documento CPF/CNPJ normalizado, validado e único quando informado; não deduplicar só por razão social. Preservar snapshots comerciais relevantes sem alterar histórico quando o cliente muda.

Índices em número, cliente, responsável, etapa/estado, prazo, criação; compostos por card e data/ID para histórico e documentos. Índice parcial de pendências abertas. Paginação por cursor; filtros no servidor; resumo por coluna sem carregar todas as demandas. Indicadores agregados via funções com autorização.

## 8. Matriz de permissões proposta

| Perfil | Escrita permitida | Limite |
|---|---|---|
| Administrador | Usuários, perfis, configuração e ações operacionais autorizadas | Não reescreve auditoria |
| Gestor | Transferência, reabertura, exceções e visão gerencial | Motivo obrigatório; sem acesso a tokens |
| Vendas | Clientes, demandas próprias/atribuídas, comunicação e aprovação interna | Não aprova inspeção nem se concede perfis |
| Projeto | Análises técnicas e registro de OP | Cards atribuídos/visibilidade do setor |
| Orçamentista | Propostas e revisões | Não substitui aprovação do cliente |
| Almoxarifado | Separação e regularização de materiais | Pode resolver pendência mesmo em produção |
| Produção | Execução, problemas e retrabalho | Não encerra inspeção de qualidade |
| Qualidade | Inspeção, reprovação e encaminhamento de retrabalho | Não altera resultado anterior |
| Entrega | Preparação, comprovação e conclusão da entrega | Exige qualidade aprovada e ausência de bloqueios |

Múltiplos perfis somam ações permitidas, sem eliminar escopo por card. Operação recebe dados técnicos necessários; preço/margem e documentos comerciais restritos ao comercial/gestão. RLS não protege colunas sozinha: separar tabelas/views e grants para informação comercial. Usuário inativo perde leitura e escrita. Atribuição não concede automaticamente privilégios administrativos. Documentos herdam card e classificação, com checagem em toda requisição.

## 9. Transições e conflitos

| Origem → destino | Condições principais |
|---|---|
| Vendas → Projeto | Cliente, demanda, responsável, produto, campos técnicos e levantamento confirmado |
| Projeto → Orçamento | Análise aprovada, responsável e conclusão; falta de informação retorna a Vendas com motivo |
| Orçamento → Aprovação | Revisão concluída, validade, data/confirmacão de envio e documentos configurados |
| Aprovação → Gerar OP | Aprovação do cliente + ação interna explícita na mesma revisão + prazo acordado |
| Aprovação → Recusados | Motivo/data; reabertura somente autorizada |
| Aprovação → Projeto/Orçamento | Modificações justificadas, nova revisão e invalidação das aprovações afetadas |
| Gerar OP → Almoxarifado | OP ERP, emissão, conferência e lista de materiais conforme regra |
| Almoxarifado → Produção | Material completo ou autorização competente de parcial, faltantes e previsão |
| Produção → Qualidade | Execução concluída, problemas bloqueantes resolvidos ou exceção formal |
| Qualidade → Produção | Reprovação fundamentada, responsável e novo ciclo de retrabalho |
| Qualidade → Entrega | Inspeção aprovada e bloqueios resolvidos |
| Entrega → Concluído | Entrega efetiva confirmada, comprovantes exigidos e pendências impeditivas encerradas |

Pendência de material continua ativa fora do almoxarifado. Não encerrar pedido com material pendente por padrão. Reprovação sem retrabalho fica bloqueada para decisão do gestor; não avançar silenciosamente. Entrega com pendência não significa concluído.

RPC transacional bloqueia a demanda, confere versão esperada, perfil, atribuição, origem/destino, campos, documentos CONFIRMADOS e pendências; conclui execução, cria próxima, grava evento e atualiza card atomicamente. Chamadas repetidas usam chave idempotente. Retorno cria execução nova; início efetivo separado da entrada. Datas manuais exigem motivo e auditoria; tempos negativos proibidos. Alteração técnica/comercial após aprovação invalida a revisão aplicável, inclusive antes de liberar OP.

## 10. Indicadores e alertas

Conversão: aprovados/(aprovados+recusados), por decisões no período; reabertura exige regra de decisão vigente para não duplicar. Tempo de aprovação: primeira decisão aprovada menos envio da revisão aprovada. Entregas no prazo: entregas concluídas até prazo acordado / entregas concluídas com prazo, excluindo cancelados; sem prazo mostrado separadamente. Etapa: espera=início−entrada, execução=conclusão−início, total=conclusão−entrada, por execução; ciclos de retrabalho identificados separadamente. Lead time: conclusão−abertura de demandas concluídas. Sem dados significa “sem base”, não zero artificial.

Alertas calculados de prazos, pendências e ocorrências persistentes. Limiares de prazo próximo e etapa parada por configuração; prazo original e renegociações preservados. Filtros por período, cliente, responsável, produto e setor aplicados no banco. Definições detalhadas e conjuntos de dados conhecidos serão testados na fase 5.

## 11. Custos e limites consultados

| Serviço | Limite de referência | Risco/ação |
|---|---|---|
| Supabase Free | Banco 500 MB, egress 5 GB, 50 mil usuários ativos/mês, 500 mil invocações Edge/mês | Auditoria e downloads podem esgotar antes dos usuários; verificar plano real |
| Cloudflare Pages Free | Arquivos estáticos com requisições gratuitas ilimitadas; builds limitados | Usar frontend estático; não habilitar plano pago |
| Google pessoal | Até 15 GB compartilhados com Gmail e Photos | Medir espaço real e reservar margem; não assumir 15 GB livres |
| Drive API | Uso padrão sem custo adicional; cotas variam por projeto e regras de 2026 | Confirmar quotas no Cloud; não vincular faturamento ou pedir aumento automaticamente |
| E-mail de autenticação | SMTP padrão Supabase não é serviço produtivo para colaboradores | Configurar SMTP apropriado antes dos convites; quota e domínio dependem do provedor escolhido |
| Backup | Exportação para equipamento/mídia externa existente | Exige espaço, rotina e responsável; não é armazenamento ilimitado gratuito |

Fontes: [Supabase billing](https://supabase.com/docs/guides/platform/billing-on-supabase), [Pages](https://developers.cloudflare.com/pages/functions/pricing/), [Google storage](https://support.google.com/drive/answer/9312312?hl=en-GB), [Drive limits](https://developers.google.com/workspace/drive/api/guides/limits), [SMTP](https://supabase.com/docs/guides/auth/auth-smtp).

A documentação Drive consultada anuncia possível cobrança por excedentes mais adiante em 2026; não assumir gratuidade ilimitada. Plano gratuito Supabase pode pausar por baixa atividade em sete dias; não criar tráfego artificial para contornar a regra. [Pausa](https://supabase.com/docs/guides/platform/free-project-pausing).

Proposta de controle: alertas em 70/85/95% dos limites configurados; reserva atômica de capacidade para uploads, teto diário conservador e interrupção de novas transferências antes do teto. Orçamento financeiro zero: nenhuma ativação paga, cartão ou upgrade automático. Alertas não substituem limites do provedor. Metadados estimam arquivos do sistema, não consumo total de Gmail, chamadas externas ou faturamento; exibir data e cobertura da estimativa. Viabilidade definitiva depende de volume informado e planos reais, ainda não inspecionados.

## 12. Migração e continuidade

Inventariar produção com acesso autenticado e exportar esquema/dados antes de qualquer migration. Proposta: desenvolver em PostgreSQL local e ambiente de teste separado quando disponível; manter v1 intacta. Novo schema versionado e migração aditiva, sem substituir `profiles` ou trigger existente às cegas. Avaliar colisões de nomes e regras de autenticação antes de escolher schema exposto.

Importação por mapeamento `legacy_order_id` único, com simulação, contagens e reconciliação de valores. Não inventar ciclos históricos que a v1 não registrou: importar evento de origem e sinalizar histórico legado. Links Drive existentes não provam autorização OAuth; reconectar/importar explicitamente. Corte final com janela de escrita controlada e rollback definido; não manter dupla escrita sem coordenação.

Backup proposto: exportação lógica diária, cópia incremental externa de documentos e manifesto ID/hash/vínculo, criptografia e rotação fora da conta Google. Teste mensal de restauração em ambiente isolado. Metas para validação: perda máxima de 24h e recuperação em um dia útil. Disponibilidade do operador/equipamento é dependência. Não contar lixeira ou backup no mesmo Drive como proteção suficiente. [Backup Supabase Free](https://supabase.com/docs/guides/platform/backups).

## 13. Plano por fases e provas de aceite

| Fase | Entrega | Testes/critério para avançar |
|---|---|---|
| 0 | Esta auditoria, desenho e decisões | Confirmar inventário produtivo e aprovar arquitetura |
| 1 | Auth, perfis, clientes/produtos, demandas, Kanban e motor | Concorrência/numeração, RLS por perfil, campos, conflito, histórico; movimentos dependentes de módulos futuros ficam bloqueados |
| 2 | OAuth, adaptador, upload/download e recuperação | Cenários documentais 5–15, 37–39; falha entre provedores, acesso negado, zero consultas Drive na navegação |
| 3 | Vendas, projeto, propostas e aprovações | Retorno, versões, recusa/reabertura, dupla aprovação e invalidação |
| 4 | OP, materiais, produção, qualidade e entrega | Parcial em produção, problemas, múltiplos retrabalhos, nova inspeção e conclusão explícita |
| 5 | Indicadores, limites, backup e implantação | Matriz integral dos 40 cenários; restauração real, desempenho e homologação |

Cada fase terá changelog de arquivos, migrations, configuração, testes efetivamente executados, limitações, pendências e instruções de implantação. Integrações com Drive usarão pasta de teste autorizada; falhas simuladas localmente quando possível. A existência de código não contará como aceite.

## 14. Dependências externas e configuração

Necessários: acesso de escrita ao GitHub oficial; acesso administrativo Supabase para inspeção e implantação autorizada; projeto Google Cloud e consentimento do proprietário; conta de hospedagem; SMTP; destino externo de backup; PDFs/modelos aprovados; lista de colaboradores e atribuições.

Configuração pública: URL/chave publicável Supabase, URL do frontend, callback OAuth e fuso. Segredos exclusivamente no backend/gerenciador: chave administrativa Supabase quando indispensável, client secret Google, refresh token protegido, chave de criptografia e credenciais SMTP/deploy. Nunca solicitar segredos colados no chat ou armazená-los no GitHub. O repositório atualmente público exige atenção especial a dados de teste e documentos empresariais.

## 15. Decisões para validação

1. Aprovar frontend estático, Supabase e OAuth Drive; Cloudflare Pages como hospedagem proposta, sem substituir v1 até homologação.
2. Confirmar existência de pedidos reais e se o Supabase atual será o destino da v2 após migração aditiva.
3. Definir quem pode autorizar produção parcial, reabrir recusados e aceitar exceções bloqueantes; proposta: gestor/admin com justificativa.
4. Confirmar segregação de valores comerciais e visibilidade entre vendedores; proposta: vendedor vê próprios/atribuídos, gestão vê todos.
5. Informar volume aproximado de usuários, orçamentos/mês e MB por orçamento, para dimensionar custo zero.
6. Validar documentos obrigatórios por etapa, limites de arquivo, necessidade de entregas parciais e tratamento de reprovação sem retrabalho.
7. Escolher SMTP e responsável/destino de backup antes do uso produtivo por colaboradores.

A aprovação pedida decorre da seção 33 da especificação do usuário: “Primeiro realizar a auditoria e apresentar a arquitetura fundamentada. Após aprovação, implementar por fases.” A Fase 0 tem pendência explícita de inspeção autenticada do banco; não deve ser apresentada como auditoria completa de produção.
