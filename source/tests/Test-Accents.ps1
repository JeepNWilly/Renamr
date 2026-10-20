# Accent-only twins (TMDB has both 'Redemption' 2013 and 'Rédemption' 2013): each file keeps the film with its own spelling, so scans do not swap them back and forth.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
$acc = 'R' + [char]0xE9 + 'demption'
$script:order = 0
function PR-TmdbGet($db, [string]$path, $params) {
    if ($path -eq '/search/movie') {
        $a = [pscustomobject]@{ id = 158394; title = 'Redemption'; original_title = 'Redemption'; release_date = '2013-05-09'; popularity = $(if ($script:order) { 1 } else { 40 }) }
        $b = [pscustomobject]@{ id = 271779; title = $acc; original_title = $acc; release_date = '2013-10-02'; popularity = $(if ($script:order) { 40 } else { 1 }) }
        return [pscustomobject]@{ results = @($(if ($script:order) { $b, $a } else { $a, $b })) }
    }
    if ($path -eq '/search/tv') {
        $a = [pscustomobject]@{ id = 1; name = 'Elite'; original_name = 'Elite'; first_air_date = '2018-01-01'; popularity = $(if ($script:order) { 1 } else { 40 }) }
        $b = [pscustomobject]@{ id = 2; name = ([string][char]0xC9 + 'lite'); original_name = ([string][char]0xC9 + 'lite'); first_air_date = '2018-03-01'; popularity = $(if ($script:order) { 40 } else { 1 }) }
        return [pscustomobject]@{ results = @($(if ($script:order) { $b, $a } else { $a, $b })) }
    }
    return [pscustomobject]@{ results = @(); episodes = @() }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ("pracc_" + [guid]::NewGuid().ToString('N').Substring(0, 6)); [void][IO.Directory]::CreateDirectory($root)
$db = New-PRTmdb -Key 'x' -CachePath (Join-Path $root 'c.json') -Source 'TMDB only'
foreach ($o in 0, 1) {
    $script:order = $o; $db = New-PRTmdb -Key 'x' -CachePath (Join-Path $root "c$o.json") -Source 'TMDB only'
    $m1 = PR-MatchMovieOne $db 'tmdb' $acc 2013; $m2 = PR-MatchMovieOne $db 'tmdb' 'Redemption' 2013
    Check ([string]$m1.Id -eq '271779') "accented file name keeps the accented film (popularity order $o)"
    Check ([string]$m2.Id -eq '158394') "plain file name keeps the plain film (popularity order $o)"
    $t1 = PR-MatchShowOne $db 'tmdb' ([string][char]0xC9 + 'lite') 2018; $t2 = PR-MatchShowOne $db 'tmdb' 'Elite' 2018
    Check ([string]$t1.Id -eq '2' -and [string]$t2.Id -eq '1') "series: each spelling keeps its own show (order $o)"
    Check ((PR-Sim $acc 'Redemption') -eq 1) "similarity still ignores accents (order $o)"
}
Check (PR-SameSpelling $acc ('r' + [char]0x65 + [char]0x301 + 'demption')) "same spelling: composed and decomposed accents are equal"
Check (-not (PR-SameSpelling $acc 'Redemption')) "same spelling: accent counts"
Check (PR-SameSpelling 'Heat.' 'heat') "same spelling: case and punctuation ignored"
Remove-Item -LiteralPath $root -Recurse -Force
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASS' }
