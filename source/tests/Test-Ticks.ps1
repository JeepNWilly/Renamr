# The grid's Accept box shows what Full Run will do: option rows (.nfo, duplicate subtitles, season folders) and high-confidence renames start ticked;
# unticking a row skips just that file / folder (a movie with its subtitles); an option that is off shows unticked with a note.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
$root = Join-Path ([IO.Path]::GetTempPath()) ("prtick_" + [guid]::NewGuid().ToString('N').Substring(0, 6)); $M = Join-Path $root 'Movies'; $S = Join-Path $root 'Series'
function MkR($old, $new, $type, $conf, $note, $gk = '') { $r = PR-NewRow $old; $r.new_path = $new; $r.media_type = $type; $r.confidence = $conf; $r.note = $note; $r.group_key = $gk; $r }
$hv = MkR "$M\a.mkv" "$M\A (2000)\A (2000).mkv" 'movie' 'high' 'matched' 'movie|a'
$hs = MkR "$M\a.en.srt" "$M\A (2000)\A (2000).en.srt" 'sidecar' 'high' 'sidecar of a.mkv' 'movie|a'
$lv = MkR "$M\b.mkv" "$M\B (2001)\B (2001).mkv" 'movie' 'low' 'matched' 'movie|b'
$nf = MkR "$M\x\x.nfo" '' 'sidecar' '' 'nfo: delete (sent to the Recycle Bin on Full Run)'
$du = MkR "$M\A (2000)\Subs\English.srt" '' 'sidecar' '' 'DUPLICATE sidecar target (same language already placed); will be recycled (Recycle Bin on Full Run; keeps A (2000).en.srt)' 'movie|a'
Add-Member -InputObject $du -NotePropertyName dup_of -NotePropertyValue "$M\A (2000)\A (2000).en.srt"
$sd = MkR "$S\Show\season 1" "$S\Show\Season 01" 'season folder' 'high' "season folder: 'season 1' -> 'Season 01'"
$al = MkR "$M\c.mkv" '' 'movie' 'high' 'already correctly named; skipped' 'movie|c'
$rows = @($hv, $hs, $lv, $nf, $du, $sd, $al)
$script:PR_DELETE_NFO = $true; $script:PR_RECYCLE_DUPSUBS = $true; $script:PR_SEASON_FIX = $true; $script:PR_ONLY_TICKED = $false
Check ((Test-PRWillAct $hv) -and (Test-PRWillAct $hs)) "high-confidence rename (and its subtitle) start ticked"
Check (-not (Test-PRWillAct $lv)) "low-confidence rename starts unticked (Only high-confidence)"
Check (Test-PRWillAct $lv $false) "low-confidence rename is ticked when Only high-confidence is off (Full Run renames it)"
Check ((Test-PRWillAct $nf) -and (Test-PRWillAct $du) -and (Test-PRWillAct $sd)) "NFO delete, duplicate subtitle recycle and season folder rows start ticked"
Check (-not (Test-PRWillAct $al) -and -not (Get-PRActKind $al)) "an already named file has nothing to tick"
# option off
$script:PR_DELETE_NFO = $false; $script:PR_RECYCLE_DUPSUBS = $false; $script:PR_SEASON_FIX = $false
Check (-not (Test-PRWillAct $nf) -and -not (Test-PRWillAct $du) -and -not (Test-PRWillAct $sd)) "option off in Setup: those rows show unticked"
Check ((Get-PROptionOff $nf) -like '*nfo*' -and (Get-PROptionOff $du) -like '*duplicate*' -and (Get-PROptionOff $sd) -like '*season*') "option off: the row names the Setup option"
$script:PR_DELETE_NFO = $true; $script:PR_RECYCLE_DUPSUBS = $true; $script:PR_SEASON_FIX = $true
# untick one duplicate subtitle: only that file
$n = Set-PRRowAct $rows $du $false
Check ($n -eq 1 -and -not (Test-PRWillAct $du) -and (Test-PRWillAct $hv) -and (Test-PRWillAct $hs)) "unticking a recycle row skips just that file (its video and kept copy still move)"
Check ((Get-PRDupSubLine $rows) -like '*: 0 *') "the duplicate-subtitle count leaves out the unticked file"
[void][IO.Directory]::CreateDirectory("$M\A (2000)\Subs"); [IO.File]::WriteAllText($du.old_path, 'x'); [IO.File]::WriteAllText($du.dup_of, 'x')
$log = New-Object System.Collections.Generic.List[object]; $res = Remove-PRDupSubs $rows $log
Check ($res.Recycled -eq 0 -and [IO.File]::Exists($du.old_path)) "Full Run keeps an unticked duplicate subtitle"
[void](Set-PRRowAct $rows $du $true); Check (Test-PRWillAct $du) "ticking it again: it will be recycled"
# NFO
[void][IO.Directory]::CreateDirectory("$M\x"); [IO.File]::WriteAllText($nf.old_path, 'n')
[void](Set-PRRowAct $rows $nf $false); $sk = @{ $nf.old_path.ToLowerInvariant() = 1 }
$res = Remove-PRNfoFiles @("$M\x") $log $sk
Check ($res.Recycled -eq 0 -and $res.Kept -eq 1 -and [IO.File]::Exists($nf.old_path)) "Full Run keeps an unticked .nfo file"
# season folder
[void][IO.Directory]::CreateDirectory($sd.old_path); [void](Set-PRRowAct $rows $sd $false)
$done = @(Invoke-PRSeasonFolders $rows $log)
Check ($done.Count -eq 0 -and (@([IO.Directory]::GetDirectories("$S\Show")) | ForEach-Object { [IO.Path]::GetFileName($_) }) -ceq 'season 1') "Full Run leaves an unticked season folder as is"
Check ((Get-PRRunCounts $rows $true).SeasonFolders -eq 0) "the confirmation does not count the unticked season folder"
# a movie: untick takes its subtitles along, so the names stay consistent
$before = (Get-PRRunCounts $rows $true).Total
$n = Set-PRRowAct $rows $hv $false
Check ($n -eq 2 -and -not (PR-ApplyTarget $hv $true) -and -not (PR-ApplyTarget $hs $true)) "unticking a high-confidence movie skips it and its subtitle"
Check ((Get-PRRunCounts $rows $true).Total -eq $before - 2) "the confirmation counts drop by those files"
[void](Set-PRRowAct $rows $hv $true); Check ((PR-ApplyTarget $hv $true) -and (Test-PRWillAct $hs)) "ticking it again restores both"
# low confidence: tick = accept
[void](Set-PRRowAct $rows $lv $true); Check ($lv.accepted -eq 'yes' -and (Test-PRWillAct $lv) -and (PR-ApplyTarget $lv $true)) "ticking a low-confidence row accepts it"
[void](Set-PRRowAct $rows $lv $false); Check (-not (Test-PRWillAct $lv) -and -not (PR-ApplyTarget $lv $false)) "unticking it: not renamed even when Only high-confidence is off"
# only ticked mode
$script:PR_ONLY_TICKED = $true; [void](Set-PRRowAct $rows $lv $true)
Check (-not (Test-PRWillAct $hv) -and (Test-PRWillAct $lv) -and (Test-PRWillAct $nf) -eq $false -and (Test-PRWillAct $du)) "Only ticked mode: untouched renames show unticked, the ticked one ticked"
$script:PR_ONLY_TICKED = $false
Remove-Item -LiteralPath $root -Recurse -Force
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASS' }
