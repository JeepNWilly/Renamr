# Offline tests for movie file-name parsing (no network). Run: powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Parse.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$fail = 0
function Chk($name, $title, $year) {
    $r = PR-ParseMovie $name
    if ($r.Title -eq $title -and $r.Year -eq $year) { Write-Host "PASS $name -> $($r.Title) ($($r.Year))" } else { Write-Host "FAIL $name -> [$($r.Title)] [$($r.Year)] expected [$title] [$year]"; $script:fail++ }
}
Chk 'The Punisher - Extended Edition (2004) 720p AAC' 'The Punisher' 2004
Chk 'The Punisher - Uncut (1989) 720p AAC' 'The Punisher' 1989
Chk 'Total Recall - Extended Edition (2012) 1080p AAC' 'Total Recall' 2012
Chk 'Total Recall - Remastered (1990) 1080p AAC' 'Total Recall' 1990
Chk 'Ghost.in.the.Shell.1995.1080p.BluRay' 'Ghost in the Shell' 1995
Chk 'Dune.Extended.2021.2160p' 'Dune' 2021
Chk 'Gladiator.2000.EXTENDED.1080p' 'Gladiator' 2000
Chk 'Kingsman The Golden Circle 2017 Extended 1080p' 'Kingsman The Golden Circle' 2017
Chk 'Blade Runner 2049 (2017) 1080p' 'Blade Runner 2049' 2017
Chk '1917 (2019) 1080p' '1917' 2019
Chk 'Heat' 'Heat' $null
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASSED' }
