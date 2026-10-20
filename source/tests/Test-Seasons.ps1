# Offline test (temp folder): Setup option "Standardize season folder names" (Season 1 / S01 / season1 ... -> Season 01, renamed in place).
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
$root = Join-Path ([IO.Path]::GetTempPath()) ("prsea_" + [guid]::NewGuid().ToString('N').Substring(0, 6))
$S = Join-Path $root 'Series'; $Sh = Join-Path $S 'Show'
foreach ($n in @('Season 1', 's2', 'Series 3', 'Season_4', 'Season 5 (2010)', 'season 06', 'S07', 'Season 07x', 'Season 08', 'Extras', 'Specials', 'Season 9', 'Season 09', 'Season10')) { [void][IO.Directory]::CreateDirectory((Join-Path $Sh $n)) }
[IO.Directory]::Delete((Join-Path $Sh 'Season 07x'))
$Sp2 = Join-Path $S 'Other\Specials'; [void][IO.Directory]::CreateDirectory($Sp2); [IO.File]::WriteAllText("$Sp2\Other - S00E01 - Pilot.mkv", 'v')
[IO.File]::WriteAllText("$Sh\Specials\Behind the scenes.mkv", 'v')
$ep = Join-Path $Sh 'Season 1\Show.S01E01.mkv'; [IO.File]::WriteAllText($ep, 'video'); [IO.File]::WriteAllText((Join-Path $Sh 'Season 1\notes.txt'), 'not planned')
[IO.File]::WriteAllText((Join-Path $Sh 'season 06\Show - S06E01.mkv'), 'video')

foreach ($c in @(@('Season 1', 'Season 01'), @('season1', 'Season 01'), @('S1', 'Season 01'), @('S01', 'Season 01'), @('Season_1', 'Season 01'), @('Series 1', 'Season 01'), @('Season 1 (2010)', 'Season 01'), @('SEASON 12', 'Season 12'), @('Season 101', 'Season 101'), @('Season 01', 'Season 01'))) {
    Check ((PR-SeasonFolderName $c[0] $root) -ceq $c[1]) "'$($c[0])' -> '$($c[1])'"
}
foreach ($x in @('Extras', 'Featurettes', 'Season', 'Show S01E01', 'Sample')) { Check ($null -eq (PR-SeasonFolderName $x $root)) "'$x' is not a season folder" }
Check ($null -eq (PR-SeasonFolderName 'Specials' (Join-Path $Sh 'Specials'))) "Specials without S00 episode names: left as is"
Check ((PR-SeasonFolderName 'Specials' $Sp2) -ceq 'Season 00') "Specials whose episodes are named S00Exx -> Season 00"
Check ($null -eq (PR-SeasonFolderName 'Season 0' (Join-Path $Sh 'Extras'))) "Season 0 without S00 episodes: left as is"

$script:PR_SEASON_FIX = $true
$rows = @(Get-PRSeasonFolderRows $S)
function SR($n) { $p = Join-Path $Sh $n; $rows | Where-Object { $_.old_path -eq $p } }
Check ((SR 'Season 1').new_path -ceq (Join-Path $Sh 'Season 01') -and (SR 's2').new_path -ceq (Join-Path $Sh 'Season 02') -and (SR 'Series 3').new_path -ceq (Join-Path $Sh 'Season 03') -and (SR 'Season_4').new_path -ceq (Join-Path $Sh 'Season 04') -and (SR 'Season 5 (2010)').new_path -ceq (Join-Path $Sh 'Season 05') -and (SR 'Season10').new_path -ceq (Join-Path $Sh 'Season 10')) "rows for each non-standard season folder"
Check ((SR 'season 06').new_path -ceq (Join-Path $Sh 'Season 06') -and (SR 'season 06').note -like '*(letter case)*') "case-only difference planned"
Check (-not (SR 'Season 9').new_path -and (SR 'Season 9').note -like 'COLLISION*' -and -not (SR 'S07').note.StartsWith('COLLISION')) "target exists: COLLISION row, no new path (not merged)"
Check ($null -eq (SR 'Season 08') -and $null -eq (SR 'Extras') -and $null -eq (SR 'Specials') -and $null -eq (SR 'Season 09')) "standard, non-season and plain Specials folders get no row"
Check (@($rows | Where-Object { $_.old_path -eq $Sp2 -and $_.new_path -ceq (Join-Path $S 'Other\Season 00') }).Count -eq 1) "Other\Specials (S00 naming) -> Season 00"
Check ((Get-PRSeasonLine $rows) -eq 'Season folders to standardize: 9 (1 collision(s) left as they are)') "scan line [$(Get-PRSeasonLine $rows)]"

