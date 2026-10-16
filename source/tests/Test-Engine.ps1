# Offline parity test: runs the engine on a path list using a cache file, writes plan CSV. Usage:
# pwsh Test-Engine.ps1 -PathsFile paths.txt -Cache cache.json -Out out.csv [-Key <tmdbkey>]
param([string]$PathsFile, [string]$Cache, [string]$Out, [string]$Key = '',
      [string]$Movies = 'Z:\LG_NAS_Backup\Media\Movies', [string]$Series = 'Z:\LG_NAS_Backup\Media\Series')
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$paths = [IO.File]::ReadAllLines($PathsFile, [Text.Encoding]::UTF8)
$db = New-PRTmdb -Key $Key -CachePath $Cache
$sw = [Diagnostics.Stopwatch]::StartNew()
$rows = New-PRPlan -Paths $paths -MoviesRoot $Movies -SeriesRoot $Series -Db $db
Export-PRPlan $rows $Out
Write-Host (Get-PRSummary $rows) "in $([int]$sw.Elapsed.TotalSeconds)s; TMDB calls: $($db.Calls)"
