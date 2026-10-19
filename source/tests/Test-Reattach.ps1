# Offline test (mocked TMDB, temp folder): orphan sidecars re-attached to the video in their folder, and the Unmatched summary line.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
$films = @{ 'heat' = @(@{ id = 949; title = 'Heat'; date = '1995-12-15'; pop = 30 }); 'dune' = @(@{ id = 438631; title = 'Dune'; date = '2021-09-15'; pop = 50 }) }
function PR-TmdbGet($db, [string]$path, $params) {
    if ($path -eq '/search/movie') {
        $list = @($films[([string]$params.query).ToLowerInvariant()])
        if ($params.primary_release_year) { $list = @($list | Where-Object { $_ -and $_.date.StartsWith([string]$params.primary_release_year) }) }
        return [pscustomobject]@{ results = @($list | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ id = $_.id; title = $_.title; original_title = $_.title; release_date = $_.date; popularity = $_.pop } }) }
    }
    return [pscustomobject]@{ results = @(); episodes = @() }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ("prre_" + [guid]::NewGuid().ToString('N').Substring(0, 6))
$M = Join-Path $root 'Movies'
$files = @('Heat (1995)\Heat (1995).mkv', 'Heat (1995)\Heat 1995 720p AAC.eng.srt', 'Heat (1995)\Heat 1995 720p.eng.CC.srt', 'Heat (1995)\Heat.1995.WEBRip.mp4.nfo',
           'Heat (1995)\Heat 1995.fra.Canada.srt', 'Heat (1995)\Heat 1995.spa.Latinoamérica.srt', 'Heat (1995)\Heat 1995.hin.sdh.srt', 'Heat (1995)\Heat 1995 notag.srt',
           'Dune (2021)\Dune (2021).mkv', 'Dune (2021)\Dune (2021).nfo', 'Dune (2021)\Dune.2021.x264.nfo',
           'Pack\Heat (1995) - 1080p.mkv', 'Pack\Dune (2021) - 1080p.mkv', 'Pack\Dune 2021 720p.eng.srt', 'Pack\Something Else.eng.srt',
           'Show S01E01.mkv',
           'Heat (1995)\Heat 1995.eng.CC eng.srt', 'Heat (1995)\Heat 1995.fra.Canada fre.srt', 'Heat (1995)\Heat 1995.spa.Latinoamérica spa.srt',
           'Clash (2020)\Clash (2020).mkv', 'Clash (2020)\Clash (2020).srt', 'Clash (2020)\Clash 2020 720p.srt',
           'Solo (2018)\Solo (2018).mkv', 'Solo (2018)\Subs\3_English.srt', 'Solo (2018)\Subs\English.srt', 'Solo (2018)\Subs\Español (Latinoamérica).spa.srt', 'Solo (2018)\Subs\Forced.srt',
           'Pack2\Quiet (2018).mkv', 'Pack2\Quiet Part II (2021).mkv', 'Pack2\Quiet Part 2.2021.fra.forced.srt', 'Pack2\Quiet Part II.2020.fra.srt',
           'Solo.2018.1080p\Subs\French.srt', 'Solo 2018-1080p x265 10bit 5.1\Subs\Español (Latinoamérica).spa.srt', 'Lonely (2014).srt')
