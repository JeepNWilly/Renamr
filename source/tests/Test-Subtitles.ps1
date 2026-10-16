# Offline test of the subtitle feature (The Subtitle Database). PR-SubGetJson / PR-SubDownload / PR-TmdbGet / PR-TvdbRaw are mocked: no network, no keys.
# File-system parts run in a temp folder (Windows only; skipped elsewhere). Nothing touches a real library.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
$isWin = ($env:OS -eq 'Windows_NT')

# ---------- sample data ----------
function New-Srt([string[]]$Lines, [string[]]$Extra = @()) {
    $sb = New-Object Text.StringBuilder; $n = 0
    foreach ($l in @($Extra) + @($Lines)) { $n++; $t0 = '{0:00}:{1:00}:{2:00},000' -f 0, [math]::Floor($n / 60), ($n % 60); [void]$sb.Append("$n`r`n$t0 --> $t0`r`n$l`r`n`r`n") }
    return $sb.ToString()
}
$enLines = 1..40 | ForEach-Object { 'I do not know what you want me to do with this, but we have to get out of here before they find us and that is all there is to it.' }
$esLines = 1..40 | ForEach-Object { 'No se que quieres que haga. Yo no puedo ir a la casa de tu madre con todo lo que ha pasado, es que no entiendo por que me lo dices ahora despues de tanto tiempo.' }
$ruLines = 1..40 | ForEach-Object { ([string][char]0x041F + [char]0x0440 + [char]0x0438 + [char]0x0432 + [char]0x0435 + [char]0x0442 + ' ' + [char]0x043C + [char]0x0438 + [char]0x0440 + ' ' + [char]0x044D + [char]0x0442 + [char]0x043E + ' ' + [char]0x043F + [char]0x0440 + [char]0x043E + [char]0x0432 + [char]0x0435 + [char]0x0440 + [char]0x043A + [char]0x0430 + ' ' + [char]0x0442 + [char]0x0435 + [char]0x043A + [char]0x0441 + [char]0x0442 + [char]0x0430 + ' ' + [char]0x0434 + [char]0x043B + [char]0x044F + ' ' + [char]0x0442 + [char]0x0435 + [char]0x0441 + [char]0x0442 + [char]0x0430) }
$enSrt = New-Srt $enLines
$adSrt = New-Srt $enLines @('Advertise your product or brand here', '<font color="#ffff00">Support us and become VIP member</font>', 'Subtitles by SomeTeam', 'Downloaded from www.example.com')
Check (PR-SubLooksEnglish $enSrt) 'English text recognised'
Check (-not (PR-SubLooksEnglish (New-Srt $esLines))) 'Spanish text rejected'
Check (-not (PR-SubLooksEnglish (New-Srt $ruLines))) 'Cyrillic text rejected'
Check (-not (PR-SubLooksEnglish (New-Srt @('Hello there.')))) 'tiny text rejected'

# ---------- name flags ----------
Check (PR-SubNameIsSdh 'Breaking Bad S01E01 Pilot.DVDRip.HI.cc.en.SNY') 'HI / cc in the release name = SDH'
Check (PR-SubNameIsSdh 'Alien.1979.1080p.BluRay.SDH') 'SDH in the release name'
Check (PR-SubNameIsSdh 'Movie 2020 Hearing Impaired') 'hearing impaired in the release name'
Check (-not (PR-SubNameIsSdh 'Alien.1979.1080p.BluRay.x264-GRP')) 'ordinary release name is not SDH'
Check (-not (PR-SubNameIsSdh 'Chicago.2002.WEB-DL')) 'letters hi/cc inside words do not count'
Check (PR-SubNameIsJunk '1080p.BluRay.DTS.x264-EBCP (commentary only)') 'commentary is junk'
Check (-not (PR-SubNameIsJunk 'Alien.1979.1080p.BluRay.x264-GRP')) 'normal name is not junk'

