param(
	[string]$ReleasePath = 'C:\Work\Godot\Project\export\GlassBeadTest.exe'
)

$ErrorActionPreference = 'Stop'
python -X utf8 (Join-Path $PSScriptRoot 'RunReleaseBenchmark.py') --executable $ReleasePath --matrix
exit $LASTEXITCODE
