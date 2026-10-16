import {createClient} from '@supabase/supabase-js';import {migrateDocument,SupabaseMigrationRepository} from './document-migration.mjs';import {GoogleDriveMigrationAdapter} from './google-drive-migration.mjs';
const [documentId,adminId,confirmation]=process.argv.slice(2);
if(confirmation!=='--confirm-migration'||!documentId||!adminId)throw new Error('Uso: node server/migrate-cli.mjs DOCUMENT_UUID ADMIN_UUID --confirm-migration. Execute somente após homologar OAuth, proxy e backup.');
for(const key of ['SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','GOOGLE_CLIENT_ID','GOOGLE_CLIENT_SECRET','GOOGLE_REFRESH_TOKEN','GOOGLE_FOLDER_ID'])if(!process.env[key])throw new Error('Configuração de backend ausente: '+key);
const client=createClient(process.env.SUPABASE_URL,process.env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
const source={download:async d=>{const {data,error}=await client.storage.from(d.bucket_name).download(d.storage_path);if(error)throw new Error('Original não pôde ser lido.');return Buffer.from(await data.arrayBuffer());}};
const target=new GoogleDriveMigrationAdapter({clientId:process.env.GOOGLE_CLIENT_ID,clientSecret:process.env.GOOGLE_CLIENT_SECRET,refreshToken:process.env.GOOGLE_REFRESH_TOKEN,folderId:process.env.GOOGLE_FOLDER_ID});
const result=await migrateDocument(documentId,{source,target,repository:new SupabaseMigrationRepository(client),actor:adminId});console.log(JSON.stringify({document_id:documentId,state:result.document.migration_status,original_preserved:true}));
