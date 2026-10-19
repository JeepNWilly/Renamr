# Offline test (temp folder, mocked TMDB): folder letter-case fix and empty-folder cleanup, with undo.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
$films = @{ 'heat' = @(@{ id = 949; title = 'Heat'; date = '1995-12-15'; pop = 30 }) }
function PR-TmdbGet($db, [string]$path, $params) {
    if ($path -eq '/search/movie') {
        $list = @($films[([string]$params.query).ToLowerInvariant()])
        if ($params.primary_release_year) { $list = @($list | Where-Object { $_ -and $_.date.StartsWith([string]$params.primary_release_year) }) }
        return [pscustomobject]@{ results = @($list | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ id = $_.id; title = $_.title; original_title = $_.title; release_date = $_.date; popularity = $_.pop } }) }
    }
    return [pscustomobject]@{ results = @(); episodes = @() }
}
function DirName([string]$parent, [string]$like) { foreach ($d in [IO.Directory]::GetDirectories($parent)) { if ([IO.Path]::GetFileName($d) -ieq $like) { return [IO.Path]::GetFileName($d) } }; return $null }
$root = Join-Path ([IO.Path]::GetTempPath()) ("prdir_" + [guid]::NewGuid().ToString('N').Substring(0, 6))
$M = Join-Path $root 'Movies'; $S = Join-Path $root 'Series'
foreach ($d in (Join-Path $M 'heat (1995)'), $S) { [void][IO.Directory]::CreateDirectory($d) }
$f = Join-Path $M 'heat (1995)\Heat (1995).mkv'; 'x' | Set-Content -LiteralPath $f
'x' | Set-Content -LiteralPath (Join-Path $M 'heat (1995)\Heat (1995).en.srt')
$db = New-PRTmdb -Key 'x' -CachePath (Join-Path $root 'c.json') -Source 'TMDB only'

# ---- case-only folder rename ----
$pl = Get-PRFiles @($M); $rows = New-PRPlan -Paths $pl -MoviesRoot $M -SeriesRoot '' -Db $db -ProbeReal $false -FolderLoose $true
Check ((@($rows | Where-Object { $_.media_type -eq 'movie' })[0]).new_path -ceq (PR-Join $M 'Heat (1995)' 'Heat (1995).mkv')) "plan wants only the folder case changed"
Check (@($rows | Where-Object { Test-PRCaseOnly $_ }).Count -eq 2) "movie and its subtitle are case-only rows"
$vid = @($rows | Where-Object { $_.media_type -eq 'movie' })[0]; $sub = @($rows | Where-Object { $_.media_type -eq 'sidecar' })[0]
Check ($vid.case_rep -eq '1' -and $vid.note -like "folder renamed: 'heat (1995)' -> 'Heat (1995)'*") "the video row carries the folder note and is the one listed"
Check ($sub.case_rep -ne '1' -and $sub.note -like 'sidecar of * (folder case fix)' -and $sub.note -notlike '*folder renamed*') "subtitle row: short note, not listed in Folder case fixes"
Check (@($rows | Where-Object { $_.case_rep -eq '1' }).Count -eq 1) "one listed row per folder"
$rc = Get-PRRunCounts $rows $true
Check ($rc.CaseFolders -eq 1 -and $rc.High -eq 0 -and $rc.Total -eq 0) "counted as 1 folder fix, not as renamed files [$($rc.CaseFolders)/$($rc.High)/$($rc.Total)]"
Check ((Get-PRSummary $rows) -like '*0 ready to rename (high confidence), 1 folder name(s) to fix (letter case)*') "summary counts folder fixes separately"
$acc = [pscustomobject]@{ old_path = (PR-Join $M 'Redemption (2013)' 'Redemption (2013).mp4'); new_path = (PR-Join $M 'Rédemption (2013)' 'Rédemption (2013).mp4'); media_type = 'movie'; confidence = 'high'; note = ''; fold_path = ''; accepted = ''; group_key = 'movie|r' }
Check (-not (Test-PRCaseOnly $acc) -and (Get-PRRunCounts @($acc) $true).High -eq 1) "an accent change is a real rename"
$undo1 = Join-Path $root 'undo1.csv'
$r1 = Invoke-PRApply -Rows $rows -HighOnly -UndoLog $undo1 -Roots @($M, $S)
Check ((DirName $M 'heat (1995)') -ceq 'Heat (1995)') "folder itself renamed to the right case"
Check ($r1.CaseFixed -eq 1 -and $r1.Failed -eq 0 -and $r1.Moved -eq 0) "one folder case fix (once for 2 files), no failures"
Check (@(Import-Csv $undo1 | Where-Object { $_.how -eq 'dircase' }).Count -eq 1) "case fix recorded in the undo CSV"
$pl = Get-PRFiles @($M); $rows2 = New-PRPlan -Paths $pl -MoviesRoot $M -SeriesRoot '' -Db $db -ProbeReal $false -FolderLoose $true
Check (@($rows2 | Where-Object { $_.new_path }).Count -eq 0) "second scan: nothing to do"
$r2 = Invoke-PRApply -Rows $rows2 -HighOnly -UndoLog (Join-Path $root 'undo2.csv') -Roots @($M, $S)
Check ($r2.Moved -eq 0 -and $r2.CaseFixed -eq 0) "second Full Run moves 0 files"
$u1 = Invoke-PRUndo -UndoLog $undo1
Check ((DirName $M 'heat (1995)') -ceq 'heat (1995)' -and [IO.File]::Exists($f) -and [IO.File]::Exists((Join-Path $M 'heat (1995)\Heat (1995).en.srt'))) "undo restores the original folder case"
Check ($r1.Moved -eq 0) "the file itself was not moved again"
$rootFolder = Join-Path $root 'movies'
Check (@(PR-FixDirCase (Join-Path $rootFolder 'X') @($M)).Count -eq 0 -and (DirName $root 'Movies') -ceq 'Movies') "the library root itself is never renamed"

