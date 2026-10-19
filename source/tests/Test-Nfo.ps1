# Offline test (temp folder, Recycle Bin mocked): Setup option "Delete .nfo files during Full Run".
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
function PR-TmdbGet($db, [string]$path, $params) { return [pscustomobject]@{ results = @(); episodes = @() } }
$root = Join-Path ([IO.Path]::GetTempPath()) ("prnfo_" + [guid]::NewGuid().ToString('N').Substring(0, 6))
$bin = Join-Path $root 'bin'; [void][IO.Directory]::CreateDirectory($bin)
$script:recycled = New-Object System.Collections.Generic.List[string]
function PR-RecycleFile([string]$p) { $script:recycled.Add($p); [IO.File]::Move($p, (Join-Path $bin ([guid]::NewGuid().ToString('N') + '.nfo'))) }   # mock: no real Recycle Bin
function PR-HasRecycleBin([string]$p) { return ($p -notlike '*NoBin*') }
$M = Join-Path $root 'Movies'
$files = @('Alpha (2000)\Alpha (2000).mkv', 'Alpha (2000)\Alpha.2000.x264.nfo', 'OnlyNfo\movie.nfo', 'Beta (2001)\Beta (2001).mkv', 'Beta (2001)\Beta (2001).nfo',
           'Hidden\h.nfo', 'Sys\s.nfo', '@eaDir\e.nfo', 'NoBin (2002)\NoBin (2002).mkv', 'NoBin (2002)\x.nfo')
foreach ($f in $files) { $p = Join-Path $M $f; [void][IO.Directory]::CreateDirectory((Split-Path $p)); [IO.File]::WriteAllText($p, $f) }
(Get-Item -LiteralPath (Join-Path $M 'Hidden')).Attributes = 'Directory, Hidden'
(Get-Item -LiteralPath (Join-Path $M 'Sys')).Attributes = 'Directory, System'
$db = New-PRTmdb -Key 'x' -CachePath (Join-Path $root 'c.json') -Source 'TMDB only'
function Plan { $pl = Get-PRFiles @($M); New-PRPlan -Paths $pl -MoviesRoot $M -SeriesRoot '' -Db $db -ProbeReal $false -FolderLoose $false }
function RowOf($rows, $rel) { $p = Join-Path $M $rel; $rows | Where-Object { $_.old_path -eq $p } }

$script:PR_DELETE_NFO = $false
$off = Plan
Check ((RowOf $off 'Alpha (2000)\Alpha.2000.x264.nfo').new_path -ceq (Join-Path $M 'Alpha (2000)\Alpha (2000).nfo')) "option off: .nfo is re-attached as before"
$script:PR_DELETE_NFO = $true
$on = Plan
$a = RowOf $on 'Alpha (2000)\Alpha.2000.x264.nfo'
Check (-not $a.new_path -and ([string]$a.note).StartsWith('nfo: delete')) "option on: .nfo planned as 'nfo: delete', not renamed"
Check (([string](RowOf $on 'Hidden\h.nfo').note).StartsWith('nfo: kept') -and ([string](RowOf $on 'Sys\s.nfo').note).StartsWith('nfo: kept')) "nfo in hidden / system folder: kept"
Check ((Get-PRNfoLine $on) -eq 'NFO files: 4 (sent to Recycle Bin on Full Run)') "scan line counts deletable .nfo files [$(Get-PRNfoLine $on)]"
Check (@(Get-PRNfoFiles @($M)).Count -eq 4) "Get-PRNfoFiles skips hidden, system and @eaDir folders"

# Full Run with the option off keeps every .nfo
$u0 = Join-Path $root 'undo0.csv'
$r0 = Invoke-PRApply -Rows @() -HighOnly -UndoLog $u0 -Roots @($M) -RemoveEmpty
Check ([IO.File]::Exists((Join-Path $M 'OnlyNfo\movie.nfo')) -and $script:recycled.Count -eq 0) "Full Run without the option: nothing deleted"

$undo = Join-Path $root 'undo.csv'
$r = Invoke-PRApply -Rows $on -HighOnly -UndoLog $undo -Roots @($M) -RemoveEmpty -DeleteNfo
Check ($r.NfoRecycled -eq 3 -and $r.NfoKept -eq 1) "3 sent to the Recycle Bin, 1 kept (no Recycle Bin on that drive) [$($r.NfoRecycled)/$($r.NfoKept)]"
Check (-not [IO.File]::Exists((Join-Path $M 'Alpha (2000)\Alpha.2000.x264.nfo')) -and -not [IO.File]::Exists((Join-Path $M 'Beta (2001)\Beta (2001).nfo'))) ".nfo files removed"
Check ([IO.File]::Exists((Join-Path $M 'NoBin (2002)\x.nfo'))) "no Recycle Bin: never hard-deleted"
Check (-not [IO.Directory]::Exists((Join-Path $M 'OnlyNfo'))) "folder that only held an .nfo is removed by the empty-folder clean-up"
Check ([IO.File]::Exists((Join-Path $M 'Hidden\h.nfo')) -and [IO.File]::Exists((Join-Path $M 'Sys\s.nfo')) -and [IO.File]::Exists((Join-Path $M '@eaDir\e.nfo'))) "hidden, system and @eaDir .nfo files untouched"
$csv = @(Import-Csv $undo)
Check (@($csv | Where-Object { $_.how -eq 'recycle' }).Count -eq 3 -and @($csv | Where-Object { $_.how -eq 'rmdir' -and $_.old_path -like '*OnlyNfo' }).Count -eq 1) "undo CSV: how=recycle per file, plus the removed folder"
$csvOrder = @($csv | ForEach-Object { $_.how }) -join ','
Check ($csvOrder.IndexOf('recycle') -lt $csvOrder.IndexOf('rmdir')) "deletions run before the empty-folder clean-up"
$un = Invoke-PRUndo -UndoLog $undo
Check ($un.Recycled -eq 3 -and [IO.Directory]::Exists((Join-Path $M 'OnlyNfo'))) "Undo reports 3 .nfo files in the Recycle Bin and still recreates the folder"
Get-ChildItem -LiteralPath $root -Recurse -Force | ForEach-Object { $_.Attributes = 'Normal' }
Remove-Item -LiteralPath $root -Recurse -Force
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASS' }
