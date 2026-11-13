from pathlib import Path
import re

sections = {
    'Sheep': ('SheepConfig', {
        'move_speed': ('羊寻找食物时的移动速度，单位为像素/秒；闲逛速度还会乘以闲逛比例。', '70 表示每秒最多移动 70 像素'),
        'flee_speed': ('羊逃离狼时的速度，单位为像素/秒。', '110 表示逃跑时每秒最多移动 110 像素'),
        'perception_radius': ('羊识别猎捕中狼的距离，也用于排除危险草点；冒险觅食可忽略普通威胁，但不会忽略紧急距离。', '190 表示 190 像素内猎捕中的狼会触发避险判断'),
        'idle_speed_scale': ('闲逛速度相对普通移动速度的比例。', '0.5 表示以普通速度的一半闲逛'),
        'flock_radius': ('计算局部羊群中心时查找同伴的半径，单位为像素。', '120 表示只参考附近 120 像素内的羊'),
        'foraging_cohesion': ('寻找食物途中靠近局部羊群中心的力度，接近草点后不再叠加。', '0 表示寻找食物时不向同伴中心靠拢'),
        'idle_cohesion': ('闲逛时靠近局部羊群中心的力度。', '数值越大，闲逛时越倾向于靠近附近同伴'),
        'initial_hunger_min': ('新生成羊的初始整数饥饿下限，范围为 0～100；修改不改变已有羊的饥饿值。', '20 表示初始饥饿不低于 20'),
        'initial_hunger_max': ('新生成羊的初始整数饥饿上限，范围为 0～100；不得低于初始下限。', '70 表示初始饥饿不高于 70'),
        'hunger_per_second': ('每模拟秒增加的整数饥饿点数，不足一点的增量累计保留，饥饿最多为 100。', '1 表示每秒增加 1 点饥饿'),
        'hungry_threshold': ('饥饿达到此值后开始觅食，必须高于停止觅食阈值。', '60 表示达到 60 点饥饿后开始找草'),
        'full_threshold': ('已经开始觅食的羊，饥饿降至此值或更低后停止觅食。', '20 表示吃到饥饿不超过 20 时停止'),
        'hunger_per_bite': ('每完成一口草降低的整数饥饿点数，最低降至 0。', '25 表示每口草减少 25 点饥饿'),
        'grazing_duration': ('完成一口草所需的连续模拟时间，单位为秒；离开吃草行为会重置进度。', '2 表示连续吃草 2 秒才消耗一口'),
        'grazing_distance': ('羊与草点距离不超过此值时可以开始吃草，单位为像素。', '18 表示进入草点周围 18 像素后可以吃草'),
        'retarget_interval': ('觅食时重新评估草目标的间隔，单位为秒；正在吃草时不因定时评估换目标。', '2 表示每隔 2 秒考虑更好的草点'),
        'retarget_improvement': ('已有有效草目标时，新目标评分需要改善的比例；评分越低越好。', '0.2 表示新目标至少改善 20% 才切换'),
        'crowd_weight': ('草点评分中其他羊预约数量的惩罚权重。', '数值越大，越倾向选择预约较少的草点'),
        'emergency_distance': ('羊与任意狼的紧急距离，单位为像素；进入后无论饥饿和冒险结果都逃跑，不得超过感知半径。', '64 表示狼进入 64 像素内时强制逃跑'),
        'safety_duration': ('看不见威胁后仍保留本次威胁遭遇的时间，单位为秒；未冒险的羊继续逃跑。', '1 表示威胁消失后继续保留 1 秒避险记忆'),
        'risk_hunger_threshold': ('饥饿超过此值才有冒险觅食的概率，概率随饥饿线性增加；下降至此值时取消冒险。修改后下一模拟步重新抽签。', '70 表示饥饿不超过 70 时不会冒险'),
        'max_risk_percent': ('饥饿为 100 时冒险觅食的概率，使用整数百分比；每次威胁遭遇只抽一次，紧急距离始终强制逃跑。修改后下一模拟步重新抽签。', '80 表示饥饿 100 时有 80% 的冒险概率'),
    }),
    'Wolves': ('WolfConfig', {
        'move_speed': ('狼搜索猎物时的移动速度，单位为像素/秒。', '70 表示搜索时每秒最多移动 70 像素'),
        'chase_speed': ('狼追赶和贴近猎物时的移动速度，单位为像素/秒。', '135 表示追赶时每秒最多移动 135 像素'),
        'retreat_speed': ('狼逃离牧羊犬时的移动速度，单位为像素/秒。', '160 表示避狗时每秒最多移动 160 像素'),
        'perception_radius': ('狼寻找羊和维持追赶的感知半径，单位为像素；猎物离开范围后放弃追赶。', '260 表示只选择 260 像素内的羊'),
        'dog_threat_distance': ('牧羊犬对狼的威慑距离，单位为像素；狼发现狗进入此距离后放弃猎物并逃跑，捕获结算时也会检查。', '160 表示狗进入狼周围 160 像素内即可打断猎捕'),
        'search_interval': ('没有可用猎物时重新搜索的间隔，单位为模拟秒；已有目标时保持追赶。', '1 表示没有猎物时每秒搜索一次'),
        'hunt_duration': ('单次追赶允许持续的最长模拟时间，单位为秒；超时后重新选择，应用配置保留已追赶时间。', '10 表示一次最多追赶 10 秒'),
        'competition_weight': ('其他狼已经追踪同一只羊时降低其选择权重，权重除以 1 加其他追踪狼数乘本值。', '3 表示已有一只狼追踪时，选择权重降为原来的四分之一'),
        'capture_distance': ('狼可以累计捕获进度的最大距离，单位为像素；超过后进度清零。', '22 表示必须持续贴近羊到 22 像素内'),
        'capture_duration': ('在捕获距离内连续维持多久才能捕获羊，单位为模拟秒；狗可以打断。', '0.5 表示持续贴近半秒后捕获'),
    }),
    'Dogs': ('SheepdogConfig', {
        'move_speed': ('牧羊犬前往局部羊群守护点时的速度，单位为像素/秒。', '80 表示守护移动时每秒最多移动 80 像素'),
        'drive_speed': ('牧羊犬拦截和驱赶狼时的速度，单位为像素/秒。', '185 表示拦截和驱赶时每秒最多移动 185 像素'),
        'return_speed': ('牧羊犬返回守护点时的速度，单位为像素/秒。', '100 表示返回时每秒最多移动 100 像素'),
        'perception_radius': ('牧羊犬能发现候选威胁狼的最大距离，单位为像素；实际威慑狼的距离由狼配置的 dog_threat_distance 控制。', '300 表示狗只处理自己周围 300 像素内的狼'),
        'local_flock_radius': ('围绕保护锚点羊计算局部羊群中心的半径，单位为像素，也参与保护覆盖评分。', '120 表示以锚点羊附近 120 像素内的羊计算中心'),
        'protection_radius': ('猎捕中或持续驱赶的狼距离保护中心不超过此半径时视为羊群威胁，还须在狗的感知范围内。', '280 表示处理保护中心周围 280 像素内的猎捕威胁'),
        'leash_distance': ('牧羊犬离保护中心超过此距离后优先返回，单位为像素。', '300 表示追离羊群超过 300 像素后返回'),
        'guard_distance': ('守护点相对局部羊群中心的偏移距离，单位为像素。', '75 表示在羊群中心外约 75 像素处守护'),
        'reassignment_interval': ('重新评估保护锚点羊的间隔，单位为模拟秒；锚点死亡时立即重新选择。', '2 表示每隔 2 秒重新评估保护对象'),
        'reassignment_improvement': ('已有保护锚点时，新锚点评分需要改善的比例；评分越低越好。', '0.25 表示新锚点至少改善 25% 才更换'),
        'coverage_weight': ('选择保护锚点时，对其他狗已有覆盖的惩罚权重。', '数值越大，越倾向保护其他狗较少覆盖的羊群'),
    }),
    'Grass': ('GrassConfig', {
        'patch_radius': ('每片草地的布局半径，单位为像素，也用于草目标距离评分；应用修改需要重启模拟。', '84 表示草点分布在半径约 84 像素的草地中'),
        'per_patch': ('每片草地包含的草点数量；应用修改需要重启模拟。', '24 表示每片草地生成 24 个草点'),
        'bites': ('每个草点可提供的口数，吃空后才开始恢复倒计时；应用修改需要重启模拟。', '2 表示每个草点可被吃两口'),
        'positions': ('各片草地中心的场地坐标；应用修改需要重启模拟，运行时数值表单不编辑此数组。', 'Vector2(340, 240) 表示一片草地的中心'),
        'regrow_duration': ('草点吃空后原地恢复全部口数的模拟时间，单位为秒；修改只影响之后吃空的草点。', '15 表示吃空后等待 15 秒恢复'),
    }),
    'World': ('SimulationConfig', {
        'arena_size': ('场地宽高，单位为像素；应用修改需要重启模拟，运行时数值表单不编辑此向量。', 'Vector2(1280, 720) 表示宽 1280、高 720'),
        'random_seed': ('统一模拟随机种子；相同配置和操作顺序可重现随机结果，应用修改需要重启。', '1337 表示使用固定种子 1337'),
        'initial_sheep': ('模拟开始时的羊数量；应用修改需要重启模拟并保留暂停状态。', '240 表示初始生成 240 只羊'),
        'initial_wolves': ('模拟开始时的狼数量；应用修改需要重启模拟并保留暂停状态。', '24 表示初始生成 24 只狼'),
        'initial_sheepdogs': ('模拟开始时的牧羊犬数量；应用修改需要重启模拟并保留暂停状态。', '12 表示初始生成 12 只牧羊犬'),
        'perception_interval': ('动物采样附近实体和软分离的间隔，单位为模拟秒；不是全部 AI 决策的更新间隔。', '0.125 表示约每 0.125 秒更新一次邻居采样'),
        'separation_distance': ('同物种动物之间软分离的作用距离，单位为像素；不等同于物理碰撞。', '24 表示同类靠近到 24 像素内时产生分离移动'),
        'death_duration': ('动物死亡后保留表现多久再移除，单位为模拟秒。', '0.3 表示死亡表现保留 0.3 秒'),
        'sheep': ('羊的移动、饥饿、觅食和避险配置资源。', '使用 CFG_Sheep.tres 调整羊的行为'),
        'wolf': ('狼的搜索、猎捕、捕获和避狗配置资源。', '使用 CFG_Wolf.tres 调整狗对狼的威慑距离'),
        'sheepdog': ('牧羊犬的移动和局部羊群保护配置资源。', '使用 CFG_Sheepdog.tres 调整保护范围'),
        'grass': ('草地布局、每点食物口数和恢复时间配置资源。', '使用 CFG_Grass.tres 调整草的周转速度'),
    }),
}

