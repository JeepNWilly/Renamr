<#
.SYNOPSIS  Apply a Plex rename plan (plan.csv from plan.py). Dry run unless -Apply.
.EXAMPLE   .\apply.ps1 -Plan .\plan.csv                 # preview only
.EXAMPLE   .\apply.ps1 -Plan .\plan.csv -Apply -HighOnly  # move only high-confidence rows
Windows PowerShell 5.1 compatible. Uses -LiteralPath everywhere (safe for [brackets], UNC and drive paths).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Plan,
    [switch]$Apply,
    [switch]$HighOnly,
    [string]$UndoLog = (Join-Path (Get-Location) ("undo_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss')))
)
$ErrorActionPreference = 'Stop'
$rows = Import-Csv -LiteralPath $Plan -Encoding UTF8
$log = New-Object System.Collections.Generic.List[object]
$moved = 0; $skipped = 0; $failed = 0
$mode = if ($Apply) { 'APPLY' } else { 'DRY RUN' }
Write-Host "[$mode] $($rows.Count) rows in $Plan" -ForegroundColor Cyan

foreach ($r in $rows) {
    $old = $r.old_path; $new = $r.new_path
    if ([string]::IsNullOrWhiteSpace($new)) { $skipped++; continue }
    if ($HighOnly -and $r.confidence -ne 'high') { Write-Host "SKIP (low confidence) $old"; $skipped++; continue }
    if (-not (Test-Path -LiteralPath $old -PathType Leaf)) { Write-Warning "SKIP missing source: $old"; $skipped++; continue }
    $caseOnly = ($old -ieq $new)
    if ((Test-Path -LiteralPath $new) -and -not $caseOnly) { Write-Warning "SKIP target exists: $new"; $skipped++; continue }
    if (-not $Apply) { Write-Host "$old`n   -> $new"; continue }
    try {
        $dir = [System.IO.Path]::GetDirectoryName($new)
        $created = ''
        if (-not (Test-Path -LiteralPath $dir)) {
            # remember the top-most folder we create so undo can remove it if it ends up empty
            $created = $dir; $up = [System.IO.Path]::GetDirectoryName($dir)
            while ($up -and -not (Test-Path -LiteralPath $up)) { $created = $up; $up = [System.IO.Path]::GetDirectoryName($up) }
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        if ($caseOnly) {   # case-only rename needs a temp hop on SMB/NTFS
            $tmp = $new + '.renametmp'
            Move-Item -LiteralPath $old -Destination $tmp
            Move-Item -LiteralPath $tmp -Destination $new
        } else {
            Move-Item -LiteralPath $old -Destination $new
        }
        $log.Add([pscustomobject]@{ moved_at = (Get-Date -Format s); old_path = $old; new_path = $new; created_dir = $created })
        $moved++
        # write log incrementally so a crash still leaves a usable undo file
        $log | Export-Csv -LiteralPath $UndoLog -NoTypeInformation -Encoding UTF8
    } catch { Write-Warning "FAILED $old : $($_.Exception.Message)"; $failed++ }
}
if ($Apply) {
    Write-Host "Moved $moved, skipped $skipped, failed $failed. Undo log: $UndoLog" -ForegroundColor Green
} else {
    Write-Host "Dry run complete; skipped $skipped. Re-run with -Apply to move files." -ForegroundColor Yellow
}
