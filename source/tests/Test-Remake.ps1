# Offline test (mocked TMDB, no network): remakes, edition words, folder year, and same-name ambiguity.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
$films = @{
    'the punisher' = @(@{ id = 7220; title = 'The Punisher'; date = '2004-04-16'; pop = 20 }, @{ id = 9999; title = 'The Punisher'; date = '1989-10-05'; pop = 5 })
    'dune'         = @(@{ id = 2; title = 'Dune'; date = '2021-09-15'; pop = 50 }, @{ id = 1; title = 'Dune'; date = '1984-12-14'; pop = 10 })
    'total recall' = @(@{ id = 861; title = 'Total Recall'; date = '1990-06-01'; pop = 30 }, @{ id = 64635; title = 'Total Recall'; date = '2012-08-01'; pop = 15 })
    'heat'         = @(@{ id = 949; title = 'Heat'; date = '1995-12-15'; pop = 30 })
}
function PR-TmdbGet($db, [string]$path, $params) {
    if ($path -eq '/search/movie') {
        $list = @($films[([string]$params.query).ToLowerInvariant()])
        if ($params.primary_release_year) { $list = @($list | Where-Object { $_ -and $_.date.StartsWith([string]$params.primary_release_year) }) }
        $res = @($list | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ id = $_.id; title = $_.title; original_title = $_.title; release_date = $_.date; popularity = $_.pop } })
        return [pscustomobject]@{ results = $res }
    }
    return [pscustomobject]@{ results = @(); episodes = @() }
}
$cache = Join-Path ([IO.Path]::GetTempPath()) ("remake_" + [guid]::NewGuid() + '.json')
$db = New-PRTmdb -Key 'x' -CachePath $cache -Source 'TMDB only'
$M = 'Z:\Media\Movies'
$paths = @(
    "$M\The Punisher - Extended Edition (2004) 720p AAC.mp4",
    "$M\The Punisher - Uncut (1989) 720p AAC.mp4",
    "$M\The Punisher.mp4",
    "$M\Dune (1984)\Dune.mkv",
    "$M\Total Recall.mkv",
    "$M\Heat.mkv")
$rows = @(New-PRPlan -Paths $paths -MoviesRoot $M -SeriesRoot '' -Db $db -ProbeReal $false | ForEach-Object { $_ })
function RowOf($leaf) { $rows | Where-Object { $_.old_path -like "*\$leaf" } | Select-Object -First 1 }
$a = RowOf 'The Punisher - Extended Edition (2004) 720p AAC.mp4'
Check ($a.new_path -like '*The Punisher (2004)*' -and $a.confidence -eq 'high' -and [string]$a.tmdb_id -eq '7220') "2004 file with edition word -> The Punisher (2004), high ($($a.new_path))"
$b = RowOf 'The Punisher - Uncut (1989) 720p AAC.mp4'
Check ($b.new_path -like '*The Punisher (1989)*' -and [string]$b.tmdb_id -eq '9999' -and $b.note -notlike 'DUPLICATE*') "1989 file is its own film, not a duplicate ($($b.new_path))"
$c = RowOf 'The Punisher.mp4'
Check ($c.new_path -eq '' -and $c.note -like 'POSSIBLE REMAKE*' -and $c.note -like '*AMBIGUOUS*') "year-less file is not renamed onto the 2004 file's name ($($c.note))"
Check (@(Get-PRDuplicateGroups $rows).Count -eq 0) 'no duplicate group is created for the remake pair'
$d = RowOf 'Dune.mkv'
Check ($d.new_path -like '*Dune (1984)*' -and $d.note -like '*taken from the folder name*') "year taken from the folder: Dune (1984)\Dune.mkv ($($d.new_path))"
$e = RowOf 'Total Recall.mkv'
Check ($e.new_path -like '*Total Recall (1990)*' -and $e.confidence -eq 'low' -and $e.note -like '*AMBIGUOUS*1990, 2012*') "year-less, no clash: still a low-confidence guess flagged AMBIGUOUS ($($e.note))"
$f = RowOf 'Heat.mkv'
Check ($f.new_path -like '*Heat (1995)*' -and $f.note -notlike '*AMBIGUOUS*') 'single-film name is not flagged ambiguous'
# option off: a movie loose in the library root is only renamed in place; one already in a folder still goes to its Name (Year) folder
$rows2 = @(New-PRPlan -Paths @("$M\Heat.mkv", "$M\Dune (1984)\Dune.mkv") -MoviesRoot $M -SeriesRoot '' -Db $db -ProbeReal $false -FolderLoose $false | ForEach-Object { $_ })
$h2 = $rows2 | Where-Object { $_.old_path -like '*\Heat.mkv' } | Select-Object -First 1
Check ($h2.new_path -eq "$M\Heat (1995).mkv") "folder option off: loose movie renamed in place ($($h2.new_path))"
$d2 = $rows2 | Where-Object { $_.old_path -like '*Dune.mkv' } | Select-Object -First 1
Check ($d2.new_path -like '*\Dune (1984)\Dune (1984).mkv') "folder option off: a movie already in a folder is unchanged ($($d2.new_path))"
$h3 = $rows | Where-Object { $_.old_path -like '*\Heat.mkv' } | Select-Object -First 1
Check ($h3.new_path -eq "$M\Heat (1995)\Heat (1995).mkv") 'folder option on (default): loose movie goes into its own folder'
Remove-Item $cache -ErrorAction SilentlyContinue
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASSED' }
