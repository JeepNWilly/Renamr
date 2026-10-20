# Offline test: the grid's one-pass row helpers (Get-PRRowState, Get-RowCells) give exactly the same answers as the per-question functions.
$ErrorActionPreference = 'Stop'
$src = Split-Path -Parent $PSScriptRoot
. (Join-Path $src 'Renamr.Engine.ps1')
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
# the GUI helpers, taken from Renamr.Gui.ps1 without starting the window
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $src 'Renamr.Gui.ps1'), [ref]$null, [ref]$null)
foreach ($fd in $ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -in 'Get-RowCells', 'Get-Status', 'Get-RowNote', 'Leaf' }, $false)) { . ([scriptblock]::Create($fd.Extent.Text)) }
Check ([bool](Get-Command Get-RowCells -ErrorAction SilentlyContinue)) 'Get-RowCells found in the GUI'
$notes = @('matched tmdb', 'nfo: delete (Recycle Bin)', 'DUPLICATE sidecar target: will be recycled', 'DUPLICATE sidecar target', 'COLLISION with x', 'season folder: Season 1', 'already correctly named', 'MULTIPLE VERSIONS of x', 'unmatched: no result', '')
$rows = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($n in $notes) { foreach ($mt in 'movie', 'sidecar', 'season folder') { foreach ($np in '', 'X:\M\A (2000)\A (2000).mkv', 'x:\m\a (2000)\A (2000).mkv') { foreach ($c in 'high', 'low') { foreach ($sk in $null, '', 'yes') { foreach ($ac in $null, '', 'yes') {
    $i++; $r = [pscustomobject]@{ old_path = 'X:\M\A (2000)\A (2000).mkv'; new_path = $np; confidence = $c; media_type = $mt; note = $n; group_key = $(if ($i % 3) { "movie|$i" } else { '' }) }
    if ($i % 2) { $r.old_path = 'X:\M\old\a.mkv' }
    if ($null -ne $sk) { Add-Member -InputObject $r -NotePropertyName skip -NotePropertyValue $sk }
    if ($null -ne $ac) { Add-Member -InputObject $r -NotePropertyName accepted -NotePropertyValue $ac }
    if ($i % 4 -eq 0) { Add-Member -InputObject $r -NotePropertyName dup_of -NotePropertyValue 'X:\M\keep.srt' }
    if ($i % 5 -eq 0) { Add-Member -InputObject $r -NotePropertyName fold_path -NotePropertyValue 'X:\M\A (2000)' }
    $rows.Add($r) } } } } } }
$bad1 = 0; $bad2 = 0; $cases = 0
foreach ($opt in 0, 3, 7, 8, 12, 15) {
    $script:PR_DELETE_NFO = [bool]($opt -band 1); $script:PR_RECYCLE_DUPSUBS = [bool]($opt -band 2); $script:PR_SEASON_FIX = [bool]($opt -band 4); $script:PR_ONLY_TICKED = [bool]($opt -band 8)
    foreach ($hi in $true, $false) { foreach ($r in $rows) {
        $cases++
        $s4 = Get-PRRowState $r $hi
        if ($s4[0] -cne (Get-PRActKind $r) -or $s4[1] -cne (Get-PROptionOff $r) -or $s4[2] -ne (Test-PRWillAct $r $hi) -or $s4[3] -ne [bool](Test-PRSkipped $r)) { $bad1++ }
        $rc = Get-RowCells $r $hi
        if ($rc[0] -ne (Test-PRWillAct $r $hi) -or $rc[1] -cne (Get-Status $r) -or $rc[2] -cne (Get-RowNote $r) -or $rc[3] -ne [bool](Test-PRReviewable $r) -or $rc[4] -ne [bool]((Get-PRActKind $r) -and -not (Get-PROptionOff $r))) { $bad2++ }
    } }
}
Check ($bad1 -eq 0) "Get-PRRowState matches Get-PRActKind / Get-PROptionOff / Test-PRWillAct / Test-PRSkipped ($cases cases, $bad1 differ)"
Check ($bad2 -eq 0) "Get-RowCells matches Get-Status / Get-RowNote / Test-PRWillAct / Test-PRReviewable ($cases cases, $bad2 differ)"
if ($fail -eq 0) { Write-Host 'ALL PASS' } else { Write-Host "$fail FAILED"; exit 1 }