$files += @('Twin (2019)\Twin (2019).mkv', 'Twin (2019)\Twin (2019).en.srt', 'Twin (2019)\Subs\English.srt', 'Twin (2019)\Subs\Eng.srt')
$fi = 0; foreach ($f in $files) { $p = Join-Path $M $f; [void][IO.Directory]::CreateDirectory((Split-Path $p)); $fi++; [IO.File]::WriteAllText($p, ($f + ' ' + ('x' * [int](1000 * [math]::Pow(1.06, $fi))))) }   # every file a different size
$same = 'subtitle text ' * 200
[IO.File]::WriteAllText((Join-Path $M 'Twin (2019)\Twin (2019).en.srt'), $same); [IO.File]::WriteAllText((Join-Path $M 'Twin (2019)\Subs\English.srt'), $same)   # identical copy
[IO.File]::WriteAllText((Join-Path $M 'Twin (2019)\Subs\Eng.srt'), $same + 'abc')   # same language, size within 3%
$db = New-PRTmdb -Key 'x' -CachePath (Join-Path $root 'c.json') -Source 'TMDB only'
$paths = @($files | ForEach-Object { Join-Path $M $_ })
$rows = New-PRPlan -Paths $paths -MoviesRoot $M -SeriesRoot '' -Db $db -ProbeReal $false -FolderLoose $true
function RowOf($rel) { $p = Join-Path $M $rel; $rows | Where-Object { $_.old_path -eq $p } }
function NP($rel) { [string](RowOf $rel).new_path }
$H = Join-Path $M 'Heat (1995)'
Check ((NP 'Heat (1995)\Heat 1995 720p AAC.eng.srt') -ceq "$H\Heat (1995).eng.srt") "orphan .eng.srt re-attached to the only video"
Check ((NP 'Heat (1995)\Heat 1995 720p.eng.CC.srt') -ceq "$H\Heat (1995).eng.CC.srt") "eng.CC tag kept"
Check ((NP 'Heat (1995)\Heat 1995.fra.Canada.srt') -ceq "$H\Heat (1995).fra.Canada.srt") "fra.Canada tag kept"
Check ((NP 'Heat (1995)\Heat 1995.spa.Latinoamérica.srt') -ceq "$H\Heat (1995).spa.Latinoamérica.srt") "spa.Latinoamérica tag kept"
Check ((NP 'Heat (1995)\Heat 1995.hin.sdh.srt') -ceq "$H\Heat (1995).hin.sdh.srt") "hin.sdh tag kept"
Check ((NP 'Heat (1995)\Heat.1995.WEBRip.mp4.nfo') -ceq "$H\Heat (1995).nfo") ".nfo re-attached as <video>.nfo"
Check ((NP 'Heat (1995)\Heat 1995 notag.srt') -ceq "$H\Heat (1995).srt" -and (RowOf 'Heat (1995)\Heat 1995 notag.srt').note -like '*no language tag (kept untagged)*') "rule 1: untagged subtitle renamed to <video>.srt"
$r1 = RowOf 'Heat (1995)\Heat 1995 720p AAC.eng.srt'
Check ($r1.confidence -eq 'high' -and $r1.note -like 'sidecar (re-attached) of Heat (1995).mkv*') "single video: high confidence, marked re-attached"
Check (-not (NP 'Dune (2021)\Dune.2021.x264.nfo') -and (RowOf 'Dune (2021)\Dune.2021.x264.nfo').note -like 'DUPLICATE*') "extra .nfo skipped as a duplicate when <video>.nfo already exists"
$tw = RowOf 'Twin (2019)\Subs\English.srt'; $tw2 = RowOf 'Twin (2019)\Subs\Eng.srt'
Check (-not $tw.new_path -and $tw.note -like 'DUPLICATE*') "identical copy of an existing subtitle: skipped as DUPLICATE, left in place"
Check (-not $tw2.new_path -and $tw2.note -like 'DUPLICATE*') "same language, size within 3%: skipped as DUPLICATE"
$cl = RowOf 'Clash (2020)\Clash 2020 720p.srt'
Check ($cl.confidence -eq 'low' -and $cl.note -like '*different content - verify*') "a different track under a new name is low (review), never automatic"
Check ((NP 'Clash (2020)\Clash 2020 720p.srt') -ceq (Join-Path $M 'Clash (2020)\Clash (2020).und.srt')) "rule 1: untagged clash -> <video>.und.srt (never overwrite)"
Check ((NP 'Heat (1995)\Heat 1995.eng.CC eng.srt') -ceq "$H\Heat (1995).en.sdh.srt") "rule 2: 'eng.CC eng' -> .en.sdh"
Check ((NP 'Heat (1995)\Heat 1995.fra.Canada fre.srt') -ceq "$H\Heat (1995).fr-CA.srt") "rule 2: 'fra.Canada fre' -> .fr-CA"
Check ((NP 'Heat (1995)\Heat 1995.spa.Latinoamérica spa.srt') -ceq "$H\Heat (1995).es-419.srt") "rule 2: 'spa.Latinoamérica spa' -> .es-419"
$S = Join-Path $M 'Solo (2018)'
$en = @((NP 'Solo (2018)\Subs\3_English.srt'), (NP 'Solo (2018)\Subs\English.srt')) | Sort-Object
Check ($en[0] -ceq "$S\Solo (2018).en.2.srt" -and $en[1] -ceq "$S\Solo (2018).en.srt" -and @(@((RowOf 'Solo (2018)\Subs\3_English.srt'), (RowOf 'Solo (2018)\Subs\English.srt')) | Where-Object { $_.new_path -like '*.en.2.srt' -and $_.confidence -eq 'low' }).Count -eq 1) "rule 3: Subs\3_English + Subs\English moved up as .en and .en.2 [$($en -join ' | ')]"
Check (@(@((RowOf 'Solo (2018)\Subs\3_English.srt'), (RowOf 'Solo (2018)\Subs\English.srt')) | Where-Object { $_.new_path -like '*.en.srt' -and $_.confidence -eq 'high' }).Count -eq 1) "rule 3: identified language + one video = high"
Check ((NP 'Solo (2018)\Subs\Español (Latinoamérica).spa.srt') -ceq "$S\Solo (2018).es-419.srt") "rule 3: Subs\Español (Latinoamérica) -> .es-419"
$fz = RowOf 'Solo (2018)\Subs\Forced.srt'
Check ($fz.new_path -ceq "$S\Solo (2018).und.srt" -and $fz.confidence -eq 'low' -and (Test-PRTickable $fz)) "rule 3: unknown language -> .und, low, tickable on its own"
$q1 = RowOf 'Pack2\Quiet Part 2.2021.fra.forced.srt'; $q2 = RowOf 'Pack2\Quiet Part II.2020.fra.srt'
Check ($q1.new_path -ceq (Join-Path $M 'Pack2\Quiet Part II (2021).fra.forced.srt') -and $q1.confidence -eq 'high') "rule 4: Part 2 = Part II plus year -> high"
Check ($q2.new_path -ceq (Join-Path $M 'Pack2\Quiet Part II (2021).fra.srt') -and $q2.confidence -eq 'low') "rule 4: title only (year differs) -> low"
$of = RowOf 'Solo.2018.1080p\Subs\French.srt'
Check ($of.new_path -ceq "$S\Solo (2018).fr.srt" -and $of.confidence -eq 'low' -and $of.note -like '*another folder*') "left-behind folder: re-attached to the movie in its own folder, low"
Check ((NP 'Solo 2018-1080p x265 10bit 5.1\Subs\Español (Latinoamérica).spa.srt') -ceq "$S\Solo (2018).es-419.2.srt") "left-behind 'Title 2018-1080p x265' folder found, numbered (es-419 already taken)"
Check (-not (NP 'Lonely (2014).srt') -and (RowOf 'Lonely (2014).srt').note -like 'sidecar: no video found*') "rule 5: loose subtitle with no video: left alone, 'no video found'"
$pk = RowOf 'Pack\Dune 2021 720p.eng.srt'
Check ($pk.new_path -ceq (Join-Path $M 'Dune (2021)\Dune (2021) - 1080p.eng.srt') -and $pk.confidence -eq 'high' -and $pk.note -like '*same title and year') "several videos: unique title + year match -> high"
Check (-not (NP 'Pack\Something Else.eng.srt')) "no title match among several videos: left in place"
$line = Get-PRUnmatchedLine $rows
Check ($line -like 'Unmatched: * movie(s), 1 episode(s), 2 sidecar(s) with no video.*choose a Series folder*') "unmatched line counts movies, episodes and sidecars [$line]"
Check (-not (RowOf 'Show S01E01.mkv').new_path) "episode in the Movies folder is not moved"
$undo = Join-Path $root 'undo.csv'
$ap = Invoke-PRApply -Rows $rows -HighOnly -UndoLog $undo -Roots @($M)
Check ([IO.File]::Exists("$H\Heat (1995).eng.CC.srt") -and [IO.File]::Exists("$H\Heat (1995).nfo") -and $ap.Failed -eq 0) "Full Run renames the re-attached sidecars"
Check ([IO.File]::Exists((Join-Path $M 'Pack2\Quiet Part II.2020.fra.srt'))) "low-confidence re-attach not applied until accepted"
Check ([IO.File]::Exists("$S\Solo (2018).en.srt") -and -not [IO.File]::Exists("$S\Solo (2018).en.2.srt") -and [IO.File]::Exists("$S\Solo (2018).es-419.srt")) "Full Run moves Subs files up next to the video"
Check (@(Import-Csv $undo | Where-Object { $_.old_path -like '*\Subs\*' }).Count -eq 2) "undo log has the moves out of Subs"
$u = Invoke-PRUndo -UndoLog $undo
Check (@($paths | Where-Object { [IO.File]::Exists($_) }).Count -eq $paths.Count) "undo restores the sidecar names"
Remove-Item -LiteralPath $root -Recurse -Force
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASS' }