# ---- empty folders ----
$e1 = Join-Path $M 'Empty A\Sub\Deeper'; $e2 = Join-Path $M 'Empty B'; $full = Join-Path $M 'Has File\Sub'; $hid = Join-Path $M 'Hidden File'; $hdir = Join-Path $M 'Kept\.hiddendir'
$rb = Join-Path $M '$RECYCLE.BIN'; $se = Join-Path $S 'Show\Season 01'
foreach ($d in $e1, $e2, $full, $hid, $hdir, $rb, $se) { [void][IO.Directory]::CreateDirectory($d) }
'x' | Set-Content -LiteralPath (Join-Path $full 'movie.mkv')
$hf = Join-Path $hid 'desktop.ini'; 'x' | Set-Content -LiteralPath $hf; [IO.File]::SetAttributes($hf, 'Hidden')
[IO.File]::SetAttributes($hdir, 'Directory, Hidden')
$t0 = [DateTime]::SpecifyKind([DateTime]'2012-01-02 03:04:05', 'Utc')
foreach ($d in (Join-Path $M 'Empty A'), $e2) { [IO.Directory]::SetLastWriteTimeUtc($d, $t0); [IO.Directory]::SetCreationTimeUtc($d, $t0) }
$list = @(Get-PREmptyFolders @($M, $S))
Check ($list.Count -eq 6) "dry run lists the 6 empty folders ($($list.Count))"
Check (($list.IndexOf($e1) -lt $list.IndexOf((Join-Path $M 'Empty A')))) "deepest folders come first"
Check (-not ($list -contains $M) -and -not ($list -contains $S)) "roots are never listed"
Check (@(Get-PREmptyFolders @('Z:\Media\Movies')).Count -eq 0) "Z: is never touched"
$undo3 = Join-Path $root 'undo3.csv'
$r3 = Invoke-PRApply -Rows @() -HighOnly -UndoLog $undo3 -Roots @($M, $S) -RemoveEmpty
Check ($r3.Removed -eq 6) "Full Run removed 6 empty folders"
Check (-not [IO.Directory]::Exists((Join-Path $M 'Empty A')) -and -not [IO.Directory]::Exists($e2) -and -not [IO.Directory]::Exists((Join-Path $S 'Show'))) "nested empty folders removed, parents too"
Check ([IO.Directory]::Exists($full) -and [IO.File]::Exists((Join-Path $full 'movie.mkv'))) "folder with a file kept"
Check ([IO.Directory]::Exists($hid)) "a hidden file keeps its folder"
Check ([IO.Directory]::Exists($hdir) -and [IO.Directory]::Exists((Join-Path $M 'Kept'))) "hidden folder (and its parent) kept"
Check ([IO.Directory]::Exists($rb)) "recycle bin kept"
Check ([IO.Directory]::Exists($M) -and [IO.Directory]::Exists($S)) "Movies and Series roots kept"
Check (@(Import-Csv $undo3 | Where-Object { $_.how -eq 'rmdir' }).Count -eq 6) "each removed folder is in the undo CSV"
$u3 = Invoke-PRUndo -UndoLog $undo3
Check ([IO.Directory]::Exists($e1) -and [IO.Directory]::Exists($e2) -and [IO.Directory]::Exists($se)) "undo recreates the folders"
Check ([IO.Directory]::GetLastWriteTimeUtc($e2) -eq $t0 -and [IO.Directory]::GetCreationTimeUtc((Join-Path $M 'Empty A')) -eq $t0 -and [IO.Directory]::GetLastWriteTimeUtc((Join-Path $M 'Empty A')) -eq $t0) "recreated folders keep their original times"
[IO.File]::SetAttributes($hdir, 'Directory'); [IO.File]::SetAttributes($hf, 'Normal')
Remove-Item -LiteralPath $root -Recurse -Force
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASS' }
