from pathlib import Path
import subprocess, json, re, time
root = Path(__file__).resolve().parent
project = root.parents[2]
runs=[]
for headless in [True,False]:
 for scenario in ['scaled','fixed']:
  for n in [1000,2000,3000,4000]:
   for repeat in range(1,4):
    runs.append(dict(group='formal',headless=headless,scenario=scenario,entities=n,repeat=repeat,stats='on',profile=False,warmup=3,duration=30))
for n in [1000,4000]:
 for repeat in range(1,4):
  runs.append(dict(group='stats_off',headless=True,scenario='scaled',entities=n,repeat=repeat,stats='off',profile=False,warmup=3,duration=30))
for scenario in ['scaled','fixed']:
 for n in [1000,4000]:
  runs.append(dict(group='profile',headless=True,scenario=scenario,entities=n,repeat=1,stats='on',profile=True,warmup=1,duration=5))
ledger=[]
for index,run in enumerate(runs):
 print(f"START {index+1}/{len(runs)} {run}",flush=True)
 command=['powershell','-NoProfile','-ExecutionPolicy','Bypass','-File',str(project/'Tests/RunBenchmark.ps1'),'-Entities',str(run['entities']),'-Scenario',run['scenario'],'-Stats',run['stats'],'-Warmup',str(run['warmup']),'-Duration',str(run['duration']),'-TimeoutSeconds','90']
 if run['headless']: command.append('-Headless')
 if run['profile']: command.append('-Profile')
 started=time.monotonic()
 process=subprocess.run(command,capture_output=True,text=True,encoding='utf-8',errors='replace',cwd=project)
 run['elapsed_seconds']=time.monotonic()-started
 run['exit_code']=process.returncode
 (root/f'run-{index+1:02d}.log').write_text(process.stdout+'\n'+process.stderr,encoding='utf-8')
 paths=re.findall(r'logs=(.+)',process.stdout)
 if paths:
  launch=Path(paths[-1].strip())
  run['launcher']=str(launch.relative_to(project))
  if (launch/'stdout.log').exists():
   stdout=(launch/'stdout.log').read_text(encoding='utf-8-sig')
   for line in stdout.splitlines():
    if line.startswith('BENCHMARK_RESULT '):
     result=json.loads(line[line.index('{'):])
     result_path=line[len('BENCHMARK_RESULT '):line.index(' {')].strip().replace('res://','')
     run['result']=result_path
     run['metrics']={k:result.get(k) for k in ['step_mean_ms','step_p95_ms','step_max_ms','perception_mean_ms','decision_mean_ms','movement_interaction_mean_ms','simulation_wall_ratio','simulation_seconds_advanced','initial_counts','final_counts','grass_meals_total','loop_hz']}
 ledger.append(run.copy())
 (root/'matrix.json').write_text(json.dumps(ledger,indent=2,ensure_ascii=False),encoding='utf-8')
 print(f"DONE {index+1}/{len(runs)} exit={process.returncode} elapsed={run['elapsed_seconds']:.1f}s metrics={run.get('metrics')}",flush=True)
print('MATRIX_COMPLETE',flush=True)
