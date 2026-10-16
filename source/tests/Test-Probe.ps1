# Tests PR-ProbeRes against real files given in -Files (or any mkv/mp4 under -Folder); prints width-derived label. Synthetic MP4 test always runs.
param([string[]]$Files = @(), [string]$Folder = '')
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
# synthetic MP4: ftyp + moov{trak{tkhd(1280x536), mdia{hdlr vide}}}
function Box($type, [byte[]]$payload) { $len = 8 + $payload.Length; $b = New-Object System.Collections.Generic.List[byte]; $b.AddRange([byte[]]([BitConverter]::GetBytes([uint32]$len)[3..0])); $b.AddRange([Text.Encoding]::ASCII.GetBytes($type)); $b.AddRange($payload); return ,$b.ToArray() }
$tk = New-Object byte[] 84; $w = [byte[]]([BitConverter]::GetBytes([uint32](1280 -shl 16))[3..0]); $h = [byte[]]([BitConverter]::GetBytes([uint32](536 -shl 16))[3..0]); [Array]::Copy($w, 0, $tk, 76, 4); [Array]::Copy($h, 0, $tk, 80, 4)
$hd = New-Object byte[] 20; [Array]::Copy([Text.Encoding]::ASCII.GetBytes('vide'), 0, $hd, 8, 4)
function ConcatB($a, $b) { $l = New-Object System.Collections.Generic.List[byte]; $l.AddRange([byte[]]$a); $l.AddRange([byte[]]$b); return ,$l.ToArray() }
$trak = Box 'trak' (ConcatB (Box 'tkhd' $tk) (Box 'mdia' (Box 'hdlr' $hd)))
$file = New-Object System.Collections.Generic.List[byte]
$file.AddRange([byte[]](Box 'ftyp' ([Text.Encoding]::ASCII.GetBytes('isom0000')))); $file.AddRange([byte[]](Box 'mdat' (New-Object byte[] 100))); $file.AddRange([byte[]](Box 'moov' $trak))
$tmp = Join-Path ([IO.Path]::GetTempPath()) 'probe_test.mp4'; [IO.File]::WriteAllBytes($tmp, $file.ToArray())
$r = PR-ProbeRes $tmp; Check ($r -and $r.Label -eq '720p' -and $r.Rank -eq 4) "synthetic mp4 1280x536 -> 720p (moov after mdat) got '$($r.Label)'"
Remove-Item $tmp -ErrorAction SilentlyContinue
Check ($null -eq (PR-ProbeRes 'C:\nonexistent\x.mkv')) 'missing file -> null'
if ($Folder) { $Files += @(Get-ChildItem -LiteralPath $Folder -Recurse -Include *.mkv, *.mp4 | Select-Object -First 8 | ForEach-Object { $_.FullName }) }
foreach ($f in $Files) { $sw = [Diagnostics.Stopwatch]::StartNew(); $x = PR-ProbeRes $f; Write-Host ("  {0} -> {1} ({2} ms)" -f $f, $(if ($x) { $x.Label } else { '(unknown)' }), $sw.ElapsedMilliseconds) }
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASSED' }
