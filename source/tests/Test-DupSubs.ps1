# Offline test (temp folder, Recycle Bin mocked): Setup option "Recycle duplicate subtitles during Full Run".
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
$films = @{ 'twin' = @(@{ id = 1; title = 'Twin'; date = '2019-01-01' }); 'trio' = @(@{ id = 2; title = 'Trio'; date = '2017-01-01' }); 'quad' = @(@{ id = 3; title = 'Quad'; date = '2016-01-01' }) }
function PR-TmdbGet($db, [string]$path, $params) {
    if ($path -eq '/search/movie') {
        $list = @($films[([string]$params.query).ToLowerInvariant()])
        return [pscustomobject]@{ results = @($list | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ id = $_.id; title = $_.title; original_title = $_.title; release_date = $_.date; popularity = 10 } }) }
    }
    return [pscustomobject]@{ results = @(); episodes = @() }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ("prdup_" + [guid]::NewGuid().ToString('N').Substring(0, 6))
$bin = Join-Path $root 'bin'; [void][IO.Directory]::CreateDirectory($bin)
$script:recycled = New-Object System.Collections.Generic.List[string]
function PR-RecycleFile([string]$p) { $script:recycled.Add($p); [IO.File]::Move($p, (Join-Path $bin ([guid]::NewGuid().ToString('N') + '.srt'))) }   # mock: no real Recycle Bin
function PR-HasRecycleBin([string]$p) { return ($p -notlike '*NoBin*') }
$M = Join-Path $root 'Movies'
$same = 'subtitle text ' * 200
$files = [ordered]@{
    'Twin (2019)\Twin (2019).mkv' = 'video'; 'Twin (2019)\Twin (2019).en.srt' = $same; 'Twin (2019)\Subs\English.srt' = $same            # extra copy of a placed subtitle (Subs folder)
    'Trio (2017)\Trio (2017).mkv' = 'video'; 'Trio (2017)\Subs\2_English.srt' = $same; 'Trio (2017)\Subs\3_English.srt' = $same           # two copies, neither placed yet: one is placed, one recycled
    'Quad (2016)\Quad (2016).mkv' = 'video'; 'Quad (2016)\Quad (2016).en.srt' = $same; 'Quad (2016)\Quad.2016.WEB.en.srt' = ('other ' * 900)   # different content: numbered .en.2.srt, kept
    'Quad (2016)\Quad (2016).nfo' = 'nfo'; 'Quad (2016)\Quad.2016.x264.nfo' = 'nfo'                                                       # duplicate .nfo: not a subtitle, never recycled here
}
foreach ($k in $files.Keys) { $p = Join-Path $M $k; [void][IO.Directory]::CreateDirectory((Split-Path $p)); [IO.File]::WriteAllText($p, $files[$k]) }
$db = New-PRTmdb -Key 'x' -CachePath (Join-Path $root 'c.json') -Source 'TMDB only'
$paths = @($files.Keys | ForEach-Object { Join-Path $M $_ })
function Plan { New-PRPlan -Paths $paths -MoviesRoot $M -SeriesRoot '' -Db $db -ProbeReal $false -FolderLoose $true }
function RowOf($rows, $rel) { $p = Join-Path $M $rel; $rows | Where-Object { $_.old_path -eq $p } }

$script:PR_RECYCLE_DUPSUBS = $false
$off = Plan
$t = RowOf $off 'Twin (2019)\Subs\English.srt'
Check ($t.note -eq 'DUPLICATE sidecar target (same language already placed); left in place' -and -not $t.PSObject.Properties['dup_of']) "option off: duplicate left in place, note unchanged"
Check (@($off | Where-Object { Test-PRDupSubRow $_ }).Count -eq 0) "option off: nothing marked for recycling"

$script:PR_RECYCLE_DUPSUBS = $true
$on = Plan
$t = RowOf $on 'Twin (2019)\Subs\English.srt'
Check ($t.note -like 'DUPLICATE sidecar target*will be recycled*' -and $t.dup_of -eq (Join-Path $M 'Twin (2019)\Twin (2019).en.srt') -and -not $t.new_path) "option on: note says 'will be recycled', keeps the placed copy"
$tr = @((RowOf $on 'Trio (2017)\Subs\2_English.srt'), (RowOf $on 'Trio (2017)\Subs\3_English.srt'))
Check (@($tr | Where-Object { $_.new_path -eq (Join-Path $M 'Trio (2017)\Trio (2017).en.srt') }).Count -eq 1 -and @($tr | Where-Object { Test-PRDupSubRow $_ }).Count -eq 1) "two identical copies: one placed, the other marked for recycling"
$q = RowOf $on 'Quad (2016)\Quad.2016.WEB.en.srt'
Check ($q.new_path -like '*Quad (2016).en.2.srt' -and -not (Test-PRDupSubRow $q)) "different content: numbered .en.2.srt, not recycled"
$qn = RowOf $on 'Quad (2016)\Quad.2016.x264.nfo'
Check ($qn.note -like 'DUPLICATE*' -and -not (Test-PRDupSubRow $qn)) "duplicate .nfo is never marked by this option"
Check ((Get-PRDupSubLine $on) -eq 'Duplicate subtitles: 2 (sent to the Recycle Bin on Full Run)') "scan line [$(Get-PRDupSubLine $on)]"

