// Publicar apenas quando a conta Google estiver autorizada. Nenhum segredo vai ao navegador.
import {createClient} from 'npm:@supabase/supabase-js@2.117.3';
Deno.serve(async req=>{
 const origin=req.headers.get('origin')||'';const allowed=(Deno.env.get('ALLOWED_ORIGINS')||'https://royal-tree-dc12.appgloboresistencias.workers.dev').split(',');
 const headers={'Access-Control-Allow-Origin':allowed.includes(origin)?origin:allowed[0],'Access-Control-Allow-Headers':'authorization,apikey,x-client-info,content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store','Vary':'Origin'};
 if(origin&&!allowed.includes(origin))return new Response('Origin denied',{status:403,headers});if(req.method==='OPTIONS')return new Response(null,{headers});if(req.method!=='POST')return new Response(null,{status:405,headers});
 try{
 const auth=req.headers.get('Authorization')||'';if(!auth.startsWith('Bearer '))return new Response(null,{status:401,headers});
 const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});
 const {error:userError}=await client.auth.getUser(auth.slice(7));if(userError)return new Response(null,{status:401,headers});
 const {document_id}=await req.json();const {data:d,error}=await client.rpc('kb_document_get',{p_id:document_id});
 if(error||!d||!['ready','archived'].includes(d.status)||d.storage_provider!=='google_drive'||!d.google_drive_file_id)return new Response('Documento indisponível',{status:403,headers});
 const token=await fetch('https://oauth2.googleapis.com/token',{method:'POST',body:new URLSearchParams({grant_type:'refresh_token',client_id:Deno.env.get('GOOGLE_CLIENT_ID')||'',client_secret:Deno.env.get('GOOGLE_CLIENT_SECRET')||'',refresh_token:Deno.env.get('GOOGLE_REFRESH_TOKEN')||''})});
 if(!token.ok)return new Response('Integração Google indisponível',{status:503,headers});const {access_token}=await token.json();
 const file=await fetch('https://www.googleapis.com/drive/v3/files/'+encodeURIComponent(d.google_drive_file_id)+'?alt=media',{headers:{Authorization:'Bearer '+access_token}});
 if(!file.ok)return new Response('Arquivo indisponível',{status:502,headers});return new Response(file.body,{headers:{...headers,'Content-Type':'application/octet-stream','X-Content-Type-Options':'nosniff'}});
 }catch{return new Response('Falha ao consultar documento',{status:400,headers});}
});
