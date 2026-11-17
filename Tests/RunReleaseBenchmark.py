import argparse
import hashlib
import json
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(executable, evidence):
    runtime = evidence / 'runtime'
    harness = evidence / 'harness'
    runtime.mkdir(parents=True, exist_ok=True)
    harness.mkdir(exist_ok=True)
    files = [executable, *executable.parent.glob('*.dll')]
    if executable.with_suffix('.pck').exists():
        files.append(executable.with_suffix('.pck'))
    manifest = {}
    for source in files:
        shutil.copy2(source, runtime / source.name)
        manifest[source.name] = sha(source)
    (evidence / 'binary-hashes.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    for source in (PROJECT / 'Tests').glob('*.gd'):
        text = source.read_text(encoding='utf-8')
        text = text.replace('res://Tests/', harness.as_posix() + '/')
        text = text.replace('load(ProjectSettings.get_setting("application/run/main_scene"))', 'load("res://Levels/Map/SCN_Boot.tscn")')
        text = text.replace('"res://output/performance/%s_%s_%d_%d"', json.dumps(evidence.as_posix() + '/results/%s_%s_%d_%d'))
        text = text.replace('res://output/', evidence.as_posix() + '/artifacts/')
        if source.name == 'RunBenchmark.gd':
            text = text.replace('func _start() -> void:\n', 'func _start() -> void:\n\troot.unresizable = true\n\troot.mode = Window.MODE_WINDOWED\n\troot.size = Vector2i(1280, 720)\n\troot.call_deferred("set_size", Vector2i(1280, 720))\n')
        (harness / source.name).write_text(text, encoding='utf-8')
    return runtime / executable.name, harness, manifest


def select_entry(runtime, harness, name):
    script = harness / 'Bootstrap.gd'
    script.write_text('''extends Node

func _ready() -> void:
	call_deferred("begin")

func begin() -> void:
	if ResourceLoader.exists("res://Tests/ReferenceSimulation.gd") or ResourceLoader.exists("res://Tests/RunBenchmark.gd") or ResourceLoader.exists("res://Shaders/Simulation/TimerCompute.glsl"):
		push_error("FAIL: release contains excluded test or timer resources")
		get_tree().quit(2)
		return
	print("RELEASE_PACKAGE debug=", OS.is_debug_build(), " tests_absent=true timer_shader_absent=true")
	var tree := get_tree()
	tree.set_script(load(''' + json.dumps((harness / name).as_posix()) + '''))
	tree.call("_initialize")
	queue_free()
''', encoding='utf-8')
    scene = harness / 'Bootstrap.tscn'
    scene.write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path=' + json.dumps(script.as_posix()) + ' id="1"]\n[node name="ReleaseVerification" type="Node"]\nscript = ExtResource("1")\n', encoding='utf-8')
    (runtime.parent / 'override.cfg').write_text('[application]\nrun/main_scene=' + json.dumps(scene.as_posix()) + '\n', encoding='utf-8')


def execute(evidence, label, args, expected=0, timeout=90):
    print('START', label, flush=True)
    (evidence / (label + '-command.json')).write_text(json.dumps([str(x) for x in args], indent=2), encoding='utf-8')
    with (evidence / (label + '-stdout.log')).open('w', encoding='utf-8') as out, (evidence / (label + '-stderr.log')).open('w', encoding='utf-8') as err:
        process = subprocess.Popen([str(x) for x in args], cwd=PROJECT, stdout=out, stderr=err)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            raise RuntimeError(label + ' timed out')
    stdout = (evidence / (label + '-stdout.log')).read_text(encoding='utf-8')
    stderr = (evidence / (label + '-stderr.log')).read_text(encoding='utf-8')
    if code != expected or 'SCRIPT ERROR' in stdout + stderr or 'FAIL:' in stdout + stderr:
        print(stdout[-1000:], stderr[-3500:], flush=True)
        raise RuntimeError(f'{label} failed: {code}')
    print('DONE', label, stdout[-180:], flush=True)
    return stdout, stderr


