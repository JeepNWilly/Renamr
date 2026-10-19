# Offline test (mocked TMDB, temp folder): Accept low-confidence rows and Choose match before a Full Run.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
$films = @{
    "brewsters millions" = @(@{ id = 11; title = "Brewster's Millions"; date = '1985-05-22'; pop = 20; ov = 'A minor-league pitcher must spend 30 million.' }, @{ id = 12; title = "Brewster's Millions"; date = '1945-04-01'; pop = 3; ov = 'Older version.' })
    'gattaca' = @(@{ id = 782; title = 'Gattaca'; date = '1997-09-07'; pop = 30; ov = '' })
}
$tv = @{ 'office' = @(@{ id = 2316; name = 'The Office'; date = '2005-03-24'; pop = 40 }, @{ id = 2996; name = 'The Office'; date = '2001-07-09'; pop = 10 }) }
function PR-TmdbGet($db, [string]$path, $params) {
    if ($path -eq '/search/movie') {
        $list = @($films[([string]$params.query).ToLowerInvariant()])
        if ($params.primary_release_year) { $list = @($list | Where-Object { $_ -and $_.date.StartsWith([string]$params.primary_release_year) }) }
        return [pscustomobject]@{ results = @($list | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ id = $_.id; title = $_.title; original_title = $_.title; release_date = $_.date; popularity = $_.pop; overview = $_.ov } }) }
    }
    if ($path -eq '/search/tv') {
        $list = @($tv[([string]$params.query).ToLowerInvariant()])
        if ($params.first_air_date_year) { $list = @($list | Where-Object { $_ -and $_.date.StartsWith([string]$params.first_air_date_year) }) }
        return [pscustomobject]@{ results = @($list | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ id = $_.id; name = $_.name; original_name = $_.name; first_air_date = $_.date; popularity = $_.pop } }) }
    }
    if ($path -match '^/tv/(\d+)/season/(\d+)$') {
        $eps = if ($Matches[1] -eq '2996') { @([pscustomobject]@{ episode_number = 1; name = 'Downsize' }, [pscustomobject]@{ episode_number = 2; name = 'Work Experience' }) } else { @([pscustomobject]@{ episode_number = 1; name = 'Pilot' }, [pscustomobject]@{ episode_number = 2; name = 'Diversity Day' }) }
        return [pscustomobject]@{ episodes = $eps }
    }
    return [pscustomobject]@{ results = @(); episodes = @() }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ("pracc_" + [guid]::NewGuid().ToString('N').Substring(0, 6))
$M = Join-Path $root 'Movies'; $S = Join-Path $root 'Series'
foreach ($d in $M, (Join-Path $S 'The Office\Season 1')) { [void][IO.Directory]::CreateDirectory($d) }
$files = @((Join-Path $M 'Brewsters Millions.avi'), (Join-Path $M 'Brewsters Millions.en.srt'), (Join-Path $M 'Gattaca.avi'), (Join-Path $M 'Heat (1995)\Heat (1995).mkv'),
           (Join-Path $S 'The Office\Season 1\Office S01E01.mkv'), (Join-Path $S 'The Office\Season 1\Office S01E02.mkv'))
foreach ($f in $files) { [void][IO.Directory]::CreateDirectory((Split-Path $f)); 'x' | Set-Content -LiteralPath $f }
$films['heat'] = @(@{ id = 949; title = 'Heat'; date = '1995-12-15'; pop = 30; ov = '' })
$db = New-PRTmdb -Key 'x' -CachePath (Join-Path $root 'c.json') -Source 'TMDB only'
function Row($rows, $leaf) { $rows | Where-Object { (PR-Base $_.old_path) -eq $leaf } }
$rows = New-PRPlan -Paths $files -MoviesRoot $M -SeriesRoot $S -Db $db -ProbeReal $false -FolderLoose $true