backup = Path(__file__).parent / 'baseline'
backup.mkdir(exist_ok=True)
help_entries = []
for section, (class_name, fields) in sections.items():
    path = Path('Scripts/Core') / (class_name + '.gd')
    text = path.read_text(encoding='utf-8-sig')
    dest = backup / path
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.exists():
        dest.write_bytes(path.read_bytes())
    for field, (tip, example) in fields.items():
        pattern = re.compile(r'^@export(?:_range\([^\n]*\))? var ' + field + r'\b.*$', re.M)
        match = pattern.search(text)
        assert match, (class_name, field)
        text = text[:match.start()] + f'## {tip}\n## 例如：{example}。\n' + text[match.start():]
        if match.group().startswith('@export_range'):
            help_entries.append(f'\t"{section}.{field}": "{tip}\\n例如：{example}。",')
    path.write_text(text, encoding='utf-8', newline='\n')

path = Path('Scripts/UI/RuntimeConfigPanel.gd')
text = path.read_text(encoding='utf-8-sig')
dest = backup / path
dest.parent.mkdir(parents=True, exist_ok=True)
if not dest.exists():
    dest.write_bytes(path.read_bytes())
start = text.index('const FIELD_HELP := {')
end = text.index('\n}', start) + 2
text = text[:start] + 'const FIELD_HELP := {\n' + '\n'.join(help_entries) + '\n}' + text[end:]
text = text.replace('FIELD_HELP.get(property.name, label.text)', 'FIELD_HELP.get(section_name + "." + str(property.name), label.text)')
path.write_text(text, encoding='utf-8', newline='\n')
print('Added Chinese Inspector tips to five CFG types and runtime tips to', len(help_entries), 'numeric fields.')
