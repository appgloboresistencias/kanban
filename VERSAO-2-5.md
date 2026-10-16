# Globo Kanban 2.5 — entrevistas e documentos no Supabase

Esta versão usa exclusivamente Supabase Storage. Os PDFs com perguntas ficam na biblioteca; as respostas e demais arquivos pertencem ao card. Não há questionário técnico no sistema nem cadastro de tipos de resistência.

## Como usar

1. Administrador: abra **Modelos de entrevista**, informe um título e cadastre o PDF com perguntas. Para atualizar, envie outro PDF e arquive o anterior.
2. Vendedor: ao criar um orçamento, consulte ou baixe os modelos disponíveis no levantamento. Isso funciona antes de salvar o card.
3. Salve o rascunho. Em **Documentos**, envie as respostas como **Respostas da entrevista (PDF)** e os demais anexos nas categorias correspondentes.
4. Preencha o levantamento livre e confirme a conclusão. Consultar perguntas não equivale a responder a entrevista.
5. Conclua as etapas pelo fluxo já existente, de Vendas até Entrega.

## Instalação no projeto existente

Projeto correto: `nwxjntiysbwqwwwpazrd`. A atualização não remove os dados automaticamente.

1. Se o SQL documental 2.4 ainda não foi executado, execute `supabase/install/VERSAO-2-4-DOCUMENTOS.sql` sobre a versão 2.3. Não use o instalador antigo do zero.
2. Execute `supabase/install/VERSAO-2-5-ENTREVISTAS.sql` no SQL Editor.
3. Para a limpeza dos testes autorizada pelo usuário, siga a seção abaixo.
4. Publique o conteúdo extraído de `Globo-Kanban-Versao-2-5-web.zip` no Cloudflare. `index.html`, `assets` e `_headers` ficam na raiz do upload. O ZIP de código é para o GitHub e não substitui o pacote web compilado.
5. Recarregue com Ctrl+F5 e confira **Versão 2.5** no menu.
6. Cadastre um modelo, consulte-o antes de salvar um orçamento e teste upload/download das respostas com uma conta de vendedor.

Os dois buckets são privados: `globo-entrevistas` (perguntas) e `globo-documentos` (arquivos dos cards). O sistema cria os metadados e controla confirmação, permissões e consumo. Cadastre modelos pela aplicação, não enviando arquivos soltos diretamente ao bucket.

## Limpeza dos testes

Execute em uma janela sem usuários operando o sistema. Preserva contas Auth, perfis, acessos, configuração das etapas, biblioteca e numeração. Remove clientes, cards, execuções, transições, documentos dos cards e históricos de teste, inclusive os eventos de auditoria existentes.

1. No painel **Storage**, exclua os arquivos de teste do bucket `globo-documentos`, se existirem. Preserve o bucket e não toque em outros buckets. Não exclua registros de `storage.objects` por SQL.
2. Execute `supabase/install/VERSAO-2-5-LIMPAR-TESTES.sql`. O script interrompe a transação se ainda houver objetos no bucket e não usa CASCADE para dependências desconhecidas.
3. Confira o resultado: cards e clientes zerados; usuários ativos e modelos preservados.

A limpeza remota não foi executada nesta entrega: o plugin continua sem permissão para o projeto Globo. O script foi validado somente em banco local descartável.

## Permissões e limites

Usuários ativos consultam modelos disponíveis; somente administradores cadastram, confirmam, cancelam reservas e arquivam modelos. Arquivos dos cards continuam restritos ao acesso de cada orçamento. Políticas restritivas protegem os buckets mesmo se outro módulo tiver permissões amplas. Não há URL pública permanente nem chave administrativa no frontend.

PDFs: 15 MB; imagens: 5 MB; DOCX/XLSX: 10 MB inicialmente. O administrador ajusta os limites na aba Documentos. A biblioteca compartilha o orçamento de armazenamento de 500 MB configurado inicialmente, que deve ser conferido com a cota real do projeto. Reservas pendentes e arquivos arquivados também contam.

Os modelos são consultados sob demanda, com paginação. Repetir o mesmo PDF retoma a reserva sem duplicar. Arquivos só ficam disponíveis após confirmação do objeto e a leitura verifica tamanho e SHA-256. Essas verificações não substituem análise antivírus.

## Validação e escopo

Testes locais cobrem permissões de administrador/vendedor/inativo, política externa ampla, limite de PDF, confirmação física, duplicidade, arquivamento, consumo, respostas obrigatórias, limpeza preservando usuários/modelos e reaplicação da migration. Teste de navegador cobre cadastro e consulta de modelo antes de salvar, anexos, retomada e todo o fluxo até conclusão.

Auth e transporte Storage são simulados nos testes de navegador; as RPCs executam SQL real em PGlite. A validação conectada ao Supabase e o deploy remoto não foram executados. Migrations e testes históricos permanecem como registro das versões anteriores; a interface atual e seus adaptadores não usam integração externa de documentos.
