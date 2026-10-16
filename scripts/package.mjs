import {readFile,writeFile,mkdir} from 'node:fs/promises';
await mkdir('supabase/install',{recursive:true});
const files=['202610090001_foundation.sql','202610090002_catalog.sql'];
const migrations=await Promise.all(files.map(f=>readFile('supabase/migrations/'+f,'utf8')));
// Um único COMMIT permite desfazer a instalação inteira se o catálogo falhar.
await writeFile('supabase/install/FASE-1-INSTALAR.sql','-- Instalação Fase 1: execute uma vez, após backup e leitura de INSTALACAO.md.\n'+migrations.map((s,i)=>i===0?s.replace(/commit;\s*$/i,''):s.replace(/^begin;\s*/i,'')).join('\n'));
console.log('SQL de instalação gerado sem segredos.');
const upgrade=await readFile('supabase/migrations/202610090003_free_interview.sql','utf8');
await writeFile('supabase/install/VERSAO-2-ATUALIZAR.sql',upgrade);
const flow=await readFile('supabase/migrations/202610090004_design_quotation.sql','utf8');
await writeFile('supabase/install/VERSAO-2-1-CORRIGIR-FLUXO.sql',flow);
const approval=await readFile('supabase/migrations/202610090005_quotation_approval.sql','utf8');
await writeFile('supabase/install/VERSAO-2-2-CORRIGIR-ORCAMENTO.sql',approval);
const complete=await readFile('supabase/migrations/202610090006_complete_workflow.sql','utf8');
await writeFile('supabase/install/VERSAO-2-3-FLUXO-COMPLETO.sql',complete);
const clean=s=>s.replace(/^\uFEFF/,'').replace(/^begin;\s*$/im,'').replace(/^commit;\s*$/im,'');
await writeFile('supabase/install/VERSAO-2-INSTALAR-DO-ZERO.sql','-- Somente para banco SEM schema kanban. Para banco existente use VERSAO-2-ATUALIZAR.sql.\nbegin;\n'+[...migrations,upgrade,flow,approval,complete].map(clean).join('\n')+'\ncommit;\n');
console.log('Versão 2: atualização preservando dados e instalação nova geradas.');

const storage=await readFile('supabase/migrations/20261016125041_temporary_document_storage.sql','utf8');
await writeFile('supabase/install/VERSAO-2-4-DOCUMENTOS.sql',storage);
console.log('SQL incremental 2.4 gerado. Aplicar somente sobre 2.3 validada.');

await writeFile('supabase/install/VERSAO-2-5-ENTREVISTAS.sql',await readFile('supabase/migrations/20261016133521_interview_library.sql','utf8'));
