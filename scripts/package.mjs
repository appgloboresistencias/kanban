import {readFile,writeFile,mkdir} from 'node:fs/promises';
await mkdir('supabase/install',{recursive:true});
const files=['202610090001_foundation.sql','202610090002_catalog.sql'];
const migrations=await Promise.all(files.map(f=>readFile('supabase/migrations/'+f,'utf8')));
// Um único COMMIT permite desfazer a instalação inteira se o catálogo falhar.
await writeFile('supabase/install/FASE-1-INSTALAR.sql','-- Instalação Fase 1: execute uma vez, após backup e leitura de INSTALACAO.md.\n'+migrations.map((s,i)=>i===0?s.replace(/commit;\s*$/i,''):s.replace(/^begin;\s*/i,'')).join('\n'));
console.log('SQL de instalação gerado sem segredos.');
