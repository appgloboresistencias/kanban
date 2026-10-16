import {storageFixture} from './storage-fixture.mjs';
import {PGlite} from '@electric-sql/pglite';
import {readFile,readdir} from 'node:fs/promises';
import assert from 'node:assert/strict';
const db=new PGlite();let count=0;
function ok(v,label){assert.ok(v,label);count++;console.log('PASS fluxo:',label);}
async function fail(fn,re,label){await assert.rejects(fn,re);count++;console.log('PASS fluxo:',label);}
await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}');create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;`);
await storageFixture(db);
for(const f of (await readdir(new URL('../supabase/migrations/',import.meta.url))).sort())await db.exec(await readFile(new URL('../supabase/migrations/'+f,import.meta.url),'utf8'));
const roles=['admin','sales','design','estimator','warehouse','production','quality','delivery'];const users={};
for(const role of roles){users[role]=crypto.randomUUID();await db.query('insert into auth.users(id,email) values($1,$2)',[users[role],role+'@test.invalid']);await db.query('insert into kanban.user_roles values($1,$2)',[users[role],role]);}
users.support=crypto.randomUUID();await db.query('insert into auth.users(id,email) values($1,$2)',[users.support,'apoio@test.invalid']);await db.query('insert into kanban.user_roles values($1,$2)',[users.support,'warehouse']);
await db.exec('update kanban.profiles set active=true');
async function as(role){await db.exec(`reset role;set role authenticated;select set_config('request.jwt.claim.sub','${users[role]}',false);`);}
async function rpc(name,args=[]){return(await db.query(`select public.kb_${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) result`,args)).rows[0].result;}
await as('sales');const customer=await rpc('save_customer',[null,0,{legal_name:'Cliente do fluxo',contact:'Contato Teste'}]);
const draft={form_version:2,title:'Pedido de teste completo',customer_id:customer,technical_notes:'Especificação coletada no PDF pelo vendedor.',interview_pdf_url:'https://drive.google.com/file/d/0123456789abcdef/view',technical_complete:true};
const id=crypto.randomUUID();await rpc('save_demand',[id,0,draft]);
let current=()=>rpc('detail',[id]);
async function start(){const d=await current();await rpc('start',[id,d.version]);}
async function finish(target,role,data={}){const d=await current();return rpc('finish',[id,d.version,target,role?users[role]:null,'Etapa conferida pelo responsável',crypto.randomUUID(),{...data,confirmed:true}]);}
const proposal={proposal_version:'R1',sent_date:'2026-01-01',valid_until_date:'2026-12-31',sent:true};
const approval={approved_version:'R1',approval_date:'2026-01-02',approval_channel:'E-mail',approval_reference:'Mensagem do cliente ABC',delivery_date:'2026-12-31',client_approved:true,internal_approved:true};
ok((await rpc('bootstrap')).workflow_version===3,'capacidade do fluxo completo');
await fail(()=>finish('design','design'),/Inicie/,'conclusão sem início bloqueada');
await start();await fail(async()=>rpc('finish',[id,(await current()).version,'design',users.design,'Motivo válido',crypto.randomUUID(),{}]),/Confirme/,'conferência explícita obrigatória');
await finish('design','design');await as('design');await start();await finish('quotation','estimator');
await as('estimator');await start();await fail(()=>finish('approval','sales'),/obrigatório/,'orçamento exige proposta e envio');
await finish('approval','sales',proposal);await as('sales');await start();
await fail(()=>finish('op','design',{...approval,internal_approved:false}),/aprovação interna/,'aprovação interna obrigatória');
await fail(()=>finish('op','design',{...approval,approved_version:'R0'}),/última proposta/,'aprovação vinculada à versão enviada');
await finish('quotation','estimator');await as('estimator');await start();await finish('approval','sales',{...proposal,proposal_version:'R2'});
await as('sales');await start();await fail(()=>finish('op','design',approval),/última proposta/,'revisão invalida aprovação anterior');
await finish('op','design',{...approval,approved_version:'R2'});await as('design');await start();
await fail(()=>finish('warehouse','warehouse'),/obrigatório/,'OP exige número e materiais');
await finish('warehouse','warehouse',{op_number:'OP-123',issue_date:'2026-01-03',materials:'Aço: 10 unidades'});
await as('warehouse');await start();const partial={material_status:'partial',missing_materials:'Aço: 2 unidades',expected_date:'2026-12-01',partial_authorized:true};
await fail(()=>finish('production','production',partial),/Gestor/,'almoxarife não autoriza sozinho material parcial');
await as('admin');await finish('production','production',partial);await as('production');ok(!!(await current()).materials_pending,'pendência acompanha produção');await start();
await fail(()=>finish('quality','quality',{work_done:'Montagem',blocked:true}),/bloqueantes/,'problema bloqueante impede conclusão');
await finish('quality','quality',{work_done:'Montagem e teste elétrico',blocked:false});await as('quality');await start();
await fail(()=>finish('delivery','delivery',{inspection:'Conforme'}),/materiais pendentes/,'material pendente impede entrega');
await finish('production','production',{inspection:'Reprovado: ajustar conexão'});await as('production');ok((await current()).rework_count===1,'retrabalho cria ciclo e contador');
await start();await finish('quality','quality',{work_done:'Conexão refeita',blocked:false});
await as('support');let d=await current();await rpc('materials_resolve',[id,d.version,'Duas unidades recebidas e entregues à produção']);ok(!(await current()).materials_pending,'almoxarife regulariza sem retorno do card');
await as('quality');await start();await finish('delivery','delivery',{inspection:'Aprovado após reinspeção'});await as('delivery');await start();
await fail(()=>finish('completed',null),/obrigatório/,'entrega exige confirmação de recebimento');
d=await current();const req=crypto.randomUUID(),payload={confirmed:true,delivered_date:'2026-01-10',received_by:'Cliente Teste',delivery_reference:'Recibo 001'};
const version=await rpc('finish',[id,d.version,'completed',null,'Entrega recebida pelo cliente',req,payload]);
ok(await rpc('finish',[id,d.version,'completed',null,'Entrega recebida pelo cliente',req,payload])===version,'repetição de finalização é idempotente');
d=await current();ok(d.status==='completed'&&!d.can_edit&&!d.execution,'conclusão encerra execução e bloqueia edição');
ok(d.cycles.filter(c=>c.stage==='quality').length===2,'inspeções anteriores preservadas');
await fail(()=>rpc('start',[id,d.version]),/Sem permissão/,'pedido encerrado não reinicia');
await fail(()=>rpc('stage_save',[id,d.version,{notes:'alterar'}]),/Sem permissão/,'pedido encerrado não aceita escrita');
await as('admin');await fail(()=>rpc('assign',[id,d.version,users.delivery,'Transferir pedido concluído']),/encerrado/,'gestão não transfere concluído');
ok((await rpc('board_v2',['',null,null,null,'completed'])).cards.some(c=>c.id===id),'concluído consultável no quadro');
ok(!(await rpc('board_v2')).cards.some(c=>c.id===id),'concluído sai da carteira aberta');
await as('sales');const refused=crypto.randomUUID();await rpc('save_demand',[refused,0,draft]);await rpc('start',[refused,1]);await rpc('finish',[refused,2,'design',users.design,'Analisar viabilidade',crypto.randomUUID(),{confirmed:true}]);
await as('design');await rpc('start',[refused,3]);await rpc('finish',[refused,4,'rejected',null,'Inviável tecnicamente',crypto.randomUUID(),{confirmed:true,decision_date:'2026-01-03'}]);
ok((await rpc('board_v2',['',null,null,null,'rejected'])).cards.some(c=>c.id===refused),'recusado consultável');
await fail(()=>rpc('finish',[refused,5,'sales',users.sales,'Reabrir com revisão',crypto.randomUUID(),{confirmed:true}]),/Somente gestão/,'reabertura exige gestão');
await as('admin');await rpc('finish',[refused,5,'sales',users.sales,'Reabrir com revisão',crypto.randomUUID(),{confirmed:true}]);
d=await rpc('detail',[refused]);ok(d.status==='open'&&d.stage==='sales'&&!d.technical_complete,'reabertura inicia novo levantamento sem apagar recusa');
await fail(()=>rpc('finish',[refused,null,'design',users.design,'Tentar versão nula',crypto.randomUUID(),{confirmed:true}]),/Conflito/,'versão nula bloqueada');
await fail(()=>rpc('transition',[refused,6,'design',users.design,'Cliente antigo',crypto.randomUUID()]),/Atualize/,'cliente antigo não contorna novos requisitos');

