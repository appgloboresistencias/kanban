# Instalação da Fase 1

A versão anterior permanece em uso. Esta fase deve ser homologada antes de qualquer substituição. Não há migration automática no navegador, no CI ou no build.

## 1. Inventário e backup

No projeto Supabase correto, execute `supabase/preflight.sql` (somente leitura). Confirme dados existentes e exporte esquema e dados com ferramenta administrativa/pg_dump, guardando cópia fora do Git. A inspeção autenticada ainda depende do proprietário; não foi afirmada ausência de dados reais.

Verifique se `kanban` e funções `public.kb_*` já existem. Se existirem, interrompa a instalação e compare a versão; o instalador é de execução única, não um reset. Ele falha em vez de substituir schema existente. A Fase 1 não altera `public.profiles`, `public.orders`, políticas ou triggers da v1.

## 2. Banco

Execute `supabase/install/FASE-1-INSTALAR.sql` no SQL Editor como administrador. O arquivo reúne duas migrations em uma transação; erro aborta toda a instalação. Em ambientes com CLI Supabase, aplique as migrations versionadas uma única vez pelo fluxo habitual; não aplique simultaneamente o arquivo combinado.

Não é necessário expor o schema `kanban` no PostgREST. O frontend usa somente RPCs `public.kb_*`, com autenticação e autorização explícitas. As tabelas também possuem RLS e não permitem escrita por usuários comuns.

Edite apenas o e-mail em `supabase/bootstrap-admin.sql` para indicar a conta administradora existente e execute esse arquivo. Contas legadas são copiadas como perfis inativos, sem copiar permissões automaticamente. Isso evita conceder acesso à v2 sem avaliação. O administrador inicial poderá ativar perfis pela página Equipe e acessos.

## 3. Autenticação

Utilize contas individuais em Supabase Auth. Configure Site URL e Redirect URLs para o domínio homologado e, temporariamente, `http://127.0.0.1:4174`. Restrinja cadastro público na configuração do projeto se não for utilizado. Configure SMTP para recuperação e convites destinados a colaboradores; o SMTP padrão não é suficiente para uso empresarial geral.

A criação de novas contas é administrativa no Supabase nesta fase. O trigger cria o perfil inativo. O sistema permite habilitar/desabilitar e associar múltiplos perfis; um administrador não modifica o próprio acesso pela aplicação.

## 4. Frontend e hospedagem

As variáveis `VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY` são públicas. O padrão do código aponta ao projeto fornecido pelo usuário. Para homologação isolada, substitua ambas em `.env.local`; nunca inclua service_role.

Build: `pnpm build`; resultado: `dist/`. Cloudflare Pages: conectar `appgloboresistencias/kanban`, Node 24, comando `pnpm install --frozen-lockfile && pnpm build`, diretório `dist`. Configurar pnpm 11.25.0. Revisar `_headers` se trocar Supabase. Não ativar Functions, plano pago, cobrança automática ou domínio pago para esta fase. A publicação no Cloudflare não foi executada sem conta/conexão disponível.

## 5. Homologação obrigatória

Entrar com administrador, ativar dois vendedores e um projetista, cadastrar cliente e rascunho, recarregar para confirmar persistência, verificar que vendedores não acessam cards alheios e testar conflito de edição em duas sessões. Confirmar a recuperação de senha com SMTP real. Conferir que tabelas e pedidos da v1 permanecem intactos.

O desenho obrigatório mantém o avanço bloqueado até a integração documental da Fase 2. Não inserir metadados falsos para liberar produção; as fixtures de documentos só são criadas nos bancos efêmeros dos testes.

## 6. Reversão

Antes da entrada em produção, basta manter a URL v1. Não remover schema ou restaurar dump por cima de dados novos sem plano de reconciliação. Após novas gravações, avaliar o delta antes de qualquer rollback. A aplicação não executa exclusão de dados nem downgrade destrutivo.
