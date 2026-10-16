import {supabase} from '../api';
import type {StorageAdapter,DocumentRecord} from './types';
export class SupabaseStorageAdapter implements StorageAdapter{
 async uploadDocument(d:DocumentRecord,file:Blob){const {error}=await supabase.storage.from(d.bucket_name).upload(d.storage_path,await file.arrayBuffer(),{contentType:d.mime_type,upsert:false,cacheControl:'0'});if(error)throw new Error('Não foi possível confirmar o envio. Selecione o mesmo arquivo para retomar.');}
 async downloadDocument(d:DocumentRecord){const {data,error}=await supabase.storage.from(d.bucket_name).download(d.storage_path);if(error||!data)throw new Error('Arquivo indisponível ou acesso não autorizado.');return data;}
}
// O backend Google, quando autorizado, recebe apenas o ID interno; nunca um caminho arbitrário.
export class GoogleDriveStorageAdapter implements StorageAdapter{
 async uploadDocument(_d:DocumentRecord,_file:Blob):Promise<void>{throw new Error('Uploads Google aguardam a autorização da integração central.');}
 async downloadDocument(d:DocumentRecord){const {data,error}=await supabase.functions.invoke('documents-drive',{body:{document_id:d.id}});if(error||!(data instanceof Blob))throw new Error('Integração Google não conectada ou documento indisponível.');return data;}
}
