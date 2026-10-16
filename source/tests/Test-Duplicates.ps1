# Tests duplicate grouping, sidecar lookup, default keep choice and deletion (permanent mode, temp folder).
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
function Row($o, $n, $t, $c, $note) { [pscustomobject]@{ old_path = $o; new_path = $n; media_type = $t; tmdb_id = '1'; confidence = $c; note = $note } }
$M = 'Z:\Media\Movies'; $S = 'Z:\Media\Series'
$rows = @(
  (Row "$M\Joker.2019.1080p.mkv" "$M\Joker (2019)\Joker (2019).mkv" 'movie' 'high' 'MULTIPLE VERSIONS (2 files) of same movie; matched'),
  (Row "$M\Joker (2019).mp4" "$M\Joker (2019)\Joker (2019).mp4" 'movie' 'high' 'MULTIPLE VERSIONS (2 files) of same movie; matched'),
  (Row "$M\Joker 720p.mp4" '' 'movie' 'low' "DUPLICATE: same target as $M\Joker (2019).mp4; matched"),
  (Row "$S\Colony\S01\Colony.S01E05.1080p.mkv" "$S\Colony (2016)\Season 01\x.mkv" 'episode' 'high' 'show'),
  (Row "$S\Colony\S01\Colony.S01E05.720p.mkv" '' 'episode' 'low' "DUPLICATE: same target as $S\Colony\S01\Colony.S01E05.1080p.mkv; show"),
  (Row "$M\Solo.mkv" "$M\Solo (2018)\Solo (2018).mkv" 'movie' 'high' 'matched'),
  (Row "$M\Joker 720p.srt" '' 'sidecar' '' 'DUPLICATE sidecar target')
)
$g = @(Get-PRDuplicateGroups $rows)   # same call shape as the GUI
$n = 0; foreach ($x in $g) { $n++ }
Check ($n -eq 2) "foreach over @(groups) iterates once per group (got $n)"
Check (@($g | Where-Object { $_.Id -is [int] }).Count -eq $g.Count) "every group Id is a scalar int"
Check (@($g | Where-Object { @($_.Paths).Count -ge 2 }).Count -eq $g.Count) "every group has >= 2 paths"
Check (($g | ForEach-Object { $_.Id }) -join ',' -eq '1,2') "group ids 1,2"
Check ($g.Count -eq 2) "2 groups found (got $($g.Count))"
$jk = $g | Where-Object { $_.Paths -contains "$M\Joker 720p.mp4" }
Check ($jk.Paths.Count -eq 3 -and $jk.Kind -eq 'both') "Joker: multiple versions + duplicate merged into one group of 3 ($($jk.Kind))"
Check ($jk.Target -eq "$M\Joker (2019)") "Joker group target is the movie folder"
$co = $g | Where-Object { $_.Paths -contains "$S\Colony\S01\Colony.S01E05.720p.mkv" }
Check ($co.Paths.Count -eq 2 -and $co.Kind -eq 'same target') "Colony duplicate group"
Check (-not ($g | Where-Object { $_.Paths -contains "$M\Solo.mkv" })) "unique movie not grouped"
$all = @("$M\Joker 720p.mp4", "$M\Joker 720p.srt", "$M\Joker 720p.en.forced.srt", "$M\Joker 720p.nfo", "$M\Joker 720p extras.srt", "$M\Subs\Joker 720p\2_English.srt", "$M\Joker.2019.1080p.srt", "$M\poster.jpg")
$sc = Get-PRSidecarsFor "$M\Joker 720p.mp4" $all
Check ($sc.Count -eq 4 -and $sc -contains "$M\Subs\Joker 720p\2_English.srt" -and -not ($sc -contains "$M\Joker 720p extras.srt")) "sidecars: same base name + Subs\stem only ($($sc.Count))"
$all2 = @("$M\Joker.mkv", "$M\Joker.srt", "$M\Joker.2019.1080p.mkv", "$M\Joker.2019.1080p.srt", "$M\Joker.2019.1080p.en.srt")
$sc2 = Get-PRSidecarsFor "$M\Joker.mkv" $all2
Check ($sc2.Count -eq 1 -and $sc2[0] -eq "$M\Joker.srt") "sidecars of Joker.mkv exclude those of Joker.2019.1080p.mkv"
# performance: sidecar lookup for 100 videos among 6000 paths must be fast (was minutes before the index)
$big = New-Object System.Collections.Generic.List[string]
for ($n = 0; $n -lt 2000; $n++) { $big.Add("$M\Movie $n (2000)\Movie $n (2000).mkv"); $big.Add("$M\Movie $n (2000)\Movie $n (2000).srt"); $big.Add("$M\Movie $n (2000)\Movie $n (2000).nfo") }
$sw = [Diagnostics.Stopwatch]::StartNew(); $ix = Get-PRSidecarIndex ([string[]]$big.ToArray()); $cnt = 0
for ($n = 0; $n -lt 100; $n++) { $cnt += (Get-PRSidecarsFor "$M\Movie $n (2000)\Movie $n (2000).mkv" $null $ix).Count }
Check ($cnt -eq 200 -and $sw.Elapsed.TotalSeconds -lt 15) "sidecar index: 100 lookups over 6000 paths in $([math]::Round($sw.Elapsed.TotalSeconds,1))s ($cnt sidecars)"
$h = PR-ResHint 'Movie.2019.4K.HDR.mkv'; Check ($h.Label -eq '2160p' -and $h.Rank -eq 6) "4K -> 2160p"
Check ((PR-ResHint 'x264.mkv').Rank -eq 0) "no false resolution from x264"
$files = @([pscustomobject]@{ Rank = 4; Size = 9GB }, [pscustomobject]@{ Rank = 5; Size = 2GB }, [pscustomobject]@{ Rank = 5; Size = 3GB })
Check ((Select-PRDefaultKeep $files) -eq 2) "default keep = highest resolution, then largest"
$files2 = @([pscustomobject]@{ Rank = 0; Size = 1GB }, [pscustomobject]@{ Rank = 0; Size = 4GB })
Check ((Select-PRDefaultKeep $files2) -eq 1) "default keep = largest when no resolution"
function Sel($g, $p, $k) { [pscustomobject]@{ Group = $g; Label = "#$g"; Path = $p; Keep = $k } }
$dp = Get-PRDeletePlan @((Sel 1 'a' $true), (Sel 1 'b' $true), (Sel 1 'c' $false), (Sel 2 'd' $true), (Sel 2 'e' $true), (Sel 3 'f' $false), (Sel 3 'g' $false))
Check ($dp.Delete.Count -eq 1 -and $dp.Delete[0].Path -eq 'c') "multi-keep: only unticked file of a valid group is deleted"
Check ($dp.Skipped -eq 1) "group with everything kept is skipped"
Check ($dp.Invalid.Count -eq 1 -and $dp.Invalid[0] -eq '#3') "group keeping nothing is reported invalid and not deleted"
Check ((PR-FormatSize 1572864) -eq '1.5 MB' -and (PR-FormatSize (2.5GB)) -eq '2.50 GB') "size formatting"
# network detection: Win32 drive-type codes (mapped Z: = 4 remote; elevated-invisible mapping = 1 no root dir)
Check ((Resolve-PRDriveIsNetwork 4) -and (Resolve-PRDriveIsNetwork 1) -and (Resolve-PRDriveIsNetwork 0) -and -not (Resolve-PRDriveIsNetwork 3) -and -not (Resolve-PRDriveIsNetwork 2)) "drive type codes: only fixed/removable are local"
$script:PRNetCache = @{}; $script:PRDriveTypeOverride = { param($l) if ($l -eq 'Z') { 4 } elseif ($l -eq 'Y') { 1 } else { 3 } }
Check ((Test-PRNetworkPath 'Z:\LG_NAS_Backup\Media\Movies\a.mkv') -and (Test-PRNetworkPath 'y:\x.mkv') -and -not (Test-PRNetworkPath 'C:\x.mkv')) "mapped Z: (remote) and Y: (not visible) are network, C: is local"
$script:PRDriveTypeOverride = $null; $script:PRNetCache = @{}
$ds = Get-PRDeleteSummary @([pscustomobject]@{ Kind = 'video'; Size = 4GB }, [pscustomobject]@{ Kind = 'sidecar'; Size = 1MB }, [pscustomobject]@{ Kind = 'video'; Size = 1GB }, [pscustomobject]@{ Kind = 'sidecar'; Size = 1MB })
Check ($ds.Videos -eq 2 -and $ds.Sidecars -eq 2 -and $ds.Text -eq '2 videos + 2 related subtitle/.nfo files' -and $ds.Header -like 'Delete 2 videos and 2 related subtitle/.nfo files - 5.00 GB') "delete summary separates videos and sidecars ($($ds.Header))"
Check ((Test-PRNetworkPath '\\nas\video\a.mkv') -eq $true) "UNC path is network"
# deletion in a temp folder (permanent mode; Recycle Bin needs Windows)
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('prdup_' + [guid]::NewGuid().ToString('N').Substring(0, 6)); [void][IO.Directory]::CreateDirectory($tmp)
$a = Join-Path $tmp 'a.mkv'; $b = Join-Path $tmp 'a.srt'; 'x' | Set-Content $a; 'y' | Set-Content $b
$logp = Join-Path $tmp 'deleted.csv'
$r = Remove-PRFiles -Items @([pscustomobject]@{ Path = $a; Group = 1; Kind = 'video' }, [pscustomobject]@{ Path = $b; Group = 1; Kind = 'sidecar' }, [pscustomobject]@{ Path = (Join-Path $tmp 'gone.mkv'); Group = 1; Kind = 'video' }) -LogPath $logp -Permanent
Check ($r.Deleted -eq 2 -and $r.Failed -eq 0 -and -not (Test-Path $a) -and -not (Test-Path $b)) "deleted 2 files, missing file skipped"
$lg = @(Import-Csv $logp); Check ($lg.Count -eq 3 -and $lg[2].result -like 'missing*') "deletion log has 3 rows incl. missing"
Remove-Item -LiteralPath $tmp -Recurse -Force
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASSED' }
