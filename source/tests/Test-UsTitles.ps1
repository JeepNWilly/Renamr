# Setup: Use US titles - TMDB asked in en-US (region US); names use TMDB's main en-US title. An alternative (US / GB) title is kept only
# when it is exactly the file's own title and not the main title; it is never substituted on its own (mocked TMDB).
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
$script:calls = New-Object System.Collections.Generic.List[string]
function F($id, $t, $d, $pop = 20) { [pscustomobject]@{ id = $id; title = $t; original_title = $t; release_date = $d; popularity = $pop } }
function A($c, $t, $ty = '') { [pscustomobject]@{ iso_3166_1 = $c; title = $t; type = $ty } }
$films = @(
    @{ F = (F 136418 'Hummingbird' '2013-05-09'); Alt = @((A 'CZ' 'Zoldner'), (A 'US' 'Redemption'), (A 'GB' 'Redemption')); Q = @('Hummingbird', 'Redemptionx') },
    @{ F = (F 300671 '13 Hours: The Secret Soldiers of Benghazi' '2016-01-13'); Alt = @((A 'US' '13 Hours')); Q = @('13 Hours The Secret Soldiers of Benghazi') },
    @{ F = (F 209112 'Batman v Superman: Dawn of Justice' '2016-03-23'); Alt = @((A 'US' 'BVS'), (A 'US' 'Batman vs Superman')); Q = @('Batman v Superman Dawn of Justice') },
    @{ F = (F 348 'Alien' '1979-05-25'); Alt = @((A 'US' 'Alien 1')); Q = @('Alien') },
    @{ F = (F 679 'Aliens' '1986-07-18'); Alt = @((A 'US' ('Alien' + [char]0xB2 + ': Special Assembly Cut Edition'))); Q = @('Aliens') },
    @{ F = (F 312221 'Creed' '2015-11-25'); Alt = @((A 'US' 'Rocky VII')); Q = @('Creed') },
    @{ F = (F 262504 'Allegiant' '2016-03-09'); Alt = @((A 'US' 'Divergente la serie: Leal'), (A 'US' 'The Divergent Series: Allegiant')); Q = @('Allegiant', 'The Divergent Series Allegiant') },
    @{ F = (F 555 'Le Film' '2013-01-01'); Alt = @((A 'US' ('R' + [char]0xE9 + 'demption'))); Q = @('Redemptionz') }
)
function PR-TmdbGet($db, [string]$path, $params) {
    $script:calls.Add($path + '?' + (($params.Keys | Sort-Object | ForEach-Object { "$_=$($params[$_])" }) -join '&'))
    if ($path -eq '/search/movie') { foreach ($x in $films) { if ($x.Q -contains [string]$params.query) { return [pscustomobject]@{ results = @($x.F) } } }; return [pscustomobject]@{ results = @() } }
    if ($path -match '^/movie/(\d+)/alternative_titles$') { foreach ($x in $films) { if ([string]$x.F.id -eq $Matches[1]) { return [pscustomobject]@{ titles = @($x.Alt) } } } }
    if ($path -eq '/search/tv') { return [pscustomobject]@{ results = @([pscustomobject]@{ id = 55; name = 'Skam'; original_name = 'Skam'; first_air_date = '2015-09-25'; popularity = 10 }) } }
    if ($path -eq '/tv/55/alternative_titles') { return [pscustomobject]@{ titles = @((A 'US' 'Shame')) } }
    return [pscustomobject]@{ results = @(); titles = @(); episodes = @() }
}
$on = New-PRTmdb -Key 'x' -CachePath '' -UsTitles $true; $off = New-PRTmdb -Key 'x' -CachePath '' -UsTitles $false
function Name($q, $y, $db = $on) { $m = PR-MatchMovieOne $db 'tmdb' $q $y; if ($m) { return [string]$m.Title }; return '' }
# regressions: the main en-US title is kept, never replaced by an alternative title
Check ((Name '13 Hours The Secret Soldiers of Benghazi' 2016) -eq '13 Hours - The Secret Soldiers of Benghazi') "13 Hours keeps its full main title ($(Name '13 Hours The Secret Soldiers of Benghazi' 2016))"
Check ((Name 'Batman v Superman Dawn of Justice' 2016) -like 'Batman v Superman*Dawn of Justice') "Batman v Superman keeps its main title, not 'BVS'"
Check ((Name 'Alien' 1979) -eq 'Alien') "Alien stays 'Alien', not 'Alien 1'"
Check ((Name 'Aliens' 1986) -eq 'Aliens') "Aliens stays 'Aliens'"
Check ((Name 'Creed' 2015) -eq 'Creed') "Creed stays 'Creed', not 'Rocky VII'"
Check ((Name 'Allegiant' 2016) -eq 'Allegiant') "Allegiant stays 'Allegiant'"
Check (-not @($script:calls | Where-Object { $_ -like '*alternative_titles*' }).Count) "a file named like the main title needs no alternative-title call"
# the file's own alternative title is kept
Check ((Name 'The Divergent Series Allegiant' 2016) -like 'The Divergent Series*Allegiant') "a file named by an exact US alternative title keeps it"
Check ((Name 'Hummingbird' 2013) -eq 'Hummingbird') "136418 named 'Hummingbird' stays 'Hummingbird'"
$m = PR-MatchMovieOne $on 'tmdb' 'Redemptionx' 2013
Check ($m -and $m.Id -eq 136418 -and $m.Title -eq 'Hummingbird') "search fallback matches by alternative title but names by the main title when the file title is not exactly one"
Check ((PR-NameTitle $on 'tmdb' 'movie' 136418 'Hummingbird' 'Redemption') -eq 'Redemption') "file 'Redemption' + 136418 keeps 'Redemption' (exact US/GB alternative title)"
Check ((PR-NameTitle $on 'tmdb' 'movie' 136418 'Hummingbird' 'redemption.') -eq 'Redemption') "case and punctuation ignored for the exact check"
Check ((PR-NameTitle $on 'tmdb' 'movie' 136418 'Hummingbird' 'Zoldner') -eq 'Hummingbird') "only US / GB alternative titles count"
Check ((PR-NameTitle $on 'tmdb' 'movie' 555 'Le Film' 'Redemption') -eq 'Le Film') "accents count: 'Redemption' is not 'R$([char]0xE9)demption'"
Check ((PR-NameTitle $off 'tmdb' 'movie' 136418 'Hummingbird' 'Redemption') -eq 'Hummingbird' -and (PR-NameTitle $on 'tvdb' 'movie' 136418 'Hummingbird' 'Redemption') -eq 'Hummingbird') "only TMDB and only when the option is on"
# requests
$script:calls.Clear(); [void](Name 'Creed' 2015)
Check (@($script:calls | Where-Object { $_ -like '/search/movie?*language=en-US*region=US*' }).Count -gt 0) "on: movie search sent language=en-US and region=US"
$script:calls.Clear(); [void](Name 'Creed' 2015 $off)
Check (-not @($script:calls | Where-Object { $_ -like '*language=*' -or $_ -like '*alternative_titles*' }).Count) "off: no language parameter and no alternative-title calls"
# series
$sh = PR-MatchShowOne $on 'tmdb' 'Skam' 2015; $sh2 = PR-MatchShowOne $on 'tmdb' 'Shame' 2015
Check ($sh.Name -eq 'Skam' -and $sh2.Name -eq 'Shame') "series: main title kept; a file named by the US alternative title keeps it"
Check (@($script:calls | Where-Object { $_ -like '/search/tv?*language=en-US*' }).Count -gt 0) "series: search sent language=en-US"
# setting + cache
$script:PR_US_TITLES = $false; $d = New-PRTmdb -Key 'x' -CachePath ''; Check (-not $d.UsTitles) "New-PRTmdb follows the Setup option when not given"
$script:PR_US_TITLES = $true; $d = New-PRTmdb -Key 'x' -CachePath ''; Check ($d.UsTitles) "the option is on by default"
$tr = PR-Trim '/movie/1/alternative_titles' ([pscustomobject]@{ id = 1; titles = @([pscustomobject]@{ iso_3166_1 = 'US'; title = 'A'; type = ''; extra = 'x' }) })
Check (@($tr.titles).Count -eq 1 -and $tr.titles[0].title -eq 'A' -and -not $tr.titles[0].PSObject.Properties['extra']) "alternative titles are trimmed for the cache"
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASS' }
