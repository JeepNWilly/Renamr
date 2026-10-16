<#
.SYNOPSIS  Reverse moves recorded by apply.ps1. Dry run unless -Apply.
.EXAMPLE   .\undo.ps1 -Log .\undo_20261013_183000.csv -Apply
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Log, [switch]$Apply)
$ErrorActionPreference = 'Stop'
$rows = @(Import-Csv -LiteralPath $Log -Encoding UTF8)
[array]::Reverse($rows)   # undo in reverse order
$ok = 0; $skip = 0
foreach ($r in $rows) {
    if (-not (Test-Path -LiteralPath $r.new_path -PathType Leaf)) { Write-Warning "SKIP not found: $($r.new_path)"; $skip++; continue }
    if ((Test-Path -LiteralPath $r.old_path) -and ($r.old_path -ine $r.new_path)) { Write-Warning "SKIP original path occupied: $($r.old_path)"; $skip++; continue }
    if (-not $Apply) { Write-Host "$($r.new_path)`n   -> $($r.old_path)"; continue }
    $dir = [System.IO.Path]::GetDirectoryName($r.old_path)
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Move-Item -LiteralPath $r.new_path -Destination $r.old_path
    $ok++
    # remove folders apply.ps1 created (walk up from the file's folder to created_dir), only while empty
    if ($r.created_dir) {
        $p = [System.IO.Path]::GetDirectoryName($r.new_path)
        while ($p -and $p.StartsWith($r.created_dir, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $p) -and -not (Get-ChildItem -LiteralPath $p -Force | Select-Object -First 1)) {
            Remove-Item -LiteralPath $p; $p = [System.IO.Path]::GetDirectoryName($p)
        }
    }
}
Write-Host ("{0}: restored {1}, skipped {2}" -f ($(if ($Apply) {'APPLY'} else {'DRY RUN'})), $ok, $skip)
