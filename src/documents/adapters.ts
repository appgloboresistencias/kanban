import {supabase} from '../api';
import type {StorageAdapter,DocumentRecord} from './types';
export class SupabaseStorageAdapter implements StorageAdapter{
 async uploadDocument(d:DocumentRecord,file:Blob){const {error}=await supabase.storage.from(d.bucket_name).upload(d.storage_path,await file.arrayBuffer(),{contentType:d.mime_type,upsert:false,cacheControl:'0'});if(error)throw new Error('Não foi possível confirmar o envio. Selecione o mesmo arquivo para retomar.');}
 async downloadDocument(d:DocumentRecord){const {data,error}=await supabase.storage.from(d.bucket_name).download(d.storage_path);if(error||!data)throw new Error('Arquivo indisponível ou acesso não autorizado.');return data;}
}
