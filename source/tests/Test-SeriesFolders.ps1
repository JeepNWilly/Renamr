# Note: mock data lives in $script:MockShows (New-PRPlan has its own $shows, and PowerShell scoping is dynamic).
# Offline test (mocked TMDB, temp folder): the show comes from its folder; years that change per season are season years;
# one search per show; the match must have the folder's episodes; exact titles win. Silicon Valley (no SxxEyy) is unaffected.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
$script:MockShows = @(
    @{ id = 1622; name = 'Supernatural'; date = '2005-09-13'; pop = 80; seasons = 15; eps = 22 },
    @{ id = 99001; name = 'Neuro - Supernatural Detective'; date = '2007-10-02'; pop = 2; seasons = 1; eps = 12 },
    @{ id = 99002; name = 'Supernatural - The Anime Series'; date = '2011-01-12'; pop = 3; seasons = 1; eps = 22 },
    @{ id = 501; name = 'The Show'; date = '2010-01-01'; pop = 50; seasons = 1; eps = 5 },
    @{ id = 502; name = 'The Show'; date = '2012-01-01'; pop = 5; seasons = 4; eps = 10 },
    @{ id = 60573; name = 'Silicon Valley'; date = '2014-04-06'; pop = 30; seasons = 6; eps = 10 }
)
$script:Searches = New-Object System.Collections.Generic.List[string]
function PR-TmdbGet($db, [string]$path, $params) {
    if ($path -eq '/search/tv') {
        $q = ([string]$params.query).ToLowerInvariant(); $y = [string]$params.first_air_date_year; $script:Searches.Add("$q|$y")
        $list = @($script:MockShows | Where-Object { (PR-Norm $_.name).Contains((PR-Norm $q)) -and (-not $y -or $_.date.StartsWith($y)) } | Sort-Object { - $_.pop })
        return [pscustomobject]@{ results = @($list | ForEach-Object { [pscustomobject]@{ id = $_.id; name = $_.name; original_name = $_.name; first_air_date = $_.date; popularity = $_.pop } }) }
    }
    if ($path -match '^/tv/(\d+)/season/(\d+)$') {
        $sh = $script:MockShows | Where-Object { $_.id -eq [int]$Matches[1] }; $sn = [int]$Matches[2]
        if (-not $sh -or $sn -gt $sh.seasons -or $sn -lt 1) { return [pscustomobject]@{ episodes = @() } }
        $t = $(if ($sh.id -eq 60573 -and $sn -eq 1) { @('Minimum Viable Product', 'The Cap Table') } else { @() })
        return [pscustomobject]@{ episodes = @(1..$sh.eps | ForEach-Object { [pscustomobject]@{ episode_number = $_; name = $(if ($_ -le $t.Count) { $t[$_ - 1] } else { "$($sh.name) $sn-$_" }) } }) }
    }
    return [pscustomobject]@{ results = @(); episodes = @() }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ("prsf_" + [guid]::NewGuid().ToString('N').Substring(0, 6))
$M = Join-Path $root 'Movies'; $S = Join-Path $root 'Series'
function Plan([string[]]$rel) {
    $files = @($rel | ForEach-Object { Join-Path $S $_ }); foreach ($f in $files) { [void][IO.Directory]::CreateDirectory((Split-Path $f)); 'x' | Set-Content -LiteralPath $f }
    $db = New-PRTmdb -Key 'x' -CachePath (Join-Path $root ("c" + [guid]::NewGuid().ToString('N').Substring(0, 4) + ".json")) -Source 'TMDB only'
    $script:Searches.Clear()
    return @(New-PRPlan -Paths $files -MoviesRoot $M -SeriesRoot $S -Db $db -ProbeReal $false -FolderLoose $true)
}
function Row($rows, $leaf) { $rows | Where-Object { (PR-Base $_.old_path) -eq $leaf } }
[void][IO.Directory]::CreateDirectory($M)
try {
    # 1. the reported case: each season carries its own release year
    $sp = @('Supernatural\Season 01\Supernatural (2005) - S01E01 - 1080p Bluray x265-HiQVE.mkv', 'Supernatural\Season 03\Supernatural (2007) - S03E01 - 1080p Bluray x265-HiQVE.mkv',
            'Supernatural\Season 03\Supernatural (2007) - S03E02 - 1080p Bluray x265-HiQVE.mkv', 'Supernatural\Season 07\Supernatural (2011) - S07E01 - 1080p Bluray x265-HiQVE.mkv')
    $rows = Plan $sp
    $s3 = Row $rows 'Supernatural (2007) - S03E01 - 1080p Bluray x265-HiQVE.mkv'; $s7 = Row $rows 'Supernatural (2011) - S07E01 - 1080p Bluray x265-HiQVE.mkv'
    Check (@($rows | Where-Object { $_.tmdb_id -eq '1622' }).Count -eq 4) "every Supernatural season matches Supernatural (2005), not Neuro (2007) or the anime (2011) [$(@($rows | ForEach-Object { $_.tmdb_id }) -join ',')]"
    Check ($s3.new_path -like '*\Supernatural (2005)\Season 03\Supernatural (2005) - S03E01 - Supernatural 3-1*.mkv') "S03 named from the matched show, with its episode title [$($s3.new_path)]"
    Check ($s7.new_path -like '*\Supernatural (2005)\Season 07\Supernatural (2005) - S07E01 - Supernatural 7-1*.mkv') "S07 (2011) also goes to Supernatural (2005)"
    Check (@($rows | ForEach-Object { $_.group_key } | Select-Object -Unique).Count -eq 1) "all seasons share one show group [$(@($rows | ForEach-Object { $_.group_key } | Select-Object -Unique) -join ' / ')]"
    Check (@($script:Searches | Select-Object -Unique).Count -eq 1) "one search for the whole show [$($script:Searches -join ' / ')]"
    Check ($s3.note -like "*year 2007 in the file name is the season's year*" -and $s3.note -notlike '*episode not found*' -and $s3.note -notlike '*filename title*') "the note explains the season year; the episode is found [$($s3.note)]"
    Check ($s3.confidence -eq 'high') "exact show match with its episodes is high confidence"
    # 2. a show folder that has the year
    $rows = Plan @('Supernatural (2005)\Supernatural (2008) - S04E01 - x265.mkv', 'Supernatural (2005)\Supernatural (2009) - S05E03 - x265.mkv')
    Check (@($rows | Where-Object { $_.tmdb_id -eq '1622' -and $_.new_path -like '*\Supernatural (2005)\Season 0?\*' }).Count -eq 2) "folder 'Supernatural (2005)' (no season folder) gives the show and its year"
    # 3. one year on every episode is still the show's year
    $rows = Plan @('The Show\The Show (2012) - S01E01.mkv', 'The Show\The Show (2012) - S01E02.mkv')
    Check (@($rows | Where-Object { $_.tmdb_id -eq '502' }).Count -eq 2) "the same year on every episode is used as the show's year (The Show 2012)"
    # 4. the match must have the episodes: The Show (2010) has one season of 5, The Show (2012) has 4 seasons
    $rows = Plan @('The Show\Season 04\The Show - S04E01.mkv', 'The Show\Season 04\The Show - S04E08.mkv')
    $r4 = Row $rows 'The Show - S04E01.mkv'
    Check (@($rows | Where-Object { $_.tmdb_id -eq '502' }).Count -eq 2) "a show without the folder's episodes loses to the top result that has them [$(@($rows | ForEach-Object { $_.tmdb_id }) -join ',')]"
    Check ($r4.note -like '*picked by episodes: has 100% of this folder*' -and $r4.new_path -like '*The Show (2012)\Season 04\The Show (2012) - S04E01 - The Show 4-1.mkv') "note says why; named with the right show's episode title [$($r4.note)]"
    # 5. exact title beats a partial one even when the year differs (file in the Series root: name from the file)
    $rows = Plan @('Supernatural (2007) - S03E05.mkv')
    Check ((Row $rows 'Supernatural (2007) - S03E05.mkv').tmdb_id -eq '1622') "exact title 'Supernatural' beats 'Neuro - Supernatural Detective' (2007)"
    # 6. Silicon Valley: no SxxEyy - unchanged
    $rows = Plan @('Silicon Valley\Silicon Valley - 01.mkv', 'Silicon Valley\Silicon Valley - 02.mkv', 'Silicon Valley.mkv')
    $a = Row $rows 'Silicon Valley - 01.mkv'; $b = Row $rows 'Silicon Valley - 02.mkv'; $c = Row $rows 'Silicon Valley.mkv'
    Check ($a.new_path -like '*\Silicon Valley (2014)\Season 01\Silicon Valley (2014) - S01E01 - Minimum Viable Product.mkv' -and $a.tmdb_id -eq '60573') "Silicon Valley - 01 (no SxxEyy) still becomes S01E01 Minimum Viable Product [$($a.new_path)]"
    Check ($b.new_path -like '*S01E02 - The Cap Table.mkv' -and $a.note -like '*assumed s01*' -and $a.confidence -eq 'low') "S01E02, with the 'assumed s01' note and low confidence as before"
    Check ($c.note -like 'unmatched: no SxxEyy*') "a stray file in the Series root is still left alone"
    # 7. a folder that is about something else does not rename the show
    $rows = Plan @('Downloads\Silicon Valley S01E01.mkv')
    Check ((Row $rows 'Silicon Valley S01E01.mkv').tmdb_id -eq '60573') "a folder unrelated to the file name ('Downloads') is ignored; the file's name is used"
} finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
if ($fail -eq 0) { Write-Host 'ALL PASS' } else { Write-Host "$fail FAILED"; exit 1 }