// Regressão das demais devoluções: cada retorno cria um novo ciclo.
async function move(target,p={}){
 let d=await rpc('detail',[refused]);
 if(d.stage==='sales'&&!d.technical_complete){await rpc('save_demand',[refused,d.version,draft]);d=await rpc('detail',[refused]);}
 if(!d.execution?.started_at){await rpc('start',[refused,d.version]);d=await rpc('detail',[refused]);}
 await rpc('finish',[refused,d.version,target,['rejected','completed'].includes(target)?null:users.admin,'Decisão registrada no teste',crypto.randomUUID(),{...proposal,...approval,op_number:'OP-2',issue_date:'2026-01-03',materials:'Materiais conferidos',...p,confirmed:true}]);
}
for(const target of ['design','design','sales','design','quotation','design','quotation','approval','design','quotation','approval','op','design','quotation','approval','op','warehouse','op','warehouse'])await move(target);
ok((await rpc('detail',[refused])).cycles.length>20,'revisões e devoluções de todas as etapas preservam ciclos');
let before=await rpc('detail',[refused]);
await fail(()=>rpc('stage_save',[refused,before.version,{expected_date:'2026-02-31'}]),/date|range/i,'data inexistente rejeitada');
ok((await rpc('detail',[refused])).version===before.version,'validação falha sem gravação parcial');
await as('sales');await fail(()=>rpc('stage_save',[refused,before.version,{observations:'Acesso indevido'}]),/Sem permissão/,'vendedor não edita etapa atribuída à gestão');
await as('admin');await move('op');await move('design');await move('quotation');await move('approval');await move('rejected',{decision_date:'2026-01-04'});
ok((await rpc('detail',[refused])).status==='rejected','recusa do cliente encerra e preserva proposta');
await db.exec('reset role');await db.exec(await readFile(new URL('../supabase/migrations/202610090006_complete_workflow.sql',import.meta.url),'utf8'));await as('admin');ok((await current()).status==='completed','reaplicar SQL preserva conclusão');
await db.exec('reset role;set role anon');await fail(()=>rpc('board_v2'),/permission denied/,'anônimo sem acesso');
await db.close();console.log(`${count} verificações do fluxo completo passaram.`);

