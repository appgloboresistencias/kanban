import {useState,useRef} from 'react';
import {rpc} from './api';
import type {Bootstrap,Detail} from './types';
import {stageActions,stageFields,type StageData} from './workflow';
export function StageWorkflow({detail:d,boot,onReload,onDirty}:{detail:Detail;boot:Bootstrap;onReload:()=>Promise<void>;onDirty:(v:boolean)=>void}){
const manager=boot.roles.some(r=>r==='admin'||r==='manager');
const actions=d.status==='rejected'&&manager?[['sales','Reabrir orçamento → Vendas']]:d.status==='open'?(stageActions[d.stage]||[]):[];
const [target,setTarget]=useState(actions.some(a=>a[0]===d.execution?.data.selected_action)?String(d.execution?.data.selected_action):actions[0]?.[0]||''),[data,setData]=useState<StageData>({blocked:false,...d.execution?.data}),[assignee,setAssignee]=useState(String(d.execution?.data.next_assignee||'')),[reason,setReason]=useState(String(d.execution?.data.decision_reason||'')),[error,setError]=useState(''),[busy,setBusy]=useState(false);
const request=useRef(crypto.randomUUID());const editable=d.can_edit||(d.status==='rejected'&&manager);
function change(k:string,v:string|boolean){setData(x=>({...x,[k]:v,...(k!=='confirmed'?{confirmed:false}:{})}));request.current=crypto.randomUUID();onDirty(true);}
async function run(fn:()=>Promise<unknown>){setBusy(true);setError('');try{await fn();onDirty(false);await onReload();}catch(e){setError(e instanceof Error?e.message:'Não foi possível concluir.');}finally{setBusy(false);}}
const terminal=target==='completed'||target==='rejected';const role=boot.stages.find(s=>s.code===target)?.role;
const fields=target==='rejected'?[{key:'decision_date',label:'Data da recusa / decisão',type:'date' as const}]:stageFields[d.stage]||[];
return <section className="stage-workflow">
{error&&<div className="error" role="alert">{error}</div>}
{d.status!=='open'&&<div className="notice">{d.status==='completed'?'Pedido concluído.':'Orçamento recusado.'} Histórico e registros preservados.</div>}
{d.materials_pending&&<div className="pending-list"><strong>Material parcial — pendência aberta</strong><p>{d.materials_pending.description}</p><p>Previsão: {d.materials_pending.expected_date}</p>{d.status==='open'&&boot.roles.some(r=>['admin','manager','warehouse'].includes(r))&&<form onSubmit={e=>{e.preventDefault();const f=new FormData(e.currentTarget);void run(()=>rpc('materials_resolve',{p_id:d.id,p_version:d.version,p_reason:f.get('resolution')}));}}><label>Regularização dos materiais<input name="resolution" required minLength={5}/></label><button disabled={busy}>Confirmar material completo</button></form>}</div>}
{d.rework_count>0&&<p className="tag">Ciclos de retrabalho: {d.rework_count}</p>}
{editable&&actions.length>0&&<form onSubmit={e=>{e.preventDefault();void run(()=>rpc('finish',{p_id:d.id,p_version:d.version,p_target:target,p_assignee:terminal?null:assignee,p_reason:reason,p_request:request.current,p_data:data}));}}>
<h3>Conclusão da etapa</h3><label>Ação da etapa<select aria-label="Ação da etapa" value={target} disabled={busy} onChange={e=>{setTarget(e.target.value);setAssignee('');setData(x=>({...x,next_assignee:''}));change('selected_action',e.target.value);}}>{actions.map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></label>
<fieldset disabled={busy}>
{fields.map(f=><label key={f.key} className={f.type==='check'?'check':undefined}>{f.type==='check'?<><input type="checkbox" checked={data[f.key]===true} onChange={e=>change(f.key,e.target.checked)}/>{f.label}</>:<><span>{f.label}</span>{f.type==='area'?<textarea aria-label={f.label} rows={3} maxLength={8000} value={String(data[f.key]||'')} onChange={e=>change(f.key,e.target.value)}/>:f.type==='select'?<select aria-label={f.label} value={String(data[f.key]||'')} onChange={e=>change(f.key,e.target.value)}><option value="">Selecione</option>{f.options?.map(([v,l])=><option key={v} value={v}>{l}</option>)}</select>:<input aria-label={f.label} type={f.type==='date'?'date':'text'} maxLength={2000} value={String(data[f.key]||'')} onChange={e=>change(f.key,e.target.value)}/>}</>}</label>)}
<label>Observações da etapa<textarea aria-label="Observações da etapa" value={String(data.observations||'')} maxLength={8000} onChange={e=>change('observations',e.target.value)}/></label>
{d.status==='open'&&<button type="button" className="secondary" disabled={busy} onClick={()=>void run(()=>rpc('stage_save',{p_id:d.id,p_version:d.version,p_data:data}))}>Salvar dados da etapa</button>}
{!terminal&&<label>Responsável pela próxima etapa<select aria-label="Responsável pela próxima etapa" required value={assignee} onChange={e=>{setAssignee(e.target.value);change('next_assignee',e.target.value);}}><option value="">Selecione</option>{boot.people.filter(p=>p.roles.some(r=>r===role||r==='admin'||r==='manager')).map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select></label>}
<label>Justificativa<textarea aria-label="Justificativa" required minLength={5} maxLength={4000} value={reason} onChange={e=>{setReason(e.target.value);change('decision_reason',e.target.value);}}/></label>
<label className="check"><input type="checkbox" required checked={data.confirmed===true} onChange={e=>change('confirmed',e.target.checked)}/>Confirmo os registros e a decisão selecionada</label>
<button disabled={busy||(d.status==='open'&&!d.execution?.started_at)||(d.stage==='sales'&&d.missing.length>0)}>Confirmar movimentação</button>
{d.status==='open'&&!d.execution?.started_at&&<p className="hint">Inicie a atividade antes de concluir a etapa.</p>}
{d.stage==='warehouse'&&<p className="hint">Material parcial só pode ser liberado por Gestor ou Administrador. Salve a pendência enquanto aguarda autorização.</p>}
</fieldset></form>}
<details className="legacy-interview"><summary>Consultar ciclos das etapas ({d.cycles.length})</summary>{d.cycles.map(c=><article key={c.id}><h4>{boot.stages.find(s=>s.code===c.stage)?.name} · {c.completed_at?'Finalizado':'Em andamento'}</h4><p>{boot.people.find(p=>p.id===c.assignee_id)?.name||'Responsável registrado'} · {new Date(c.entered_at).toLocaleString('pt-BR')}{c.completed_at&&<> · Conclusão: {new Date(c.completed_at).toLocaleString('pt-BR')}</>}</p><dl>{Object.entries(c.data||{}).map(([k,v])=><div key={k}><dt>{[...Object.values(stageFields).flat(),{key:'confirmed',label:'Conferência'},{key:'observations',label:'Observações'},{key:'selected_action',label:'Destino selecionado'},{key:'decision_reason',label:'Justificativa'},{key:'next_assignee',label:'Responsável escolhido'},{key:'decision_date',label:'Data da decisão'}].find(f=>f.key===k)?.label||k}</dt><dd>{typeof v==='boolean'?(v?'Sim':'Não'):v}</dd></div>)}</dl></article>)}</details>
</section>;
}
