# Versão 2.4 — documentos temporários no Supabase

## Entrega

Aba Documentos no card, com múltiplos arquivos, categoria, etapa de origem, usuário/data, tamanho, versão, visualização, download e arquivamento. Arquivos acompanham o card sem cópias ao mudar de etapa. O fluxo 2.3 continua funcionando e o levantamento permanece livre.

Uploads usam o bucket privado `globo-documentos`. PDFs até 15 MB, fotos JPG/PNG/WEBP até 5 MB, DOCX/XLSX até 10 MB. O administrador ajusta os limites na aba Documentos. O orçamento inicial conservador é 500 MiB para o projeto, configurável até 1 GiB nesta versão; não é detecção automática nem contratação de cota do plano. Conferir o espaço realmente disponível no painel Supabase antes de aumentá-lo. O limite global do serviço também se aplica.

O consumo inclui metadados de objetos de todos os buckets do projeto e reservas sem objeto. É medido no envio e quando o administrador solicita Atualizar consumo; a aba mostra a última medição. Avisos em 70%, 85% e 95%. Arquivamento não libera espaço, pois nenhum arquivo é excluído automaticamente.

## Instalação e homologação

**Nenhuma alteração foi aplicada no Supabase/Cloudflare de produção.** A conexão atual não tem acesso ao projeto Globo; veja `AUDITORIA-STORAGE.md`.

1. Conectar a conta correta e executar `supabase/storage-preflight.sql`, somente leitura. Conferir versão 2.3, usuários, políticas e bucket existente.
2. Em ambiente controlado já na versão 2.3, executar `supabase/install/VERSAO-2-4-DOCUMENTOS.sql`. É a única migration nova; não reaplicar instaladores anteriores no banco existente. O SQL cria o bucket privado e políticas RLS; aborta se já existir um bucket público com esse nome.
3. Conferir no painel Storage que `globo-documentos` é privado, tem limite de 50 MiB no bucket e MIME types permitidos. Limites menores por tipo são aplicados no banco. O limite global precisa permitir ao menos 15 MiB para os PDFs padrão.
4. Publicar o conteúdo extraído de `Globo-Kanban-Versao-2-4-web.zip` numa implantação de homologação do Cloudflare: raiz com index.html, assets e _headers. Preservar os cabeçalhos, inclusive blob para prévias. Se usar outra URL, autorizar esse endereço no Supabase Auth.
5. Com contas reais de teste, executar o roteiro abaixo. Só então atualizar o mesmo Worker de produção. Fazer cópia de segurança do banco antes da implantação real.

Nenhuma chave administrativa é necessária no frontend. Para o armazenamento temporário não é preciso configurar Google, publicar Edge Function ou usar service_role no navegador. `Globo-Kanban-Versao-2-4-codigo.zip` é o pacote para atualizar manualmente o GitHub, que está atrasado.

## Uso

Salve uma nova demanda como rascunho para obter seu card. Em Documentos, escolha a categoria, selecione um ou vários arquivos e clique Enviar documentos. Para substituir por revisão, clique Nova versão: o original permanece no histórico. Para a entrevista, escolha Entrevista (PDF); ela passa a satisfazer a referência do levantamento sem depender do Drive.

Em falha de rede, selecione o mesmo arquivo para retomar. A operação reutiliza o identificador e só confirma o documento quando o Storage registrar o objeto. Verificar envio recupera uploads que chegaram ao servidor mas cuja confirmação foi interrompida. Cancelar reserva só funciona quando não há objeto armazenado. A retomada reinicia a transferência do arquivo quando necessário; não é retomada por byte/TUS.

Visualizar abre PDF e imagens sem torná-los públicos. DOCX/XLSX são baixados para abrir no aplicativo correspondente. Downloads são autenticados; não há URLs públicas permanentes. O navegador verifica tamanho/SHA-256 antes de abrir o arquivo.

Arquivar exige justificativa e autorização. Mostrar documentos arquivados permite consultá-los com as mesmas permissões do card. A última entrevista confirmada não pode ser arquivada enquanto for necessária à confirmação do levantamento.

## Roteiro de homologação conectado

- PDF, JPG/PNG, DOCX e XLSX; vários arquivos no mesmo card e nova versão.
- Download e prévia com usuário autorizado; negar acesso a outra conta sem acesso ao card, inclusive por caminho direto.
- PDF maior que 15 MB, imagem maior que 5 MB e Office maior que 10 MB devem ser recusados.
- Interromper a rede durante envio e repetir; conferir que a reserva é recuperada sem duplicação.
- Mover o card e confirmar que arquivos anteriores continuam acessíveis. Concluir o fluxo até a entrega.
- Arquivar, consultar histórico e confirmar ausência de exclusão física.
- Abrir card/aba sem chamada a listagem de objetos do Storage; consulta somente aos metadados.
- Conferir avisos e consumo no painel administrativo, incluindo reservas e arquivos arquivados.

