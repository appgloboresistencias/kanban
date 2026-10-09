# Globo Resistências — Kanban 2.0

Fase 1: fundação em React + TypeScript, Supabase Auth e PostgreSQL. Repositório oficial: https://github.com/appgloboresistencias/kanban.

Leia [INSTALACAO.md](INSTALACAO.md) e [FASE-1.md](FASE-1.md). Arquitetura aprovada: [AUDITORIA-FASE-0.md](AUDITORIA-FASE-0.md).

## Desenvolvimento

Node 24 e pnpm 11.25.0:

```sh
pnpm install --frozen-lockfile
pnpm dev
pnpm test
pnpm test:db
pnpm build
```

URL local: http://127.0.0.1:4174. O aplicativo usa o banco real configurado; não contém modo demonstração nem fallback em memória. Sem migrations/perfis ativos, mostra erro de instalação/acesso. Credenciais Supabase publicáveis ficam em `.env.example`; segredos não pertencem ao frontend.

## Teste de interface isolado

Com servidor local iniciado:

```sh
pnpm exec playwright install chromium
node tests/browser.mjs
```

Opcionalmente `TEST_CHROMIUM_PATH` seleciona um Chromium/Edge já instalado. O teste intercepta a API Supabase em um navegador isolado, simula apenas Auth e executa as RPCs contra PostgreSQL WASM efêmero. Não usa contas nem dados reais. Isso não substitui homologação com Supabase Auth real. Screenshots em `tmp/` não entram no Git.

## Estrutura

- `src/`: interface, tipos e cliente RPC.
- `supabase/migrations/`: schema isolado, políticas, motor transacional e catálogo técnico.
- `supabase/install/`: SQL combinado para instalação manual.
- `tests/`: verificações de arquitetura, integração SQL/RLS e navegador.
- `.github/workflows/`: CI sem deploy automático.
- `public/_headers`: cabeçalhos de segurança Cloudflare Pages; ajustar origem Supabase se mudar de projeto.

As etapas após Projeto permanecem bloqueadas. A ausência do Drive na Fase 1 não é contornada: anexos obrigatórios precisam da Fase 2 para permitir avanço em produção.
