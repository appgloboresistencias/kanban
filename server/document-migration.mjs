import {createHash,randomUUID} from 'node:crypto';
export const checksum=bytes=>createHash('sha256').update(bytes).digest('hex');
// Repositório é backend-only. O destino deve reutilizar o ID reservado em qualquer repetição.
export async function migrateDocument(id,{repository,source,target,actor}){
 const token=randomUUID();let job=await repository.step(id,'claim',token,actor);if(job.done)return job;
 const d=job.document;
 try{
 const bytes=await source.download(d);
 if(bytes.length!==d.size_bytes||checksum(bytes)!==d.checksum)throw new Error('Integridade da origem divergente.');
 let targetId=job.checkpoint.target_id;
 if(!targetId){targetId=await target.reserveId();job=await repository.step(id,'target',token,actor,{target:targetId});}
 // Um crash após a cópia não gera um segundo arquivo. O destino é sempre o mesmo ID.
 let copied=await target.readIfExists(targetId);
 if(!copied){await target.upload(targetId,bytes,d);copied=await target.readIfExists(targetId);}
 await repository.step(id,'copied',token,actor);
 if(!copied||copied.length!==d.size_bytes||checksum(copied)!==d.checksum)throw new Error('Integridade do destino divergente.');
 await repository.step(id,'validated',token,actor,{hash:checksum(copied),size:copied.length});
 return await repository.step(id,'complete',token,actor);
 }catch(error){try{await repository.step(id,'fail',token,actor,{error:String(error.message)});}catch{}throw error;}
}
export class SupabaseMigrationRepository{
 constructor(client){this.client=client;}
 async step(id,action,token,actor,data={}){const {data:result,error}=await this.client.rpc('kb_document_migration',{p_id:id,p_action:action,p_token:token,p_actor:actor,p_target:data.target||null,p_hash:data.hash||null,p_size:data.size??null,p_error:data.error||null});if(error)throw new Error(error.message);return result;}
}