## Migração futura e operação híbrida

Metadados registram provedor, caminho original, ID Google, versão, tamanho, SHA-256 e estado da migração. A interface escolhe o adaptador pelo provedor registrado. Se o acesso Google falhar após uma migração, a leitura tenta o original privado preservado no Supabase.

O worker `server/document-migration.mjs` implementa PENDENTE → EM_MIGRACAO → COPIADO → VALIDADO → CONCLUIDO, com FALHA recuperável. Reserva o ID de destino antes de enviar, verifica bytes de origem e destino, grava checkpoints e só então troca o provedor. Nunca apaga o original. Uma reserva de execução vence em 15 minutos, permitindo retomada após queda do processo.

Quando a conta Google voltar:

1. Autorizar OAuth central e identificar uma pasta privada. Validar escopos, acesso, renovação de token e condições do aplicativo OAuth. Não colocar credenciais no Git nem no frontend.
2. Homologar `supabase/functions/documents-drive/index.ts`, o proxy que verifica usuário/card antes de ler o Google. Configurar secrets GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REFRESH_TOKEN e ALLOWED_ORIGINS apenas no backend.
3. Configurar o processo administrativo com SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY e as credenciais Google mais GOOGLE_FOLDER_ID. Rodar `node server/migrate-cli.mjs DOCUMENT_UUID ADMIN_UUID --confirm-migration` para os IDs selecionados. Esse comando não foi executado contra serviços reais nesta entrega.
4. Repetir de forma incremental. Arquivos concluídos são ignorados; falhas mantêm o Supabase como origem. Em divergência de checksum, interromper e investigar o destino, sem apagar o original.
5. Manter janela de validação/rollback acordada com o administrador, sugerida de 30 dias. `kb_document_rollback` exige administrador, justificativa e existência do original. Nenhum purge é disponibilizado; eventual exclusão exige autorização administrativa, backup e validação separados.

O provedor padrão é configuração protegida no banco, inicialmente supabase. A seleção de google_drive permanece bloqueada até validar a integração. O adaptador de leitura e o worker de migração estão preparados; novos uploads diretamente no Google ainda exigirão habilitar seu backend de upload após OAuth. Não altere somente a flag para ativá-los. A conta Google bloqueada não foi contornada.

## Validação entregue

45 verificações SQL de documentos, incluindo RLS, quota, recuperação, versões, arquivamento, migração simulada, integridade, convivência de provedores e rollback. As 109 verificações anteriores continuam passando. Teste de navegador com PDF/foto/DOCX/XLSX, falha de rede, download, prévia, arquivo arquivado, paginação do histórico e fluxo completo até Entrega; Auth e transporte Storage simulados, SQL real em PGlite.

Testes locais não comprovam funcionamento da API Storage de produção. A criação do bucket, o upload real e os advisors do projeto Globo continuam pendentes de conexão/homologação.

## Arquivos principais

- `src/documents/DocumentsTab.tsx`: aba, envio múltiplo, versões, consulta, prévias, download, arquivamento e administração de limites.
- `src/documents/service.ts`, `adapters.ts`, `types.ts`: serviço único, validação, SHA-256 e seleção do provedor.
- `src/main.tsx`, `src/api.ts`, `src/styles.css`, `public/_headers`: integração no card e política de conteúdo para prévias locais.
- `supabase/migrations/20261016125041_temporary_document_storage.sql`: evolução de metadados, bucket privado, RLS, reservas, consumo e checkpoints de migração.
- `server/document-migration.mjs`, `google-drive-migration.mjs`, `migrate-cli.mjs`: processo administrativo futuro, fora do frontend.
- `supabase/functions/documents-drive/index.ts`: proxy futuro de leitura Google autenticada; não é necessário para uploads temporários.
- `tests/documents.mjs`, `tests/storage-fixture.mjs`, `tests/browser.mjs` e fixtures Office: testes de segurança, recuperação, migração e interface.

Políticas criadas em storage.objects: `globo_doc_insert`, `globo_doc_read` e restritivas `globo_doc_insert_guard`, `globo_doc_read_guard`, `globo_doc_update_guard`, `globo_doc_delete_guard`. Nenhuma política permite a usuários substituir ou excluir o objeto físico. Os arquivos são escritos pela API, não por SQL.
