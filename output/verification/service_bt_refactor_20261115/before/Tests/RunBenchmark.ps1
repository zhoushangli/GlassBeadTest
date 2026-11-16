param(
	[string]$GodotPath = 'C:\Work\Godot\Editor\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe',
	[ValidateSet(1000, 2000, 3000, 4000)][int]$Entities,
	[ValidateSet('scaled', 'fixed')][string]$Scenario,
	[ValidateSet(1, 2, 4, 6)][int]$Tiles = 1,
	[ValidateSet('spread', 'cluster')][string]$Layout = 'spread',
	[ValidateSet('on', 'off')][string]$Stats = 'on',
	[ValidateSet('off', 'stages', 'detailed')][string]$Sampling = 'stages',
	[ValidateSet('on', 'off')][string]$Hud = 'on',
	[ValidateSet('off', 'on', 'details')][string]$Overlay = 'on',
	[ValidateSet('on', 'off')][string]$Animals = 'on',
	[ValidatePattern('^[a-zA-Z][a-zA-Z0-9_-]*$')][string]$Label = 'benchmark',
	[ValidateRange(0.01, 3600)][double]$Duration = 30,
	[ValidateRange(0, 3600)][double]$Warmup = 3,
	[ValidateRange(1, 3600)][int]$TimeoutSeconds = 120,
	[ValidateRange(0, 10000)][int]$MaxFps = 0,
	[switch]$Headless,
	[switch]$Profile
)

$ErrorActionPreference = 'Stop'
if ($PSBoundParameters.ContainsKey('Entities') -or $PSBoundParameters.ContainsKey('Scenario')) {
	if (-not $Entities -or -not $Scenario -or $PSBoundParameters.ContainsKey('Tiles') -or $PSBoundParameters.ContainsKey('Layout')) {
		throw 'Use -Entities and -Scenario together, without -Tiles or -Layout.'
	}
	$populationArguments = "--entities=$Entities --scenario=$Scenario"
} else {
	$populationArguments = "--tiles=$Tiles --layout=$Layout"
}
if (-not $PSBoundParameters.ContainsKey('Sampling') -and $Stats -eq 'off') {
	$Sampling = 'off'
}
$projectPath = Split-Path -Parent $PSScriptRoot
$godotExecutable = (Resolve-Path -LiteralPath $GodotPath).Path
$runName = '{0}_launcher_{1}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$logDirectory = Join-Path $projectPath "output\performance\$runName"
New-Item -ItemType Directory -Path $logDirectory | Out-Null
$flags = @()
if ($Headless) {
	$flags += '--headless'
}
if ($Profile) {
	$flags += '--debug', '--profiling'
}
$culture = [Globalization.CultureInfo]::InvariantCulture
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $godotExecutable
$startInfo.WorkingDirectory = $projectPath
$startInfo.Arguments = '--path "{0}" --script res://Tests/RunBenchmark.gd {1} -- {2} --stats={3} --duration={4} --warmup={5} --max-fps={6}' -f $projectPath, ($flags -join ' '), $populationArguments, $Stats, $Duration.ToString($culture), $Warmup.ToString($culture), $MaxFps
$startInfo.Arguments += ' --sampling={0} --hud={1} --overlay={2} --animals={3} --label={4}' -f $Sampling, $Hud, $Overlay, $Animals, $Label
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$process = New-Object System.Diagnostics.Process
$process.StartInfo = $startInfo
$clock = [Diagnostics.Stopwatch]::StartNew()
$process.Start() | Out-Null
$stdout = $process.StandardOutput.ReadToEndAsync()
$stderr = $process.StandardError.ReadToEndAsync()
$status = [ordered]@{
	pid = $process.Id
	executable = $godotExecutable
	arguments = $startInfo.Arguments
	timeout_seconds = $TimeoutSeconds
	state = 'running'
}
$statusPath = Join-Path $logDirectory 'launcher.json'
$status | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8
Write-Output "BENCHMARK_LAUNCH pid=$($process.Id) timeout=${TimeoutSeconds}s logs=$logDirectory"
$completed = $process.WaitForExit($TimeoutSeconds * 1000)
if (-not $completed) {
	# 1) Stop only the process tree created by this launcher.
	& taskkill.exe /PID $process.Id /T /F | Out-Null
	if ($LASTEXITCODE -ne 0 -or -not $process.WaitForExit(5000)) {
		$status.state = 'cleanup_failed'
		$status | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8
		throw "Unable to stop benchmark process $($process.Id)."
	}
}
if (-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)) {
	throw 'Benchmark output streams did not close after process exit.'
}
$outputText = $stdout.Result
$outputText | Set-Content -LiteralPath (Join-Path $logDirectory 'stdout.log') -Encoding UTF8
$stderr.Result | Set-Content -LiteralPath (Join-Path $logDirectory 'stderr.log') -Encoding UTF8
$status.state = if ($completed) { 'exited' } else { 'timeout' }
$status['exit_code'] = $process.ExitCode
$status['wall_seconds'] = $clock.Elapsed.TotalSeconds
$status['has_result'] = $outputText.Contains('BENCHMARK_RESULT ')
$resultMatch = [regex]::Match($outputText, 'BENCHMARK_RESULT (res://\S+/result.json) ')
if ($resultMatch.Success) {
	$status['result_path'] = $resultMatch.Groups[1].Value
}
$status | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8
Write-Output "BENCHMARK_EXIT state=$($status.state) code=$($status.exit_code) result=$($status.has_result) logs=$logDirectory"
$exitCode = $process.ExitCode
$process.Dispose()
if (-not $completed) {
	exit 124
}
if ($exitCode -eq 0 -and -not $status.has_result) {
	exit 1
}
exit $exitCode
