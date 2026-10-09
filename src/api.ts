import {createClient} from '@supabase/supabase-js';
const url=import.meta.env.VITE_SUPABASE_URL||'https://nwxjntiysbwqwwwpazrd.supabase.co';
const key=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY||'sb_publishable_xNLFYzJk9U1jBcdruVyFLA_55eh6XAY';
export const supabase=createClient(url,key,{auth:{storage:sessionStorage,persistSession:true,autoRefreshToken:true,detectSessionInUrl:true,flowType:'pkce'}});
export async function rpc<T>(name:string,args:Record<string,unknown>={}):Promise<T>{
const {data,error}=await supabase.rpc('kb_'+name,args);
if(error){if(error.code==='PGRST202'||error.code==='42883')throw new Error('A Fase 1 ainda não foi instalada neste Supabase. Solicite a instalação das migrations ao administrador.');
if(error.code==='23514'||error.code==='23502'||error.code==='22P02'||error.code==='22007')throw new Error('Confira os campos obrigatórios e o formato dos dados.');
if(error.code==='42501')throw new Error('Acesso não autorizado. Verifique a ativação do seu cadastro.');
throw new Error(error.code==='P0001'?error.message:'Não foi possível concluir a operação. Verifique sua conexão e tente novamente.');}return data as T;
}