# Full Run with the option off (switch not passed): nothing recycled
$u0 = Join-Path $root 'undo0.csv'
$r0 = Invoke-PRApply -Rows @() -HighOnly -UndoLog $u0 -Roots @($M)
Check ($script:recycled.Count -eq 0 -and $r0.DupRecycled -eq 0) "Full Run without the option: nothing recycled"

# safety: Z:, kept copy missing, no Recycle Bin, a video row
$fake = New-Object System.Collections.Generic.List[object]
$nb = Join-Path $M 'NoBin (2000)'; [void][IO.Directory]::CreateDirectory($nb); [IO.File]::WriteAllText("$nb\a.en.srt", 'x'); [IO.File]::WriteAllText("$nb\b.en.srt", 'x')
$gone = Join-Path $M 'Gone (2000)'; [void][IO.Directory]::CreateDirectory($gone); [IO.File]::WriteAllText("$gone\b.en.srt", 'x')
$mk = { param($o, $k) $r = PR-NewRow $o; $r.media_type = 'sidecar'; $r.note = 'DUPLICATE sidecar target (same language already placed); will be recycled (Recycle Bin on Full Run; keeps x)'; Add-Member -InputObject $r -NotePropertyName dup_of -NotePropertyValue $k; $r }
$bad = @((& $mk 'Z:\Movies\X\x.en.srt' 'Z:\Movies\X\X.en.srt'), (& $mk "$gone\b.en.srt" "$gone\Gone (2000).en.srt"), (& $mk "$nb\b.en.srt" "$nb\a.en.srt"), (& $mk (Join-Path $M 'Twin (2019)\Twin (2019).mkv') (Join-Path $M 'Twin (2019)\Twin (2019).en.srt')))
$res = Remove-PRDupSubs $bad $fake
Check ($res.Recycled -eq 0 -and $script:recycled.Count -eq 0 -and [IO.File]::Exists("$gone\b.en.srt") -and [IO.File]::Exists("$nb\b.en.srt") -and [IO.File]::Exists((Join-Path $M 'Twin (2019)\Twin (2019).mkv'))) "never: Z:, a missing kept copy, a drive without a Recycle Bin, or a video [$($res.Kept) kept]"
Remove-Item -LiteralPath $nb, $gone -Recurse -Force

$undo = Join-Path $root 'undo.csv'
$r = Invoke-PRApply -Rows $on -HighOnly -UndoLog $undo -Roots @($M) -RemoveEmpty -RecycleDupSubs
Check ($r.DupRecycled -eq 2) "Full Run: 2 duplicate subtitles sent to the Recycle Bin [$($r.DupRecycled)]"
Check (-not [IO.File]::Exists((Join-Path $M 'Twin (2019)\Subs\English.srt')) -and [IO.File]::Exists((Join-Path $M 'Twin (2019)\Twin (2019).en.srt')) -and [IO.File]::Exists((Join-Path $M 'Twin (2019)\Twin (2019).mkv'))) "duplicate gone; kept copy and video untouched"
Check ([IO.File]::Exists((Join-Path $M 'Trio (2017)\Trio (2017).en.srt')) -and @([IO.Directory]::GetFiles((Join-Path $M 'Trio (2017)'), '*.srt', 'AllDirectories')).Count -eq 1) "Trio: one copy placed, the other recycled"
Check ([IO.File]::Exists((Join-Path $M 'Quad (2016)\Quad (2016).en.2.srt')) -or [IO.File]::Exists((Join-Path $M 'Quad (2016)\Quad.2016.WEB.en.srt'))) "numbered different-content subtitle still exists"
Check ([IO.File]::Exists((Join-Path $M 'Quad (2016)\Quad.2016.x264.nfo'))) "duplicate .nfo kept (this option only handles subtitles)"
Check (-not [IO.Directory]::Exists((Join-Path $M 'Twin (2019)\Subs')) -and -not [IO.Directory]::Exists((Join-Path $M 'Trio (2017)\Subs'))) "emptied Subs folders removed by the empty-folder clean-up"
$csv = @(Import-Csv $undo); $order = @($csv | ForEach-Object { $_.how }) -join ','
Check (@($csv | Where-Object { $_.how -eq 'recycle' }).Count -eq 2 -and $order.IndexOf('recycle') -lt $order.IndexOf('rmdir') -and $order.LastIndexOf('rename') -lt $order.IndexOf('recycle')) "undo CSV: moves, then recycle per file, then removed folders [$order]"
$un = Invoke-PRUndo -UndoLog $undo
Check ($un.Recycled -eq 2 -and [IO.Directory]::Exists((Join-Path $M 'Twin (2019)\Subs'))) "Undo (mocked bin): reports 2 files to restore from the Recycle Bin, recreates the Subs folder"

Get-ChildItem -LiteralPath $root -Recurse -Force | ForEach-Object { $_.Attributes = 'Normal' }
Remove-Item -LiteralPath $root -Recurse -Force
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASS' }
