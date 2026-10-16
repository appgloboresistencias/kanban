import {storageFixture} from './storage-fixture.mjs';
// Teste local: autenticação simulada; todas as RPCs executam SQL real em PGlite.
// Nenhum pedido ou credencial de produção é usado.
import {PGlite} from '@electric-sql/pglite';
import {chromium} from 'playwright';
import {readFile,mkdir} from 'node:fs/promises';
import assert from 'node:assert/strict';
const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}');create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;`);
await storageFixture(db);
for(const f of ['202610090001_foundation.sql','202610090002_catalog.sql','202610090003_free_interview.sql','202610090004_design_quotation.sql','202610090005_quotation_approval.sql','202610090006_complete_workflow.sql','20261016125041_temporary_document_storage.sql'])await db.exec(await readFile(new URL('../supabase/migrations/'+f,import.meta.url),'utf8'));
const uid='11111111-1111-4111-8111-111111111111';
const designer='44444444-4444-4444-8444-444444444444';
await db.exec(`insert into auth.users(id,email,raw_user_meta_data) values('${uid}','teste@example.test','{"name":"Vendedor Teste"}'),('${designer}','projeto@example.test','{"name":"Projetista Teste"}');update kanban.profiles set active=true;insert into kanban.user_roles values('${uid}','admin'),('${uid}','estimator'),('${uid}','sales'),('${uid}','design'),('${designer}','design'),('${designer}','estimator');set role authenticated;select set_config('request.jwt.claim.sub','${uid}',false);`);
await mkdir(new URL('../tmp/',import.meta.url),{recursive:true});
const browser=await chromium.launch({headless:true,executablePath:process.env.TEST_CHROMIUM_PATH||undefined});const page=await browser.newPage({viewport:{width:1440,height:1000}});let driveCalls=0;const errors=[];
page.on('pageerror',e=>errors.push(e.message));
page.on('request',r=>{if(/googleapis\.com\/(?:drive|upload)/.test(r.url()))driveCalls++;});
const storedFiles=new Map();let physicalLists=0,failUpload=process.env.TEST_DOCUMENTS==='1';
await page.route('https://nwxjntiysbwqwwwpazrd.supabase.co/**',async route=>{
const url=new URL(route.request().url());let body={};let status=200;
if(url.pathname.startsWith('/auth/v1/')){
const user={id:uid,email:'teste@example.test',aud:'authenticated',role:'authenticated',app_metadata:{provider:'email'},user_metadata:{name:'Vendedor Teste'},created_at:new Date().toISOString()};
body=url.pathname.includes('/token')?{access_token:'fixture-session',token_type:'bearer',refresh_token:'fixture-refresh',expires_in:3600,user}:user;
}else if(url.pathname.startsWith('/rest/v1/rpc/kb_')){
const name=url.pathname.split('/').at(-1);const args=route.request().postDataJSON()||{};
try {body=(await db.query(`select public.${name}(${Object.keys(args).map((k,i)=>`${k} => $${i+1}`).join(',')}) result`,Object.values(args))).rows[0].result;}catch(e){status=400;body={code:e.code||'P0001',message:e.message};}
 }else if(url.pathname.startsWith('/storage/v1/')){
 if(url.pathname.includes('/list/'))physicalLists++;
 const objectPath=decodeURIComponent(url.pathname.replace(/^\/storage\/v1\/object\/(authenticated\/)?/,''));const slash=objectPath.indexOf('/');const bucket=objectPath.slice(0,slash),name=objectPath.slice(slash+1);
 if(route.request().method()==='POST'){
 if(failUpload){failUpload=false;await route.abort('failed');return;}
 const request=new Request('http://fixture.local',{method:'POST',headers:route.request().headers(),body:route.request().postDataBuffer()});const file=route.request().headers()['content-type']?.includes('multipart/form-data')?[...(await request.formData()).values()].find(v=>typeof v!=='string'):new Blob([route.request().postDataBuffer()],{type:route.request().headers()['content-type']});
 try{await db.query('insert into storage.objects(bucket_id,name,metadata) values($1,$2,$3)',[bucket,name,{size:file.size,mimetype:file.type}]);storedFiles.set(objectPath,Buffer.from(await file.arrayBuffer()));body={Key:objectPath,Id:crypto.randomUUID()};}catch(e){status=400;body={message:e.message};}
 }else{const allowed=await db.query('select name from storage.objects where bucket_id=$1 and name=$2',[bucket,name]);if(allowed.rows.length&&storedFiles.has(objectPath)){await route.fulfill({status:200,contentType:'application/octet-stream',body:storedFiles.get(objectPath)});return;}status=404;body={message:'not found'};}
 }else {status=404;body={};}
await route.fulfill({status,contentType:'application/json',body:JSON.stringify(body)});
});
try{
await page.goto(process.env.TEST_URL||'http://127.0.0.1:4174');
await page.getByLabel('E-mail',{exact:true}).fill('teste@example.test');await page.getByLabel('Senha',{exact:true}).fill('fixture-password');await page.getByRole('button',{name:'Entrar no sistema'}).click();
await page.getByRole('button',{name:'Clientes',exact:false}).click();await page.getByRole('button',{name:'Cadastrar cliente'}).click();
await page.getByLabel('Razão social').fill('Metalúrgica Horizonte');await page.getByLabel('Contato *',{exact:true}).fill('Contato Teste');await page.getByLabel('CPF/CNPJ').fill('11222333000181');await page.getByRole('button',{name:'Salvar cliente',exact:true}).click();
await page.getByRole('cell',{name:'Metalúrgica Horizonte',exact:true}).waitFor();
await page.getByRole('button',{name:'Quadro de demandas'}).click();await page.getByRole('button',{name:'Novo orçamento'}).click();
await page.getByLabel('Nome da demanda').fill('Resistência para extrusora');
const customer=(await db.query('select id from kanban.customers')).rows[0].id;
await page.getByLabel('Cliente *',{exact:true}).selectOption(customer);
assert.equal(await page.getByRole('button',{name:'Tipos de resistência'}).count(),0);
assert.equal(await page.getByLabel('Tipo de resistência').count(),0);
assert.equal(await page.getByLabel('Tensão').count(),0);
const notes='Cliente solicita resistência para extrusora.\nMedidas e aplicação registradas conforme entrevista no PDF.\nPrazo e detalhes ainda em levantamento.';
await page.getByLabel('Levantamento técnico / informações do cliente').fill(notes);
if(process.env.TEST_DOCUMENTS!=='1')await page.getByLabel('Link externo do PDF (opcional se anexado)').fill('https://drive.google.com/file/d/0123456789abcdef/view');
await page.getByLabel('Nome ou versão do PDF').fill('Entrevista do cliente — revisão 02.pdf');
if(process.env.TEST_DOCUMENTS!=='1')assert.equal(await page.getByRole('link',{name:'Abrir PDF de referência'}).getAttribute('href'),'https://drive.google.com/file/d/0123456789abcdef/view');
await page.screenshot({path:new URL('../tmp/versao-2-levantamento.png',import.meta.url).pathname.replace(/^\/([A-Za-z]:)/,'$1'),fullPage:true});
await page.getByRole('button',{name:'Salvar levantamento'}).click();
await page.getByText('Salvo no Supabase · versão 1',{exact:true}).waitFor();
await page.getByRole('button',{name:'Fechar painel'}).click();
await page.locator('button.card').waitFor();
assert.match(await page.locator('button.card').innerText(),/Resistência para extrusora/);
await page.screenshot({path:new URL('../tmp/kanban-desktop.png',import.meta.url).pathname.replace(/^\/([A-Za-z]:)/,'$1'),fullPage:true});
await page.reload();await page.locator('button.card').click();
assert.equal(await page.getByLabel('Nome da demanda').inputValue(),'Resistência para extrusora');
assert.equal(await page.getByLabel('Levantamento técnico / informações do cliente').inputValue(),notes);

if(process.env.TEST_DOCUMENTS==='1'){
await page.getByRole('button',{name:'Documentos',exact:true}).click();
await page.getByLabel('Tipo de documento',{exact:true}).selectOption('interview');
const pdf={name:'entrevista.pdf',mimeType:'application/pdf',buffer:Buffer.from('%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\n%%EOF')};
await page.getByLabel('Selecionar arquivos').setInputFiles(pdf);await page.getByRole('button',{name:'Enviar documentos',exact:true}).click();await page.getByRole('alert').waitFor();
await page.getByLabel('Selecionar arquivos').setInputFiles(pdf);await page.getByRole('button',{name:'Enviar documentos',exact:true}).click();await page.getByText('Arquivos armazenados e confirmados.',{exact:true}).waitFor();
assert.equal((await db.query('select count(*)::int n from kanban.documents')).rows[0].n,1);
await page.getByLabel('Tipo de documento',{exact:true}).selectOption('other');
const photo={name:'foto.png',mimeType:'image/png',buffer:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jB1sAAAAASUVORK5CYII=','base64')};
const docx={name:'texto.docx',mimeType:'application/vnd.openxmlformats-officedocument.wordprocessingml.document',buffer:await readFile('tests/fixtures/texto.docx')};
const xlsx={name:'planilha.xlsx',mimeType:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',buffer:await readFile('tests/fixtures/planilha.xlsx')};
await page.getByLabel('Selecionar arquivos').setInputFiles([photo,docx,xlsx]);await page.getByRole('button',{name:'Enviar documentos',exact:true}).click();await page.getByText('Arquivos armazenados e confirmados.',{exact:true}).waitFor();
assert.equal(await page.locator('.document-item').count(),4);
const photoCard=page.locator('.document-item').filter({has:page.getByText('foto.png',{exact:true})});
await photoCard.getByRole('button',{name:'Visualizar',exact:true}).click();await page.locator('.document-preview img').waitFor();await page.getByRole('button',{name:'Fechar prévia'}).click();
const downloadEvent=page.waitForEvent('download');await photoCard.getByRole('button',{name:'Baixar',exact:true}).click();const download=await downloadEvent;assert.equal(download.suggestedFilename(),'foto.png');
await photoCard.getByRole('button',{name:'Arquivar',exact:true}).click();await page.getByLabel('Motivo do arquivamento').fill('Imagem de teste substituída');await page.getByRole('button',{name:'Confirmar arquivamento'}).click();await photoCard.waitFor({state:'detached'});
await page.getByLabel('Mostrar documentos arquivados').check();await photoCard.waitFor();
await page.screenshot({path:'tmp/documentos-desktop.png',fullPage:true});await page.setViewportSize({width:390,height:844});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.screenshot({path:'tmp/documentos-mobile.png',fullPage:true});await page.setViewportSize({width:1440,height:1000});
assert.equal(physicalLists,0);await page.getByRole('button',{name:'Levantamento',exact:true}).click();
}
let version=1;
async function saved(){version++;await page.getByText('Salvo no Supabase · versão '+version,{exact:true}).waitFor();}
async function start(){await page.getByRole('button',{name:'Iniciar atividade'}).click();await saved();}
async function finish(target,fields={}){
 await page.getByLabel('Ação da etapa',{exact:true}).selectOption(target);
 for(const [label,value] of Object.entries(fields)){const el=page.getByLabel(label,{exact:true});if(typeof value==='boolean')await el.setChecked(value);else if(label==='Situação dos materiais')await el.selectOption(value);else await el.fill(value);}
 if(!['completed','rejected'].includes(target))await page.getByLabel('Responsável pela próxima etapa',{exact:true}).selectOption(uid);
 await page.getByLabel('Justificativa',{exact:true}).fill('Etapa conferida e concluída no teste.');
 await page.getByLabel('Confirmo os registros e a decisão selecionada',{exact:true}).check();
 await page.getByRole('button',{name:'Confirmar movimentação',exact:true}).click();await saved();
}
await page.getByRole('button',{name:'Etapa atual',exact:true}).click();
assert.equal(await page.getByRole('button',{name:'Confirmar movimentação'}).isDisabled(),true);
await start();
await page.getByRole('button',{name:'Levantamento',exact:true}).click();await page.getByLabel('Confirmo que concluí o levantamento técnico').check();await page.getByRole('button',{name:'Salvar levantamento'}).click();await saved();
await page.getByRole('button',{name:'Etapa atual',exact:true}).click();await finish('design');
await start();await finish('quotation');await start();
await page.getByLabel('Versão da proposta',{exact:true}).fill('R1');await page.getByRole('button',{name:'Salvar dados da etapa'}).click();await saved();assert.equal(await page.getByLabel('Versão da proposta',{exact:true}).inputValue(),'R1');
await finish('approval',{'Versão da proposta':'R1','Data de envio ao cliente':'2026-01-01','Validade da proposta':'2026-12-31','Confirmo que a proposta foi enviada ao cliente':true});
await start();
await page.screenshot({path:'tmp/fluxo-aprovacao.png',fullPage:true});
await finish('op',{'Versão aprovada':'R1','Data da aprovação do cliente':'2026-01-02','Meio de aprovação (e-mail, telefone, etc.)':'E-mail','Referência da comunicação / evidência':'Mensagem ABC','Prazo de entrega acordado':'2026-12-31','O cliente aprovou esta versão da proposta':true,'Conferi a aprovação e autorizo internamente esta versão':true});
await start();await finish('warehouse',{'Número oficial da OP no ERP':'OP-123','Data de emissão da OP':'2026-01-03','Lista de materiais / referência no Drive':'Aço e cabos conferidos'});
await start();await finish('production',{'Situação dos materiais':'total'});
await start();await finish('quality',{'Serviço executado / retrabalho':'Produzido e testado'});
await start();await finish('production',{'Resultado da inspeção / não conformidade':'Reprovado: ajustar conexão'});
await start();await finish('quality',{'Serviço executado / retrabalho':'Conexão refeita'});
await start();await finish('delivery',{'Resultado da inspeção / não conformidade':'Aprovado após reinspeção'});
await start();await finish('completed',{'Data efetiva da entrega':'2026-01-10','Recebido por':'Cliente Teste','Comprovante / referência da entrega':'Recibo 001'});
await page.getByText('Pedido concluído. Histórico e registros preservados.',{exact:true}).waitFor();assert.equal(await page.getByRole('button',{name:'Confirmar movimentação'}).count(),0);
await page.getByRole('button',{name:'Histórico',exact:true}).click();await page.locator('.timeline article').first().waitFor();if(!(await page.getByRole('heading',{name:'Orçamento aberto'}).count()))await page.getByRole('button',{name:'Carregar eventos anteriores'}).click();await page.getByRole('heading',{name:'Orçamento aberto'}).waitFor();
await page.getByRole('button',{name:'Fechar painel'}).click();
await page.getByLabel('Filtrar situação').selectOption('completed');await page.locator('button.card').waitFor();
await page.screenshot({path:'tmp/fluxo-concluidos.png',fullPage:true});
await page.setViewportSize({width:390,height:844});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'sem overflow horizontal');
await page.screenshot({path:'tmp/fluxo-mobile.png',fullPage:true});
assert.equal(driveCalls,0);assert.equal(physicalLists,0);assert.deepEqual(errors,[]);
console.log('PASS: fluxo completo no navegador, aprovação, rascunho por etapa, retrabalho, entrega, concluídos e histórico. Auth simulado; SQL real isolado.');
}finally{await browser.close();await db.close();}
