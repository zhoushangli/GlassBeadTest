from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
STAGED = ROOT / 'output/soa-migration/staged'

def read(path):
    return (ROOT / path).read_text(encoding='utf-8-sig')

def write(path, text):
    destination = STAGED / path
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text.rstrip() + '\n', encoding='utf-8')

groups = {
    'identity': ('AnimalIdentity', 'identity'),
    'motion': ('AnimalMotion', 'motion'),
    'memory': ('AnimalMemory', 'memory'),
    'brain': ('AnimalBrain', 'brain'),
    'sheep_state': ('SheepState', 'sheep'),
    'wolf_state': ('WolfState', 'wolf'),
    'dog_state': ('SheepdogState', 'dog'),
}
fields = {}
for component, (cls, prefix) in groups.items():
    source = read(f'Scripts/ECS/Components/{cls}.gd')
    entries = []
    for match in re.finditer(r'^var (\w+)(?:: ([^=\n]+?))?(?:\s*(?::=|=)\s*([^\n]+))?$', source, re.M):
        name, typ, default = match.groups()
        if name.startswith('_') or name == 'generation' or (typ or '').endswith(':'):
            continue
        typ = (typ or '').strip()
        default = (default or '').strip()
        if default.startswith('Vector2.'):
            array_type = 'PackedVector2Array'
        elif typ == 'bool':
            array_type = 'PackedByteArray'
        elif typ in ('int', 'Strategy', 'AnimalEntity.Kind', 'AnimalEntity.Behavior'):
            array_type = 'PackedInt64Array'
        elif typ == 'float':
            array_type = 'PackedFloat64Array'
        elif name == 'strategy_failures':
            array_type, default = 'PackedVector4Array', 'Vector4.ZERO'
        elif typ.startswith('Array'):
            array_type = 'Array[PackedInt32Array]' if name == 'nearby' else 'Array[Array]'
            default = 'PackedInt32Array()' if name == 'nearby' else '[]'
        else:
            array_type = f'Array[{typ}]'
            default = 'null'
        if name == 'strategy':
            default = 'AnimalEntity.Strategy.FRONTAL'
        entries.append((name, array_type, default))
    # Property-backed references become immutable life handles in shared columns.
    for name in {'memory':['target'], 'wolf_state':['nearest_threat'], 'dog_state':['protected_sheep','collected_sheep']}.get(component, []):
        entries.append((name, 'Array[AnimalEntity]', 'null'))
    fields[component] = entries

columns = [(f'{groups[c][1]}_{name}', typ, default) for c, entries in fields.items() for name, typ, default in entries]
columns += [('settings', 'Array[Resource]', 'null'), ('identity_uid', 'PackedInt64Array', '0')]
header = 'class_name AnimalData\nextends RefCounted\n\n'
for comp, entries in fields.items():
    prefix = groups[comp][1]
    header += '\n'.join(f'var {prefix}_{name}: {typ} = []' for name, typ, default in entries) + '\n\n'
header += 'var settings: Array[Resource] = []\nvar identity_uid := PackedInt64Array()\nvar row_to_slot := PackedInt32Array()\nvar slot_to_row := PackedInt32Array()\nvar handles: Array[AnimalEntity] = []\nvar active_count: int = 0\nvar retained_count: int = 0\n\n'
header += 'func append_slot() -> int:\n\tvar row := row_to_slot.size()\n\trow_to_slot.append(row)\n\tslot_to_row.append(row)\n\thandles.append(null)\n'
for col, typ, default in columns:
    header += f'\t{col}.append({default})\n'
header += '\treturn row\n\nfunc reset_row(row: int) -> void:\n'
for col, typ, default in columns:
    if col in ('brain_view','brain_player','identity_uid'):
        continue
    header += f'\t{col}[row] = {default}\n'
header += '\nfunc swap_rows(first: int, second: int) -> void:\n\tif first == second:\n\t\treturn\n'
for i, (col, typ, default) in enumerate(columns):
    header += f'\tvar value_{i} = {col}[first]\n\t{col}[first] = {col}[second]\n\t{col}[second] = value_{i}\n'
header += '\tvar handle := handles[first]\n\thandles[first] = handles[second]\n\thandles[second] = handle\n\tvar slot := row_to_slot[first]\n\trow_to_slot[first] = row_to_slot[second]\n\trow_to_slot[second] = slot\n\tslot_to_row[row_to_slot[first]] = first\n\tslot_to_row[row_to_slot[second]] = second\n\n'
header += 'func row_of(handle: AnimalEntity) -> int:\n\tif handle == null or handle.slot < 0 or handle.slot >= slot_to_row.size():\n\t\treturn -1\n\tvar row := slot_to_row[handle.slot]\n\treturn row if identity_uid[row] == handle.uid else -1\n\nfunc live(handle: AnimalEntity) -> AnimalEntity:\n\tvar row := row_of(handle)\n\treturn handle if row >= 0 and row < active_count and identity_alive[row] else null\n'
write('Scripts/ECS/AnimalData.gd', header)

entity = read('Scripts/ECS/AnimalEntity.gd').split('var identity:')[0].replace('extends Entity', 'extends RefCounted')
entity += 'enum Strategy { FRONTAL, SIDE, REAR, HOWL }\nconst STRATEGY_NAMES := ["Frontal", "Side", "Rear", "Howl"]\n\nvar slot: int = -1\nvar uid: int = 0\nvar row: int:\n\tget:\n\t\treturn g_gameplayEngine.entity_service.data.row_of(self)\nvar enabled: bool:\n\tget:\n\t\treturn g_gameplayEngine.entity_service.data.live(self) != null\n'
write('Scripts/ECS/AnimalEntity.gd', entity)

