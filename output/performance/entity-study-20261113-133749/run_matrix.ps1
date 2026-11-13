$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$runs = @()
foreach ($headless in @($true, $false)) {
 foreach ($scenario in @('scaled','fixed')) {
  foreach ($count in @(1000,2000,3000,4000)) {
   foreach ($repeat in 1..3) {
    $runs += [ordered]@{group='formal';headless=$headless;scenario=$scenario;entities=$count;repeat=$repeat;stats='on';profile=$false;warmup=3;duration=30}
   }
  }
 }
}
foreach ($count in @(1000,4000)) {
 foreach ($repeat in 1..3) {
  $runs += [ordered]@{group='stats_off';headless=$true;scenario='scaled';entities=$count;repeat=$repeat;stats='off';profile=$false;warmup=3;duration=30}
 }
}
foreach ($scenario in @('scaled','fixed')) {
 foreach ($count in @(1000,4000)) {
  $runs += [ordered]@{group='profile';headless=$true;scenario=$scenario;entities=$count;repeat=1;stats='on';profile=$true;warmup=1;duration=5}
 }
}
$ledger = @()
$index = 0
foreach ($run in $runs) {
 $index++
 Write-Output "START $index/$($runs.Count) $($run.group) headless=$($run.headless) $($run.scenario) $($run.entities) repeat=$($run.repeat)"
 $arguments = @{Entities=$run.entities;Scenario=$run.scenario;Stats=$run.stats;Warmup=$run.warmup;Duration=$run.duration;TimeoutSeconds=90;Headless=$run.headless;Profile=$run.profile}
 $timer = [Diagnostics.Stopwatch]::StartNew()
 $lines = @(& (Join-Path $projectPath 'Tests/RunBenchmark.ps1') @arguments)
 $run['exit_code'] = $LASTEXITCODE
 $run['elapsed_seconds'] = $timer.Elapsed.TotalSeconds
 $lines | Set-Content -LiteralPath (Join-Path $PSScriptRoot ('run-{0:d2}.log' -f $index)) -Encoding UTF8
 $launchLine = $lines | Where-Object { $_ -match 'logs=' } | Select-Object -Last 1
 if ($launchLine -match 'logs=(.+)$') {
  $launch = $Matches[1].Trim()
  $run['launcher'] = $launch.Substring($projectPath.Length + 1).Replace('\','/')
  $stdout = Get-Content -LiteralPath (Join-Path $launch 'stdout.log') -Encoding UTF8
  $resultLine = $stdout | Where-Object { $_ -like 'BENCHMARK_RESULT *' } | Select-Object -Last 1
  if ($resultLine -match '^BENCHMARK_RESULT (res://.+) (\{.+)$') {
   $run['result'] = $Matches[1].Substring(6)
   $result = $Matches[2] | ConvertFrom-Json
   Write-Output ('METRICS step={0:N2}ms p95={1:N2}ms max={2:N2}ms ratio={3:N3} sim={4:N2}s' -f $result.step_mean_ms,$result.step_p95_ms,$result.step_max_ms,$result.simulation_wall_ratio,$result.simulation_seconds_advanced)
  }
 }
 $ledger += [pscustomobject]$run
 ConvertTo-Json -InputObject @($ledger) -Depth 12 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'matrix.json') -Encoding UTF8
 Write-Output "DONE $index/$($runs.Count) exit=$($run.exit_code) elapsed=$([math]::Round($run.elapsed_seconds,1))s"
}
Write-Output 'MATRIX_COMPLETE'
