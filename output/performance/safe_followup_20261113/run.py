import subprocess,json,time
from pathlib import Path
out=Path(__file__).resolve().parent
cases=[(1,'spread','on',30,3,45,False),(2,'spread','on',30,3,45,False),(2,'spread','off',30,3,45,False),(2,'cluster','on',30,3,45,False),(6,'spread','on',30,3,5,False),(6,'cluster','on',30,3,5,False),(2,'spread','on',1,0,30,True)]
rows=[]
for tiles,layout,stats,duration,warmup,timeout,profile in cases:
    name=f'headless_{tiles}_{layout}_{stats}'+('_profile' if profile else '')
    args=['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File','Tests/RunBenchmark.ps1','-Headless','-Tiles',str(tiles),'-Layout',layout,'-Stats',stats,'-Duration',str(duration),'-Warmup',str(warmup),'-TimeoutSeconds',str(timeout)]
    if profile:args+=['-Profile']
    print('RUN',name,flush=True)
    start=time.monotonic()
    result=subprocess.run(args,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=timeout+20)
    (out/(name+'.log')).write_text(result.stdout+'\n'+result.stderr,encoding='utf-8')
    rows.append({'case':name,'exit':result.returncode,'wall_seconds':time.monotonic()-start,'output':result.stdout,'command':args})
    (out/'runs.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
    print('DONE',name,result.returncode,round(rows[-1]['wall_seconds'],1),flush=True)