refs = {'memory_target', 'wolf_nearest_threat', 'dog_protected_sheep', 'dog_collected_sheep'}

def expression_start(s, end):
    # Find a primary expression preceding a component member suffix.
    i = end - 1
    while i >= 0:
        if s[i] in '])':
            close, opening = s[i], '[' if s[i] == ']' else '('
            depth = 1
            i -= 1
            while i >= 0 and depth:
                if s[i] == close: depth += 1
                if s[i] == opening: depth -= 1
                i -= 1
        elif s[i].isalnum() or s[i] in '_.':
            i -= 1
        else:
            break
    return i + 1

def translate_expr(s):
    pattern = r'\.(identity|motion|memory|brain|sheep_state|wolf_state|dog_state)\.(\w+)'
    while match := re.search(pattern, s):
        start = expression_start(s, match.start())
        expr = s[start:match.start()]
        comp, field = match.groups()
        if comp == 'identity' and field == 'generation':
            value = expr + '.uid'
        else:
            col = groups[comp][1] + '_' + field
            value = f'data.{col}[{expr}.row]'
            tail = s[match.end():].lstrip()
            if col in refs and not (tail.startswith('=') and not tail.startswith('==')):
                value = f'data.live({value})'
        s = s[:start] + value + s[match.end():]
    # settings belongs to the shared row, except resource settings variables.
    while match := re.search(r'(?<![\w.])(?!data\b)([\w.]+(?:\[[^\]\n]+\])?)\.settings\b', s):
        expr = match.group(1)
        if expr == 'data': break
        s = s[:match.start()] + f'data.settings[{expr}.row]' + s[match.end():]
    s = s.replace('WolfState.Strategy', 'AnimalEntity.Strategy').replace('WolfState.STRATEGY_NAMES', 'AnimalEntity.STRATEGY_NAMES')
    s = re.sub(r' as AnimalEntity.Strategy\b', '', s)
    return s

def translate_function(body):
    aliases = {}
    lines = body.splitlines()
    remaining = []
    for line in lines:
        m = re.match(r'\s*var (\w+)(?:: \w+)?\s*(?::=|=)\s*(.+)\.(identity|motion|memory|brain|sheep_state|wolf_state|dog_state)\s*$', line)
        if m:
            aliases[m[1]] = (m[2],m[3])
        else:
            remaining.append(line)
    body = '\n'.join(remaining)
    for name, (expr, comp) in aliases.items():
        body = re.sub(r'(?<![\w.])'+re.escape(name)+r'\.(\w+)', lambda m: expr+'.'+comp+'.'+m[1], body)
    # Do not rewrite quoted labels or comments.
    parts = re.split(r'("(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|#[^\n]*)', body)
    body = ''.join(p if i%2 else translate_expr(p) for i,p in enumerate(parts))
    for comp in ('sheep_state','wolf_state','dog_state'):
        kind = {'sheep_state':'SHEEP','wolf_state':'WOLF','dog_state':'SHEEPDOG'}[comp]
        body = re.sub(r'([\w.]+)\.'+comp+r' != null', rf'data.identity_kind[\1.row] == AnimalEntity.Kind.{kind}', body)
        body = re.sub(r'([\w.]+)\.'+comp+r' == null', rf'data.identity_kind[\1.row] != AnimalEntity.Kind.{kind}', body)
    if 'data.' in body:
        # Data is available before simulation startup as an empty store.
        newline = body.index('\n')
        body = body[:newline] + '\n\tvar data: AnimalData = g_gameplayEngine.entity_service.data' + body[newline:]
        # Reuse the row inside animal helpers instead of resolving it per field.
        m = re.match(r'func \w+\(animal: AnimalEntity',body)
        if m and '[animal.row]' in body:
            body = body.replace('[animal.row]', '[row]')
            pos = body.index('\n',body.index('\n')+1)
            body = body[:pos]+'\n\tvar row := animal.row'+body[pos:]
    return body

for folder in ('Scripts','Tests'):
    for path in (ROOT/folder).rglob('*.gd'):
        if path.parent.name == 'Components' or path.name in ('AnimalData.gd','AnimalEntity.gd','EntityService.gd','AnimalStageSystem.gd'):
            continue
        source = path.read_text(encoding='utf-8-sig')
        if path.parent.name == 'Systems':
            source = source.replace('extends System','extends RefCounted')
            source = re.sub(r'func query\(\) -> QueryBuilder:.*?(?=\nfunc )', '',source,flags=re.S)
            source = re.sub(r'func process\(entities: Array\[Entity\], _components: Array, delta: float\) -> void:.*?(?=\nfunc )','',source,flags=re.S)
        parts = re.split(r'(?=^func )',source,flags=re.M)
        source = parts[0]+'\n\n'.join(translate_function(p).rstrip() for p in parts[1:])
        source = re.sub(r'(?m)^(\t*)for (\w+) in ([\w.]+)\.(sheep|wolves|dogs):$', lambda m: m[1]+'for '+m[2]+'_row in '+m[3]+'.'+{'sheep':'sheep_rows','wolves':'wolf_rows','dogs':'dog_rows'}[m[4]]+':\n'+m[1]+'\tvar '+m[2]+' := data.handles['+m[2]+'_row]', source)
        source = source.replace('entity_service.dogs.reverse()', 'entity_service.dog_rows.reverse()')
        source = re.sub(r'\n{3,}', '\n\n',source)
        write(path.relative_to(ROOT), source)

print('Generated shared columns and migrated field access')
