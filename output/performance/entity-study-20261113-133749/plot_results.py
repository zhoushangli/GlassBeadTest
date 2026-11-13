from pathlib import Path
import json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
root=Path(__file__).resolve().parent
summary=json.loads((root/'summary.json').read_text())
fig,axes=plt.subplots(2,2,figsize=(12,8),layout='constrained')
settings=[(True,'step_mean_ms','Headless mean simulation step (ms)',16.667),(True,'simulation_wall_ratio','Headless simulation seconds / wall second',1),(False,'loop_hz','Desktop process loop frequency (Hz)',60),(False,'loop_p95_ms','Desktop process frame P95 (ms)',16.667)]
for ax,(headless,metric,title,reference) in zip(axes.flat,settings):
 for scenario,color in [('scaled','#2563eb'),('fixed','#dc2626')]:
  group=sorted([r for r in summary if r['group']=='formal' and r['headless']==headless and r['scenario']==scenario],key=lambda r:r['entities'])
  valid=[r for r in group if r[metric+'_median']!='']
  ax.plot([r['entities'] for r in valid],[r[metric+'_median'] for r in valid],marker='o',label=scenario,color=color)
  ax.fill_between([r['entities'] for r in valid],[r[metric+'_min'] for r in valid],[r[metric+'_max'] for r in valid],color=color,alpha=.12)
  failed=[str(r['entities']) for r in group if r['successes']==0]
  if failed: ax.text(.02,.95 if scenario=='scaled' else .86,f"{scenario}: no completed sample at {', '.join(failed)}",transform=ax.transAxes,va='top',color=color,fontsize=8)
 ax.axhline(reference,color='#64748b',linestyle='--',linewidth=1,label=f'reference {reference:g}')
 ax.set_title(title,fontsize=11)
 ax.set_xticks([1000,2000,3000,4000])
 ax.set_xlabel('Configured initial animals')
 ax.set_yscale('log')
 ax.grid(alpha=.2)
 ax.legend(loc='best',fontsize=8)
fig.suptitle('Godot 4.7.2 / LimboAI 1.8.1 - median and range of independent runs',fontsize=12)
fig.savefig(root/'performance.png',dpi=170)
fig.savefig(root/'performance.svg')
print(root/'performance.png')
