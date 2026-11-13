import subprocess,time,json
from pathlib import Path
exe=r"C:\Work\Godot\Editor\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
project=str(Path.cwd())
out=Path(__file__).resolve().parent
cases=[('desktop',1,'spread','on'),('desktop',2,'spread','on'),('desktop',4,'spread','on'),('desktop',6,'spread','on'),('desktop',2,'cluster','on'),('desktop',6,'cluster','on'),('headless',1,'spread','on'),('headless',6,'spread','on'),('headless',6,'cluster','on'),('desktop',2,'spread','off')]
summary=json.loads((out/"matrix.json").read_text(encoding="utf-8")) if (out/"matrix.json").exists() else []
completed={row["case"] for row in summary}
for mode,tiles,layout,stats in cases:
    name=f'{mode}_{tiles}_{layout}_{stats}'
    if name in completed: continue
    cmd=[exe,'--path',project,'--script','res://Tests/RunBenchmark.gd']
    if mode=='headless': cmd+=['--headless']
    cmd+=['--',f'--tiles={tiles}',f'--layout={layout}',f'--stats={stats}','--warmup=3','--duration=30']
    print('RUN',name,flush=True)
    start=time.monotonic()
    with (out/(name+'.log')).open('w',encoding='utf-8') as log:
        try:
            process=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT)
            code=process.wait(timeout=180)
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill','/PID',str(process.pid),'/T','/F'],capture_output=True)
            process.wait()
            code='timeout_180s'
    row={'case':name,'exit':code,'wall_seconds':time.monotonic()-start,'command':cmd}
    summary.append(row)
    (out/'matrix.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print('DONE',name,code,round(row['wall_seconds'],1),flush=True)
