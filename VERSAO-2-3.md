# Versão 2.3 — fluxo completo para testes

## Atualização do ambiente atual

1. No Supabase, execute somente `supabase/install/VERSAO-2-3-FLUXO-COMPLETO.sql`. O ambiente já deve ter a versão 2 instalada. Resultado esperado: sucesso, sem linhas retornadas.
2. Extraia `Globo-Kanban-Versao-2-3-web.zip` e publique seu conteúdo no Worker Cloudflare existente. A raiz enviada contém `index.html`, `assets/` e `_headers`.
3. Recarregue o site. Se a aplicação pedir a atualização do banco, confira a execução do SQL acima. Não use o instalador do zero no banco atual.

A migration acrescenta campos e funções e preserva clientes, demandas, respostas, contas e histórico. Pode ser reaplicada. Não muda automaticamente a etapa de nenhum card. Contas existentes continuam válidas; não repita o bootstrap administrativo.

## Operação

Em cada card, abra **Etapa atual**, clique em **Iniciar atividade**, preencha os registros e escolha a ação. É possível **Salvar dados da etapa** incompletos, sair e continuar depois. Para movimentar, selecione o responsável, escreva a justificativa e marque a conferência. As validações também são feitas no banco.

| Etapa | Conclusão e decisões disponíveis |
|---|---|
| Vendas | Levantamento livre confirmado e referência do PDF → Projeto. |
| Projeto | Aprovar → Orçamento; pedir informações → Vendas; registrar novo ciclo de revisão; encerrar por inviabilidade. |
| Orçamento | Registrar versão, envio e validade da proposta → Aprovação; devolver ao Projeto. |
| Aprovação | Registrar versão, data, meio e referência da aprovação do cliente, conferência interna e prazo acordado → OP; pedir revisão de Projeto/Orçamento; registrar recusa. |
| Gerar OP | Informar número oficial do ERP, emissão e materiais → Almoxarifado; devolver ao Projeto. |
| Almoxarifado | Material completo → Produção; material parcial exige descrição, previsão e autorização da gestão; devolver para corrigir OP. |
| Produção | Registrar serviço executado e confirmar ausência de bloqueios → Qualidade. |
| Qualidade | Aprovar inspeção → Entrega; reprovar com justificativa → Produção, criando retrabalho. |
| Entrega | Registrar data efetiva, recebedor e referência do comprovante → Pedido concluído. |

A aprovação interna fica registrada com usuário, data e versão da proposta. Revisões comerciais/técnicas retornam pelo fluxo e exigem nova aprovação. Para cards antigos que já estavam em Aprovação sem versão de proposta registrada, informe a versão e a evidência ao aprovar; a nova regra não inventa documentos anteriores.

O prazo de entrega acordado aparece no card após aprovação. A produção e a qualidade não encerram o pedido automaticamente.

## Equipe e acessos

Crie cada conta individual no Supabase Auth e ative os perfis em **Equipe e acessos**. O responsável escolhido deve estar ativo e ter o perfil da próxima etapa, ou ser Gestor/Administrador.

- Vendas e Aprovação: Vendas.
- Projeto e OP: Projeto.
- Orçamento: Orçamentista.
- Almoxarifado, Produção, Qualidade e Entrega: respectivos perfis.
- Gestão pode transferir a responsabilidade e reabrir recusados.

O responsável atual edita sua etapa. Quem participou como responsável ou registrou uma ação auditada pode consultar o histórico do card. Outros colaboradores do setor podem consultar os cards da etapa conforme as regras existentes, mas não concluir a atividade de outro responsável. Contas inativas não acessam o sistema.

## Exceções e rastreabilidade

Material parcial só é liberado por Gestor/Administrador, com autorização explícita. O almoxarife salva a pendência e a gestão conclui a decisão. A pendência acompanha o card e pode ser regularizada pelo Almoxarifado ou gestão sem retornar a etapa. Enquanto estiver aberta, impede Qualidade → Entrega.

Na Produção, marque problemas bloqueantes e registre sua descrição/tratamento. Salve para manter o alerta no quadro. Para concluir, registre a solução e desmarque o bloqueio; as alterações permanecem auditadas. Nesta versão, esse controle usa os registros da etapa, sem módulo separado de múltiplas ocorrências e responsáveis por ocorrência.

Cada devolução cria uma nova execução; não apaga a anterior. Retrabalhos criam novas produções e inspeções. Consulte **Consultar ciclos das etapas** e **Histórico**.

Use o filtro **Pedidos concluídos** ou **Orçamentos recusados** para consultar encerrados. Concluídos não podem ser editados ou transferidos. Recusados podem ser reabertos somente pela gestão, com justificativa, responsável de Vendas e nova confirmação do levantamento.

## Roteiro de teste da equipe

1. Use um cliente e uma demanda identificados como TESTE.
2. Percorra Vendas → Projeto → Orçamento → Aprovação com contas de cada setor.
3. Confira que não é possível avançar sem início, responsável, conferência e registros obrigatórios.
4. Solicite revisão na Aprovação, altere a versão da proposta e confira a exigência de nova aprovação.
5. Registre OP e teste material completo. Em outra demanda, teste material parcial com autorização e posterior regularização.
6. Marque um bloqueio em Produção, salve e confira o impedimento de concluir; registre a solução.
7. Reprove na Qualidade, conclua o retrabalho e faça nova inspeção.
8. Finalize a entrega e confira o filtro Concluídos e o histórico.
9. Recuse outra demanda, confira o filtro Recusados e teste a reabertura pela gestão.

## Validação e limites

109 verificações de banco passaram (33 da fundação, 41 das atualizações anteriores e 35 do fluxo completo), além dos testes de arquitetura, TypeScript, build e navegador. Testes locais usam PostgreSQL isolado e autenticação simulada no navegador. Foram verificados o caminho completo, salvamento parcial, permissão por papel, revisões, recusa/reabertura, material parcial, bloqueios, retrabalho, histórico, concorrência e encerramento. Nenhum teste grava no Supabase real.

A entrevista continua fora do sistema: campo livre e referência ao arquivo escolhido no Drive. Os demais documentos também são referências registradas manualmente. Não há upload integrado, leitura automática de arquivos, comprovação do conteúdo dos documentos ou aprovação automática por e-mail. A OP é emitida no ERP; o Kanban registra seu número. Integração OAuth do Drive e indicadores avançados não fazem parte desta atualização.

`Globo-Kanban-Versao-2-3-codigo.zip` contém o código para versionamento manual no GitHub; o pacote web é o usado no Cloudflare.