# ---------- parsing the TSDB response ----------
$json = @'
{"title":{"imdb":"tt0078748","tmdb_id":348,"media_type":"movie","name":"Alien","year":1979},
 "subtitles":{"total":9,"limit":100,"offset":0,"items":[
 {"id":101,"language":"en","format":"srt","cues":1900,"duration_s":6986,"bytes":170000,"encoding":"utf-8-sig","release_name":"Alien.1979.1080p.BluRay.x264-GRP","hearing_impaired":false,"added_at":"2020-01-01T00:00:00Z"},
 {"id":102,"language":"en","format":"srt","cues":1880,"duration_s":7000,"bytes":170000,"encoding":"utf-8","release_name":"Alien.1979.720p.WEB-DL.x265-OTHER","hearing_impaired":false,"added_at":"2021-01-01T00:00:00Z"},
 {"id":103,"language":"en","format":"srt","cues":1885,"duration_s":7007,"bytes":171382,"encoding":"utf-8","release_name":"1080p.BluRay.DTS.x264-EBCP (commentary only)","hearing_impaired":false,"added_at":"2017-07-04T21:00:22Z"},
 {"id":104,"language":"ea","format":"srt","cues":1900,"duration_s":7000,"bytes":170000,"encoding":"utf-8","release_name":"Alien.1979.1080p.BluRay.x264-GRP.spanish","hearing_impaired":false,"added_at":"2022-01-01T00:00:00Z"},
 {"id":105,"language":"pl","format":"srt","cues":1900,"duration_s":7000,"bytes":170000,"encoding":"utf-8","release_name":"Alien.1979.1080p.BluRay.x264-GRP","hearing_impaired":false,"added_at":"2022-01-01T00:00:00Z"},
 {"id":106,"language":"en","format":"srt","cues":5,"duration_s":7000,"bytes":400,"encoding":"utf-8","release_name":"Alien.1979.1080p.BluRay.x264-GRP.tiny","hearing_impaired":false,"added_at":"2022-01-01T00:00:00Z"},
 {"id":107,"language":"en","format":"srt","cues":1950,"duration_s":7000,"bytes":175000,"encoding":"utf-8","release_name":"Alien.1979.1080p.BluRay.x264-GRP","hearing_impaired":true,"added_at":"2022-01-01T00:00:00Z"},
 {"id":108,"language":"en","format":"srt","cues":1940,"duration_s":7000,"bytes":174000,"encoding":"utf-8","release_name":"Alien.1979.720p.BluRay.SDH","hearing_impaired":false,"added_at":"2022-01-02T00:00:00Z"},
 {"id":109,"language":"en","format":"srt","cues":1930,"duration_s":7000,"bytes":173000,"encoding":"utf-8","release_name":"Alien.1979.1080p.BluRay.x264-GRP.forced","hearing_impaired":false,"added_at":"2022-01-03T00:00:00Z"}
 ]}}
'@ | ConvertFrom-Json
$items = PR-SubItems $json
Check ($items.Count -eq 7) "other languages ('ea', 'pl') dropped, 7 English kept (got $($items.Count))"
Check ((@($items | Where-Object { $_.Id -eq '108' })[0]).Sdh -eq $true) 'SDH detected from the name when the flag is false'
Check ((@($items | Where-Object { $_.Id -eq '107' })[0]).Sdh -eq $true) 'SDH from the hearing_impaired flag'
Check ($items[0].Id -is [string] -and $items[0].Cues -eq 1900) 'fields mapped'

# ---------- selection ----------
$std = PR-SubPick $items 'Alien.1979.1080p.BluRay.x264-GRP' $false 'standard' 3
Check (@($std).Count -eq 2 -and $std[0].Id -eq '101' -and $std[1].Id -eq '102') "standard: best release match first, commentary / tiny / SDH / forced excluded (got: $(@($std | ForEach-Object { $_.Id }) -join ','))"
$std2 = PR-SubPick $items 'Alien.1979.720p.WEB-DL.x265-OTHER' $false 'standard' 3
Check ($std2[0].Id -eq '102') 'standard: ranking follows the video file name (720p WEB-DL x265 OTHER)'
$sdh = PR-SubPick $items 'Alien.1979.1080p.BluRay.x264-GRP' $false 'sdh' 3
Check (@($sdh).Count -eq 2 -and $sdh[0].Id -eq '107' -and $sdh[1].Id -eq '108') "sdh: flag + name-detected SDH, best release match first (got: $(@($sdh | ForEach-Object { $_.Id }) -join ','))"
$one = PR-SubPick $items 'Alien.1979.1080p.BluRay.x264-GRP' $false 'standard' 1
Check (@($one).Count -eq 1) 'max candidates respected'
$ep = PR-SubPick (PR-SubItems ('{"subtitles":{"items":[{"id":1,"language":"en","format":"srt","cues":60,"bytes":3000,"release_name":"Show.S01E01.720p","hearing_impaired":false},{"id":2,"language":"en","format":"srt","cues":40,"bytes":3000,"release_name":"Show.S01E01.1080p","hearing_impaired":false}]}}' | ConvertFrom-Json)) 'Show.S01E01.1080p' $true 'standard' 3
Check (@($ep).Count -eq 1 -and $ep[0].Id -eq '1') 'episodes need >= 50 cues (movies >= 100)'
$none = PR-SubPick (PR-SubItems ('{"subtitles":{"items":[{"id":1,"language":"fr","format":"srt","cues":900,"bytes":30000,"release_name":"x","hearing_impaired":false}]}}' | ConvertFrom-Json)) 'x' $false 'standard' 3
Check (@($none).Count -eq 0) 'no English candidates -> empty'

