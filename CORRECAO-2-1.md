# Correção 2.1 — Projeto para Orçamento

Ao finalizar Projeto, a ação padrão agora encaminha o card para Orçamento. A devolução para Vendas fica separada na opção “Devolver para Vendas para ajustes”. Selecione um responsável com perfil Orçamentista, Gestor ou Administrador e informe a justificativa. A atividade deve estar iniciada.

Para atualizar o ambiente que já está na versão 2:

1. Execute `supabase/install/VERSAO-2-1-CORRIGIR-FLUXO.sql` no SQL Editor do Supabase. Não reinstale o banco.
2. Extraia `Globo-Kanban-Versao-2-1-web.zip` e publique o conteúdo no mesmo Worker Cloudflare. Recarregue a aplicação.

A correção preserva registros e histórico. Cards devolvidos anteriormente permanecem em Vendas: revise e encaminhe novamente para Projeto antes de concluir. Não há movimentação automática de dados existentes.

As etapas após Orçamento ainda não estão habilitadas nesta entrega. Esta correção libera especificamente Projeto → Orçamento.

Validação: 34 verificações de banco da versão 2, incluindo permissões, concorrência, histórico, repetição de requisição e devolução explícita; TypeScript e build aprovados. Testes isolados não escrevem no ambiente real.
