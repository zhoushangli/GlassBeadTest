from pathlib import Path
import re
import json

tips = {
    'Sheep': ('SheepConfig', {
        'perception_radius': ('羊在饥饿为 0 时的基础避险距离，也是扫描狼的最大距离；实际避险距离随饥饿百分比线性缩短，饥饿 100 时降至紧急距离。威胁判断和选草共用此距离。', '基础 130、紧急 36 时，饥饿 50 对应避险距离 83 像素'),
        'emergency_distance': ('羊对任意狼的强制逃跑距离，单位为像素，也是饥饿 100 时的最小避险距离；不得超过基础避险距离。', '36 表示狼进入 36 像素内时始终逃跑'),
        'safety_duration': ('狼离开实际避险范围后仍继续逃跑的模拟时间，单位为秒；减少此值可更快恢复觅食。', '0.5 表示危险解除后继续逃跑半秒'),
        'retarget_interval': ('觅食时重新评估草目标的间隔，单位为秒；正在吃草时不因定时评估换目标。', '1 表示每隔 1 秒考虑更好的草点'),
    }),
    'Wolves': ('WolfConfig', {
        'dog_threat_distance': ('牧羊犬对狼的威慑距离，单位为像素；狼发现狗进入此距离后放弃猎物并逃跑，捕获结算时也会检查。', '90 表示狗进入狼周围 90 像素内即可打断猎捕'),
    }),
    'Dogs': ('SheepdogConfig', {
        'perception_radius': ('牧羊犬能发现候选威胁狼的最大距离，单位为像素；实际威慑狼的距离由狼配置的 dog_threat_distance 控制。', '240 表示狗只处理自己周围 240 像素内的狼'),
        'protection_radius': ('猎捕中或持续驱赶的狼距离保护中心不超过此半径时视为羊群威胁，还须在狗的感知范围内。', '200 表示处理保护中心周围 200 像素内的猎捕威胁'),
        'leash_distance': ('牧羊犬离保护中心超过此距离后优先返回，单位为像素。', '240 表示追离羊群超过 240 像素后返回'),
        'guard_distance': ('守护点相对局部羊群中心的偏移距离，单位为像素。', '60 表示在羊群中心外约 60 像素处守护'),
    }),
}
panel_path = Path('Scripts/UI/RuntimeConfigPanel.gd')
panel = panel_path.read_text(encoding='utf-8')
for section, (config, fields) in tips.items():
    path = Path('Scripts/Core') / (config + '.gd')
    text = path.read_text(encoding='utf-8')
    for field, (tip, example) in fields.items():
        pattern = re.compile(r'(?:^##[^\n]*\n){2}(^@export_range\([^\n]*\) var ' + field + r'\b[^\n]*)', re.M)
        text, count = pattern.subn(lambda m: f'## {tip}\n## 例如：{example}。\n' + m[1], text)
        assert count == 1, (config, field)
        key = section + '.' + field
        value = json.dumps(tip + '\n例如：' + example + '。', ensure_ascii=False)
        pattern = re.compile(r'^\t"' + re.escape(key) + r'": [^\n]*', re.M)
        panel, count = pattern.subn(lambda m: f'\t"{key}": {value},', panel)
        assert count == 1, key
    path.write_text(text, encoding='utf-8', newline='\n')
panel_path.write_text(panel, encoding='utf-8', newline='\n')

p = Path('AGENTS.md')
s = p.read_text(encoding='utf-8')
s = s.replace('管理整数饥饿、冒险觅食和逃跑', '管理整数饥饿、动态避险距离、觅食和逃跑')
s = s.replace('高饥饿羊按遭遇抽签决定是否冒险觅食，紧急距离始终逃跑。', '羊的实际避险距离按饥饿百分比，从基础距离线性降至紧急距离；威胁判断与选草共用此距离，不再使用概率冒险，紧急距离始终逃跑。')
s = s.replace('冒险参数实际变化会在下一模拟步重新评估本次遭遇。', '避险距离配置在下一模拟步按当前饥饿重新计算，已有威胁记忆自然计时。')
p.write_text(s, encoding='utf-8', newline='\n')
