export type StageData=Record<string,string|boolean>;
export type InputField={key:string;label:string;type?:'date'|'check'|'area'|'select';options?:[string,string][]};
export const stageFields:Record<string,InputField[]>={
sales:[],design:[{key:'notes',label:'Resultado da análise / observações',type:'area'}],
quotation:[{key:'proposal_version',label:'Versão da proposta'},{key:'sent_date',label:'Data de envio ao cliente',type:'date'},{key:'valid_until_date',label:'Validade da proposta',type:'date'},{key:'reference',label:'Referência da proposta (opcional)'},{key:'sent',label:'Confirmo que a proposta foi enviada ao cliente',type:'check'}],
approval:[{key:'approved_version',label:'Versão aprovada'},{key:'approval_date',label:'Data da aprovação do cliente',type:'date'},{key:'approval_channel',label:'Meio de aprovação (e-mail, telefone, etc.)'},{key:'approval_reference',label:'Referência da comunicação / evidência'},{key:'delivery_date',label:'Prazo de entrega acordado',type:'date'},{key:'client_approved',label:'O cliente aprovou esta versão da proposta',type:'check'},{key:'internal_approved',label:'Conferi a aprovação e autorizo internamente esta versão',type:'check'}],
op:[{key:'op_number',label:'Número oficial da OP no ERP'},{key:'issue_date',label:'Data de emissão da OP',type:'date'},{key:'materials',label:'Lista de materiais / referência dos documentos',type:'area'}],
warehouse:[{key:'material_status',label:'Situação dos materiais',type:'select',options:[['total','Separação total'],['partial','Separação parcial']]},{key:'missing_materials',label:'Materiais e quantidades pendentes',type:'area'},{key:'expected_date',label:'Previsão de regularização',type:'date'},{key:'partial_authorized',label:'Como gestor, autorizo produção com material parcial',type:'check'}],
production:[{key:'work_done',label:'Serviço executado / retrabalho',type:'area'},{key:'blocked',label:'Há problema bloqueante em aberto',type:'check'},{key:'problem',label:'Problema e tratamento realizado',type:'area'}],
quality:[{key:'inspection',label:'Resultado da inspeção / não conformidade',type:'area'},{key:'reference',label:'Referência das evidências (opcional)'}],
delivery:[{key:'delivered_date',label:'Data efetiva da entrega',type:'date'},{key:'received_by',label:'Recebido por'},{key:'delivery_reference',label:'Comprovante / referência da entrega'}]
};
export const stageActions:Record<string,[string,string][]>= {
sales:[['design','Concluir levantamento → Projeto']],
design:[['quotation','Aprovar Projeto → Orçamento'],['sales','Solicitar informações → Vendas'],['design','Registrar revisão de Projeto'],['rejected','Encerrar por inviabilidade técnica']],
quotation:[['approval','Finalizar Orçamento → Aprovação'],['design','Solicitar revisão → Projeto']],
approval:[['op','Registrar aprovação → Gerar OP'],['quotation','Cliente solicitou revisão → Orçamento'],['design','Cliente solicitou revisão → Projeto'],['rejected','Registrar recusa do cliente']],
op:[['warehouse','Conferir OP → Almoxarifado'],['design','Corrigir projeto → Projeto']],
warehouse:[['production','Liberar materiais → Produção'],['op','Solicitar ajuste → Gerar OP']],
production:[['quality','Concluir Produção → Qualidade']],
quality:[['delivery','Aprovar inspeção → Entrega'],['production','Reprovar inspeção → Retrabalho']],
delivery:[['completed','Confirmar entrega → Pedido concluído']]
};
