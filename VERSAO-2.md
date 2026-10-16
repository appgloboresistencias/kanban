# Versão 2 — levantamento livre

> Versão atual para testes: [Fluxo completo 2.3](VERSAO-2-3.md). Use o SQL e o pacote web dessa versão no ambiente existente.

> Atualização mais recente: [Correção Projeto → Orçamento](CORRECAO-2-1.md). Para ambientes já na versão 2, aplique essa correção.

O vendedor escolhe o PDF da entrevista no Google Drive, copia o link para o card e registra as informações coletadas em um campo livre. Não há cadastro de tipos de resistência nem perguntas técnicas no sistema.

O rascunho aceita informações parciais. Para concluir o levantamento, informe o texto, o link do arquivo e marque a confirmação. Alterar o texto ou a referência pede nova confirmação. O avanço de Vendas para Projeto exige também início da atividade e responsável elegível. As etapas posteriores continuam reservadas às próximas entregas.

## Atualizar o ambiente atual

1. Guarde uma cópia de segurança do banco. No SQL Editor do projeto Supabase `nwxjntiysbwqwwwpazrd`, execute todo o conteúdo de `supabase/install/VERSAO-2-ATUALIZAR.sql`. O resultado esperado é sucesso, sem linhas retornadas.
2. Extraia `Globo-Kanban-Versao-2-web.zip`. No Cloudflare, publique seu conteúdo no Worker existente `royal-tree-dc12`, usando o mesmo processo de envio manual da primeira versão. A raiz enviada deve conter `index.html`, `assets/` e `_headers`.
3. Recarregue https://royal-tree-dc12.appgloboresistencias.workers.dev/ e entre com a conta atual. Confira que o menu não contém Tipos de resistência. Abra uma demanda e confira o campo livre e a referência do PDF.

Execute o SQL antes de publicar a interface. Não execute novamente o instalador da Fase 1 nem `VERSAO-2-INSTALAR-DO-ZERO.sql` neste banco. Não é necessário recriar o administrador ou alterar o endereço de autenticação.

A atualização adiciona campos e substitui funções de aplicação. Mantém clientes, demandas, números, usuários e histórico. As respostas antigas ficam disponíveis para consulta no card; não são convertidas automaticamente em texto nem apagadas. Ao revisar uma demanda antiga em Vendas, preencha o novo levantamento e confirme novamente.

## Google Drive nesta entrega

O botão Escolher no Drive abre o Google Drive em outra aba. Escolha o arquivo ali e cole seu link no card. A abertura respeita as permissões da conta Google; não é necessário tornar a pasta pública.

Esta versão salva a referência e o nome opcional do PDF. Não verifica o conteúdo, a extensão real, a existência ou a versão do arquivo. Não inclui listagem integrada, upload ou autorização OAuth do Drive. O nome/revisão informado é uma anotação do vendedor.

## Código e validação

`Globo-Kanban-Versao-2-codigo.zip` contém o código para atualizar o repositório manualmente. Não é o pacote de publicação do Cloudflare. A aplicação pronta está no ZIP web.

Validação local: testes de arquitetura e links, TypeScript, build, testes PostgreSQL isolados e teste de navegador com autenticação simulada. Foram verificados rascunho, persistência, confirmação, avanço para Projeto, histórico, preservação dos registros anteriores e layout móvel. Os testes não modificam o Supabase de produção.

Instalações novas podem usar `supabase/install/VERSAO-2-INSTALAR-DO-ZERO.sql` somente em banco sem schema `kanban`, seguindo depois a configuração de Auth e o bootstrap administrativo descritos na documentação original.