def main():
    parser = argparse.ArgumentParser(description='Verify and benchmark the actual GPU-required release without adding tests to its PCK.')
    parser.add_argument('--executable', type=Path, default=Path(r'C:\Work\Godot\Project\export\GlassBeadTest.exe'))
    parser.add_argument('--evidence', type=Path)
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--matrix', action='store_true')
    parser.add_argument('--smoke', action='store_true')
    parser.add_argument('--population', type=int)
    parser.add_argument('--max-fps', type=int, default=60)
    parser.add_argument('--failure', choices=['shader', 'pipeline', 'movement', 'readback'])
    parser.add_argument('--headless-failure', action='store_true')
    options = parser.parse_args()
    if options.population is not None and not 1 <= options.population <= 30000:
        parser.error('--population must be between 1 and 30000')
    if options.max_fps < 0:
        parser.error('--max-fps must be nonnegative; 0 disables the cap')
    evidence = (options.evidence or PROJECT / 'output' / ('release-gpu-' + datetime.now().strftime('%Y%m%d-%H%M%S'))).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    executable, harness, manifest = prepare(options.executable.resolve(), evidence)
    if options.verify:
        for name in ['ComputeVerification', 'NumericComputeVerification', 'AsyncDecisionVerification', 'JobVerification', 'SimulationVerification', 'PerformanceVerification', 'DogRegionVerification', 'RenderBufferVerification', 'BrainInstanceVerification']:
            select_entry(executable, harness, name + '.gd')
            stdout, _ = execute(evidence, 'release-' + name, [executable])
            assert 'failures=0' in stdout and 'debug=false' in stdout
    if options.failure:
        select_entry(executable, harness, 'ComputeFailureVerification.gd')
        flags = ['--headless'] if options.headless_failure else []
        stdout, _ = execute(evidence, 'failure-' + options.failure, [executable, *flags, '--', '--phase=' + options.failure], expected=1, timeout=180)
        assert 'stopped=true debug=false' in stdout
    if options.matrix or options.smoke or options.population is not None:
        select_entry(executable, harness, 'RunBenchmark.gd')
        runs = []
        for repeat in range(1, 2 if options.smoke else 4):
            for population in ([options.population] if options.population is not None else [5000] if options.smoke else [10000, 8000, 5000] if repeat == 2 else [5000, 8000, 10000]):
                label = f'gpu_required_{population}_r{repeat}'
                stdout, stderr = execute(evidence, label, [executable, '--', '--main-scene=on', f'--population={population}', '--warmup=' + ('1' if options.smoke else '5'), '--duration=' + ('2' if options.smoke else '30'), f'--max-fps={options.max_fps}', '--sampling=stages', '--hud=on', '--overlay=on', '--animals=on', '--label=' + label])
                assert not stderr.strip(), stderr
                paths = list((evidence / 'results').glob('*_' + label + '_*/result.json'))
                assert len(paths) == 1
                data = json.loads(paths[0].read_text())
                assert data['is_debug_build'] is False and data['compute']['device'] == 'local' and not data['compute']['failure']
                assert data['max_fps'] == options.max_fps
                assert data['compute']['samples'] and all(s['backend'] == 'gpu' for s in data['compute']['samples'])
                assert data['compute']['numeric']['samples']['Movement']
                runs.append({'population': population, 'repeat': repeat, 'path': str(paths[0])})
                (evidence / 'runs.json').write_text(json.dumps(runs, indent=2), encoding='utf-8')
                print('RESULT', population, repeat, data['average_fps'], data['actual_simulation_hz'], flush=True)
    assert all(sha(executable.parent / name) == value for name, value in manifest.items())
    print('RELEASE_CHECK_COMPLETE', evidence, flush=True)


if __name__ == '__main__':
    main()