# an episode in 'Season 1' already planned into 'Season 01' (as New-PRPlan does), plus a case-only episode row
$e = PR-NewRow $ep; $e.media_type = 'episode'; $e.confidence = 'high'; $e.new_path = Join-Path $Sh 'Season 01\Show - S01E01 - Pilot.mkv'
$e6 = PR-NewRow (Join-Path $Sh 'season 06\Show - S06E01.mkv'); $e6.media_type = 'episode'; $e6.confidence = 'high'; $e6.new_path = Join-Path $Sh 'Season 06\Show - S06E01.mkv'
$all = @($rows) + @($e, $e6)
$rc = Get-PRRunCounts $all $true
Check ($rc.SeasonFolders -eq 9 -and $rc.Total -eq 1 -and $rc.CaseFolders -eq 0) "confirmation counts: 9 season folders, 1 file, the case-only episode folder not counted twice [$($rc.SeasonFolders)/$($rc.Total)/$($rc.CaseFolders)]"
$t1 = PR-TimesOf (Join-Path $Sh 'Season 1'); $t2 = PR-TimesOf (Join-Path $Sh 's2'); $tp = PR-TimesOf $Sh
$undo = Join-Path $root 'undo.csv'
$r = Invoke-PRApply -Rows $all -HighOnly -UndoLog $undo -Roots @($S) -FixSeasons
Check ($r.SeasonFixed -eq 9 -and $r.Moved -eq 1 -and $r.Failed -eq 0 -and $r.Skipped -eq 0) "Full Run: 9 folders renamed, episode renamed, nothing skipped [$($r.SeasonFixed)/$($r.Moved)/$($r.Skipped)/$($r.Failed)]"
Check (-not [IO.Directory]::Exists((Join-Path $Sh 'Season 1')) -and [IO.File]::Exists((Join-Path $Sh 'Season 01\Show - S01E01 - Pilot.mkv')) -and [IO.File]::Exists((Join-Path $Sh 'Season 01\notes.txt'))) "folder renamed in place (unplanned files went along), episode renamed inside it"
Check ((PR-TimesOf (Join-Path $Sh 'Season 02')) -eq $t2) "timestamps of a renamed folder kept [$t2 / $(PR-TimesOf (Join-Path $Sh 'Season 02'))]"
Check ((PR-TimesOf $Sh) -eq $tp) "timestamps of the show folder kept [$tp / $(PR-TimesOf $Sh)]"
Check ((PR-TimesOf (Join-Path $Sh 'Season 01')).Split('|')[0] -eq $t1.Split('|')[0]) "creation time of a renamed folder with an episode renamed inside kept"
Check (([IO.DirectoryInfo](Join-Path $Sh 'Season 06')).Name -ceq 'Season 06' -and @(Get-ChildItem -LiteralPath $Sh -Directory | Where-Object { $_.Name -ceq 'season 06' }).Count -eq 0) "case-only rename done (via a temporary name)"
Check ([IO.Directory]::Exists((Join-Path $Sh 'Season 9')) -and [IO.Directory]::Exists((Join-Path $Sh 'Season 09'))) "collision: both folders untouched"
Check ([IO.Directory]::Exists((Join-Path $Sh 'Specials')) -and [IO.Directory]::Exists((Join-Path $S 'Other\Season 00'))) "plain Specials kept; S00 Specials -> Season 00"
$csv = @(Import-Csv $undo)
Check (@($csv | Where-Object { $_.how -eq 'seasondir' }).Count -eq 9 -and $csv[0].how -eq 'seasondir' -and ($csv | Where-Object { $_.how -eq 'rename' }).old_path -eq (Join-Path $Sh 'Season 01\Show.S01E01.mkv')) "undo log: folders first, the episode logged from its new folder"
$un = Invoke-PRUndo -UndoLog $undo
Check ($un.Skipped -eq 0 -and [IO.File]::Exists($ep) -and [IO.File]::Exists((Join-Path $Sh 'Season 1\notes.txt')) -and -not [IO.Directory]::Exists((Join-Path $Sh 'Season 01')) -and @(Get-ChildItem -LiteralPath $Sh -Directory | Where-Object { $_.Name -ceq 'season 06' }).Count -eq 1) "Undo: episode and folder names back (including the letter case)"
Check ((PR-TimesOf (Join-Path $Sh 's2')) -eq $t2) "Undo keeps the folder's timestamps [$t2 / $(PR-TimesOf (Join-Path $Sh 's2'))]"

