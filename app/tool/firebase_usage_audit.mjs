// Read-only project metrics. Never reads health documents or prints credentials.
// Run with the existing Firebase CLI login; no service enablement or billing changes.
import {createRequire} from 'node:module';
import {writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const app = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(path.join(app, 'tool/security_rules/node_modules/firebase-tools/package.json'));
const auth = require('./lib/auth.js');
const project = 'fatigue-project-e28a3';
const args = process.argv.slice(2);
const option = (key, fallback) => args.includes(key) ? args[args.indexOf(key)+1] : fallback;
const end = option('--end', new Date().toISOString());
// Convert the local calendar midnight, including Pacific daylight-saving days.
function pacificMidnight(instant) {
 const formatter = new Intl.DateTimeFormat('en-US', {timeZone:'America/Los_Angeles',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'});
 const parts = date => Object.fromEntries(formatter.formatToParts(date).filter(p=>p.type!=='literal').map(p=>[p.type,Number(p.value)]));
 const date=parts(new Date(instant));
 const target=Date.UTC(date.year,date.month-1,date.day);
 let guess=target;
 for(let i=0;i<3;i++) {
  const local=parts(new Date(guess));
  const delta=target-Date.UTC(local.year,local.month-1,local.day,local.hour,local.minute,local.second);
  guess+=delta;
  if(delta===0) break;
 }
 return new Date(guess).toISOString();
}
const start = option('--start', pacificMidnight(end));
const output = option('--out', '/private/tmp/tonyo-firebase-usage.json');
if (!(Date.parse(start)<Date.parse(end))) throw new Error('Provide a valid --start / --end interval.');
const account = auth.getProjectDefaultAccount(app);
if (!account?.tokens?.refresh_token) throw new Error('Sign in with Firebase CLI first.');
const tokens = account.tokens.expires_at > Date.now()+60000 ? account.tokens : await auth.getAccessToken(account.tokens.refresh_token, []);
const allowed = new Map([
 ['monitoring.googleapis.com', `/v3/projects/${project}/`],
 ['serviceusage.googleapis.com', `/v1beta1/projects/${project}/services/firestore.googleapis.com/consumerQuotaMetrics`],
 ['cloudbilling.googleapis.com', `/v1/projects/${project}/billingInfo`],
]);
async function get(url) {
 const u = new URL(url);
 if (u.protocol !== 'https:' || !allowed.has(u.hostname) || !u.pathname.startsWith(allowed.get(u.hostname))) throw new Error('Non-metadata endpoint refused.');
 const response = await fetch(u, {headers:{Authorization:`Bearer ${tokens.access_token}`}, signal:AbortSignal.timeout(30000)});
 const body = await response.json().catch(()=>({}));
 if (!response.ok) return {unavailable:true, httpStatus:response.status, reason:body.error?.status ?? 'unknown', message:body.error?.message ?? 'No detail'};
 return body;
}
async function pages(url, key) {
 const rows=[];
 do {
  const body=await get(url);
  if (body.unavailable) return body;
  rows.push(...(body[key]??[]));
  if (!body.nextPageToken) return rows;
  const u=new URL(url);u.searchParams.set('pageToken',body.nextPageToken);url=u.href;
 } while(true);
}
const base=`https://monitoring.googleapis.com/v3/projects/${project}`;
const results=await Promise.allSettled([
 pages(`${base}/metricDescriptors?filter=${encodeURIComponent('metric.type = starts_with("firestore.googleapis.com/")')}`, 'metricDescriptors'),
 pages(`https://serviceusage.googleapis.com/v1beta1/projects/${project}/services/firestore.googleapis.com/consumerQuotaMetrics?view=FULL`, 'metrics'),
 get(`https://cloudbilling.googleapis.com/v1/projects/${project}/billingInfo`),
]);
const [descriptors, quotas, billing] = results.map(r=>r.status==='fulfilled'?r.value:{unavailable:true,message:r.reason.message});
const runtimeDescriptors = await pages(`${base}/metricDescriptors?filter=${encodeURIComponent('metric.type = starts_with("serviceruntime.googleapis.com/quota/")')}`, 'metricDescriptors');
const relevant = Array.isArray(descriptors) ? descriptors.filter(d=>/document\/(read|write|delete)_count|storage\/|quota\//.test(d.type)) : [];
if (Array.isArray(runtimeDescriptors)) relevant.push(...runtimeDescriptors);
const metrics=await Promise.all(relevant.map(async descriptor=>{
 const u=new URL(`${base}/timeSeries`);
 u.searchParams.set('filter',`metric.type = "${descriptor.type}"` + (descriptor.type.startsWith("serviceruntime.") ? ' AND resource.labels.service = "firestore.googleapis.com"' : ""));
 u.searchParams.set('interval.startTime',start);u.searchParams.set('interval.endTime',end);u.searchParams.set('view','FULL');
 const series=await pages(u.href,'timeSeries');
 if (!Array.isArray(series)) return {type:descriptor.type,...series};
 return {type:descriptor.type,kind:descriptor.metricKind,unit:descriptor.unit,description:descriptor.description,
  series:series.map(s=>({resource:s.resource,labels:s.metric.labels??{},points:s.points??[]}))};
}));
const report={project,checkedAt:new Date().toISOString(),interval:{start,end},readOnly:true,
 notice:'Monitoring usage is not a billing statement. Missing metrics are unknown, never zero.',
 billingEnabled:billing.unavailable?null:billing.billingEnabled===true,
 billingError:billing.unavailable?billing:undefined,
 descriptorError:Array.isArray(descriptors)?undefined:descriptors,
 availableMetricTypes:Array.isArray(descriptors)?descriptors.map(d=>d.type):[], quotas, metrics};
const quotaUsage = quota => {
 const rows=metrics.find(m=>m.type==='serviceruntime.googleapis.com/quota/rate/net_usage')?.series?.filter(s=>s.labels.quota_metric===`firestore.googleapis.com/${quota}`);
 return rows?.length ? rows.reduce((sum,s)=>sum+s.points.reduce((n,p)=>n+Number(p.value.int64Value??p.value.doubleValue??0),0),0) : null;
};
const limit = quota => Array.isArray(quotas) ? quotas.find(q=>q.metric===`firestore.googleapis.com/${quota}`)?.consumerQuotaLimits?.[0]?.quotaBuckets?.[0]?.effectiveLimit ?? null : null;
const storage=metrics.find(m=>m.type==='firestore.googleapis.com/storage/data_and_index_storage_bytes')?.series?.filter(s=>s.resource.labels.database_id==='(default)').flatMap(s=>s.points).sort((a,b)=>b.interval.endTime.localeCompare(a.interval.endTime))[0];
report.summary={
 billingEnabled:report.billingEnabled,
 reads:{usage:quotaUsage('read_operations_per_project'),limit:limit('read_operations_per_project')},
 writes:{usage:quotaUsage('write_operations_per_project'),limit:limit('write_operations_per_project')},
 storage:{bytes:storage?Number(storage.value.int64Value):null,measuredAt:storage?.interval.endTime,freeAllowanceBytes:1073741824},
 confirmedExceeded:metrics.filter(m=>m.type==='serviceruntime.googleapis.com/quota/exceeded').flatMap(m=>(m.series??[]).flatMap(s=>{
  const observed=s.points.filter(p=>p.value.boolValue===true).sort((a,b)=>b.interval.endTime.localeCompare(a.interval.endTime))[0];
  return observed?[{quota:s.labels.quota_metric,limitName:s.labels.limit_name,observedAt:observed.interval.endTime}]:[];
 })),
};
await writeFile(output,JSON.stringify(report,null,2)+'\n',{mode:0o600});
console.log(JSON.stringify({report:output,interval:report.interval,...report.summary,errors:[report.descriptorError,report.billingError,Array.isArray(quotas)?null:quotas].filter(Boolean)},null,2));