$bm = Row $rows 'Brewsters Millions.avi'; $ga = Row $rows 'Gattaca.avi'; $e1 = Row $rows 'Office S01E01.mkv'; $e2 = Row $rows 'Office S01E02.mkv'
Check ($bm.confidence -eq 'low' -and $bm.accepted -eq '') "after a scan a low-confidence movie is not accepted"
Check (Test-PRReviewable $bm) "low-confidence movie is listed for review"
Check (-not (Test-PRReviewable (Row $rows 'Heat (1995).mkv'))) "high-confidence movie is not listed for review"
Check (-not (Test-PRReviewable (Row $rows 'Brewsters Millions.en.srt'))) "subtitle rows are not listed separately"
Check ((Row $rows 'Brewsters Millions.en.srt').group_key -eq $bm.group_key) "subtitle belongs to its movie's group"
Check ($e1.group_key -eq $e2.group_key -and $e1.group_key -like 'show|*') "episodes of one show share one group"
$named = [pscustomobject]@{ old_path = 'X:\M\5050 (2011)\5050 (2011) - 720p.mp4'; new_path = ''; media_type = 'movie'; tmdb_id = '40807'; confidence = 'low'; note = 'already correctly named; skipped'; fold_path = ''; accepted = ''; group_key = 'movie|x'; query = '' }
$nomatch = [pscustomobject]@{ old_path = 'X:\M\Odd Thing.mkv'; new_path = ''; media_type = 'movie'; tmdb_id = ''; confidence = ''; note = 'unmatched: no TMDB movie for "Odd Thing" (None)'; fold_path = ''; accepted = ''; group_key = 'movie|y'; query = 'Odd Thing|' }
Check (-not (Test-PRReviewable $named)) "already-named low-confidence file is not listed for review"
Check (Test-PRReviewable $nomatch) "unmatched movie is listed for review (Choose match)"
$rc = Get-PRReviewCounts (@($rows) + @($named, $nomatch))
Check ($rc.Low -eq 3 -and $rc.NoMatch -eq 1 -and $rc.Total -eq 4) "review count: 3 low-confidence (show counted once), 1 with no match [$($rc.Low)/$($rc.NoMatch)]"
Check ((Get-PRSummary (@($rows) + @($named, $nomatch))) -like '*4 movie(s)/show(s) to review (3 low-confidence matches, 1 with no match)*') "summary line uses the same review counts"

$c0 = Get-PRRunCounts $rows $true
Check ($e1.confidence -eq 'low' -and (Test-PRReviewable $e1)) "low-confidence show is listed for review"
Check ($c0.High -eq 0 -and $c0.Accepted -eq 0 -and $c0.Folder -eq 3) "counts before accepting: 0 high, 0 accepted, 3 folder-only [$($c0.High)/$($c0.Accepted)/$($c0.Folder)]"

$all = @($rows) + @($nomatch)
$keys = @($all | Where-Object { Test-PRReviewable $_ } | ForEach-Object { $_.group_key })
$b1 = Set-PRAcceptedBulk $all $keys $true
Check ($b1.Accepted -eq 3 -and $b1.Skipped -eq 1) "Accept all: 3 accepted (2 movies + 1 show), 1 skipped (no match) [$($b1.Accepted)/$($b1.Skipped)]"
Check (@($rows | Where-Object { $_.accepted -eq 'yes' }).Count -eq 5) "subtitle and both episodes follow"
$cb = Get-PRRunCounts $rows $true
Check ($cb.Accepted -eq 5 -and $cb.Folder -eq 0) "Full Run counts: 5 accepted, 0 folder-only [$($cb.Accepted)/$($cb.Folder)]"
$b2 = Set-PRAcceptedBulk $all $keys $false
$cc = Get-PRRunCounts $rows $true
Check ($b2.Accepted -eq 3 -and @($rows | Where-Object { $_.accepted -eq 'yes' }).Count -eq 0 -and $cc.Accepted -eq 0 -and $cc.Folder -eq 3) "Clear accepts unticks everything; counts back to 0 accepted, 3 folder-only"
$b3 = Set-PRAcceptedBulk $all @($bm.group_key) $true; [void](Set-PRAcceptedBulk $all @($bm.group_key) $false)
Check ($b3.Accepted -eq 1 -and $b3.Skipped -eq 0) "Accept all only touches the groups in the current view"
# Setup option "Full Run applies only ticked rows"
$hrow = [pscustomobject]@{ old_path = 'X:\M\a.mkv'; new_path = 'X:\M\A (2000)\A (2000).mkv'; media_type = 'movie'; confidence = 'high'; note = ''; fold_path = ''; accepted = ''; group_key = 'movie|h' }
Check ((Test-PRTickable $hrow) -and (PR-ApplyTarget $hrow $true)) "default: high rows are tickable and Full Run applies them ticked or not"
$hrow.accepted = 'yes'; $hc = Get-PRRunCounts @($hrow) $true
Check ($hc.High -eq 1 -and $hc.Accepted -eq 0) "default: a ticked high row still counts as high, not as accepted"; $hrow.accepted = ''
Check (-not (Test-PRTickable $named)) "already-named row stays untickable"
$cr = [pscustomobject]@{ old_path = 'X:\M\a b (2000)\A B (2000).mkv'; new_path = 'X:\M\A B (2000)\A B (2000).mkv'; media_type = 'movie'; confidence = 'high'; note = ''; fold_path = ''; accepted = ''; group_key = 'movie|c' }
Check (Test-PRTickable $cr) "folder-case row is tickable"
$script:PR_ONLY_TICKED = $true
Check ((Test-PRTickable $hrow) -and -not (PR-ApplyTarget $hrow $true)) "only-ticked: high row is tickable and is skipped until ticked"
Check ((Get-PRRunCounts $rows $true).Total -eq 0) "only-ticked: nothing ticked, nothing applied"
$v1 = Set-PRAcceptedBulk $all @($ga.group_key) $true; $k1 = Get-PRRunCounts $rows $true
Check ($v1.Accepted -eq 1 -and $k1.Total -eq 1 -and $k1.Accepted -eq 1 -and (PR-ApplyTarget $ga $true) -eq $ga.new_path) "only-ticked: Accept all on a view ticks just that view; ticked low row gets the full rename"
[void](Set-PRAcceptedBulk $all @($ga.group_key) $false); $script:PR_ONLY_TICKED = $false
$cands = @(Get-PRCandidates $db 'movie' 'Brewsters Millions' $null)
Check ($cands.Count -eq 2 -and @($cands | Where-Object { [int]$_.Year -eq 1945 }).Count -eq 1) "several candidates are offered (1985 and 1945) [n=$($cands.Count)]"
Check (($cands | Where-Object { $_.Id -eq 11 }).Overview -like 'A minor-league*') "candidate shows a short overview"
$pick = @($cands | Where-Object { [int]$_.Year -eq 1945 })[0]
$rows = Update-PRPlanGroup $rows $bm.group_key $pick $db $M $S $false $true
$bm = Row $rows 'Brewsters Millions.avi'; $bs = Row $rows 'Brewsters Millions.en.srt'
Check ($bm.new_path -eq (PR-Join $M "Brewster's Millions (1945)" "Brewster's Millions (1945).avi") -and $bm.accepted -eq 'yes') "chosen match recalculates the target and is accepted"
Check ($bs.new_path -eq (PR-Join $M "Brewster's Millions (1945)" "Brewster's Millions (1945).en.srt") -and $bs.accepted -eq 'yes') "its subtitle follows the chosen match"
Check (@($rows).Count -eq $files.Count -and (PR-Base $rows[0].old_path) -ne '') "the rest of the plan is kept"