# ---------- text handling ----------
$c = PR-SubClean $adSrt
Check ($c.Removed -eq 4) "4 ad lines removed (got $($c.Removed))"
Check ($c.Cues -eq 40 -and $c.Text -notmatch 'VIP|Advertise|Subtitles by|example\.com') "ad cues dropped and the rest kept ($($c.Cues) cues)"
Check ($c.Text.StartsWith("1`r`n00:") -and $c.Text -match "`r`n40`r`n") 'cues renumbered 1..40'
$c2 = PR-SubClean ($enSrt.Replace('I do not know', 'OpenSubtitles.org: I do not know'))
Check ($c2.Removed -ge 1) 'OpenSubtitles line removed'
$utf8bom = [byte[]](@(0xEF, 0xBB, 0xBF) + [Text.Encoding]::UTF8.GetBytes('caf' + [char]0x00E9))
Check ((PR-SubDecode $utf8bom 'utf-8-sig') -eq ('caf' + [char]0x00E9)) 'UTF-8 with BOM decoded'
Check ((PR-SubDecode ([byte[]](0x63, 0x61, 0x66, 0xE9)) 'windows-1252') -eq ('caf' + [char]0x00E9)) 'windows-1252 decoded when not valid UTF-8'
Check ((PR-SubDecode ([Text.Encoding]::UTF8.GetBytes('caf' + [char]0x00E9)) 'cp1252') -eq ('caf' + [char]0x00E9)) 'valid UTF-8 wins over a wrong encoding label'

# ---------- naming ----------
Check ((Get-PRSubTarget 'Z:\M\Alien (1979)\Alien (1979) - 1080p.mkv' 'standard') -eq 'Z:\M\Alien (1979)\Alien (1979) - 1080p.en.srt') 'standard file name'
Check ((Get-PRSubTarget 'Z:\M\Alien (1979)\Alien (1979).mkv' 'sdh') -eq 'Z:\M\Alien (1979)\Alien (1979).en.sdh.srt') 'SDH file name'

# ---------- the new files stay compatible with rename / duplicates ----------
Check ((PR-LangSuffix '3_English.sdh') -eq '.en.sdh' -and (PR-LangSuffix '3_English') -eq '.en') 'language-suffix logic (Subs\ folders) keeps .en and .en.sdh'
$M = 'Z:\Media\Movies'
$all = @("$M\Alien.1979.1080p.mkv", "$M\Alien.1979.1080p.en.srt", "$M\Alien.1979.1080p.en.sdh.srt", "$M\Alien.1979.1080p.5.1.en.srt")
$scs = [string[]](Get-PRSidecarsFor "$M\Alien.1979.1080p.mkv" $all)
Check ($scs -contains "$M\Alien.1979.1080p.en.srt" -and $scs -contains "$M\Alien.1979.1080p.en.sdh.srt") 'Duplicates sidecar lookup finds .en.srt and .en.sdh.srt'
function PR-TmdbGet($db, [string]$path, $params) {
    if ($path -eq '/search/movie') { return ('{"results":[{"id":348,"title":"Alien","original_title":"Alien","release_date":"1979-05-25","popularity":50}]}' | ConvertFrom-Json) }
    return [pscustomobject]@{ results = @(); episodes = @() }
}
$cache = Join-Path ([IO.Path]::GetTempPath()) ("subtest_" + [guid]::NewGuid() + '.json')
$db = New-PRTmdb -Key 'x' -CachePath $cache -Source 'TMDB only'
$rows = @(New-PRPlan -Paths @("$M\Alien.1979.1080p.mkv", "$M\Alien.1979.1080p.en.srt", "$M\Alien.1979.1080p.en.sdh.srt") -MoviesRoot $M -SeriesRoot 'Z:\Media\Series' -Db $db -ProbeReal $false | ForEach-Object { $_ })
$v = $rows | Where-Object { $_.media_type -eq 'movie' }
$s1 = $rows | Where-Object { $_.old_path -like '*.en.srt' }
$s2 = $rows | Where-Object { $_.old_path -like '*.en.sdh.srt' }
Check ($v.new_path -eq "$M\Alien (1979)\Alien (1979) - 1080p.mkv") "video renamed ($($v.new_path))"
Check ($s1.new_path -eq "$M\Alien (1979)\Alien (1979) - 1080p.en.srt") "rename moves .en.srt with the video ($($s1.new_path))"
Check ($s2.new_path -eq "$M\Alien (1979)\Alien (1979) - 1080p.en.sdh.srt") "rename moves .en.sdh.srt with the video ($($s2.new_path))"

