# Entrega da Fase 1 — Fundação

Data: 09/10/2026. Código implementado e validado localmente. Homologação no Supabase real e implantação externa pendentes.

## Funcionalidades implementadas

- Login individual Supabase, sessão por aba, renovação de sessão, logout e solicitação de recuperação de senha.
- Perfis múltiplos e ativação administrativa; bloqueio de usuário inativo e de autopromoção.
- Cadastro/edição de clientes e contato; CPF, CNPJ numérico e CNPJ alfanumérico, com unicidade do documento normalizado.
- Oito tipos de resistência e entrevistas versionadas; edição de nome/situação dos tipos pela gestão.
- Abertura de orçamento com numeração anual no banco, rascunho persistente, respostas condicionais e aviso de alterações não salvas.
- Kanban com nove colunas, pesquisa, filtro de etapa, paginação por cursor, responsáveis, prazo solicitado, tempo na etapa e pendências.
- Detalhe, início de atividade, transferência por gestor, histórico paginado e versões para concorrência.
- Motor transacional: Vendas → Projeto e retorno justificado Projeto → Vendas. Restante bloqueado até suas fases, sem atalhos pelo frontend.
- Schema `kanban` isolado da v1, RLS, grants restritos e RPCs autenticadas. Ausência de consultas Drive no frontend.

Documentos obrigatórios não são dispensados: em produção, o avanço aguarda integração da Fase 2. A fixture de teste confirma documento somente no banco efêmero para exercitar o motor.

## Arquivos e migrations

Interface: `src/main.tsx`, `src/styles.css`, `src/api.ts`, `src/types.ts`, `index.html`.

Banco: `supabase/migrations/202610090001_foundation.sql` e `202610090002_catalog.sql`; instalador combinado `supabase/install/FASE-1-INSTALAR.sql`, inventário `supabase/preflight.sql` e habilitação explícita `supabase/bootstrap-admin.sql`.

Qualidade: `tests/database.mjs`, `tests/architecture.test.mjs`, `tests/browser.mjs`, `.github/workflows/ci.yml`. Build e dependências: `package.json`, lockfile, configuração pnpm/TypeScript. Segurança de hospedagem: `public/_headers`. Documentação: README, auditoria e instalação.

## Testes executados

| Verificação | Resultado |
|---|---|
| PostgreSQL WASM / PGlite | 33 verificações passaram |
| Arquitetura estática | 2 testes passaram |
| TypeScript estrito | Sem erros |
| Build Vite | Concluído |
| Auditoria de dependências de produção | Nenhuma vulnerabilidade conhecida reportada na consulta |
| Navegador Edge headless, desktop e 390 px | Fluxo passou; screenshots inspecionadas |

Banco: catálogo, CPF/CNPJ, duplicidade, rascunho, numeração, salto de etapa, exigência documental, RLS entre vendedores, escrita direta proibida, elevação de privilégio, usuário inativo, conflito de edição, idempotência da transição, retorno, execuções preservadas, auditoria, perfis múltiplos, transferência, paginação e preservação de tabela legada de teste.

Interface: login simulado, cliente, campo condicional da bainha, gravação por SQL real no PGlite, recarga mantendo dados, bloqueio de avanço, início de atividade, histórico, ausência de overflow da página em 390 px, nenhuma chamada Drive e nenhum erro JavaScript capturado. Screenshots em `tmp/kanban-desktop.png` e `tmp/kanban-mobile.png` são de dados fictícios de teste.

Limite dos testes: Auth foi simulado no navegador; nenhum teste autenticado executado contra produção. PGlite serializa a conexão: solicitações concorrentes no cliente foram testadas, mas não substituem ensaio PostgreSQL com duas conexões independentes. Isso permanece no checklist de homologação. SMTP e recuperação ponta a ponta ainda dependem da configuração real.

## Configuração e implantação

Seguir `INSTALACAO.md`: inventário, backup, instalação única, bootstrap do administrador e configuração de URLs/SMTP. Nenhuma migration foi aplicada automaticamente. Nenhum dado da v1 foi alterado.

O código atual usa a chave publicável fornecida para o projeto. Não há service_role, client secret ou refresh token Google no repositório. O código não tem modo demonstrativo para contornar uma falha de instalação.

## Limitações e fases seguintes

- Um contato principal e um item/produto por demanda nesta fase; expansão deve preservar os vínculos existentes.
- Alteração de questionários/criação de novos tipos ocorre por migration versionada; interface permite nome/ativação dos oito tipos existentes.
- Contas novas criadas administrativamente em Supabase Auth; convites automatizados não entregues nesta fase.
- Upload, download, checklist PDF e OAuth ficam na Fase 2.
- Projeto completo, propostas e aprovações ficam na Fase 3; OP, materiais e produção na Fase 4; indicadores completos e backup automatizado na Fase 5.
- Numeração admite lacunas. Não há movimentação livre por arrastar cards.
- Fase 1 não foi implantada em produção; a versão anterior continua sendo a publicada.
- Envio ao GitHub bloqueado pela revisão automática: o repositório oficial é público e é necessária autorização explícita para expor o código e a arquitetura. Código e commits permanecem locais.

Referência para validação alfanumérica: [manual oficial Receita Federal](https://www.gov.br/receitafederal/pt-br/centrais-de-conteudo/publicacoes/documentos-tecnicos/cnpj/manual-dv-cnpj.pdf), algoritmo ASCII − 48 e módulo 11; exemplo 12.ABC.345/01DE-35 incluído nos testes.
