$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$launcher = Join-Path $projectPath 'Tests\RunBenchmark.ps1'
$runs = @(
	@{ Label = 'fixed-stages-1'; Scenario = 'fixed' },
	@{ Label = 'scaled-stages-1'; Scenario = 'scaled' },
	@{ Label = 'fixed-stages-2'; Scenario = 'fixed' },
	@{ Label = 'scaled-stages-2'; Scenario = 'scaled' },
	@{ Label = 'fixed-stages-3'; Scenario = 'fixed' },
	@{ Label = 'scaled-stages-3'; Scenario = 'scaled' },
	@{ Label = 'fixed-off'; Scenario = 'fixed'; Sampling = 'off' },
	@{ Label = 'fixed-detailed'; Scenario = 'fixed'; Sampling = 'detailed' },
	@{ Label = 'fixed-headless'; Scenario = 'fixed'; Headless = $true },
	@{ Label = 'fixed-no-debug'; Scenario = 'fixed'; Hud = 'off'; Overlay = 'off' },
	@{ Label = 'fixed-lines'; Scenario = 'fixed'; Overlay = 'details' },
	@{ Label = 'fixed-hide-animals'; Scenario = 'fixed'; Animals = 'off' },
	@{ Label = 'fixed-hide-grass'; Scenario = 'fixed'; Grass = 'off' },
	@{ Label = 'fixed-hide-both'; Scenario = 'fixed'; Animals = 'off'; Grass = 'off' },
	@{ Label = 'fixed-cap60'; Scenario = 'fixed'; MaxFps = 60 },
	@{ Label = 'fixed-profiler'; Scenario = 'fixed'; Profile = $true },
	@{ Label = 'fixed-closing'; Scenario = 'fixed' }
)
$manifest = @()
foreach ($run in $runs) {
	$arguments = @('-NoProfile', '-File', $launcher, '-Entities', '1000', '-Warmup', '5', '-Duration', '60', '-TimeoutSeconds', '120')
	foreach ($key in $run.Keys) {
		$arguments += '-' + $key
		if ($run[$key] -isnot [bool]) {
			$arguments += [string]$run[$key]
		}
	}
	Write-Output "SUITE_START $($run.Label)"
	$output = & powershell @arguments 2>&1
	$runExitCode = $LASTEXITCODE
	$output | Set-Content -LiteralPath (Join-Path $PSScriptRoot ($run.Label + '.launcher.log')) -Encoding UTF8
	$match = [regex]::Match(($output -join "`n"), 'BENCHMARK_LAUNCH[^\r\n]*logs=([^\r\n]+)')
	$entry = [ordered]@{ label = $run.Label; exit_code = $runExitCode; options = $run }
	if ($match.Success) {
		$launcherPath = Join-Path $match.Groups[1].Value.Trim() 'launcher.json'
		$entry.launcher = $launcherPath
		$entry.status = Get-Content -LiteralPath $launcherPath -Raw | ConvertFrom-Json
	}
	$manifest += $entry
	ConvertTo-Json -InputObject $manifest -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Encoding UTF8
	Write-Output "SUITE_FINISH $($run.Label) exit=$runExitCode"
}