[void](Set-PRAccepted $rows $bm.group_key $false); Check ((Row $rows 'Brewsters Millions.avi').accepted -eq '' -and (Row $rows 'Brewsters Millions.en.srt').accepted -eq '') "un-ticking clears the whole movie group"
[void](Set-PRAccepted $rows $bm.group_key $true)

$sc = @(Get-PRCandidates $db 'show' 'Office' $null)
Check ($sc.Count -eq 2) "show offers both candidates [n=$($sc.Count)]"
$rows = Update-PRPlanGroup $rows $e1.group_key (@($sc | Where-Object { [int]$_.Id -eq 2996 })[0]) $db $M $S $false $true
$e1 = Row $rows 'Office S01E01.mkv'; $e2 = Row $rows 'Office S01E02.mkv'
Check ($e1.new_path -eq (PR-Join $S 'The Office (2001)' 'Season 01' 'The Office (2001) - S01E01 - Downsize.mkv') -and $e2.new_path -like '*S01E02 - Work Experience.mkv') "chosen show applies to every episode"
Check ($e1.accepted -eq 'yes' -and $e2.accepted -eq 'yes') "every episode of the show is accepted"

$c1 = Get-PRRunCounts $rows $true
Check ($c1.Accepted -eq 4 -and $c1.Folder -eq 1 -and $c1.High -eq 0) "counts after accepting: Gattaca still folder-only ($($c1.High) high, $($c1.Accepted) accepted, $($c1.Folder) folder)"
$planCsv = Join-Path $root 'plan.csv'; Export-PRPlan $rows $planCsv
$pc = @(Import-Csv -LiteralPath $planCsv); Check (($pc[0].PSObject.Properties.Name -contains 'accepted') -and @($pc | Where-Object { $_.accepted -eq 'yes' }).Count -ge 4) "plan CSV records the accepts"

$undo = Join-Path $root 'undo.csv'
$r = Invoke-PRApply -Rows $rows -HighOnly -UndoLog $undo
Check ($r.Failed -eq 0 -and $r.Moved -eq $c1.Total) "Full Run moved every counted file ($($r.Moved))"
Check ([IO.File]::Exists((PR-Join $M "Brewster's Millions (1945)" "Brewster's Millions (1945).avi"))) "accepted movie renamed"
Check ([IO.File]::Exists((PR-Join $M 'Gattaca (1997)' 'Gattaca.avi'))) "not-accepted low movie only foldered"
Check ([IO.File]::Exists((PR-Join $S 'The Office (2001)' 'Season 01' 'The Office (2001) - S01E02 - Work Experience.mkv'))) "accepted show renamed"
$ul = @(Import-Csv -LiteralPath $undo)
Check (@($ul | Where-Object { $_.how -eq 'accepted' }).Count -ge 4 -and @($ul | Where-Object { $_.how -eq 'folder-only' }).Count -eq 1) "undo CSV records accepted and folder-only moves"
$u = Invoke-PRUndo -UndoLog $undo
Check (@($files | Where-Object { [IO.File]::Exists($_) }).Count -eq $files.Count) "undo puts every file back"
Remove-Item -LiteralPath $root -Recurse -Force
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASS' }
