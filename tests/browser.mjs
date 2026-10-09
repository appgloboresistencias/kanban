// Teste local: autenticação simulada; todas as RPCs executam SQL real em PGlite.
// Nenhum pedido ou credencial de produção é usado.
import {PGlite} from '@electric-sql/pglite';
import {chromium} from 'playwright';
import {readFile,mkdir} from 'node:fs/promises';
import assert from 'node:assert/strict';
const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}');create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;`);
for(const f of ['202610090001_foundation.sql','202610090002_catalog.sql'])await db.exec(await readFile(new URL('../supabase/migrations/'+f,import.meta.url),'utf8'));
const uid='11111111-1111-4111-8111-111111111111';
await db.exec(`insert into auth.users(id,email,raw_user_meta_data) values('${uid}','teste@example.test','{"name":"Vendedor Teste"}');update kanban.profiles set active=true;insert into kanban.user_roles values('${uid}','sales');set role authenticated;select set_config('request.jwt.claim.sub','${uid}',false);`);
await mkdir(new URL('../tmp/',import.meta.url),{recursive:true});
const browser=await chromium.launch({headless:true,executablePath:process.env.TEST_CHROMIUM_PATH||undefined});const page=await browser.newPage({viewport:{width:1440,height:1000}});let driveCalls=0;const errors=[];
page.on('pageerror',e=>errors.push(e.message));
page.on('request',r=>{if(/googleapis\.com\/(?:drive|upload)/.test(r.url()))driveCalls++;});
await page.route('https://nwxjntiysbwqwwwpazrd.supabase.co/**',async route=>{
const url=new URL(route.request().url());let body={};let status=200;
if(url.pathname.startsWith('/auth/v1/')){
const user={id:uid,email:'teste@example.test',aud:'authenticated',role:'authenticated',app_metadata:{provider:'email'},user_metadata:{name:'Vendedor Teste'},created_at:new Date().toISOString()};
body=url.pathname.includes('/token')?{access_token:'fixture-session',token_type:'bearer',refresh_token:'fixture-refresh',expires_in:3600,user}:user;
}else if(url.pathname.startsWith('/rest/v1/rpc/kb_')){
const name=url.pathname.split('/').at(-1);const args=route.request().postDataJSON()||{};
try {body=(await db.query(`select public.${name}(${Object.keys(args).map((k,i)=>`${k} => $${i+1}`).join(',')}) result`,Object.values(args))).rows[0].result;}catch(e){status=400;body={code:e.code||'P0001',message:e.message};}
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
await page.getByLabel('Tipo de resistência').selectOption('bainha');
await page.getByLabel('Tipo de ligação').selectOption('Rabicho na espessura');
await page.getByLabel('Comprimento do rabicho').waitFor();
await page.getByRole('button',{name:'Salvar levantamento'}).click();
await page.getByText('Salvo no Supabase · versão 1',{exact:true}).waitFor();
await page.getByRole('button',{name:'Fechar painel'}).click();
await page.locator('button.card').waitFor();
assert.match(await page.locator('button.card').innerText(),/Resistência para extrusora/);
await page.screenshot({path:new URL('../tmp/kanban-desktop.png',import.meta.url).pathname.replace(/^\/([A-Za-z]:)/,'$1'),fullPage:true});
await page.reload();await page.locator('button.card').click();
assert.equal(await page.getByLabel('Nome da demanda').inputValue(),'Resistência para extrusora');
assert.equal(await page.getByLabel('Tipo de ligação').inputValue(),'Rabicho na espessura');
await page.getByRole('button',{name:'Etapa atual',exact:true}).click();
assert.equal(await page.getByRole('button',{name:'Confirmar movimentação'}).isDisabled(),true);
await page.getByRole('button',{name:'Iniciar atividade'}).click();await page.getByText('Salvo no Supabase · versão 2',{exact:true}).waitFor();
await page.getByRole('button',{name:'Histórico',exact:true}).click();await page.getByRole('heading',{name:'Orçamento aberto'}).waitFor();
await page.getByRole('button',{name:'Fechar painel'}).click();
await page.setViewportSize({width:390,height:844});
assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'sem overflow horizontal da página');
await page.screenshot({path:new URL('../tmp/kanban-mobile.png',import.meta.url).pathname.replace(/^\/([A-Za-z]:)/,'$1'),fullPage:true});
assert.equal(driveCalls,0);assert.deepEqual(errors,[]);
console.log('PASS: login simulado, cliente, campos condicionais, rascunho SQL, persistência ao recarregar, bloqueio de avanço, início de atividade, histórico, layout móvel, zero chamadas Drive e zero erros JS.');
}finally{await browser.close();await db.close();}
