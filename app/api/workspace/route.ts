import {identity} from '../../../lib/supabase-server';
import {SECTIONS,completeness,rankReports,sampleReports,type Report} from '../../../lib/domain';
export const dynamic='force-dynamic';
export const runtime='nodejs';
const json=(v:unknown,status=200)=>Response.json(v,{status,headers:{'Cache-Control':'private, no-store'}});
function failure(e:unknown){const msg=e instanceof Error?e.message:'Unexpected error';return json({error:msg==='AUTH'?'Sign in to open your workspace.':msg},msg==='AUTH'?401:500)}
export async function GET(){try{
 const {supabase,user}=await identity();
 const [records,audits]=await Promise.all([supabase.from('omniscient_records').select('id,kind,data,revision').eq('owner',user.id).order('updated_at',{ascending:false}).limit(2000),supabase.from('omniscient_audits').select('id,actor,action,resource,created_at').eq('owner',user.id).order('created_at',{ascending:false}).limit(200)]);
 if(records.error||audits.error)return json({error:'Could not load the workspace. Please retry.'},500);
 return json({user:{name:user.user_metadata?.full_name||user.email,email:user.email},records:records.data.map(r=>({...r.data,id:r.id,kind:r.kind,revision:r.revision})),audits:audits.data});
}catch(e){return failure(e)}}
export async function POST(req:Request){try{
 if(req.headers.get('origin')!==new URL(req.url).origin)return json({error:'Invalid origin'},403);
 const {supabase,user}=await identity();const raw=await req.text();if(raw.length>350000)return json({error:'Request too large'},413);
 let b;try{b=JSON.parse(raw)}catch{return json({error:'Invalid JSON'},400)}
 if(b.op==='seed'){
  const reports=sampleReports();const tasks=[{id:crypto.randomUUID(),title:'Add peak-load checks for connection pool changes',reportId:reports[0].id,assignee:'Platform on-call',due:'2026-11-06',priority:'High',status:'Open'},{id:crypto.randomUUID(),title:'Add a dead letter queue for inventory events',reportId:reports[1].id,assignee:'Commerce team',due:'2026-10-31',priority:'High',status:'In progress'},{id:crypto.randomUUID(),title:'Separate bulk and incremental indexing queues',reportId:reports[2].id,assignee:'Search team',due:'2026-11-10',priority:'Medium',status:'Open'}];
  const {error}=await supabase.rpc('omniscient_seed',{p_reports:reports,p_tasks:tasks});return error?json({error:'Examples require an empty workspace. Refresh to see your records.'},409):json({ok:true});
 }
 if(b.op==='search'){
  if(typeof b.query!=='string'||b.query.length>2000)return json({error:'Enter a question under 2,000 characters.'},400);
  const {data,error}=await supabase.from('omniscient_records').select('data').eq('owner',user.id).eq('kind','report').limit(2000);if(error)return json({error:'Search unavailable'},500);
  const matches=rankReports(data.map(r=>r.data as Report),b.query);
  const audit=await supabase.rpc('omniscient_log_search',{p_query:b.query,p_documents:matches.map(x=>x.report.id)});if(audit.error)return json({error:'Could not record this query. Please retry.'},500);
  return json({matches,mode:'extractive',message:matches.length?'Matching evidence from your workspace. These are source excerpts, not an AI-generated answer.':"I don't have enough matching evidence. Try a service name or incident keyword."});
 }
 if(b.op!=='save'||!['report','task','team'].includes(b.kind)||!b.data||typeof b.data!=='object')return json({error:'Invalid operation'},400);
 const d=b.data;const id=d.id||crypto.randomUUID();if(typeof id!=='string'||!/^\w{8}-\w{4}-\w{4}-\w{4}-\w{12}$/.test(id))return json({error:'Invalid record identifier'},400);
 let data:any;
 if(b.kind==='report'){
  if(typeof d.title!=='string'||!d.title.trim()||d.title.length>200)return json({error:'A title of 1–200 characters is required.'},400);
  if(!['Public','Internal','Confidential','Restricted'].includes(d.label)||!['SEV 1','SEV 2','SEV 3','SEV 4'].includes(d.severity))return json({error:'Invalid severity or sensitivity'},400);
  const sections=Object.fromEntries(SECTIONS.map(s=>[s,typeof d.sections?.[s]==='string'?d.sections[s].slice(0,18000):'']));
  if(/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}|\b(?:ghp|github_pat)_[A-Za-z0-9_]{20,}/.test(JSON.stringify(d)))return json({error:'A possible credential was detected. Remove it before saving.'},400);
  data={id,title:d.title.trim(),service:String(d.service||'General').slice(0,100),team:String(d.team||'Platform').slice(0,100),label:d.label,severity:d.severity,date:/^\d{4}-\d{2}-\d{2}$/.test(d.date)?d.date:new Date().toISOString().slice(0,10),sections,status:d.status||'Draft'};
  if(!['Draft','In review','Changes requested'].includes(data.status))return json({error:'Independent approval is not configured.'},400);
  if(data.status==='In review'&&completeness(data)<100)return json({error:'Complete all 10 sections before requesting review.'},400);
 }else if(b.kind==='task'){
  if(typeof d.title!=='string'||!d.title.trim()||d.title.length>300||!['Open','In progress','Done'].includes(d.status)||!['High','Medium','Low'].includes(d.priority))return json({error:'Invalid action item'},400);
  if(!/^\d{4}-\d{2}-\d{2}$/.test(d.due)||isNaN(Date.parse(d.due)))return json({error:'Choose a valid due date'},400);
  data={id,title:d.title.trim(),reportId:d.reportId,assignee:String(d.assignee||'Unassigned').slice(0,100),due:d.due,priority:d.priority,status:d.status};
 }else{
  if(typeof d.name!=='string'||!d.name.trim()||d.name.length>100)return json({error:'Team name required'},400);
  data={id,name:d.name.trim(),manager:String(d.manager||'').slice(0,100),approver:String(d.approver||'').slice(0,200),members:String(d.members||'').slice(0,3000)};
  if(data.members.split(',').filter((s:string)=>s.trim()).length>30)return json({error:'A team can have at most 30 members.'},400);
 }
 const result=await supabase.rpc('omniscient_save',{p_id:id,p_kind:b.kind,p_data:data,p_revision:Number.isInteger(d.revision)?d.revision:null});
 if(result.error){const message=result.error.message;if(result.error.code==='40001'||result.error.code==='23505')return json({error:'This record changed. Reload before saving.'},409);return json({error:message.includes('owned RCA')?'Choose an RCA in your workspace.':'Could not save the record. Check its fields and retry.'},400)}
 return json(result.data);
}catch(e){return failure(e)}}
