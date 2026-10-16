# Creates a fake library in a temp folder, applies a hand-made plan, checks results, then undoes it.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Renamr.Engine.ps1')
$root = Join-Path ([IO.Path]::GetTempPath()) ("prtest_" + [guid]::NewGuid().ToString('N').Substring(0, 6))
function JP { $p = $root; foreach ($x in $args) { $p = [IO.Path]::Combine($p, [string]$x) }; return $p }
foreach ($d in (JP 'Movies'), (JP 'Series' 'Colony' 'S01'), (JP 'Movies' 'Exists (2000)')) { [void][IO.Directory]::CreateDirectory($d) }
'a'   | Set-Content -LiteralPath (JP 'Movies' 'Baby Driver.mp4')
'a'   | Set-Content -LiteralPath (JP 'Movies' 'Baby Driver.srt')
'b'   | Set-Content -LiteralPath (JP 'Movies' 'Odd [2016] name.mkv')
'c'   | Set-Content -LiteralPath (JP 'Movies' 'exists.mkv')
'old' | Set-Content -LiteralPath (JP 'Movies' 'Exists (2000)' 'Exists (2000).mkv')
'd'   | Set-Content -LiteralPath (JP 'Series' 'Colony' 'S01' 'Colony.S01E05.mkv')
$tsOld = [DateTime]::SpecifyKind([DateTime]'2015-03-04 05:06:07', 'Utc'); $tsCre = [DateTime]::SpecifyKind([DateTime]'2014-01-02 03:04:05', 'Utc')
foreach ($f in (JP 'Series' 'Colony' 'S01' 'Colony.S01E05.mkv'), (JP 'Movies' 'Odd [2016] name.mkv')) { [IO.File]::SetCreationTimeUtc($f, $tsCre); [IO.File]::SetLastWriteTimeUtc($f, $tsOld) }
function MkRow($o, $n, $c = 'high') { [pscustomobject]@{ old_path = $o; new_path = $n; media_type = 'movie'; tmdb_id = '1'; confidence = $c; note = '' } }
$rows = @(
  (MkRow (JP 'Movies' 'Baby Driver.mp4') (JP 'Movies' 'Baby Driver (2017)' 'Baby Driver (2017).mp4') 'low'),
  (MkRow (JP 'Movies' 'Baby Driver.srt') (JP 'Movies' 'Baby Driver (2017)' 'Baby Driver (2017).srt') 'low'),
  (MkRow (JP 'Movies' 'Odd [2016] name.mkv') (JP 'Movies' 'Odd [x] (2016)' 'Odd [x] (2016).mkv')),
  (MkRow (JP 'Movies' 'exists.mkv') (JP 'Movies' 'Exists (2000)' 'Exists (2000).mkv')),
  (MkRow (JP 'Movies' 'missing.mkv') (JP 'Movies' 'Missing (2001)' 'Missing (2001).mkv')),
  (MkRow (JP 'Series' 'Colony' 'S01' 'Colony.S01E05.mkv') (JP 'Series' 'Colony (2016)' 'Season 01' 'Colony (2016) - S01E05 - Geronimo.mkv')),
  (MkRow (JP 'Movies' 'unmatched.mkv') '')
)
$fail = 0
function Check($cond, $msg) { if ($cond) { Write-Host "PASS $msg" } else { Write-Host "FAIL $msg"; $script:fail++ } }
$log1 = JP 'undo_high.csv'
$r1 = Invoke-PRApply -Rows $rows -HighOnly -UndoLog $log1
Check ($r1.Moved -eq 2 -and $r1.Skipped -eq 2) "HighOnly: moved 2, skipped 2 (existing target, missing source)"
Check ([IO.File]::Exists((JP 'Movies' 'Baby Driver.mp4'))) "low-confidence row untouched with -HighOnly"
Check ((Get-Content -LiteralPath (JP 'Movies' 'Exists (2000)' 'Exists (2000).mkv')) -eq 'old') "existing target not overwritten"
Check ([IO.File]::Exists((JP 'Movies' 'Odd [x] (2016)' 'Odd [x] (2016).mkv'))) "bracket names moved"
$nf = JP 'Movies' 'Odd [x] (2016)' 'Odd [x] (2016).mkv'
Check ([IO.File]::GetLastWriteTimeUtc($nf) -eq $tsOld -and [IO.File]::GetCreationTimeUtc($nf) -eq $tsCre) "rename keeps the file's modified and created times"
$log2 = JP 'undo_all.csv'
$r2 = Invoke-PRApply -Rows $rows -UndoLog $log2
Check ($r2.Moved -eq 2) "second full run moved the remaining 2 low rows"
$u2 = Invoke-PRUndo -UndoLog $log2
$u1 = Invoke-PRUndo -UndoLog $log1
$cf = JP 'Series' 'Colony' 'S01' 'Colony.S01E05.mkv'
Check ([IO.File]::GetLastWriteTimeUtc($cf) -eq $tsOld -and [IO.File]::GetCreationTimeUtc($cf) -eq $tsCre) "times still the original after rename and undo"
Check ($u1.Restored -eq 2 -and $u2.Restored -eq 2) "undo restored 4 files"
Check (-not [IO.Directory]::Exists((JP 'Series' 'Colony (2016)'))) "undo removed created show folder"
Check (-not [IO.Directory]::Exists((JP 'Movies' 'Baby Driver (2017)'))) "undo removed created movie folder"
Check ([IO.Directory]::Exists((JP 'Movies' 'Exists (2000)'))) "undo kept pre-existing folder"
$back = @((JP 'Movies' 'Baby Driver.mp4'), (JP 'Movies' 'Baby Driver.srt'), (JP 'Movies' 'Odd [2016] name.mkv'), (JP 'Movies' 'exists.mkv'), (JP 'Series' 'Colony' 'S01' 'Colony.S01E05.mkv'))
Check (@($back | Where-Object { -not [IO.File]::Exists($_) }).Count -eq 0) "all originals back in place"
# Stop button: a run that is stopped moves nothing further and reports Cancelled
$script:PRSync = [pscustomobject]@{ Cancel = $true; Phase = ''; Done = 0; Total = 0; Log = (New-Object System.Collections.Concurrent.ConcurrentQueue[string]) }
'x' | Set-Content -LiteralPath (JP 'Movies' 'stopme.mkv')
$rs = Invoke-PRApply -Rows @((MkRow (JP 'Movies' 'stopme.mkv') (JP 'Movies' 'Stop Me (2001)' 'Stop Me (2001).mkv'))) -UndoLog (JP 'undo_stop.csv')
Check ($rs.Cancelled -eq $true -and $rs.Moved -eq 0 -and [IO.File]::Exists((JP 'Movies' 'stopme.mkv'))) "stopped run moves nothing and reports Cancelled"
$script:PRSync = $null
Remove-Item -LiteralPath $root -Recurse -Force
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASSED' }