# ---------- lookup, plan, download with mocked HTTP ----------
$script:calls = New-Object System.Collections.Generic.List[string]
function Mk([int]$id, [string]$name, [bool]$hi, [int]$cues = 1500) { "{`"id`":$id,`"language`":`"en`",`"format`":`"srt`",`"cues`":$cues,`"duration_s`":6000,`"bytes`":90000,`"encoding`":`"utf-8`",`"release_name`":`"$name`",`"hearing_impaired`":$($hi.ToString().ToLower()),`"added_at`":`"2020-01-01T00:00:00Z`"}" }
function PR-SubGetJson($S, [string]$path, $query) {
    $script:calls.Add($path + '?' + (PR-UrlEncode $query))
    if ($path -eq '/by-tmdb/348') {
        $its = @((Mk 1 'Alien.1979.1080p.BluRay.x264-GRP' $false), (Mk 2 'Alien.1979.1080p.BluRay.SDH' $false), (Mk 3 'Alien.1979.720p.WEB' $false))
        return ('{"title":{"media_type":"movie","name":"Alien"},"subtitles":{"total":3,"items":[' + ($its -join ',') + ']}}' | ConvertFrom-Json)
    }
    if ($path -eq '/by-tmdb/1396') {   # a TMDB id that is a movie in TSDB but we asked for TV episode path -> media_type mismatch
        return ('{"title":{"media_type":"movie","name":"The Mirror"},"subtitles":{"total":1,"items":[' + (Mk 9 'Mirror.1975' $false) + ']}}' | ConvertFrom-Json)
    }
    if ($path -eq '/by-tmdb/5000/season/1/episode/1') {
        $its = @((Mk 11 'Show.S01E01.720p.HDTV.x264-AAA' $false 700), (Mk 12 'Show.S01E01.WEB.x264-BBB' $false 700), (Mk 13 'Show.S01E01.WEB.x264-CCC' $false 700), (Mk 14 'Show.S01E01.HI.cc' $true 700))
        return ('{"title":{"media_type":"tv","name":"Show"},"subtitles":{"total":4,"items":[' + ($its -join ',') + ']}}' | ConvertFrom-Json)
    }
    if ($path -eq '/by-tmdb/5000/season/1/episode/2') { return ('{"title":{"media_type":"tv"},"subtitles":{"total":1,"items":[' + (Mk 21 'Show.S01E02.720p' $false 700) + ']}}' | ConvertFrom-Json) }
    if ($path -eq '/by-imdb/tt7777777/season/1/episode/3') { return ('{"title":{"media_type":"tv"},"subtitles":{"total":1,"items":[' + (Mk 31 'Show.S01E03.720p' $false 700) + ']}}' | ConvertFrom-Json) }
    return $null
}
$script:dl = New-Object System.Collections.Generic.List[string]
$script:limitAt = 0
function PR-SubDownload($S, [string]$id) {
    $script:dl.Add($id)
    if ($script:limitAt -gt 0 -and $script:dl.Count -ge $script:limitAt) { throw 'LIMIT:300' }
    $text = $enSrt
    if ($id -eq '12') { $text = New-Srt $esLines }                  # not English -> rejected, next candidate
    if ($id -eq '13') { $text = New-Srt @('x', 'y') }               # too few cues
    if ($id -eq '11') { $text = $adSrt }
    if ($id -eq '2') { $text = New-Srt $enLines @('[music]', '[door slams]') }
    return ,[byte[]][Text.Encoding]::UTF8.GetBytes($text)
}
function PR-TmdbGet($db, [string]$path, $params) {
    if ($path -eq '/find/4444') { return ('{"movie_results":[],"tv_results":[{"id":5000}]}' | ConvertFrom-Json) }
    return [pscustomobject]@{ results = @(); episodes = @() }
}
function PR-TvdbRaw($db, [string]$path, $params) {
    if ($path -eq '/series/6666/extended') { return ('{"data":{"remoteIds":[{"id":"tt7777777","sourceName":"IMDB","type":2},{"id":"99","sourceName":"TheMovieDB.com","type":12}]}}' | ConvertFrom-Json) }
    return $null
}
$S0 = New-PRSubs -Db $null -Version 'test'
$lk = PR-SubLookup $S0 'movie' 'tmdb' '348'
Check (@($lk).Count -eq 3 -and $script:calls[0] -like '/by-tmdb/348?*format=srt*lang=en*limit=100*') "movie lookup URL and parsing (got $($script:calls[0]))"
$lk1b = PR-SubLookup $S0 'movie' 'tmdb' '348'
Check ($script:calls.Count -eq 1 -and @($lk1b).Count -eq 3 -and $lk1b[0].Cues -gt 0 -and $lk1b[0] -isnot [System.Array]) 'second lookup served from the cache with flat, usable items'
$pk = PR-SubPick $lk1b 'Alien.1979.1080p.BluRay.x264-GRP' $false 'standard' 3
Check (@($pk).Count -eq 2 -and $pk[0].Id -eq '1') 'candidates picked from cached items'
$lk2 = PR-SubLookup $S0 'tv' 'tmdb' '1396' 1 1
Check (@($lk2).Count -eq 0) 'media_type mismatch (id belongs to a movie) -> no candidates'
$lk3 = PR-SubLookup $S0 'tv' 'tmdb' '5000' 1 1
Check ($script:calls[-1] -like '/by-tmdb/5000/season/1/episode/1?*' -and @($lk3).Count -eq 4) 'episode lookup URL'
# id mapping for tvdb: ids
$dbm = New-PRTmdb -Key 'k' -CachePath $cache -TvdbKey 'tk'
$Sm = New-PRSubs -Db $dbm -Version 'test'
$r1 = PR-SubResolve $Sm 'tvdb:4444' 'tv'
Check ($r1 -and $r1.Type -eq 'tmdb' -and $r1.Id -eq '5000') 'tvdb id mapped through TMDB /find'
$dbm2 = New-PRTmdb -Key '' -CachePath $cache -TvdbKey 'tk'
$r2 = PR-SubResolve (New-PRSubs -Db $dbm2 -Version 'test') 'tvdb:6666' 'tv'
Check ($r2 -and $r2.Type -eq 'imdb' -and $r2.Id -eq 'tt7777777') 'tvdb id mapped to IMDb id through TVDB remote ids when there is no TMDB key'
$r3 = PR-SubResolve (New-PRSubs -Db (New-PRTmdb -Key '' -CachePath $cache) -Version 'test') 'tvdb:6666' 'tv'
Check ($null -eq $r3) 'no keys -> tvdb id cannot be mapped'
$r4 = PR-SubResolve $Sm '348' 'movie'
Check ($r4.Type -eq 'tmdb' -and $r4.Id -eq '348') 'plain TMDB id used directly'

