# Choose match on any row, remembered picks (match_overrides.json), Clear pick, and search by TMDB / TVDB ID (mocked TMDB, temp folder).
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
function PR-TmdbGet($db, [string]$path, $params) {
    switch -regex ($path) {
        '^/search/movie$' { if ([string]$params.query -eq 'Redemption') { return [pscustomobject]@{ results = @([pscustomobject]@{ id = 158394; title = 'Redemption'; original_title = 'Redemption'; release_date = '2013-04-05'; popularity = 2 }) } }; if ([string]$params.query -eq 'Hummingbird') { return [pscustomobject]@{ results = @([pscustomobject]@{ id = 136418; title = 'Hummingbird'; original_title = 'Hummingbird'; release_date = '2013-05-09'; popularity = 20 }) } }; return [pscustomobject]@{ results = @() } }
        '^/movie/136418$' { return [pscustomobject]@{ id = 136418; title = 'Hummingbird'; original_title = 'Hummingbird'; release_date = '2013-05-09' } }
        '^/movie/136418/alternative_titles$' { return [pscustomobject]@{ titles = @([pscustomobject]@{ iso_3166_1 = 'US'; title = 'Redemption'; type = '' }) } }
        '^/search/tv$' { return [pscustomobject]@{ results = @([pscustomobject]@{ id = 55; name = 'Skam'; original_name = 'Skam'; first_air_date = '2015-09-25'; popularity = 10 }) } }
        '^/tv/99$' { return [pscustomobject]@{ id = 99; name = 'Real Show'; original_name = 'Real Show'; first_air_date = '2016-01-01' } }
        '^/tv/(55|99)/season/1$' { return [pscustomobject]@{ episodes = @([pscustomobject]@{ episode_number = 1; name = 'Pilot' }) } }
        default { return [pscustomobject]@{ results = @(); titles = @(); episodes = @() } }
    }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ("prov_" + [guid]::NewGuid().ToString('N').Substring(0, 6))
$M = Join-Path $root 'Movies'; $S = Join-Path $root 'Series'; $ovf = Join-Path $root 'match_overrides.json'
$f1 = Join-Path $M 'Redemption (2013)\Redemption (2013) - 720p.mp4'; $f2 = Join-Path $M 'Redemption.2013.mkv'; $f3 = Join-Path $S 'Skam\Skam S01E01.mkv'
foreach ($f in $f1, $f2, $f3) { [void][IO.Directory]::CreateDirectory((Split-Path $f)); [IO.File]::WriteAllText($f, $f) }
$db = New-PRTmdb -Key 'x' -CachePath '' -UsTitles $true
function Plan { @(New-PRPlan -Paths @(Get-ChildItem $root -Recurse -File -Filter *.m* | ForEach-Object FullName) -MoviesRoot $M -SeriesRoot $S -Db $db -ProbeReal $false -FolderLoose $true) }
function RowOf($rows, $p) { $rows | Where-Object { $_.old_path -eq $p } | Select-Object -First 1 }
$script:PR_OVR = @{}
$rows = Plan; $r = RowOf $rows $f1
Check ([string]$r.tmdb_id -eq '158394' -and $r.confidence -eq 'high') "before: the file matches the documentary at high confidence (no pick yet)"
Check (-not (Test-PRHasOverride $rows $r.group_key $M)) "before: no remembered pick"
$c1 = @(Get-PRCandidates $db 'movie' 'tmdb:136418' $null); $c2 = @(Get-PRCandidates $db 'movie' '136418' 2013)
Check ($c1.Count -eq 1 -and $c1[0].Id -eq 136418 -and $c1[0].Title -eq 'Hummingbird' -and $c2.Count -eq 1 -and $c2[0].Provider -eq 'tmdb') "search by TMDB ID (tmdb:136418 and 136418)"
$c3 = @(Get-PRCandidates $db 'movie' 'tvdb:1884' $null); Check ($c3.Count -eq 0) "tvdb:1884 without a TVDB key: nothing (logged), no error"
# pick on a high-confidence, already named row
$gk = $r.group_key; $rows = Update-PRPlanGroup $rows $gk $c1[0] $db $M $S $false $true
[void](Set-PROverride $rows $gk $c1[0] $M); Export-PROverrides $ovf
$r = RowOf $rows $f1
Check ([string]$r.tmdb_id -eq '136418') "pick applies to a high-confidence row"
Check (-not $r.new_path -and [string]$r.note -like '*already correctly named*') "pick 136418 keeps the name 'Redemption (2013) - 720p' (US title)"
# fresh scan with the saved file
$script:PR_OVR = @{}; Check ((Import-PROverrides $ovf) -ge 1) "overrides file read back"
Check (@($script:PR_OVR.Keys | Where-Object { $_ -like '* *|*' -and $_ -notlike 'movie|*' }).Count -eq 0) "each remembered name is its own entry"
$rows = Plan; $r = RowOf $rows $f1
Check ([string]$r.tmdb_id -eq '136418' -and $r.confidence -eq 'high' -and [string]$r.note -like '*your pick*') "later scan: the pick is used first, high confidence, note 'your pick'"
$rows2 = Plan; Check ([string](RowOf $rows2 $f1).tmdb_id -eq '136418' -and -not (RowOf $rows2 $f1).new_path) "stable on another scan"
# loose file: pick, rename, scan again
$r2 = RowOf $rows $f2; $hb = @(Get-PRCandidates $db 'movie' 'Hummingbird' 2013)[0]
$rows = Update-PRPlanGroup $rows $r2.group_key $hb $db $M $S $false $true; [void](Set-PROverride $rows $r2.group_key $hb $M)
$r2 = RowOf $rows $f2; $tgt = $(if ($r2.new_path) { $r2.new_path } else { $r2.fold_path })
Check ($tgt -like '*\Redemption (2013)\Redemption (2013).mkv' -and $r2.accepted -eq 'yes') "loose file picked as 136418 is planned as Redemption (2013)\Redemption (2013).mkv and ticked"
[IO.File]::Move($f1, "$f1.keep")   # free the folder name the target needs (same folder as the first file)
[void][IO.Directory]::CreateDirectory((Split-Path $tgt)); [IO.File]::Move($f2, $tgt)
$rows = Plan; $r3 = RowOf $rows $tgt
Check ($r3 -and [string]$r3.tmdb_id -eq '136418' -and [string]$r3.note -like '*your pick*') "after the rename the pick still applies (by the new name)"
[IO.File]::Move($tgt, $f2); [IO.File]::Move("$f1.keep", $f1)
# clear
$rows = Plan; $r = RowOf $rows $f1
$n = Remove-PROverride $rows $r.group_key $M; Export-PROverrides $ovf
Check ($n -ge 1 -and -not (Test-PRHasOverride $rows $r.group_key $M)) "Clear pick removes the remembered names ($n)"
$script:PR_OVR = @{}; [void](Import-PROverrides $ovf); $rows = Plan
Check ([string](RowOf $rows $f1).tmdb_id -eq '158394') "after Clear pick a scan matches automatically again"
# show
$e = RowOf $rows $f3; Check ([string]$e.tmdb_id -eq '55') "show matched automatically first"
$rs = @(Get-PRCandidates $db 'show' 'tmdb:99' $null)[0]; Check ($rs.Id -eq 99 -and $rs.Title -eq 'Real Show') "search a show by TMDB ID"
$rows = Update-PRPlanGroup $rows $e.group_key $rs $db $M $S $false $true; [void](Set-PROverride $rows $e.group_key $rs $M); Export-PROverrides $ovf
$script:PR_OVR = @{}; $nk = Import-PROverrides $ovf; Check ($nk -ge 2 -and $script:PR_OVR.ContainsKey($e.group_key)) "several picks read back as separate entries ($nk)"
$rows = Plan; $e = RowOf $rows $f3
Check ([string]$e.tmdb_id -eq '99' -and $e.new_path -like '*\Real Show (2016)\*' -and $e.accepted -eq 'yes' -and $e.confidence -eq 'high' -and [string]$e.note -like 'your pick*') "show pick remembered: episodes use it, ticked, high, 'your pick'"
$script:PR_OVR = @{}
Remove-Item -LiteralPath $root -Recurse -Force
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASS' }
