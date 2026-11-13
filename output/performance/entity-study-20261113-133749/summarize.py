from pathlib import Path
from collections import defaultdict
import json,csv,statistics,re
root=Path(__file__).resolve().parent
project=root.parents[2]
ledger=json.loads((root/'matrix.json').read_text(encoding='utf-8-sig'))
rows=[]
for run in ledger:
 row={k:v for k,v in run.items() if k not in ['metrics']}
 if run.get('launcher'):
  launch=project/run['launcher']
  status=json.loads((launch/'launcher.json').read_text(encoding='utf-8-sig'))
  row['launcher_state']=status['state']
  stdout=(launch/'stdout.log').read_text(encoding='utf-8-sig')
  stderr=(launch/'stderr.log').read_text(encoding='utf-8-sig')
  row['stderr_nonempty']=bool(stderr.strip())
  partial=re.findall(r'BENCHMARK_SAMPLE tier=\d+ wall=([0-9.]+) loop_hz=([0-9.]+) step_ms=([0-9.]+) alive=\((\d+), (\d+), (\d+)\) sim=([0-9.]+)',stdout)
  row['logged_sample_count']=len(partial)
  if partial:
   last=partial[-1]
   row['last_reported_wall_seconds']=float(last[0])
   row['last_reported_simulation_seconds']=float(last[6])
   row['last_reported_alive']=sum(int(x) for x in last[3:6])
 if run.get('result'):
  result=json.loads((project/run['result']).read_text(encoding='utf-8'))
  row.update({k:v for k,v in result.items() if not isinstance(v,(dict,list))})
  for k in ['configured_counts','initial_counts','final_counts','arena_size']:
   row[k]=json.dumps(result[k])
  row['alive_start']=sum(result['initial_counts'])
  row['alive_end']=sum(result['final_counts'])
 rows.append(row)
fields=list(dict.fromkeys(k for r in rows for k in r))
with (root/'runs.csv').open('w',encoding='utf-8-sig',newline='') as f:
 writer=csv.DictWriter(f,fieldnames=fields);writer.writeheader();writer.writerows(rows)
metrics=['step_mean_ms','step_p95_ms','step_max_ms','perception_mean_ms','decision_mean_ms','movement_interaction_mean_ms','simulation_wall_ratio','simulation_seconds_advanced','loop_hz','loop_p95_ms','spatial_queries_per_step','spatial_candidates_per_query','spatial_max_candidates','spatial_max_occupancy','alive_start','alive_end','captures_during_measurement','grass_meals_total','grass_regrowths_total','physics_steps','measured_wall_seconds']
groups=defaultdict(list)
for row in rows: groups[(row['group'],row['headless'],row['scenario'],row['entities'])].append(row)
summary=[]
for key,group in groups.items():
 entry=dict(zip(['group','headless','scenario','entities'],key))
 entry.update(attempts=len(group),successes=sum('step_mean_ms' in r for r in group),failures=sum('step_mean_ms' not in r for r in group))
 for metric in metrics:
  values=[r[metric] for r in group if metric in r]
  for label,fn in [('median',statistics.median),('min',min),('max',max)]:
   entry[metric+'_'+label]=fn(values) if values else ''
 summary.append(entry)
fields=list(dict.fromkeys(k for r in summary for k in r))
with (root/'summary.csv').open('w',encoding='utf-8-sig',newline='') as f:
 writer=csv.DictWriter(f,fieldnames=fields);writer.writeheader();writer.writerows(summary)
(root/'summary.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False),encoding='utf-8')
profiles=[]
for run in ledger:
 if run['group']!='profile' or not run.get('launcher'): continue
 stdout=(project/run['launcher']/'stdout.log').read_text(encoding='utf-8-sig')
 blocks=[]
 for block in stdout.split('FRAME:')[1:]:
  header=re.match(r' total: ([0-9.eE+-]+) script: ([0-9.eE+-]+)',block)
  funcs=[]
  for match in re.finditer(r'^\d+:(.+)\n\s*total: ([0-9.eE+-]+)/[^\n]*self: ([0-9.eE+-]+)/[^\n]*tcalls: (\d+)',block,re.M):
   funcs.append(dict(function=match[1],inclusive_seconds=float(match[2]),self_seconds=float(match[3]),calls=int(match[4])))
  if header: blocks.append(dict(total_seconds=float(header[1]),script_seconds=float(header[2]),functions=funcs))
 profiles.append(dict(entities=run['entities'],scenario=run['scenario'],exit_code=run['exit_code'],launcher=run['launcher'],profiling_started='BEGIN PROFILING' in stdout,blocks=blocks))
(root/'profiles.json').write_text(json.dumps(profiles,indent=2),encoding='utf-8')
for r in summary:
 if r['group']=='formal':
  print(r['headless'],r['scenario'],r['entities'],r['successes'],'step',r['step_mean_ms_median'],'p95',r['step_p95_ms_median'],'max',r['step_max_ms_median'],'ratio',r['simulation_wall_ratio_median'],'hz',r['loop_hz_median'])
print('Completed',len(ledger),'runs; profiles',len(profiles))
