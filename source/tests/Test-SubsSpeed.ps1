# Sidecar matching speed-up: the prebuilt title index must give exactly the same matches as the plain scan.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
function V($old, $new = '') { [pscustomobject]@{ old_path = $old; new_path = $new; media_type = 'movie' } }
$vids = @((V 'M:\a\Heat (1995).mkv'), (V 'M:\b\Heat (2013).mkv'), (V 'M:\c\heat.mkv' 'M:\Heat (1986)\Heat (1986).mkv'), (V 'M:\d\Dune (2021).mkv'),
          (V 'M:\e\Dune.1984.mkv'), (V 'M:\f\Solo (2018).mkv'), (V 'M:\g\Quiet Part II (2021).mkv'), (V 'M:\h\Alien (1979).mkv'), (V 'M:\h\ALIEN (1979).mkv'))
$ix = PR-TitleIndex $vids
$probes = 'Heat 1995', 'Heat 2013', 'Heat 1986', 'Heat', 'Dune 2021', 'Dune 1984', 'Dune 2000', 'Solo', 'Solo 2017', 'Quiet Part II 2021', 'Quiet Part 2 2021', 'Alien 1979', 'Nothing 1999', 'alien'
foreach ($q in $probes) {
    $sp = PR-ParseMovie $q
    $a = PR-TitleMatch $sp $vids; $b = PR-TitleMatch $sp $vids $ix
    $sa = if ($a) { "$($a.V.old_path)|$($a.Year)" } else { 'none' }; $sb = if ($b) { "$($b.V.old_path)|$($b.Year)" } else { 'none' }
    Check ($sa -ceq $sb) "indexed title match same as plain scan for '$q' ($sa)"
}
$sp = PR-ParseMovie 'Heat 1995'; $script:PR_TK_CACHE.Clear()
$r1 = PR-TitleMatch $sp $vids; $r2 = PR-TitleMatch $sp $vids
Check ($r1.V.old_path -eq $r2.V.old_path -and $script:PR_TK_CACHE.Count -eq $vids.Count) "cached names give the same result on a second call"
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASS' }
