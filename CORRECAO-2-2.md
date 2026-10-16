# Correção 2.2 — Orçamento para Aprovação

A etapa Orçamento agora oferece “Finalizar Orçamento → Aprovação”. Inicie a atividade, selecione o responsável de Vendas (ou Gestor/Administrador), informe a justificativa e confirme a movimentação. O histórico, o levantamento e os dados existentes são preservados. Enviar para Aprovação não significa que o cliente já aprovou.

Para atualizar o ambiente que já usa a versão 2:

1. Execute `supabase/install/VERSAO-2-2-CORRIGIR-ORCAMENTO.sql` no SQL Editor do Supabase.
2. Extraia `Globo-Kanban-Versao-2-2-web.zip` e envie o conteúdo para o mesmo Worker Cloudflare. Recarregue a aplicação.

Não reinstale o banco. Cards já em Orçamento poderão usar a ação após a atualização. Este SQL também mantém Projeto → Orçamento e a devolução explícita para Vendas.

A conclusão de Aprovação e as etapas posteriores ainda não estão habilitadas. Esta entrega corrige especificamente a conclusão de Orçamento.

Validação local: 41 verificações de banco, TypeScript e build. O teste de navegador percorre Vendas → Projeto → Orçamento → Aprovação com autenticação simulada e banco isolado; não altera produção.
