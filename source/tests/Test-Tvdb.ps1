# Offline test of the TVDB provider: PR-TvdbRaw and PR-TmdbGet are mocked, no network or keys needed.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
$script:tvdbCalls = @()
function PR-TvdbRaw($db, [string]$path, $params) {
    $script:tvdbCalls += $path
    if ($path -eq '/search' -and $params.type -eq 'series') {
        return ('{"data":[{"tvdb_id":"777","name":"Obscure Show","year":"2015","translations":{"eng":"Obscure Show"}},{"tvdb_id":"778","name":"Other","year":"1999"}]}' | ConvertFrom-Json)
    }
    if ($path -eq '/search' -and $params.type -eq 'movie') {
        return ('{"data":[{"tvdb_id":"55","name":"Hidden Gem","year":"2012"}]}' | ConvertFrom-Json)
    }
    if ($path -like '/series/777/episodes/default*') {
        if ($params.page -eq 0) { return ('{"data":{"episodes":[{"number":1,"seasonNumber":1,"name":"Pilot"},{"number":2,"seasonNumber":1,"name":"Second: Try"}]},"links":{"next":1}}' | ConvertFrom-Json) }
        return ('{"data":{"episodes":[{"number":3,"seasonNumber":1,"name":"Third"}]},"links":{"next":null}}' | ConvertFrom-Json)
    }
    return $null
}
function PR-TmdbGet($db, [string]$path, $params) { return [pscustomobject]@{ results = @(); episodes = @() } }
$cache = Join-Path ([IO.Path]::GetTempPath()) ("tvdbtest_" + [guid]::NewGuid() + '.json')

# provider order
$db = New-PRTmdb -Key 'x' -CachePath $cache -TvdbKey 'k' -Source 'TMDB first'
Check ((PR-Providers $db) -join ',' -eq 'tmdb,tvdb') 'TMDB first order'
$db.Source = 'TVDB first'; Check ((PR-Providers $db) -join ',' -eq 'tvdb,tmdb') 'TVDB first order'
$db.Source = 'TVDB only'; Check ((PR-Providers $db) -join ',' -eq 'tvdb') 'TVDB only order'
$db.Source = 'Movies: TMDB, TV: TVDB'
Check ((PR-Providers $db 'movie') -join ',' -eq 'tmdb,tvdb') 'default: movies TMDB first'
Check ((PR-Providers $db 'tv') -join ',' -eq 'tvdb,tmdb') 'default: TV TVDB first'
$db2 = New-PRTmdb -Key 'x' -CachePath $cache -Source 'TVDB first'
Check ((PR-Providers $db2) -join ',' -eq 'tmdb') 'no TVDB key falls back to TMDB'

# search + season shaping
$db = New-PRTmdb -Key 'x' -CachePath $cache -TvdbKey 'k'
$sh = PR-MatchShow $db 'Obscure Show' 2015
Check ($sh -and $sh.Provider -eq 'tvdb' -and [string]$sh.Id -eq '777') 'show falls back to TVDB when TMDB has nothing'
$se = PR-Season $db @{} '777' 1 'tvdb'
Check ($se.Map.Count -eq 3 -and $se.Map[2] -eq 'Second: Try') 'season paginates 3 episodes'
$mv = PR-MatchMovie $db 'Hidden Gem' 2012
Check ($mv -and $mv.Provider -eq 'tvdb' -and $mv.Conf -eq 'high' -and $mv.Note -like 'TVDB:*') 'movie falls back to TVDB'

