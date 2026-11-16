param(
	[string]$GodotPath = 'C:\Work\Godot\Editor\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
)

$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$evidencePath = Join-Path $projectPath "output\compute-$stamp"
New-Item -ItemType Directory -Path $evidencePath | Out-Null
New-Item -ItemType File -Path (Join-Path $evidencePath '.gdignore') | Out-Null
$sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $projectPath 'Scripts'), (Join-Path $projectPath 'Shaders'), (Join-Path $projectPath 'Resources'), (Join-Path $projectPath 'Levels'), (Join-Path $projectPath 'Prefabs'), (Join-Path $projectPath 'Tests') -Recurse -File | Where-Object { $_.Extension -in @('.gd', '.glsl', '.tres', '.tscn', '.ps1') })
$sourceFiles += Get-Item -LiteralPath (Join-Path $projectPath 'project.godot')
$sourceHashes = @($sourceFiles | Get-FileHash)
$sourceHashes | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidencePath 'source-hashes.json') -Encoding UTF8
$runs = @()
foreach ($population in @(2000, 5000)) {
	foreach ($repeat in 1..3) {
		$backends = if ($repeat % 2 -eq 1) { @('cpu', 'gpu') } else { @('gpu', 'cpu') }
		foreach ($backend in $backends) {
			$deadline = [DateTime]::UtcNow.AddSeconds(120)
			while (@(Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'Godot*' -and $_.CommandLine -like '*RunBenchmark.gd*' }).Count -gt 0) {
				if ([DateTime]::UtcNow -gt $deadline) { throw 'Another benchmark is still running; retry after it exits.' }
				Start-Sleep -Seconds 2
			}
			foreach ($source in $sourceHashes) {
				if ((Get-FileHash -LiteralPath $source.Path).Hash -ne $source.Hash) { throw "Source changed during matrix: $($source.Path)" }
			}
			$label = "compute_${population}_${backend}_${repeat}_$stamp"
			$logPath = Join-Path $evidencePath "$label.log"
			& (Join-Path $PSScriptRoot 'RunBenchmark.ps1') -GodotPath $GodotPath -Compute $backend -Entities $population -Scenario scaled -Population 1000 -ArenaSize 5120x2880 -SimulationHz 30 -SheepHz 12 -Warmup 5 -Duration 30 -MaxFps 0 -Sampling stages -Hud on -Overlay on -Animals on -Label $label -TimeoutSeconds 120 *> $logPath
			if ($LASTEXITCODE -ne 0) {
				throw "Benchmark failed: $logPath"
			}
			$resultDirectory = Get-ChildItem -LiteralPath (Join-Path $projectPath 'output\performance') -Directory | Where-Object { $_.Name -like "*_$label`_*" } | Select-Object -Last 1
			if ($null -eq $resultDirectory) {
				throw "Missing result for $label"
			}
			$resultPath = Join-Path $resultDirectory.FullName 'result.json'
			$result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
			if ($result.renderer -ne 'forward_plus' -or $result.compute.samples.Count -eq 0 -or @($result.compute.samples | Where-Object { $_.backend -ne $backend }).Count -gt 0) {
				throw "Backend or renderer mismatch: $resultPath"
			}
			if ($backend -eq 'gpu' -and $result.compute.metrics.gpu_ms.count -ne $result.compute.samples.Count) {
				throw "Missing GPU timestamps: $resultPath"
			}
			$runs += [ordered]@{ population = $population; backend = $backend; repeat = $repeat; result = $resultPath }
			$runs | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidencePath 'runs.json') -Encoding UTF8
			Write-Output "COMPUTE_RUN population=$population backend=$backend repeat=$repeat fps=$($result.average_fps) latency_ms=$($result.compute.metrics.latency_ms.mean) result=$resultPath"
		}
	}
}
foreach ($source in $sourceHashes) {
	if ((Get-FileHash -LiteralPath $source.Path).Hash -ne $source.Hash) { throw "Source changed during matrix: $($source.Path)" }
}
Write-Output "COMPUTE_MATRIX_COMPLETE evidence=$evidencePath"
