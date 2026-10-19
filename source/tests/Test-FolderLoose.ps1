# Offline test (mocked TMDB, temp folder): "Put movies that are not in a folder into their own folder" during a Full Run.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
$films = @{ 'heat' = @(@{ id = 949; title = 'Heat'; date = '1995-12-15'; pop = 30 }); 'baby driver' = @(@{ id = 339403; title = 'Baby Driver'; date = '2017-06-28'; pop = 30 }) }
function PR-TmdbGet($db, [string]$path, $params) {
    if ($path -eq '/search/movie') {
        $list = @($films[([string]$params.query).ToLowerInvariant()])
        if ($params.primary_release_year) { $list = @($list | Where-Object { $_ -and $_.date.StartsWith([string]$params.primary_release_year) }) }
        return [pscustomobject]@{ results = @($list | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ id = $_.id; title = $_.title; original_title = $_.title; release_date = $_.date; popularity = $_.pop } }) }
    }
    return [pscustomobject]@{ results = @(); episodes = @() }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ("prfold_" + [guid]::NewGuid().ToString('N').Substring(0, 6))
$M = Join-Path $root 'Movies'; [void][IO.Directory]::CreateDirectory($M)
$files = 'Heat (1995).mkv', 'Baby Driver.mp4', 'Baby Driver.en.srt', 'Nothing Known (2001).mkv'   # already-correct name, rename needed (low: no year), its subtitle, unmatched
foreach ($f in $files) { 'x' | Set-Content -LiteralPath (Join-Path $M $f) }
$db = New-PRTmdb -Key 'x' -CachePath (Join-Path $root 'c.json') -Source 'TMDB only'
$paths = @($files | ForEach-Object { Join-Path $M $_ })
function Row($rows, $leaf) { $rows | Where-Object { (PR-Base $_.old_path) -eq $leaf } }

$rows = New-PRPlan -Paths $paths -MoviesRoot $M -SeriesRoot '' -Db $db -ProbeReal $false -FolderLoose $true
Check ((Row $rows 'Heat (1995).mkv').new_path -eq (PR-Join $M 'Heat (1995)' 'Heat (1995).mkv')) "already-correct loose name is planned into its own folder"
Check ((Row $rows 'Baby Driver.mp4').confidence -eq 'low') "no-year loose file is low confidence (the case that was skipped)"
Check ((Row $rows 'Baby Driver.mp4').fold_path -eq (PR-Join $M 'Baby Driver (2017)' 'Baby Driver.mp4')) "low row has a folder-only target"
Check ((Row $rows 'Baby Driver.en.srt').fold_path -eq (PR-Join $M 'Baby Driver (2017)' 'Baby Driver.en.srt')) "subtitle follows its video into the folder"
Check ((Row $rows 'Nothing Known (2001).mkv').fold_path -eq (PR-Join $M 'Nothing Known (2001)' 'Nothing Known (2001).mkv')) "unmatched loose file still gets a folder"

$undo = Join-Path $root 'undo.csv'
$r = Invoke-PRApply -Rows $rows -HighOnly -UndoLog $undo
Check ($r.Moved -eq 4 -and $r.Failed -eq 0) "Full Run (high-confidence only) moved all 4 loose files"
Check ([IO.File]::Exists((PR-Join $M 'Heat (1995)' 'Heat (1995).mkv'))) "already-correct file is now in its folder"
Check ([IO.File]::Exists((PR-Join $M 'Baby Driver (2017)' 'Baby Driver.mp4'))) "low-confidence file foldered, name kept"
Check ([IO.File]::Exists((PR-Join $M 'Baby Driver (2017)' 'Baby Driver.en.srt'))) "its subtitle foldered too"
Check (@([IO.Directory]::GetFiles($M)).Count -eq 0) "no loose files left in the Movies root"
$u = Invoke-PRUndo -UndoLog $undo
Check (@($files | Where-Object { [IO.File]::Exists((Join-Path $M $_)) }).Count -eq 4 -and @([IO.Directory]::GetDirectories($M)).Count -eq 0) "undo puts everything back and removes the new folders"

foreach ($f in $files) { if (-not [IO.File]::Exists((Join-Path $M $f))) { 'x' | Set-Content -LiteralPath (Join-Path $M $f) } }
$rows2 = New-PRPlan -Paths $paths -MoviesRoot $M -SeriesRoot '' -Db $db -ProbeReal $false -FolderLoose $false
Check (@($rows2 | Where-Object { $_.fold_path }).Count -eq 0) "option off: no folder-only moves"
Check ((Row $rows2 'Heat (1995).mkv').new_path -eq '') "option off: already-correct loose file left alone"
$r2 = Invoke-PRApply -Rows $rows2 -HighOnly -UndoLog (Join-Path $root 'undo2.csv')
Check ([IO.File]::Exists((Join-Path $M 'Baby Driver.mp4'))) "option off: low-confidence loose file untouched"
Remove-Item -LiteralPath $root -Recurse -Force
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASS' }