# show name + year parsing from the part before SxxEyy
$pp = PR-ParseShow 'Lioness 2023 - '
Check ($pp.Title -eq 'Lioness' -and $pp.Year -eq 2023) "year parsed before ' - ' (title '$($pp.Title)' year '$($pp.Year)')"
$pp = PR-ParseShow 'Last.Man.Standing.2011.'
Check ($pp.Title -eq 'Last Man Standing' -and $pp.Year -eq 2011) 'dotted show name with year'
$pp = PR-ParseShow 'Colony'
Check ($pp.Title -eq 'Colony' -and $null -eq $pp.Year) 'show name without year'
# name cleanup
Check ((PR-StripYear 'Last Man Standing (2011)') -eq 'Last Man Standing') 'trailing (year) removed from a TVDB title'
Check ((PR-StripYear 'Blade Runner 2049') -eq 'Blade Runner 2049') 'year-like number without parentheses is kept'
Check ((PR-Safe ('Alien' + [char]0x00B3 + ' (1992)')) -eq 'Alien3 (1992)') 'superscript 3 becomes plain 3'
Check ((PR-Safe ('Foo' + [char]0x2122 + ': Bar')) -eq 'Foo - Bar') 'trademark sign dropped'
Check ((PR-Safe ('Am' + [char]0x00E9 + 'lie (2001)')) -eq ('Am' + [char]0x00E9 + 'lie (2001)')) 'accented letters are kept'

# full plan
$M = 'Z:\Media\Movies'; $S = 'Z:\Media\Series'
$paths = @("$S\Obscure Show\Season 1\Obscure.Show.S01E02.720p.mkv", "$M\Hidden.Gem.2012.1080p.mkv")
$rows = @(New-PRPlan -Paths $paths -MoviesRoot $M -SeriesRoot $S -Db $db | ForEach-Object { $_ })
$e = $rows | Where-Object { $_.media_type -eq 'episode' } | Select-Object -First 1
Check ($e.tmdb_id -eq 'tvdb:777') "episode id tagged tvdb ($($e.tmdb_id))"
Check ($e.new_path -like '*Obscure Show (2015)*Season 01*S01E02*Second*Try*720p.mkv') "episode path (uppercase code, resolution kept): $($e.new_path)"
$m = $rows | Where-Object { $_.media_type -eq 'movie' } | Select-Object -First 1
Check ($m.tmdb_id -eq 'tvdb:55' -and $m.new_path -like '*Hidden Gem (2012)*' -and $m.new_path -like '* - 1080p.mkv') "movie row: $($m.tmdb_id) $($m.new_path)"

# cache roundtrip: no TVDB calls on second run, even with no key
Save-PRTmdbCache $db
$before = $script:tvdbCalls.Count
$db3 = New-PRTmdb -Key 'x' -CachePath $cache -TvdbKey 'k' -Source 'TVDB only'
$null = PR-MatchShow $db3 'Obscure Show' 2015
Check ($script:tvdbCalls.Count -eq $before) 'second run served from cache'
# a same-named show with the wrong year on TVDB must lose to the right one on TMDB
function PR-TvdbRaw($db, [string]$path, $params) {
    if ($path -eq '/search' -and $params.type -eq 'series') { return ('{"data":[{"tvdb_id":"900","name":"Lioness","year":"2021"}]}' | ConvertFrom-Json) }
    return $null
}
function PR-TmdbGet($db, [string]$path, $params) {
    if ($path -eq '/search/tv') { return ('{"results":[{"id":113962,"name":"Lioness","original_name":"Lioness","first_air_date":"2023-07-23","popularity":200}]}' | ConvertFrom-Json) }
    return [pscustomobject]@{ results = @(); episodes = @() }
}
$dbL = New-PRTmdb -Key 'x' -CachePath (Join-Path ([IO.Path]::GetTempPath()) ("tvdbL_" + [guid]::NewGuid() + '.json')) -TvdbKey 'k'
$ls = PR-MatchShow $dbL 'Lioness' 2023
Check ($ls -and $ls.Provider -eq 'tmdb' -and [string]$ls.Id -eq '113962') "wrong-year TVDB show rejected, TMDB used (got $($ls.Provider) $($ls.Id) $($ls.Year))"
$ls2 = PR-MatchShow $dbL 'Lioness' $null
Check ($ls2 -and $ls2.Provider -eq 'tvdb') 'no year in file: TVDB match is accepted'

Remove-Item $cache -ErrorAction SilentlyContinue
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASSED' }
