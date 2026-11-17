param(
	[string]$GodotPath = 'C:\Work\Godot\Editor\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
)

$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$evidencePath = Join-Path $projectPath "output\motion-$stamp"
New-Item -ItemType Directory -Path $evidencePath | Out-Null
New-Item -ItemType File -Path (Join-Path $evidencePath '.gdignore') | Out-Null
$sources = @(foreach ($directory in @('Scripts', 'Shaders', 'Resources', 'Levels', 'Prefabs', 'Tests')) {
	Get-ChildItem -LiteralPath (Join-Path $projectPath $directory) -Recurse -File | Where-Object { $_.Extension -in @('.gd', '.glsl', '.tres', '.tscn', '.ps1') }
})
$sources += Get-Item -LiteralPath (Join-Path $projectPath 'project.godot')
$hashes = @($sources | Get-FileHash)
$hashes | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidencePath 'source-hashes.json') -Encoding UTF8
$runs = @()
$cases = @()
foreach ($repeat in 1..3) {
	$order = if ($repeat % 2 -eq 1) { @('cpu', 'gpu') } else { @('gpu', 'cpu') }
	foreach ($backend in $order) {
		$cases += @{ name = "regions_$backend"; movement = $backend; timers = 'cpu'; wolfHz = 4; dogHz = 4; grids = $false; repeat = $repeat }
	}
}
foreach ($repeat in 1..3) {
	$cases += @{ name = 'timers64'; movement = 'gpu'; timers = 'gpu'; wolfHz = 4; dogHz = 4; grids = $false; repeat = $repeat }
	$cases += @{ name = 'dogs10'; movement = 'gpu'; timers = 'cpu'; wolfHz = 10; dogHz = 10; grids = $false; repeat = $repeat }
}
$cases += @{ name = 'grids'; movement = 'gpu'; timers = 'cpu'; wolfHz = 4; dogHz = 4; grids = $true; repeat = 1 }
foreach ($case in $cases) {
	foreach ($source in $hashes) {
		if ((Get-FileHash -LiteralPath $source.Path).Hash -ne $source.Hash) { throw "Source changed during matrix: $($source.Path)" }
	}
	$label = "motion_$($case.name)_$($case.repeat)_$stamp"
	$logPath = Join-Path $evidencePath "$label.log"
	& (Join-Path $PSScriptRoot 'RunBenchmark.ps1') -GodotPath $GodotPath -MainScene -Compute gpu -MovementCompute $case.movement -TimersCompute $case.timers -SimulationHz 30 -SheepHz 4 -WolfHz $case.wolfHz -DogHz $case.dogHz -DebugGrids:$case.grids -Warmup 5 -Duration 30 -MaxFps 60 -Sampling stages -Hud on -Overlay on -Animals on -Label $label *> $logPath
	if ($LASTEXITCODE -ne 0) { throw "Benchmark failed: $logPath" }
	$directory = Get-ChildItem -LiteralPath (Join-Path $projectPath 'output\performance') -Directory | Where-Object { $_.Name -like "*_$label`_*" } | Select-Object -Last 1
	if ($null -eq $directory) { throw "Missing result: $label" }
	$resultPath = Join-Path $directory.FullName 'result.json'
	$result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
	if ($result.renderer -ne 'forward_plus' -or $result.compute.failure -ne '' -or $result.compute.fallback_reason -ne '') { throw "Backend failure: $resultPath" }
	foreach ($stage in @(@('Movement', $case.movement), @('Timers', $case.timers))) {
		$samples = @($result.compute.numeric.samples.($stage[0]))
		if ($stage[1] -eq 'gpu' -and ($samples.Count -eq 0 -or @($samples | Where-Object { $_.gpu_ms -lt 0 }).Count -gt 0)) { throw "Missing numeric GPU timestamps: $resultPath" }
	}
	$runs += [ordered]@{ case = $case; result = $resultPath }
	$runs | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidencePath 'runs.json') -Encoding UTF8
	Write-Output "MOTION_RUN case=$($case.name) repeat=$($case.repeat) hz=$($result.actual_simulation_hz) step_ms=$($result.step_mean_ms) result=$resultPath"
}
foreach ($source in $hashes) {
	if ((Get-FileHash -LiteralPath $source.Path).Hash -ne $source.Hash) { throw "Source changed during matrix: $($source.Path)" }
}
Write-Output "MOTION_MATRIX_COMPLETE evidence=$evidencePath"