if ($isWin) {
    $root = Join-Path ([IO.Path]::GetTempPath()) ("prsub_" + [guid]::NewGuid().ToString('N').Substring(0, 6))
    function JP { $p = $root; foreach ($x in $args) { $p = [IO.Path]::Combine($p, [string]$x) }; return $p }
    foreach ($d in (JP 'Movies' 'Alien (1979)'), (JP 'Movies' 'Other (2000)'), (JP 'Movies' 'Joker (2019)'), (JP 'Series' 'Show (2020)' 'Season 01'), (JP 'Movies' 'Subs' 'Sub (2001)')) { [void][IO.Directory]::CreateDirectory($d) }
    $alien = JP 'Movies' 'Alien (1979)' 'Alien (1979) - 1080p.mkv'; 'v' | Set-Content -LiteralPath $alien
    $other = JP 'Movies' 'Other (2000)' 'Other (2000).mkv'; 'v' | Set-Content -LiteralPath $other
    'x' | Set-Content -LiteralPath (JP 'Movies' 'Other (2000)' 'Other (2000).eng.srt')
    $joker = JP 'Movies' 'Joker (2019)' 'Joker.mkv'; 'v' | Set-Content -LiteralPath $joker
    'x' | Set-Content -LiteralPath (JP 'Movies' 'Joker (2019)' 'Joker.2019.en.srt')
    $e1 = JP 'Series' 'Show (2020)' 'Season 01' 'Show (2020) - S01E01 - Pilot.mkv'; 'v' | Set-Content -LiteralPath $e1
    $e2 = JP 'Series' 'Show (2020)' 'Season 01' 'Show (2020) - S01E02 - Two.mkv'; 'v' | Set-Content -LiteralPath $e2
    $e3 = JP 'Series' 'Show (2020)' 'Season 01' 'Show (2020) - S01E03 - Three.mkv'; 'v' | Set-Content -LiteralPath $e3

    # existing-file detection
    $Sx = New-PRSubs -Db $null -Version 'test'
    $x1 = Get-PRSubExisting $Sx $other
    Check ($x1.Standard -and -not $x1.Sdh) 'existing .eng.srt counts as the standard English subtitle'
    $x2 = Get-PRSubExisting $Sx $joker
    Check (-not $x2.Standard) 'Joker.2019.en.srt belongs to another video, not Joker.mkv'
    $x3 = Get-PRSubExisting $Sx $alien
    Check (-not $x3.Standard -and -not $x3.Sdh) 'nothing exists yet for Alien'
    'x' | Set-Content -LiteralPath (JP 'Movies' 'Alien (1979)' 'Alien (1979) - 1080p.en.hi.srt')
    $Sx.DirCache.Clear()
    $x4 = Get-PRSubExisting $Sx $alien
    Check ($x4.Sdh -and -not $x4.Standard) '.en.hi.srt counts as SDH only'
    Remove-Item -LiteralPath (JP 'Movies' 'Alien (1979)' 'Alien (1979) - 1080p.en.hi.srt')
    $sub = JP 'Movies' 'Sub (2001).mkv'; 'v' | Set-Content -LiteralPath $sub; 'x' | Set-Content -LiteralPath (JP 'Movies' 'Subs' 'Sub (2001)' '2_English.srt')
    # (Subs\<stem>\ is looked up relative to the video folder)
    [void][IO.Directory]::CreateDirectory((JP 'Movies' 'Subs' 'Sub (2001)'))
    $x5 = Get-PRSubExisting $Sx $sub
    Check ($x5.Standard) 'Subs\<video stem>\2_English.srt counts as existing'

    # plan (dry run)
    function MkR($old, $new, $type, $id, $conf = 'high', $note = '') { [pscustomobject]@{ old_path = $old; new_path = $new; media_type = $type; tmdb_id = $id; confidence = $conf; note = $note } }
    $rowsP = @(
        (MkR (JP 'Movies' 'old alien.mkv') $alien 'movie' '348'),                                  # renamed already: new_path exists -> used
        (MkR $other '' 'movie' '348' 'high' 'already correctly named; skipped'),                   # standard exists, SDH wanted
        (MkR (JP 'Series' 'Show.S01E01.mkv') $e1 'episode' 'tvdb:4444'),                           # mapped via TMDB /find -> 5000
        (MkR $e2 '' 'episode' '5000' 'high' 'already correctly named; skipped'),
        (MkR $e3 '' 'episode' 'tvdb:6666' 'low'),                                                  # low confidence
        (MkR $joker '' 'movie' '' 'low' 'unmatched: no TMDB movie'),                               # no id
        (MkR (JP 'Movies' 'dup.mkv') '' 'movie' '348' 'low' 'DUPLICATE: same target as x')         # duplicate: skipped
    )
    $script:calls.Clear()
    $plan = Get-PRSubsPlan -Rows $rowsP -S (New-PRSubs -Db $dbm -Version 'test') -HighOnly -Standard $true -Sdh $true
    $byName = @{}; foreach ($i in $plan.Items) { $byName[$i.Name] = $i }
    $pa = $byName['Alien (1979) - 1080p.mkv']
    Check ($pa -and $pa.StdStatus -eq 'found' -and $pa.StdCands[0].Id -eq '1' -and $pa.SdhStatus -eq 'found' -and $pa.SdhCands[0].Id -eq '2') 'movie: standard (best match) and SDH found'
    $po = $byName['Other (2000).mkv']
    Check ($po -and $po.StdStatus -eq 'exists' -and $po.SdhStatus -eq 'found') 'existing standard is skipped, SDH still wanted'
    $p1 = $byName['Show (2020) - S01E01 - Pilot.mkv']
    Check ($p1 -and $p1.StdStatus -eq 'found' -and $p1.SdhStatus -eq 'found' -and $p1.SdhCands[0].Id -eq '14') 'episode via tvdb: id found (standard + SDH)'
    Check (-not $byName.ContainsKey('Show (2020) - S01E03 - Three.mkv')) 'low-confidence row skipped with Only high-confidence'
    Check (-not $byName.ContainsKey('Joker.mkv')) 'row without an id skipped'
    Check ($plan.Std -eq 3 -and $plan.Sdh -eq 3) "counts: 3 standard, 3 SDH (got $($plan.Std)/$($plan.Sdh)) - e2 has no SDH so 3rd SDH is Alien/Other/E01 -> $($plan.Sdh)"
    Check (-not (Test-Path -LiteralPath (Get-PRSubTarget $alien 'standard'))) 'dry run writes nothing'
    Check ($script:dl.Count -eq 0) 'dry run downloads nothing'

    # download: 3-candidate fallback, rejection, ad stripping, naming
    $script:dl.Clear()
    $logp = JP 'subs_log.csv'
    $res = Invoke-PRSubsDownload -Plan $plan -S (New-PRSubs -Db $null -Version 'test') -LogPath $logp
    $f1 = Get-PRSubTarget $alien 'standard'; $f2 = Get-PRSubTarget $alien 'sdh'
    Check ([IO.File]::Exists($f1) -and [IO.File]::Exists($f2)) 'Alien: .en.srt and .en.sdh.srt written next to the video'
    Check (([IO.File]::ReadAllText($f2)) -match '\[music\]') 'SDH file has the SDH content'
    $t11 = Get-PRSubTarget $e1 'standard'
    Check ([IO.File]::Exists($t11)) 'episode standard written'
    Check (([IO.File]::ReadAllText($t11)) -notmatch 'VIP|Advertise|Subtitles by') 'ad lines stripped from the saved file'
    $bytes = [IO.File]::ReadAllBytes($t11); Check (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)) 'saved as UTF-8 without BOM'
    $t21 = Get-PRSubTarget $e2 'standard'
    # E02 has one candidate (id 21): fine; E01's own candidates 11 (ads, OK) -> first accepted
    Check ([IO.File]::Exists($t21)) 'second episode standard written'
    Check (-not [IO.File]::Exists((Get-PRSubTarget $other 'standard'))) 'no standard downloaded where one already exists'
    Check ([IO.File]::Exists((Get-PRSubTarget $other 'sdh'))) 'SDH downloaded for Other'
    Check ($res.Standard -eq 3 -and $res.Sdh -eq 3 -and $res.Failed -eq 0 -and $res.Stopped -eq '') "download counts (std $($res.Standard), sdh $($res.Sdh), rejected $($res.Rejected), failed $($res.Failed))"
    $csv = @(Import-Csv -LiteralPath $logp -Encoding UTF8)
    Check ($csv.Count -ge 6 -and @($csv | Where-Object { $_.result -eq 'downloaded' }).Count -eq 6) "CSV log lists the downloaded files ($($csv.Count) rows)"

    # skipping on re-run
    $plan2 = Get-PRSubsPlan -Rows $rowsP -S (New-PRSubs -Db $dbm -Version 'test') -HighOnly -Standard $true -Sdh $true
    Check ($plan2.Std -eq 0 -and $plan2.Sdh -eq 0) 're-run finds nothing left to download (existing .en.srt / .en.sdh.srt skipped)'

    # 3-candidate fallback: candidates 12 (Spanish), 13 (tiny), then 11 (good)
    $e4 = JP 'Series' 'Show (2020)' 'Season 01' 'Show (2020) - S01E04 - Four.mkv'; 'v' | Set-Content -LiteralPath $e4
    $fakeItem = [pscustomobject]@{ Video = $e4; Name = 'Show (2020) - S01E04 - Four.mkv'; Kind = 'episode'; Id = '5000'; StdStatus = 'found'; StdCands = @(([pscustomobject]@{ Id = '12'; Name = 'es'; Cues = 700; Sdh = $false; Encoding = 'utf-8' }), ([pscustomobject]@{ Id = '13'; Name = 'tiny'; Cues = 700; Sdh = $false; Encoding = 'utf-8' }), ([pscustomobject]@{ Id = '1'; Name = 'good'; Cues = 700; Sdh = $false; Encoding = 'utf-8' })); SdhStatus = 'none'; SdhCands = @(); Note = '' }
    $script:dl.Clear(); $logp2 = JP 'subs_log2.csv'
    $res2 = Invoke-PRSubsDownload -Plan @{ Items = @($fakeItem) } -S (New-PRSubs -Db $null -Version 'test') -LogPath $logp2
    Check ($script:dl -join ',' -eq '12,13,1') "fallback tries candidates in order until one is valid ($($script:dl -join ','))"
    Check ($res2.Standard -eq 1 -and $res2.Rejected -eq 2 -and [IO.File]::Exists((Get-PRSubTarget $e4 'standard'))) 'non-English and tiny candidates rejected, third accepted'
    $csv2 = @(Import-Csv -LiteralPath $logp2 -Encoding UTF8)
    Check (@($csv2 | Where-Object { $_.result -like 'rejected: not English' }).Count -eq 1 -and @($csv2 | Where-Object { $_.result -like 'rejected: too few cues' }).Count -eq 1) 'rejections logged with reasons'

    # all three bad -> nothing written
    $e5 = JP 'Series' 'Show (2020)' 'Season 01' 'Show (2020) - S01E05 - Five.mkv'; 'v' | Set-Content -LiteralPath $e5
    $bad = [pscustomobject]@{ Video = $e5; Name = 'e5'; Kind = 'episode'; Id = '5000'; StdStatus = 'found'; StdCands = @(([pscustomobject]@{ Id = '12'; Name = 'a'; Cues = 700; Sdh = $false; Encoding = 'utf-8' }), ([pscustomobject]@{ Id = '13'; Name = 'b'; Cues = 700; Sdh = $false; Encoding = 'utf-8' }), ([pscustomobject]@{ Id = '12'; Name = 'c'; Cues = 700; Sdh = $false; Encoding = 'utf-8' }), ([pscustomobject]@{ Id = '1'; Name = 'd'; Cues = 700; Sdh = $false; Encoding = 'utf-8' })); SdhStatus = 'none'; SdhCands = @(); Note = '' }
    $script:dl.Clear()
    $res3 = Invoke-PRSubsDownload -Plan @{ Items = @($bad) } -S (New-PRSubs -Db $null -Version 'test') -LogPath (JP 'subs_log3.csv')
    Check ($res3.Standard -eq 0 -and $script:dl.Count -eq 3 -and -not [IO.File]::Exists((Get-PRSubTarget $e5 'standard'))) 'only 3 candidates are tried, nothing written when all are bad'

    # rate limit: stops cleanly, keeps what it got
    $e6 = JP 'Series' 'Show (2020)' 'Season 01' 'Show (2020) - S01E06 - Six.mkv'; 'v' | Set-Content -LiteralPath $e6
    $e7 = JP 'Series' 'Show (2020)' 'Season 01' 'Show (2020) - S01E07 - Seven.mkv'; 'v' | Set-Content -LiteralPath $e7
    $mkItem = { param($v) [pscustomobject]@{ Video = $v; Name = (Split-Path -Leaf $v); Kind = 'episode'; Id = '5000'; StdStatus = 'found'; StdCands = @([pscustomobject]@{ Id = '1'; Name = 'good'; Cues = 700; Sdh = $false; Encoding = 'utf-8' }); SdhStatus = 'none'; SdhCands = @(); Note = '' } }
    $script:dl.Clear(); $script:limitAt = 2
    $res4 = Invoke-PRSubsDownload -Plan @{ Items = @((& $mkItem $e6), (& $mkItem $e7)) } -S (New-PRSubs -Db $null -Version 'test') -LogPath (JP 'subs_log4.csv')
    $script:limitAt = 0
    Check ($res4.Standard -eq 1 -and $res4.Stopped -like '*Download limit reached*5 minute*' -and [IO.File]::Exists((Get-PRSubTarget $e6 'standard')) -and -not [IO.File]::Exists((Get-PRSubTarget $e7 'standard'))) "429 stops cleanly after 1 file ($($res4.Stopped))"

    # cache persistence
    $cp = JP 'subs_cache.json'
    $Sc = New-PRSubs -Db $null -Version 'test' -CachePath $cp
    $script:calls.Clear(); $null = PR-SubLookup $Sc 'movie' 'tmdb' '348'; Save-PRSubsCache $Sc
    $Sc2 = New-PRSubs -Db $null -Version 'test' -CachePath $cp
    $script:calls.Clear(); $lkc = PR-SubLookup $Sc2 'movie' 'tmdb' '348'
    Check ($script:calls.Count -eq 0 -and @($lkc).Count -ge 2) 'lookups are cached on disk between runs'

    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
} else { Write-Host 'SKIP file-system tests (Windows only)' }
Check ((Get-PRSubsEstimate 0) -eq 'nothing to download') 'estimate: nothing'
Check ((Get-PRSubsEstimate 100) -like 'about*minute*') 'estimate: minutes for <= 200'
Check ((Get-PRSubsEstimate 450) -like 'about 3 hour*') 'estimate: hours beyond the 200/hour cap'

Remove-Item $cache -ErrorAction SilentlyContinue
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASSED' }
