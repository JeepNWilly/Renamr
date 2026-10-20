# GUI test for the Get subtitles feature (Windows only). Builds a temp copy of the app (settings/cache/logs stay in the temp folder),
# appends a test driver in place of the final ShowDialog, and runs it in STA PowerShell. The main window flashes briefly.
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-GuiSubs.ps1          # UI state, layout, theme, settings
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-GuiSubs.ps1 -Live    # also runs the real worker: lookup + download of Alien (tmdb 348) into a temp folder
param([switch]$Live)
$ErrorActionPreference = 'Stop'
$src = Split-Path -Parent $PSScriptRoot
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("prgui_" + [guid]::NewGuid().ToString('N').Substring(0, 6))
[void][IO.Directory]::CreateDirectory($tmp)
Copy-Item -LiteralPath (Join-Path $src 'Renamr.Engine.ps1') -Destination $tmp
Copy-Item -LiteralPath (Join-Path $src 'Renamr.ico') -Destination $tmp -ErrorAction SilentlyContinue
$gui = [IO.File]::ReadAllText((Join-Path $src 'Renamr.Gui.ps1'))
$end = '[void]$form.ShowDialog()'
if (-not $gui.Contains($end)) { throw 'final ShowDialog line not found in the GUI source' }
$driver = @'
$global:T_fail = 0
function Chk($c, $m) { if ($c) { Write-Host "PASS $m" } else { Write-Host "FAIL $m"; $global:T_fail++ } }
function Pump([int]$ms) { $sw = [Diagnostics.Stopwatch]::StartNew(); while ($sw.ElapsedMilliseconds -lt $ms) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 } }
function Wait-For([scriptblock]$cond, [int]$sec) { $sw = [Diagnostics.Stopwatch]::StartNew(); while (-not (& $cond) -and $sw.Elapsed.TotalSeconds -lt $sec) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }; return [bool](& $cond) }
try {
    $form.StartPosition = 'Manual'; $form.Location = New-Object System.Drawing.Point(40, 40); $form.Show(); Pump 400
    Chk ($form.Text -like 'Renamr Plus v*') "window title ($($form.Text))"
    Chk (-not $chkSubs.Checked) 'subtitle checkbox is off by default'
    Chk (-not $btnSubs.Visible) 'Get subtitles button hidden by default'
    Chk ($chkSubStd.Checked -and $chkSubSdh.Checked) 'standard + SDH options default ON'
    Chk (-not $chkSubStd.Enabled -and -not $chkSubSdh.Enabled) 'sub-options disabled while the master checkbox is off'
    $baseRight = $txtSearch.Right; $baseFilterRight = $cmbFilter.Right
    # turn on
    $chkSubs.Checked = $true; Pump 200
    Chk ($btnSubs.Visible) 'button visible after ticking the Setup checkbox (live)'
    Chk ($chkSubStd.Enabled -and $chkSubSdh.Enabled) 'sub-options enabled when the master is on'
    Chk ($btnSubs.Text -eq 'Get subtitles...') 'button text'
    # layout: nothing in the button row overlaps
    $row = @($form.Controls | Where-Object { $_.Visible -and $_.Top -ge 105 -and $_.Top -le 125 })
    $bad = @()
    for ($i = 0; $i -lt $row.Count; $i++) { for ($j = $i + 1; $j -lt $row.Count; $j++) { if ($row[$i].Bounds.IntersectsWith($row[$j].Bounds)) { $bad += "$($row[$i].Text)|$($row[$i].Name) x $($row[$j].Text)|$($row[$j].Name)" } } }
    Chk ($bad.Count -eq 0) "no overlapping controls in the button row ($($bad -join '; '))"
    Chk ($btnSubs.Left -gt $btnDups.Right -and $btnSubs.Right -lt $lblShow.Left) 'button sits between Duplicates... and the Show filter'
    Chk ($btnSubs.Right -lt $lblShow.Left) 'Get subtitles button does not run into the Show filter'
    Chk ($lblSearch.Left -ge $chkHigh.Right -and $txtSearch.Left -gt $lblSearch.Right -and [math]::Abs($txtSearch.Top - $chkHigh.Top) -le 6) 'Search sits on the Name source row, right of Only high-confidence'
    Chk ($txtSearch.Right -lt $btnSetup.Left) 'Search box ends before the Setup button'
    Chk ($lblShow.Right -lt $cmbFilter.Left -and $cmbFilter.Right -eq $baseFilterRight -and $cmbFilter.Right -ge $form.ClientSize.Width - 30 -and ($cmbFilter.Anchor -band [Windows.Forms.AnchorStyles]::Right)) 'Show selector is right-justified and anchored right'
    # settings round trip
    $chkSubSdh.Checked = $false; Save-Settings
    $st2 = Load-Settings
    Chk ($st2.SubsEnable -eq $true -and $st2.SubsStd -eq $true -and $st2.SubsSdh -eq $false) 'settings saved and loaded (SubsEnable/SubsStd/SubsSdh)'
    $chkSubSdh.Checked = $true
    # busy state
    Set-Busy $true; Chk (-not $btnSubs.Enabled) 'button disabled while busy'; Set-Busy $false; Chk ($btnSubs.Enabled) 'button enabled again when idle'
    # theme coverage
    $cmbTheme.SelectedItem = 'Dark'; Pump 200
    Chk ($btnSubs.BackColor.ToArgb() -eq $Themes['Dark'].Button.ToArgb() -and $btnSubs.FlatStyle -eq 'Flat') 'new button follows the dark theme'
    Chk ($chkSubs.ForeColor.ToArgb() -eq $Themes['Dark'].Fore.ToArgb() -and $chkSubStd.BackColor.ToArgb() -eq $Themes['Dark'].Back.ToArgb()) 'new Setup checkboxes follow the dark theme'
    $cmbTheme.SelectedItem = 'Light'; Pump 200
    Chk ($chkSubs.ForeColor.ToArgb() -eq $Themes['Light'].Fore.ToArgb()) 'new Setup checkboxes follow the light theme'
    # duplicate shading: best copy green, others orange (dry-run rows built by hand)
    $dd = Join-Path $AppDir 'dupshade'; [void][IO.Directory]::CreateDirectory($dd)
    $pa = Join-Path $dd 'Movie.1080p.mkv'; $pb = Join-Path $dd 'Movie.720p.mkv'; $pc = Join-Path $dd 'Solo (2000).mkv'
    foreach ($q in $pa, $pb, $pc) { [IO.File]::WriteAllBytes($q, (New-Object byte[] 1024)) }
    $mk = { param($old, $new, $note) [pscustomobject]@{ status = ''; confidence = 'high'; media_type = 'movie'; old_path = $old; new_path = $new; note = $note; tmdb_id = '1' } }
    $rowsD = @((& $mk $pa (Join-Path $dd 'Movie (2000).mkv') 'matched'), (& $mk $pb (Join-Path $dd 'Movie (2000).mkv') "DUPLICATE: same target as $pa"), (& $mk $pc $pc 'already correctly named; skipped'))
    $script:Rows = $rowsD; $script:Mode = 'plan'
    $ngD = Update-DupMarks
    Chk ($ngD -eq 1 -and $script:DupMark[$pa.ToLowerInvariant()] -eq 'keep' -and $script:DupMark[$pb.ToLowerInvariant()] -eq 'del' -and -not $script:DupMark.ContainsKey($pc.ToLowerInvariant())) "duplicate marks: best=keep, other=del, non-duplicate unmarked (groups=$ngD)"
    Fill-Table $rowsD 'plan'; Pump 200
    $fmt = $grid.GetType().GetMethod('OnCellFormatting', [Reflection.BindingFlags]'NonPublic,Instance', $null, [Type[]]@([System.Windows.Forms.DataGridViewCellFormattingEventArgs]), $null)
    $styleOf = { param($ri) $cs = New-Object System.Windows.Forms.DataGridViewCellStyle; $cs.BackColor = [System.Drawing.Color]::White
        $ea = New-Object System.Windows.Forms.DataGridViewCellFormattingEventArgs(3, $ri, 'x', [string], $cs); [void]$fmt.Invoke($grid, [object[]]@($ea.psobject.BaseObject)); $cs.BackColor }
    $colors = @{}; for ($ri = 0; $ri -lt $grid.Rows.Count; $ri++) { $colors[[string]$grid.Rows[$ri].DataBoundItem.Row['old_path']] = (& $styleOf $ri) }
    $cKeep = $colors[$pa]; $cDel = $colors[$pb]; $cNone = $colors[$pc]
    Chk ($cKeep.G -gt $cKeep.R -and $cKeep.G -gt $cKeep.B) "keep row is shaded green ($cKeep)"
    Chk ($cDel.R -gt $cDel.B -and $cDel.G -gt $cDel.B -and $cDel.R -ge $cDel.G) "deleted row is shaded orange ($cDel)"
    Chk ($cNone.ToArgb() -eq [System.Drawing.Color]::White.ToArgb()) 'non-duplicate row keeps its normal colour'
    # copies of a group stay together: unrelated rows in between must not split them
    $pz = Join-Path $dd 'Zzz (2001).mkv'; [IO.File]::WriteAllBytes($pz, (New-Object byte[] 1024))
    $rowsE = @($rowsD[1], (& $mk $pz $pz 'already correctly named; skipped'), $rowsD[0], $rowsD[2], (& $mk (Join-Path $dd 'Movie.480p.mkv') (Join-Path $dd 'Movie (2000).mkv') "DUPLICATE: same target as $pa"))
    [IO.File]::WriteAllBytes((Join-Path $dd 'Movie.480p.mkv'), (New-Object byte[] 1024))
    $script:Rows = $rowsE; $script:Mode = 'plan'; [void](Update-DupMarks); Fill-Table $rowsE 'plan'; Pump 200
    $order = @(for ($ri = 0; $ri -lt $grid.Rows.Count; $ri++) { [IO.Path]::GetFileName([string]$grid.Rows[$ri].DataBoundItem.Row['old_path']) })
    $iA = [array]::IndexOf($order, 'Movie.1080p.mkv'); $iB = [array]::IndexOf($order, 'Movie.720p.mkv'); $iC = [array]::IndexOf($order, 'Movie.480p.mkv')
    Chk ($iA -ge 0 -and $iB -eq $iA + 1 -and $iC -eq $iA + 2) "duplicate group rows are adjacent, keeper first ($($order -join ', '))"
    $cmbFilter.SelectedItem = 'Duplicates / collisions'; Pump 100
    $shown = @(for ($ri = 0; $ri -lt $grid.Rows.Count; $ri++) { [IO.Path]::GetFileName([string]$grid.Rows[$ri].DataBoundItem.Row['old_path']) })
    Chk ($shown -contains 'Movie.1080p.mkv' -and $shown -contains 'Movie.720p.mkv' -and $shown.Count -eq 3) "Duplicates filter shows the keeper too ($($shown -join ', '))"
    $cmbFilter.SelectedItem = 'All'; Pump 100
    $script:Mode = 'undo'; Chk ((& $styleOf 0).ToArgb() -eq [System.Drawing.Color]::White.ToArgb()) 'no shading outside plan mode'
    $script:Mode = 'plan'; $script:Rows = $null; $script:DupMark = @{}
    # turn off
    $chkSubs.Checked = $false; Pump 200
    Chk (-not $btnSubs.Visible -and $txtSearch.Right -eq $baseRight -and $cmbFilter.Right -eq $baseFilterRight) 'turning it off hides the button and leaves Search and Show where they were'
    $chkSubs.Checked = $true; Pump 100

    if ($env:PRGUI_LIVE -eq '1') {
        $media = Join-Path $AppDir 'Movies'; [void][IO.Directory]::CreateDirectory((Join-Path $media 'Alien (1979)'))
        $vid = Join-Path $media 'Alien (1979)\Alien (1979) - 1080p.mkv'; 'x' | Set-Content -LiteralPath $vid
        $rows = @([pscustomobject]@{ old_path = $vid; new_path = ''; media_type = 'movie'; tmdb_id = '348'; confidence = 'high'; note = 'already correctly named; skipped' })
        $script:Rows = $rows; $script:Mode = 'plan'
        $script:planGot = $null; $script:dlGot = $null
        Start-Work 'subsplan' @{ Rows = $rows; HighOnly = $true; Std = $true; Sdh = $true; Key = ''; CachePath = $CachePath; SubsCache = $SubsCachePath; TvdbKey = ''; TvdbPin = ''; Source = 'TMDB only'; Version = $AppVersion } { param($p) $script:planGot = $p }
        Chk ($btnSubs.Enabled -eq $false -and $btnCancel.Enabled) 'busy state during the lookup'
        $ok = Wait-For { $null -ne $script:planGot } 120
        Chk ($ok -and $script:planGot.Std -eq 1 -and $script:planGot.Sdh -eq 1) "worker lookup (dry run) found 1 standard + 1 SDH (got $($script:planGot.Std)/$($script:planGot.Sdh); $($txtLog.Text.Split([char]10)[-3]))"
        Chk (-not [IO.File]::Exists((Get-PRSubTarget $vid 'standard'))) 'dry run wrote nothing'
        Chk ($btnSubs.Enabled) 'buttons re-enabled after the lookup'
        $logp = Join-Path $AppDir 'subs_test_log.csv'
        Start-Work 'subsget' @{ Plan = $script:planGot; Version = $AppVersion; LogPath = $logp } { param($r) $script:dlGot = $r }
        $ok = Wait-For { $null -ne $script:dlGot } 180
        Chk ($ok -and $script:dlGot.Standard -eq 1 -and $script:dlGot.Sdh -eq 1) "worker download wrote 1 standard + 1 SDH (got $($script:dlGot.Standard)/$($script:dlGot.Sdh))"
        Chk ([IO.File]::Exists((Get-PRSubTarget $vid 'standard')) -and [IO.File]::Exists((Get-PRSubTarget $vid 'sdh')) -and [IO.File]::Exists($logp)) 'subtitle files and CSV log exist'
        Chk (Test-Path -LiteralPath $SubsCachePath) 'lookup cache file written'
        Chk (-not $Sync.Error) "no worker error ($($Sync.Error))"
    }
} catch { Write-Host "FAIL exception: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"; $global:T_fail++ }
finally { try { $form.Close() } catch { } }
if ($global:T_fail) { Write-Host "$($global:T_fail) FAILED"; exit 1 } else { Write-Host 'ALL PASSED'; exit 0 }
'@
[IO.File]::WriteAllText((Join-Path $tmp 'Renamr.Gui.ps1'), $gui.Replace($end, $driver), (New-Object Text.UTF8Encoding($true)))
if ($Live) { $env:PRGUI_LIVE = '1' } else { $env:PRGUI_LIVE = '0' }
$out = & powershell -STA -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tmp 'Renamr.Gui.ps1') 2>&1
$out | ForEach-Object { Write-Host $_ }
$code = $LASTEXITCODE
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($code -ne 0 -or -not ($out -match 'ALL PASSED')) { Write-Host 'GUI TEST FAILED'; exit 1 } else { Write-Host 'GUI TEST PASSED' }