# season folder format (Setup text field): validation, tokens, custom formats
foreach ($ok in @('Season {NN}', 'S{NN}', 'Season {N}', 'Staffel {NNN}', 'Series {NN} (extras)')) { Check (-not (Test-PRSeasonFormat $ok)) "format '$ok' is valid" }
foreach ($bad in @('', '   ', 'Season', 'Season {NN} {N}', 'Season {NNNN}', 'Season {X}', 'Season: {NN}', 'S/{NN}', 'Season {NN}?', 'Season {NN}.', ' Season {NN}')) { Check ([bool](Test-PRSeasonFormat $bad)) "format '$bad' is rejected [$(Test-PRSeasonFormat $bad)]" }
Check ((PR-FormatSeason 1 'Season {N}') -ceq 'Season 1' -and (PR-FormatSeason 1 'Season {NN}') -ceq 'Season 01' -and (PR-FormatSeason 1 'Season {NNN}') -ceq 'Season 001' -and (PR-FormatSeason 12 'S{NN}') -ceq 'S12') "tokens {N} {NN} {NNN}"
Check ((PR-FormatSeason 3 'bad:{NN}') -ceq 'Season 03') "an invalid format falls back to the default"
$C = Join-Path $root 'Custom'; $Cs = Join-Path $C 'Show'
foreach ($n in @('Season 1', 'S02', 'season 3', 'S4', 'Season 05', 'Extras', 'S 6')) { [void][IO.Directory]::CreateDirectory((Join-Path $Cs $n)) }
$script:PR_SEASON_FIX = $true
$script:PR_SEASON_FORMAT = 'S{NN}'
$cr = @(Get-PRSeasonFolderRows $C); function CR($n) { $p = Join-Path $Cs $n; $cr | Where-Object { $_.old_path -eq $p } }
Check ((CR 'Season 1').new_path -ceq (Join-Path $Cs 'S01') -and (CR 'season 3').new_path -ceq (Join-Path $Cs 'S03') -and (CR 'S4').new_path -ceq (Join-Path $Cs 'S04') -and (CR 'Season 05').new_path -ceq (Join-Path $Cs 'S05') -and (CR 'S 6').new_path -ceq (Join-Path $Cs 'S06')) "format S{NN}: Season 1 -> S01, season 3 -> S03, S4 -> S04, S 6 -> S06"
Check ($null -eq (CR 'S02') -and $null -eq (CR 'Extras')) "format S{NN}: S02 already matches, left alone"
$script:PR_SEASON_FORMAT = 'Season {N}'
$cr = @(Get-PRSeasonFolderRows $C)
Check ($null -eq (CR 'Season 1') -and (CR 'S02').new_path -ceq (Join-Path $Cs 'Season 2') -and (CR 'Season 05').new_path -ceq (Join-Path $Cs 'Season 5') -and (CR 'season 3').new_path -ceq (Join-Path $Cs 'Season 3')) "format Season {N}: Season 1 kept; S02 -> Season 2, Season 05 -> Season 5, season 3 -> Season 3"
$script:PR_SEASON_FORMAT = 'Staffel {NN}'; [void][IO.Directory]::CreateDirectory((Join-Path $Cs 'Staffel 7'))
$cr = @(Get-PRSeasonFolderRows $C)
Check ((CR 'Staffel 7').new_path -ceq (Join-Path $Cs 'Staffel 07') -and (CR 'Season 1').new_path -ceq (Join-Path $Cs 'Staffel 01')) "custom words: variants of the format itself are recognised (Staffel 7 -> Staffel 07)"
[void][IO.Directory]::CreateDirectory((Join-Path $Cs 'Season 2'))
$script:PR_SEASON_FORMAT = 'S{NN}'; $cr = @(Get-PRSeasonFolderRows $C)
Check (@($cr | Where-Object { $_.note -like 'COLLISION*S02*' }).Count -ge 1) "two folders for the same season (S02 exists, Season 2 too): COLLISION, not merged"
$u3 = Join-Path $root 'undo3.csv'; $r3 = Invoke-PRApply -Rows $cr -HighOnly -UndoLog $u3 -Roots @($C) -FixSeasons
Check ([IO.Directory]::Exists((Join-Path $Cs 'S01')) -and [IO.Directory]::Exists((Join-Path $Cs 'S02')) -and [IO.Directory]::Exists((Join-Path $Cs 'Season 2')) -and $r3.Failed -eq 0) "Full Run with S{NN}: renamed, the collision left as is"
$script:PR_SEASON_FORMAT = 'Season {NN}'
# option off: no rows, and Invoke-PRApply without -FixSeasons renames nothing
$script:PR_SEASON_FIX = $false
$u2 = Join-Path $root 'undo2.csv'; $r2 = Invoke-PRApply -Rows $rows -HighOnly -UndoLog $u2 -Roots @($S)
Check ($r2.SeasonFixed -eq 0 -and [IO.Directory]::Exists((Join-Path $Sh 's2'))) "Full Run without the option: no folder renamed"
# never Z:
$z = PR-NewRow 'Z:\Series\Show\Season 1'; $z.media_type = 'season folder'; $z.new_path = 'Z:\Series\Show\Season 01'
$zl = New-Object System.Collections.Generic.List[object]
Check (@(Invoke-PRSeasonFolders @($z) $zl).Count -eq 0 -and @(Get-PRSeasonFolderRows 'Z:\Series').Count -eq 0) "Z: is never touched"
Remove-Item -LiteralPath $root -Recurse -Force
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASS' }
