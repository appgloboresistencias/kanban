# Globo Resistências — Kanban 2.5

Biblioteca de PDFs com perguntas, levantamento livre e respostas/anexos privados no Supabase Storage. Fluxo completo de Vendas até Entrega.

Siga [VERSAO-2-5.md](VERSAO-2-5.md) para instalar, limpar os testes e publicar. O SQL de limpeza é separado da atualização e preserva usuários e modelos.

## Desenvolvimento

Node 24 e pnpm. Execute `pnpm install --frozen-lockfile`, `pnpm test`, `pnpm test:db` e `pnpm build`. Para testar no navegador, inicie `pnpm dev` e execute `node tests/browser.mjs` com Chromium do Playwright instalado ou TEST_CHROMIUM_PATH configurado.

As migrations históricas preservam a evolução do banco; não execute instaladores antigos no ambiente existente. Testes SQL usam PGlite descartável. Testes de navegador simulam Auth/Storage e não substituem homologação conectada.
