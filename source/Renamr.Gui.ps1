# Renamr GUI (WinForms). Windows PowerShell 5.1. The engine runs in a background runspace so the UI stays responsive.
# In a built Renamr.ps1 / .exe, build_exe.ps1 inserts the engine source into $PR_EMBEDDED_ENGINE below.
$PR_EMBEDDED_ENGINE = $null  #@@ENGINE@@
$AppVersion = 'dev'  #@@VERSION@@
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------- locate app folder and engine ----------
$AppDir = $PSScriptRoot
if (-not $AppDir) { $AppDir = Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
$EngineCode = $PR_EMBEDDED_ENGINE
if (-not $EngineCode) {
    foreach ($c in (Join-Path $AppDir 'Renamr.Engine.ps1'), (Join-Path $AppDir 'source\Renamr.Engine.ps1')) {
        if (Test-Path -LiteralPath $c) { $EngineCode = [IO.File]::ReadAllText($c); break }
    }
}
if (-not $EngineCode) { [System.Windows.Forms.MessageBox]::Show("Renamr.Engine.ps1 not found next to the app.", 'Renamr') | Out-Null; return }
. ([scriptblock]::Create($EngineCode))   # main thread uses CSV/export helpers

$SettingsPath = Join-Path $AppDir 'settings.json'
$CachePath    = Join-Path $AppDir 'tmdb_cache.json'
$LogDir       = Join-Path $AppDir 'Logs'
$SubsCachePath = Join-Path $AppDir 'subs_cache.json'

# ---------- settings (TMDB key protected with Windows DPAPI for the current user) ----------
function Load-Settings {
    $s = @{ MoviesRoot = ''; SeriesRoot = ''; HighOnly = $true; Key = ''; Theme = 'System'; TvdbKey = ''; TvdbPin = ''; Source = 'Movies: TMDB, TV: TVDB'; ProbeAlways = $false; ProbeScan = $true; SubsEnable = $false; SubsStd = $true; SubsSdh = $true; AutoSubs = $false; FolderLoose = $true }
    if (Test-Path -LiteralPath $SettingsPath) {
        try {
            $j = [IO.File]::ReadAllText($SettingsPath) | ConvertFrom-Json
            if ($j.MoviesRoot) { $s.MoviesRoot = $j.MoviesRoot }
            if ($j.SeriesRoot) { $s.SeriesRoot = $j.SeriesRoot }
            if ($null -ne $j.HighOnly) { $s.HighOnly = [bool]$j.HighOnly }
            if (@('System', 'Light', 'Dark') -contains $j.Theme) { $s.Theme = [string]$j.Theme }
            if ($null -ne $j.ProbeAlways) { $s.ProbeAlways = [bool]$j.ProbeAlways }
            if ($null -ne $j.ProbeScan) { $s.ProbeScan = [bool]$j.ProbeScan }
            if ($null -ne $j.SubsEnable) { $s.SubsEnable = [bool]$j.SubsEnable }
            if ($null -ne $j.SubsStd) { $s.SubsStd = [bool]$j.SubsStd }
            if ($null -ne $j.SubsSdh) { $s.SubsSdh = [bool]$j.SubsSdh }
            if ($null -ne $j.FolderLoose) { $s.FolderLoose = [bool]$j.FolderLoose }
            if ($null -ne $j.AutoSubs) { $s.AutoSubs = [bool]$j.AutoSubs }
            if (@('Movies: TMDB, TV: TVDB', 'TMDB first', 'TVDB first', 'TMDB only', 'TVDB only') -contains $j.Source) { $s.Source = [string]$j.Source }
            if ($j.TvdbKeyProtected) { try { $s.TvdbKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR((ConvertTo-SecureString $j.TvdbKeyProtected))) } catch { } }
            if ($j.TvdbPinProtected) { try { $s.TvdbPin = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR((ConvertTo-SecureString $j.TvdbPinProtected))) } catch { } }
            if ($j.TmdbKeyProtected) {
                $sec = ConvertTo-SecureString $j.TmdbKeyProtected
                $s.Key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
            }
        } catch { }
    }
    return $s
}
function Save-Settings {
    $prot = ''
    if ($txtKey.Text.Trim()) { $prot = ConvertFrom-SecureString (ConvertTo-SecureString $txtKey.Text.Trim() -AsPlainText -Force) }
    $tk = ''; if ($txtTvdb.Text.Trim()) { $tk = ConvertFrom-SecureString (ConvertTo-SecureString $txtTvdb.Text.Trim() -AsPlainText -Force) }
    $tp = ''; if ($txtPin.Text.Trim()) { $tp = ConvertFrom-SecureString (ConvertTo-SecureString $txtPin.Text.Trim() -AsPlainText -Force) }
    $o = [ordered]@{ ProbeAlways = $chkProbe.Checked; ProbeScan = $chkScanProbe.Checked; SubsEnable = $chkSubs.Checked; SubsStd = $chkSubStd.Checked; SubsSdh = $chkSubSdh.Checked; AutoSubs = $chkAutoSubs.Checked; FolderLoose = $chkFolderLoose.Checked; Source = [string]$cmbSource.SelectedItem; TvdbKeyProtected = $tk; TvdbPinProtected = $tp; MoviesRoot = $txtMovies.Text.Trim(); SeriesRoot = $txtSeries.Text.Trim(); HighOnly = $chkHigh.Checked; Theme = [string]$cmbTheme.SelectedItem; TmdbKeyProtected = $prot }
    [IO.File]::WriteAllText($SettingsPath, ($o | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
}

# ---------- form ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Renamr v$AppVersion"; $form.Size = New-Object System.Drawing.Size(1250, 820); $form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(900, 600)
$font = New-Object System.Drawing.Font('Segoe UI', 9); $form.Font = $font
# window icon: Renamr.ico next to the app or in source\, else the icon embedded in Renamr.exe; silent fallback
try {
    $icoFile = @((Join-Path $AppDir 'Renamr.ico'), (Join-Path $AppDir 'source\Renamr.ico')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($icoFile) { $form.Icon = New-Object System.Drawing.Icon($icoFile) }
    else {
        $exePath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($exePath -notmatch '\\(powershell|pwsh)\.exe$') { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($exePath) }
    }
} catch { }

function Set-FillColumns($grid, [string[]]$Names) {
    # columns share the available width in proportion to their default widths (minimum width 200 or less)
    foreach ($col in $grid.Columns) {
        if ($Names -and $Names -notcontains $col.Name) { continue }
        $w = [int]$col.Width; $col.MinimumWidth = [math]::Min($w, 200); $col.FillWeight = [float]$w; $col.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
    }
}
$script:UiHost = $form
function New-Label($text, $x, $y) { $l = New-Object System.Windows.Forms.Label; $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y); $l.AutoSize = $true; $script:UiHost.Controls.Add($l); $l }
function New-Text($x, $y, $w) { $t = New-Object System.Windows.Forms.TextBox; $t.Location = New-Object System.Drawing.Point($x, $y); $t.Width = $w; $t.Anchor = 'Top,Left,Right'; $script:UiHost.Controls.Add($t); $t }
function New-Button($text, $x, $y, $w) { $b = New-Object System.Windows.Forms.Button; $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, $y); $b.Width = $w; $b.Height = 28; $script:UiHost.Controls.Add($b); $b }

[void](New-Label 'Movies folder:' 12 16);  $txtMovies = New-Text 120 12 1000
$btnMovies = New-Button 'Browse...' 1130 10 90; $btnMovies.Anchor = 'Top,Right'
[void](New-Label 'Series folder:' 12 48);  $txtSeries = New-Text 120 44 1000
$btnSeries = New-Button 'Browse...' 1130 42 90; $btnSeries.Anchor = 'Top,Right'
[void](New-Label 'Name source:' 12 80)
$cmbSource = New-Object System.Windows.Forms.ComboBox; $cmbSource.DropDownStyle = 'DropDownList'; $cmbSource.Location = New-Object System.Drawing.Point(120, 76); $cmbSource.Width = 175
@('Movies: TMDB, TV: TVDB', 'TMDB first', 'TVDB first', 'TMDB only', 'TVDB only') | ForEach-Object { [void]$cmbSource.Items.Add($_) }; $cmbSource.SelectedIndex = 0; $form.Controls.Add($cmbSource)
$chkHigh = New-Object System.Windows.Forms.CheckBox; $chkHigh.Text = 'Only high-confidence'; $chkHigh.Location = New-Object System.Drawing.Point(320, 78); $chkHigh.AutoSize = $true; $form.Controls.Add($chkHigh)
$btnSetup = New-Button 'Setup...' 1130 74 90; $btnSetup.Anchor = 'Top,Right'

# ---------- Setup window (API keys, PIN, theme, real-resolution options). Controls live here but are used exactly like before ----------
$setup = New-Object System.Windows.Forms.Form
$setup.Text = 'Renamr - Setup'; $setup.ClientSize = New-Object System.Drawing.Size(560, 558); $setup.StartPosition = 'CenterParent'
$setup.FormBorderStyle = 'FixedDialog'; $setup.MaximizeBox = $false; $setup.MinimizeBox = $false; $setup.ShowInTaskbar = $false; $setup.Font = $font
if ($form.Icon) { $setup.Icon = $form.Icon }
$script:UiHost = $setup
[void](New-Label 'TMDB API key:' 16 20);   $txtKey = New-Text 130 16 330; $txtKey.UseSystemPasswordChar = $true; $txtKey.Anchor = 'Top,Left'
$chkShow = New-Object System.Windows.Forms.CheckBox; $chkShow.Text = 'Show keys'; $chkShow.Location = New-Object System.Drawing.Point(472, 18); $chkShow.AutoSize = $true; $setup.Controls.Add($chkShow)
[void](New-Label 'TVDB API key:' 16 56);   $txtTvdb = New-Text 130 52 330; $txtTvdb.UseSystemPasswordChar = $true; $txtTvdb.Anchor = 'Top,Left'
[void](New-Label 'TVDB PIN (if any):' 16 92); $txtPin = New-Text 130 88 140; $txtPin.UseSystemPasswordChar = $true; $txtPin.Anchor = 'Top,Left'
[void](New-Label 'Theme:' 16 128)
$cmbTheme = New-Object System.Windows.Forms.ComboBox; $cmbTheme.DropDownStyle = 'DropDownList'; $cmbTheme.Location = New-Object System.Drawing.Point(130, 124); $cmbTheme.Width = 140
@('System', 'Light', 'Dark') | ForEach-Object { [void]$cmbTheme.Items.Add($_) }; $cmbTheme.SelectedIndex = 0; $setup.Controls.Add($cmbTheme)
$chkScanProbe = New-Object System.Windows.Forms.CheckBox; $chkScanProbe.Text = 'Check real resolution on scan (corrects the resolution in new names)'; $chkScanProbe.Location = New-Object System.Drawing.Point(16, 168); $chkScanProbe.AutoSize = $true; $chkScanProbe.Checked = $true; $setup.Controls.Add($chkScanProbe)
$chkProbe = New-Object System.Windows.Forms.CheckBox; $chkProbe.Text = 'Always read real resolution (Duplicates window)'; $chkProbe.Location = New-Object System.Drawing.Point(16, 198); $chkProbe.AutoSize = $true; $setup.Controls.Add($chkProbe)
$chkFolderLoose = New-Object System.Windows.Forms.CheckBox; $chkFolderLoose.Text = 'Put movies that are not in a folder into their own "Name (Year)" folder'; $chkFolderLoose.Location = New-Object System.Drawing.Point(16, 226); $chkFolderLoose.AutoSize = $true; $chkFolderLoose.Checked = $true; $setup.Controls.Add($chkFolderLoose)
$chkSubs = New-Object System.Windows.Forms.CheckBox; $chkSubs.Text = 'Enable subtitle download (shows the Get subtitles button)'; $chkSubs.Location = New-Object System.Drawing.Point(16, 266); $chkSubs.AutoSize = $true; $setup.Controls.Add($chkSubs)
$chkSubStd = New-Object System.Windows.Forms.CheckBox; $chkSubStd.Text = 'Get standard subtitles'; $chkSubStd.Location = New-Object System.Drawing.Point(40, 292); $chkSubStd.AutoSize = $true; $chkSubStd.Checked = $true; $setup.Controls.Add($chkSubStd)
$chkSubSdh = New-Object System.Windows.Forms.CheckBox; $chkSubSdh.Text = 'Also get SDH / HI subtitles when available'; $chkSubSdh.Location = New-Object System.Drawing.Point(40, 318); $chkSubSdh.AutoSize = $true; $chkSubSdh.Checked = $true; $setup.Controls.Add($chkSubSdh)
$chkAutoSubs = New-Object System.Windows.Forms.CheckBox; $chkAutoSubs.Text = 'Auto Get Subtitles (download them automatically after each Full Run)'; $chkAutoSubs.Location = New-Object System.Drawing.Point(40, 344); $chkAutoSubs.AutoSize = $true; $setup.Controls.Add($chkAutoSubs)
[void](New-Label 'English only, from The Subtitle Database (no account needed).' 40 372)
[void](New-Label 'Saved next to the video as <name>.en.srt and <name>.en.sdh.srt.' 40 392)
$lblSubLimits = New-Label 'Service limits: the free service allows about 200 subtitle downloads per hour, and lookups are rate-limited too. When a limit is reached, Renamr stops cleanly and tells you roughly when to try again; the next run continues where it left off. Existing subtitle files are never overwritten.' 40 416
$lblSubLimits.AutoSize = $true; $lblSubLimits.MaximumSize = New-Object System.Drawing.Size(500, 0)
$lblSetupNote = New-Label 'Keys are stored encrypted for your Windows user. Changes are saved when you close this window.' 16 498
$btnSetupClose = New-Button 'Close' 454 518 90; $setup.AcceptButton = $btnSetupClose; $setup.CancelButton = $btnSetupClose; $btnSetupClose.DialogResult = 'OK'
$script:UiHost = $form
$btnScan   = New-Button 'Scan' 12 112 130
$btnRun    = New-Button 'Full Run' 150 112 100
$btnUndo   = New-Button 'Undo...' 258 112 90
$btnExport = New-Button 'Export plan CSV...' 356 112 140
$btnCancel = New-Button 'Stop' 504 112 80; $btnCancel.Enabled = $false   # halts whatever is running (Scan, Full Run, Undo, subtitles) after the current file
$btnDups = New-Button 'Duplicates...' 592 112 100; $btnDups.Enabled = $false
$btnSubs = New-Button 'Get subtitles...' 700 112 120; $btnSubs.Visible = $false   # shown only when subtitle download is enabled in Setup (Update-SubsUi)

$lblShow = New-Label 'Show:' 996 118; $lblShow.Anchor = 'Top,Right'   # right-justified on the button row
$cmbFilter = New-Object System.Windows.Forms.ComboBox; $cmbFilter.DropDownStyle = 'DropDownList'; $cmbFilter.Location = New-Object System.Drawing.Point(1040, 114); $cmbFilter.Width = 180; $cmbFilter.Anchor = 'Top,Right'
@('All', 'Will move - high', 'Will move - low', 'Multiple versions', 'Duplicates / collisions', 'Unmatched / left in place', 'Already correctly named') | ForEach-Object { [void]$cmbFilter.Items.Add($_) }
$cmbFilter.SelectedIndex = 0; $form.Controls.Add($cmbFilter)
$lblSearch = New-Label 'Search:' 490 80; $txtSearch = New-Text 545 76 235; $txtSearch.Anchor = 'Top,Left'   # sits on the Name source row, right of 'Only high-confidence'

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(12, 150); $grid.Size = New-Object System.Drawing.Size(1208, 430); $grid.Anchor = 'Top,Bottom,Left,Right'
$grid.ReadOnly = $true; $grid.AllowUserToAddRows = $false; $grid.AllowUserToDeleteRows = $false; $grid.RowHeadersVisible = $false
$grid.SelectionMode = 'FullRowSelect'; $grid.AutoSizeColumnsMode = 'None'
$form.Controls.Add($grid)

$progress = New-Object System.Windows.Forms.ProgressBar; $progress.Location = New-Object System.Drawing.Point(12, 588); $progress.Size = New-Object System.Drawing.Size(900, 18); $progress.Anchor = 'Bottom,Left,Right'
$form.Controls.Add($progress)
$lblStatus = New-Object System.Windows.Forms.Label; $lblStatus.Location = New-Object System.Drawing.Point(920, 588); $lblStatus.Size = New-Object System.Drawing.Size(300, 18); $lblStatus.Anchor = 'Bottom,Right'; $form.Controls.Add($lblStatus)
$txtLog = New-Object System.Windows.Forms.TextBox; $txtLog.Multiline = $true; $txtLog.ScrollBars = 'Vertical'; $txtLog.ReadOnly = $true
$txtLog.Location = New-Object System.Drawing.Point(12, 612); $txtLog.Size = New-Object System.Drawing.Size(1208, 146); $txtLog.Anchor = 'Bottom,Left,Right'
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9); $form.Controls.Add($txtLog)
$lblVersion = New-Object System.Windows.Forms.Label; $lblVersion.Text = "v$AppVersion"; $lblVersion.AutoSize = $false; $lblVersion.TextAlign = 'MiddleRight'
$lblVersion.Location = New-Object System.Drawing.Point(1020, 762); $lblVersion.Size = New-Object System.Drawing.Size(200, 16); $lblVersion.Anchor = 'Bottom,Right'
$lblVersion.Font = New-Object System.Drawing.Font('Segoe UI', 7.5); $form.Controls.Add($lblVersion)

# ---------- data table ----------
$table = New-Object System.Data.DataTable
foreach ($c in 'status', 'confidence', 'media_type', 'old_name', 'new_name', 'note', 'tmdb_id', 'old_path', 'new_path', 'dup_sort', 'dup_flag') { [void]$table.Columns.Add($c) }
$grid.DataSource = $table
$script:Rows = $null; $script:Mode = 'plan'

function Get-Status($r) {
    $n = [string]$r.note
    if ($n -like '*DUPLICATE*' -or $n -like '*COLLISION*') { return 'duplicate/collision' }
    if ($n -like '*already correctly named*') { return 'already named' }
    if (-not $r.new_path) { return 'unmatched/left' }
    if ($n -like '*MULTIPLE VERSIONS*') { return 'move: multiple versions' }
    return 'move: ' + $r.confidence
}
function Leaf([string]$p) { if (-not $p) { return '' }; return [System.IO.Path]::GetFileName($p) }
function Fill-Table($rows, [string]$mode) {
    $grid.DataSource = $null; $table.Clear(); $table.BeginLoadData()
    foreach ($r in $rows) {
        if ($mode -eq 'undo') { [void]$table.Rows.Add('undo', '', '', (Leaf $r.new_path), (Leaf $r.old_path), "moved $($r.moved_at)", '', $r.new_path, $r.old_path) }
        else { [void]$table.Rows.Add((Get-Status $r), $r.confidence, $r.media_type, (Leaf $r.old_path), (Leaf $r.new_path), $r.note, $r.tmdb_id, $r.old_path, $r.new_path) }
    }
    Update-DupSortKeys
    $table.EndLoadData(); $grid.DataSource = $table
    $table.DefaultView.Sort = 'dup_sort ASC'   # original order, but the copies of a duplicate group stay together (best first)
    $w = @{ status = 140; confidence = 75; media_type = 70; old_name = 380; new_name = 380; note = 400; tmdb_id = 60; old_path = 100; new_path = 100 }
    foreach ($col in $grid.Columns) { if ($w.ContainsKey($col.Name)) { $col.Width = $w[$col.Name] }; $col.SortMode = 'Automatic' }
    Set-FillColumns $grid @('old_name', 'new_name', 'note')
    $grid.Columns['old_path'].Visible = $false; $grid.Columns['new_path'].Visible = $false; $grid.Columns['dup_sort'].Visible = $false; $grid.Columns['dup_flag'].Visible = $false
    foreach ($cn in 'status', 'confidence', 'media_type', 'tmdb_id') { $grid.Columns[$cn].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::AllCells }
    Apply-Filter
    $grid.CurrentCell = $null; $grid.ClearSelection()
}
function Apply-Filter {
    $f = @()
    switch ($cmbFilter.SelectedItem) {
        'Will move - high'          { $f += "status = 'move: high'" }
        'Will move - low'           { $f += "status = 'move: low'" }
        'Multiple versions'         { $f += "status = 'move: multiple versions'" }
        'Duplicates / collisions'   { $f += "(status = 'duplicate/collision' OR dup_flag = '1')" }   # includes the green keeper rows of each group
        'Unmatched / left in place' { $f += "status = 'unmatched/left'" }
        'Already correctly named'   { $f += "status = 'already named'" }
    }
    $q = $txtSearch.Text.Trim()
    if ($q) {
        $e = ($q -replace "'", "''") -replace '([\[\]\*%])', '[$1]'
        $f += "(old_path LIKE '%$e%' OR new_path LIKE '%$e%' OR note LIKE '%$e%')"
    }
    try { $table.DefaultView.RowFilter = ($f -join ' AND ') } catch { $table.DefaultView.RowFilter = '' }
    $lblStatus.Text = "$($table.DefaultView.Count) of $($table.Rows.Count) rows shown"
}
# ---------- duplicate shading in the main grid ----------
# green = the copy that would be kept, orange = copies that would be deleted (nothing is deleted until Duplicates > Delete others)
$script:DupMark = @{}; $script:DupGroup = @{}
function Update-DupSortKeys {
    # key = original position, except that every member of a duplicate group takes the position of its first member, keeper first
    $n = $table.Rows.Count; $pos = @{}
    for ($i = 0; $i -lt $n; $i++) { $pos[([string]$table.Rows[$i]['old_path']).ToLowerInvariant()] = $i }
    $anchor = @{}
    if ($script:Mode -eq 'plan') { foreach ($k in $script:DupGroup.Keys) { if ($pos.ContainsKey($k)) { $g = $script:DupGroup[$k]; if (-not $anchor.ContainsKey($g) -or $pos[$k] -lt $anchor[$g]) { $anchor[$g] = $pos[$k] } } } }
    for ($i = 0; $i -lt $n; $i++) {
        $lp = ([string]$table.Rows[$i]['old_path']).ToLowerInvariant(); $a = $i; $rk = 0
        if ($anchor.Count -gt 0 -and $script:DupGroup.ContainsKey($lp)) { $a = $anchor[$script:DupGroup[$lp]]; if ($script:DupMark[$lp] -eq 'del') { $rk = 1 } }
        $table.Rows[$i]['dup_sort'] = ('{0:D7}{1}{2:D7}' -f $a, $rk, $i)
        $table.Rows[$i]['dup_flag'] = $(if ($anchor.Count -gt 0 -and $script:DupGroup.ContainsKey($lp)) { '1' } else { '' })
    }
}
function Update-DupMarks {
    $script:DupMark = @{}; $script:DupGroup = @{}
    if (-not $script:Rows) { return 0 }
    $groups = @(Get-PRDuplicateGroups $script:Rows)
    foreach ($g in $groups) {
        $files = @()
        foreach ($p in @($g.Paths)) {
            $fi = New-Object IO.FileInfo($p); $exists = $fi.Exists
            $size = 0; if ($exists) { $size = $fi.Length }
            $rh = PR-ResHint (PR-Base $p)
            if ($exists -and ($rh.Rank -eq 0 -or $chkProbe.Checked)) { $pr = PR-ProbeRes $p; if ($pr) { $rh = @{ Label = ($pr.Label + '*'); Rank = $pr.Rank } } }
            $files += [pscustomobject]@{ Path = $p; Size = $size; Rank = $rh.Rank }
        }
        $keep = [int](Select-PRDefaultKeep $files)
        for ($i = 0; $i -lt $files.Count; $i++) { $lk = ([string]$files[$i].Path).ToLowerInvariant(); $script:DupMark[$lk] = $(if ($i -eq $keep) { 'keep' } else { 'del' }); $script:DupGroup[$lk] = [int]$g.Id }
    }
    return $groups.Count
}
$grid.Add_CellFormatting({ param($s, $e)
    if ($e.RowIndex -lt 0 -or $script:Mode -ne 'plan' -or $script:DupMark.Count -eq 0) { return }
    try {
        $dv = $grid.Rows[$e.RowIndex].DataBoundItem; if (-not $dv) { return }
        $mk = $script:DupMark[([string]$dv.Row['old_path']).ToLowerInvariant()]
        if (-not $mk) { return }
        $dark = ($script:ThemeEff -eq 'Dark')
        if ($mk -eq 'keep') { $e.CellStyle.BackColor = $(if ($dark) { C '#1F4D2B' } else { C '#C8E6C9' }) }
        else                { $e.CellStyle.BackColor = $(if ($dark) { C '#7A4A10' } else { C '#FFD9A0' }) }
    } catch { }
})
# start with nothing selected, so no row is highlighted until the user clicks one
$grid.Add_DataBindingComplete({ $grid.CurrentCell = $null; $grid.ClearSelection() })
$grid.ShowCellToolTips = $true
$grid.Add_CellToolTipTextNeeded({ param($s, $e)
    if ($e.RowIndex -ge 0 -and ($e.ColumnIndex -eq $grid.Columns['old_name'].Index -or $e.ColumnIndex -eq $grid.Columns['new_name'].Index)) {
        $pc = if ($e.ColumnIndex -eq $grid.Columns['old_name'].Index) { 'old_path' } else { 'new_path' }
        $e.ToolTipText = [string]$grid.Rows[$e.RowIndex].Cells[$pc].Value
    }
})
$cmbFilter.Add_SelectedIndexChanged({ Apply-Filter })
$txtSearch.Add_TextChanged({ Apply-Filter })

# ---------- background worker (runspace) ----------
$Sync = [hashtable]::Synchronized(@{})
$script:PS = $null; $script:Handle = $null; $script:OnDone = $null
$worker = {
    param($EngineCode, $Sync, $Kind, $A)
    try {
        . ([scriptblock]::Create($EngineCode))
        $script:PRSync = $Sync
        switch ($Kind) {
            'scan' {
                $files = Get-PRFiles @($A.MoviesRoot, $A.SeriesRoot)
                PR-Log "Found $($files.Count) files."
                $db = New-PRTmdb -Key $A.Key -CachePath $A.CachePath -TvdbKey $A.TvdbKey -TvdbPin $A.TvdbPin -Source $A.Source
                $rows = New-PRPlan -Paths $files -MoviesRoot $A.MoviesRoot -SeriesRoot $A.SeriesRoot -Db $db -ProbeReal ([bool]$A.ProbeReal) -FolderLoose ([bool]$A.FolderLoose)
                PR-Log ((Get-PRSummary $rows) + " Online lookups made: $($db.Calls).")
                $Sync.Result = $rows
            }
            'apply' { $Sync.Result = Invoke-PRApply -Rows $A.Rows -HighOnly:$A.HighOnly -UndoLog $A.UndoLog }
            'undo'  { $Sync.Result = Invoke-PRUndo -UndoLog $A.UndoLog }
            'delete' { $Sync.Result = Remove-PRFiles -Items $A.Items -LogPath $A.LogPath -Folders $A.Folders }
            'subsplan' {
                $db = New-PRTmdb -Key $A.Key -CachePath $A.CachePath -TvdbKey $A.TvdbKey -TvdbPin $A.TvdbPin -Source $A.Source
                $S = New-PRSubs -Db $db -Version $A.Version -CachePath $A.SubsCache
                $Sync.Result = Get-PRSubsPlan -Rows $A.Rows -S $S -HighOnly:([bool]$A.HighOnly) -Standard ([bool]$A.Std) -Sdh ([bool]$A.Sdh)
            }
            'subsget' {
                $S = New-PRSubs -Db $null -Version $A.Version
                $Sync.Result = Invoke-PRSubsDownload -Plan $A.Plan -S $S -LogPath $A.LogPath
            }
        }
    } catch { if ($_.Exception.Message -eq 'Cancelled') { $Sync.Stopped = $true } else { $Sync.Error = $_.Exception.Message } }   # Stop pressed: not an error
    finally { $Sync.Finished = $true }
}
function Set-Busy([bool]$busy) {
    foreach ($b in $btnScan, $btnRun, $btnUndo, $btnExport, $btnMovies, $btnSeries, $btnSetup, $btnSubs) { $b.Enabled = -not $busy }
    $btnCancel.Enabled = $busy
    $btnDups.Enabled = (-not $busy) -and ($null -ne $script:Rows) -and ($script:Mode -eq 'plan')
    $form.Cursor = if ($busy) { 'AppStarting' } else { 'Default' }
}
function Update-SubsUi {
    # the Get subtitles button follows the Setup checkbox
    $on = [bool]$chkSubs.Checked
    $chkSubStd.Enabled = $on; $chkSubSdh.Enabled = $on; $chkAutoSubs.Enabled = $on
    $btnSubs.Visible = $on
}
function Start-Work([string]$kind, $argsHash, [scriptblock]$onDone) {
    $Sync.Clear()
    $Sync.Log = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
    $Sync.Done = 0; $Sync.Total = 0; $Sync.Phase = 'Starting'; $Sync.Cancel = $false; $Sync.Finished = $false
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.Open()
    $script:PS = [powershell]::Create(); $script:PS.Runspace = $rs
    [void]$script:PS.AddScript($worker.ToString()).AddArgument($EngineCode).AddArgument($Sync).AddArgument($kind).AddArgument($argsHash)
    $script:OnDone = $onDone
    Set-Busy $true
    $script:Handle = $script:PS.BeginInvoke()
    $timer.Start()
}
function Write-UiLog([string]$m) { $txtLog.AppendText($m + "`r`n") }
$timer = New-Object System.Windows.Forms.Timer; $timer.Interval = 200
$timer.Add_Tick({
    $m = $null; $sb = New-Object Text.StringBuilder
    while ($Sync.Log -and $Sync.Log.TryDequeue([ref]$m)) { [void]$sb.Append($m + "`r`n") }
    if ($sb.Length) { $txtLog.AppendText($sb.ToString()) }
    if ($Sync.Total -gt 0) { $progress.Maximum = [int]$Sync.Total; $progress.Value = [math]::Min([int]$Sync.Done, [int]$Sync.Total) }
    $lblStatus.Text = [string]$Sync.Phase
    if ($Sync.Finished) {
        $timer.Stop()
        try { $script:PS.EndInvoke($script:Handle) } catch {}
        $script:PS.Runspace.Close(); $script:PS.Dispose()
        while ($Sync.Log.TryDequeue([ref]$m)) { Write-UiLog $m }
        Set-Busy $false
        if ($Sync.Stopped) { Write-UiLog 'Stopped. Nothing was changed.' }
        elseif ($Sync.Error) { Write-UiLog "ERROR: $($Sync.Error)"; [System.Windows.Forms.MessageBox]::Show($Sync.Error, 'Renamr', 'OK', 'Error') | Out-Null }
        else { & $script:OnDone $Sync.Result }
    }
})

# ---------- actions ----------
function Pick-Folder($tb) {
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.ShowNewFolderButton = $false
    if ($tb.Text -and (Test-Path -LiteralPath $tb.Text)) { $d.SelectedPath = $tb.Text }
    if ($d.ShowDialog($form) -eq 'OK') { $tb.Text = $d.SelectedPath }
}
$btnSetup.Add_Click({ [void]$setup.ShowDialog($form); try { Save-Settings } catch { Write-UiLog "Could not save settings: $($_.Exception.Message)" }; Update-SubsUi })
$btnMovies.Add_Click({ Pick-Folder $txtMovies })
$btnSeries.Add_Click({ Pick-Folder $txtSeries })
$chkScanProbe.Add_CheckedChanged({ if ($script:SettingsLoaded) { try { Save-Settings } catch { } } })
$chkProbe.Add_CheckedChanged({ if ($script:SettingsLoaded) { try { Save-Settings } catch { } } })
$chkSubs.Add_CheckedChanged({ Update-SubsUi; if ($script:SettingsLoaded) { try { Save-Settings } catch { } } })
$chkSubStd.Add_CheckedChanged({ if ($script:SettingsLoaded) { try { Save-Settings } catch { } } })
$chkSubSdh.Add_CheckedChanged({ if ($script:SettingsLoaded) { try { Save-Settings } catch { } } })
$chkAutoSubs.Add_CheckedChanged({ if ($script:SettingsLoaded) { try { Save-Settings } catch { } } })
$chkShow.Add_CheckedChanged({ $txtKey.UseSystemPasswordChar = -not $chkShow.Checked; $txtTvdb.UseSystemPasswordChar = -not $chkShow.Checked; $txtPin.UseSystemPasswordChar = -not $chkShow.Checked })
$btnCancel.Add_Click({ $Sync.Cancel = $true; $btnCancel.Enabled = $false; Write-UiLog 'Stopping... finishing the current file first.' })

$btnScan.Add_Click({
    $m = $txtMovies.Text.Trim().TrimEnd('\'); $s = $txtSeries.Text.Trim().TrimEnd('\')
    if (-not $m -and -not $s) { [System.Windows.Forms.MessageBox]::Show('Choose a Movies and/or Series folder first.', 'Renamr') | Out-Null; return }
    foreach ($p in $m, $s) { if ($p -and -not (Test-Path -LiteralPath $p)) { [System.Windows.Forms.MessageBox]::Show("Folder not found:`n$p", 'Renamr') | Out-Null; return } }
    $src = [string]$cmbSource.SelectedItem
    if ($src -eq 'TVDB only' -and -not $txtTvdb.Text.Trim()) { [System.Windows.Forms.MessageBox]::Show('Enter your TVDB API key in Setup first, or change Name source.', 'Renamr') | Out-Null; return }
    if ($src -ne 'TVDB only' -and -not $txtKey.Text.Trim() -and -not (Test-Path -LiteralPath $CachePath)) {
        [System.Windows.Forms.MessageBox]::Show('Open Setup and enter your TMDB API key (v3) first. Get one free at themoviedb.org > Settings > API.', 'Renamr') | Out-Null; return
    }
    try { Save-Settings } catch { Write-UiLog "Could not save settings: $($_.Exception.Message)" }
    Write-UiLog "Scanning (dry run, nothing is changed)..."
    Start-Work 'scan' @{ MoviesRoot = $m; SeriesRoot = $s; Key = $txtKey.Text.Trim(); CachePath = $CachePath; TvdbKey = $txtTvdb.Text.Trim(); TvdbPin = $txtPin.Text.Trim(); Source = $src; ProbeReal = $chkScanProbe.Checked; FolderLoose = $chkFolderLoose.Checked } {
        param($rows)
        $script:Rows = $rows; $script:Mode = 'plan'
        $ng = 0; $form.Cursor = 'WaitCursor'; try { $ng = Update-DupMarks } catch { $script:DupMark = @{}; $script:DupGroup = @{} } finally { $form.Cursor = 'Default' }
        Fill-Table $rows 'plan'
        if ($ng -gt 0) { Write-UiLog "Duplicates: $ng group(s). Green rows = the copy that would be kept, orange rows = copies that would be deleted. Nothing is deleted unless you use Duplicates... > Delete others." }
        $btnDups.Enabled = $true
        Write-UiLog 'Dry run complete. Review the grid; nothing has been changed. Use Full Run to apply.'
    }
})
$btnExport.Add_Click({
    if (-not $script:Rows -or $script:Mode -ne 'plan') { [System.Windows.Forms.MessageBox]::Show('Run Scan first.', 'Renamr') | Out-Null; return }
    $d = New-Object System.Windows.Forms.SaveFileDialog; $d.Filter = 'CSV (*.csv)|*.csv'; $d.FileName = "plan_$(Get-Date -Format yyyyMMdd_HHmmss).csv"
    if ($d.ShowDialog($form) -eq 'OK') { Export-PRPlan $script:Rows $d.FileName; Write-UiLog "Plan exported to $($d.FileName)" }
})
$btnRun.Add_Click({
    if (-not $script:Rows -or $script:Mode -ne 'plan') { [System.Windows.Forms.MessageBox]::Show('Run Scan first, then review the plan.', 'Renamr') | Out-Null; return }
    $hi = $chkHigh.Checked
    $n = @($script:Rows | Where-Object { $_.new_path -and (-not $hi -or $_.confidence -eq 'high') }).Count
    if ($n -eq 0) { [System.Windows.Forms.MessageBox]::Show('Nothing to move.', 'Renamr') | Out-Null; return }
    $what = 'ALL planned'; if ($hi) { $what = 'high-confidence' }
    $ok = [System.Windows.Forms.MessageBox]::Show("Move/rename $n $what files now?`n`nIf a file with the new name already exists, that file is skipped. An undo log will be written to the Logs folder.", 'Confirm Full Run', 'YesNo', 'Warning')
    if ($ok -ne 'Yes') { return }
    if (-not (Test-Path -LiteralPath $LogDir)) { [void](New-Item -ItemType Directory -Path $LogDir) }
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    Export-PRPlan $script:Rows (Join-Path $LogDir "plan_$ts.csv")
    $undo = Join-Path $LogDir "undo_$ts.csv"
    Write-UiLog "Applying... (plan saved as Logs\plan_$ts.csv)"
    Start-Work 'apply' @{ Rows = $script:Rows; HighOnly = $hi; UndoLog = $undo } {
        param($r)
        if ($r.Cancelled) { $head = "Full Run STOPPED. Moved $($r.Moved) before stopping (skipped $($r.Skipped), failed $($r.Failed)); the rest were not touched."; $ttl = 'Full Run stopped' } else { $head = "Moved $($r.Moved), skipped $($r.Skipped), failed $($r.Failed)."; $ttl = 'Full Run finished' }
        $undoNote = ''; if ($r.Moved) { $undoNote = "`n`nUndo log: $($r.Log)" }
        [System.Windows.Forms.MessageBox]::Show("$head$undoNote`n`nRun Scan again to see the new state.", $ttl) | Out-Null
        $doneRows = $script:Rows
        $script:Rows = $null; $table.Clear()
        if ($chkSubs.Checked -and $chkAutoSubs.Checked -and ($chkSubStd.Checked -or $chkSubSdh.Checked) -and [int]$r.Moved -gt 0 -and -not $r.Cancelled) { Start-AutoSubs $doneRows ([bool]$chkHigh.Checked) }
    }
})
$btnUndo.Add_Click({
    $d = New-Object System.Windows.Forms.OpenFileDialog; $d.Filter = 'Undo logs (undo_*.csv)|undo_*.csv|CSV (*.csv)|*.csv'
    if (Test-Path -LiteralPath $LogDir) { $d.InitialDirectory = $LogDir }
    if ($d.ShowDialog($form) -ne 'OK') { return }
    $log = @(Import-Csv -LiteralPath $d.FileName -Encoding UTF8)
    if ($log.Count -eq 0 -or -not ($log[0].PSObject.Properties.Name -contains 'new_path')) { [System.Windows.Forms.MessageBox]::Show('That is not an undo log.', 'Renamr') | Out-Null; return }
    $script:Mode = 'undo'; $script:Rows = $null
    Fill-Table $log 'undo'
    Write-UiLog "Undo preview: $($log.Count) moves would be reversed (grid shows current -> original)."
    $ok = [System.Windows.Forms.MessageBox]::Show("Reverse $($log.Count) moves from`n$($d.FileName)?`n`nFiles are moved back only where the original path is free.", 'Confirm Undo', 'YesNo', 'Warning')
    if ($ok -ne 'Yes') { Write-UiLog 'Undo cancelled.'; return }
    Start-Work 'undo' @{ UndoLog = $d.FileName } {
        param($r)
        [System.Windows.Forms.MessageBox]::Show("Restored $($r.Restored), skipped $($r.Skipped).", 'Undo finished') | Out-Null
        $table.Clear()
    }
})


# ---------- subtitles (Get subtitles... button): dry-run lookup -> confirmation -> download ----------
function Show-SubsDone($r) {
    if (-not $r) { return }
    $m = "Downloaded $($r.Standard) standard and $($r.Sdh) SDH/HI subtitle file(s).`n`nRejected (wrong language / too short): $($r.Rejected). Failed: $($r.Failed). Already existed: $($r.Skipped)."
    if ($r.Cancelled) { $m += "`n`nCancelled before finishing." }
    if ($r.Stopped) { $m += "`n`n" + $r.Stopped }
    $m += "`n`nLog: $($r.Log)"
    [System.Windows.Forms.MessageBox]::Show($m, 'Get subtitles finished') | Out-Null
}
function Start-SubsDownload($plan) {
    if (-not $plan) { return }
    if ($plan.Cancelled) { Write-UiLog 'Subtitle lookup cancelled.'; return }
    $ns = [int]$plan.Std; $nh = [int]$plan.Sdh; $tot = $ns + $nh
    if ($tot -eq 0) {
        $m = 'No new English subtitles to download.'
        if ($plan.Limit) { $m += "`n`n" + $plan.Limit }
        [System.Windows.Forms.MessageBox]::Show($m + "`n`nSee the log below the table for each video.", 'Get subtitles') | Out-Null
        return
    }
    $est = Get-PRSubsEstimate $tot
    $m = "Download $ns standard and $nh SDH/HI English subtitle file(s) ($tot in total)?`n`nEstimated time: $est.`n`nThey are saved next to each video as <name>.en.srt and <name>.en.sdh.srt. Existing subtitle files are never overwritten. A log of every file is written to the Logs folder so they can be removed later."
    if ($plan.Limit) { $m += "`n`nNote: $($plan.Limit). The list is partial." }
    $ok = [System.Windows.Forms.MessageBox]::Show($m, 'Confirm subtitle download', 'YesNo', 'Question')
    if ($ok -ne 'Yes') { Write-UiLog 'Subtitle download cancelled.'; return }
    if (-not (Test-Path -LiteralPath $LogDir)) { [void](New-Item -ItemType Directory -Path $LogDir) }
    $logp = Join-Path $LogDir ("subtitles_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    Write-UiLog "Downloading $tot subtitle file(s)... (log: $logp)"
    Start-Work 'subsget' @{ Plan = $plan; Version = $AppVersion; LogPath = $logp } { param($r) Show-SubsDone $r }
}
function Start-AutoSubs($rows, [bool]$hi) {
    # "Auto Get Subtitles": after a Full Run, look up and download English subtitles for the files that were just renamed (no extra prompt; limits stop it cleanly)
    Write-UiLog 'Auto Get Subtitles: looking up English subtitles for the renamed videos...'
    Start-Work 'subsplan' @{ Rows = $rows; HighOnly = $hi; Std = $chkSubStd.Checked; Sdh = $chkSubSdh.Checked; Key = $txtKey.Text.Trim(); CachePath = $CachePath; SubsCache = $SubsCachePath; TvdbKey = $txtTvdb.Text.Trim(); TvdbPin = $txtPin.Text.Trim(); Source = [string]$cmbSource.SelectedItem; Version = $AppVersion } {
        param($plan)
        if (-not $plan -or $plan.Cancelled) { Write-UiLog 'Auto Get Subtitles: stopped.'; return }
        $tot = [int]$plan.Std + [int]$plan.Sdh
        if ($tot -eq 0) { $m = 'Auto Get Subtitles: no new English subtitles to download.'; if ($plan.Limit) { $m += ' ' + $plan.Limit + '.' }; Write-UiLog $m; return }
        if (-not (Test-Path -LiteralPath $LogDir)) { [void](New-Item -ItemType Directory -Path $LogDir) }
        $logp = Join-Path $LogDir ("subtitles_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        Write-UiLog "Auto Get Subtitles: downloading $tot subtitle file(s)... (log: $logp)"
        Start-Work 'subsget' @{ Plan = $plan; Version = $AppVersion; LogPath = $logp } {
            param($r)
            if (-not $r) { return }
            $m = "Auto Get Subtitles finished: $($r.Standard) standard and $($r.Sdh) SDH/HI downloaded, $($r.Rejected) rejected, $($r.Failed) failed, $($r.Skipped) already existed."
            if ($r.Cancelled) { $m += ' Stopped before finishing.' }
            if ($r.Stopped) { $m += ' ' + $r.Stopped }
            Write-UiLog "$m Log: $($r.Log)"
        }
    }
}
$btnSubs.Add_Click({
    if (-not $script:Rows -or $script:Mode -ne 'plan') { [System.Windows.Forms.MessageBox]::Show('Run Scan first, then use Get subtitles.', 'Renamr') | Out-Null; return }
    if (-not ($chkSubStd.Checked -or $chkSubSdh.Checked)) { [System.Windows.Forms.MessageBox]::Show('Tick "Get standard subtitles" and/or "Also get SDH / HI subtitles" in Setup first.', 'Renamr') | Out-Null; return }
    $withId = @($script:Rows | Where-Object { ($_.media_type -eq 'movie' -or $_.media_type -eq 'episode') -and [string]$_.tmdb_id }).Count
    if ($withId -eq 0) { [System.Windows.Forms.MessageBox]::Show('No scanned video has a movie/show id yet. Run Scan and check that titles were matched.', 'Renamr') | Out-Null; return }
    try { Save-Settings } catch { Write-UiLog "Could not save settings: $($_.Exception.Message)" }
    Write-UiLog 'Looking up English subtitles (dry run - nothing is downloaded yet)...'
    Start-Work 'subsplan' @{ Rows = $script:Rows; HighOnly = $chkHigh.Checked; Std = $chkSubStd.Checked; Sdh = $chkSubSdh.Checked; Key = $txtKey.Text.Trim(); CachePath = $CachePath; SubsCache = $SubsCachePath; TvdbKey = $txtTvdb.Text.Trim(); TvdbPin = $txtPin.Text.Trim(); Source = [string]$cmbSource.SelectedItem; Version = $AppVersion } { param($plan) Start-SubsDownload $plan }
})

# ---------- theme (System / Light / Dark) ----------
if (-not ('PRDwm' -as [type])) {
    try {
        Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class PRDwm {
  [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
  public static void SetDark(IntPtr hwnd, bool dark) {
    int v = dark ? 1 : 0;
    try { if (DwmSetWindowAttribute(hwnd, 20, ref v, 4) != 0) DwmSetWindowAttribute(hwnd, 19, ref v, 4); } catch { }
  }
}
'@ -ErrorAction Stop
    } catch { }
}
function C([string]$hex) { return [System.Drawing.ColorTranslator]::FromHtml($hex) }
$Themes = @{
    Light = @{ Back = [System.Drawing.SystemColors]::Control; Fore = [System.Drawing.SystemColors]::ControlText; Input = [System.Drawing.SystemColors]::Window
               InputFore = [System.Drawing.SystemColors]::WindowText; Button = $null; Border = (C '#ADADAD'); Grid = [System.Drawing.SystemColors]::Window
               Alt = (C '#F5F5F5'); Header = (C '#EAEAEA'); Lines = (C '#D8D8D8'); Sel = (C '#E5A00D'); SelFore = (C '#1E1E1E'); Log = [System.Drawing.SystemColors]::Window }
    Dark  = @{ Back = (C '#202124'); Fore = (C '#E8E8E8'); Input = (C '#2B2D31'); InputFore = (C '#F0F0F0'); Button = (C '#33363B'); Border = (C '#4A4D52')
               Grid = (C '#26282B'); Alt = (C '#2C2E32'); Header = (C '#33363B'); Lines = (C '#3A3D42'); Sel = (C '#E5A00D'); SelFore = (C '#1E1E1E'); Log = (C '#18191B') }
}
$Accent = C '#E5A00D'
function Get-SystemTheme {
    try {
        $v = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme
        if ($v -eq 0) { return 'Dark' }
    } catch { }
    return 'Light'
}
function Style-Button($b, $t, [bool]$dark, [bool]$primary) {
    if ($dark -or $primary) {
        $b.FlatStyle = 'Flat'; $b.UseVisualStyleBackColor = $false
        if ($primary) { $b.BackColor = $Accent; $b.ForeColor = (C '#1E1E1E'); $b.FlatAppearance.BorderColor = (C '#B97F00') }
        else { $b.BackColor = $t.Button; $b.ForeColor = $t.Fore; $b.FlatAppearance.BorderColor = $t.Border }
        $b.FlatAppearance.MouseOverBackColor = [System.Windows.Forms.ControlPaint]::Light($b.BackColor, 0.15)
        $b.FlatAppearance.MouseDownBackColor = [System.Windows.Forms.ControlPaint]::Dark($b.BackColor, 0.05)
    } else {
        $b.FlatStyle = 'Standard'; $b.UseVisualStyleBackColor = $true; $b.ForeColor = $t.Fore
    }
}
function Get-EffectiveTheme([string]$name) { if ($name -eq 'Light' -or $name -eq 'Dark') { return $name }; return (Get-SystemTheme) }
function Theme-Controls($parent, $t, [bool]$dark, $primary) {
    foreach ($c in $parent.Controls) {
        if ($c -is [System.Windows.Forms.Button]) { Style-Button $c $t $dark ($primary -contains $c) }
        elseif ($c -is [System.Windows.Forms.TextBox]) {
            $c.BackColor = $t.Input; $c.ForeColor = $t.InputFore
            if ($dark) { $c.BorderStyle = 'FixedSingle' } else { $c.BorderStyle = 'Fixed3D' }
        }
        elseif ($c -is [System.Windows.Forms.ComboBox]) {
            $c.BackColor = $t.Input; $c.ForeColor = $t.InputFore
            if ($dark) { $c.FlatStyle = 'Flat' } else { $c.FlatStyle = 'Standard' }
        }
        elseif ($c -is [System.Windows.Forms.CheckBox]) {
            $c.BackColor = $t.Back; $c.ForeColor = $t.Fore
            if ($dark) { $c.FlatStyle = 'Flat'; $c.FlatAppearance.BorderColor = $t.Border; $c.FlatAppearance.CheckedBackColor = $t.Input } else { $c.FlatStyle = 'Standard' }
        }
        elseif ($c -is [System.Windows.Forms.DataGridView]) { Theme-Grid $c $t $dark }
        elseif ($c -is [System.Windows.Forms.Label]) { $c.BackColor = $t.Back; $c.ForeColor = $t.Fore }
        elseif ($c -is [System.Windows.Forms.Panel]) { $c.BackColor = $t.Back; $c.ForeColor = $t.Fore; Theme-Controls $c $t $dark $primary }
        elseif ($c -is [System.Windows.Forms.ProgressBar]) { $c.BackColor = $t.Input; $c.ForeColor = $Accent }
    }
}
function Theme-Grid($g, $t, [bool]$dark) {
    $g.EnableHeadersVisualStyles = $false
    $g.BackgroundColor = $t.Grid; $g.GridColor = $t.Lines
    if ($dark) { $g.BorderStyle = 'FixedSingle' } else { $g.BorderStyle = 'Fixed3D' }
    $g.DefaultCellStyle.BackColor = $t.Grid; $g.DefaultCellStyle.ForeColor = $t.InputFore
    $g.DefaultCellStyle.SelectionBackColor = $t.Sel; $g.DefaultCellStyle.SelectionForeColor = $t.SelFore
    $g.AlternatingRowsDefaultCellStyle.BackColor = $t.Alt; $g.AlternatingRowsDefaultCellStyle.ForeColor = $t.InputFore
    $g.AlternatingRowsDefaultCellStyle.SelectionBackColor = $t.Sel; $g.AlternatingRowsDefaultCellStyle.SelectionForeColor = $t.SelFore
    $g.ColumnHeadersDefaultCellStyle.BackColor = $t.Header; $g.ColumnHeadersDefaultCellStyle.ForeColor = $t.Fore
    $g.ColumnHeadersDefaultCellStyle.SelectionBackColor = $t.Header; $g.ColumnHeadersDefaultCellStyle.SelectionForeColor = $t.Fore
    $g.ColumnHeadersBorderStyle = 'Single'
    $g.RowHeadersDefaultCellStyle.BackColor = $t.Header; $g.RowHeadersDefaultCellStyle.ForeColor = $t.Fore
}
function Theme-Window($frm, [bool]$dark) {
    if ($frm.IsHandleCreated -and ('PRDwm' -as [type])) {
        try { [PRDwm]::SetDark($frm.Handle, $dark); $frm.Width += 1; $frm.Width -= 1 } catch { }   # nudge so the title bar repaints
    }
}
function Apply-Theme([string]$name) {
    $eff = Get-EffectiveTheme $name; $script:ThemeEff = $eff
    $t = $Themes[$eff]; $dark = ($eff -eq 'Dark')
    $form.SuspendLayout()
    $form.BackColor = $t.Back; $form.ForeColor = $t.Fore
    Theme-Controls $form $t $dark @($btnScan, $btnRun)
    $txtLog.BackColor = $t.Log; $txtLog.ForeColor = $t.InputFore
    $setup.BackColor = $t.Back; $setup.ForeColor = $t.Fore; Theme-Controls $setup $t $dark @($btnSetupClose)
    $lblVersion.ForeColor = $t.Border
    $form.ResumeLayout(); $form.Refresh()
    Theme-Window $form $dark
    Theme-Window $setup $dark
}
$cmbTheme.Add_SelectedIndexChanged({
    Apply-Theme ([string]$cmbTheme.SelectedItem)
    if ($script:SettingsLoaded) { try { Save-Settings } catch { } }
})
$form.Add_HandleCreated({ Apply-Theme ([string]$cmbTheme.SelectedItem) })
$setup.Add_HandleCreated({ Apply-Theme ([string]$cmbTheme.SelectedItem) })


# ---------- Duplicates dialog ----------
function Show-DeleteConfirm($owner, $pl, [bool]$net, $t, [bool]$dark) {
    # themed confirmation: header with videos vs related files, grouped list with type and size, kept files, warning
    $sm = Get-PRDeleteSummary $pl.Items
    $script:DupFolders = [string[]]@([string[]](Get-PRFoldersToRemove -Paths ([string[]]@($pl.Items | ForEach-Object { [string]$_.Path })) -Roots @($txtMovies.Text.Trim(), $txtSeries.Text.Trim())) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($script:DupFolders.Count -gt 0) { $sm.Header += $(if ($script:DupFolders.Count -eq 1) { ' + 1 empty folder' } else { " + $($script:DupFolders.Count) empty folders" }) }
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Confirm delete - Renamr'; $f.Size = New-Object System.Drawing.Size(980, 640); $f.StartPosition = 'CenterParent'
    $f.MinimumSize = New-Object System.Drawing.Size(700, 450); $f.Font = $owner.Font; if ($owner.Icon) { $f.Icon = $owner.Icon }
    $f.MinimizeBox = $false; $f.MaximizeBox = $true; $f.ShowInTaskbar = $false
    $hdr = New-Object System.Windows.Forms.Label; $hdr.Location = New-Object System.Drawing.Point(12, 10); $hdr.Size = New-Object System.Drawing.Size(940, 26); $hdr.Anchor = 'Top,Left,Right'
    $hdr.Font = New-Object System.Drawing.Font -ArgumentList ([System.Drawing.FontFamily]$f.Font.FontFamily), ([single]($f.Font.Size + 3)), ([System.Drawing.FontStyle]::Bold); $hdr.Text = $sm.Header
    $f.Controls.Add($hdr)
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(12, 42); $grid.Size = New-Object System.Drawing.Size(940, 330); $grid.Anchor = 'Top,Bottom,Left,Right'
    $grid.ReadOnly = $true; $grid.AllowUserToAddRows = $false; $grid.AllowUserToDeleteRows = $false; $grid.AllowUserToResizeRows = $false
    $grid.RowHeadersVisible = $false; $grid.SelectionMode = 'FullRowSelect'; $grid.MultiSelect = $false
    foreach ($spec in @(@('Group', 160), @('Type', 70), @('Size', 80), @('File', 610))) {
        $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn; $c.Name = $spec[0]; $c.HeaderText = $spec[0]; $c.Width = $spec[1]; $c.SortMode = 'NotSortable'
        [void]$grid.Columns.Add($c)
    }
    $grid.Columns['File'].AutoSizeMode = 'Fill'
    $f.Controls.Add($grid)
    $keptLbl = New-Object System.Windows.Forms.Label; $keptLbl.Location = New-Object System.Drawing.Point(12, 380); $keptLbl.Size = New-Object System.Drawing.Size(940, 20); $keptLbl.Anchor = 'Bottom,Left,Right'
    $keptLbl.Text = "Keeping: $($pl.Kept.Count) file(s) in these groups"
    $f.Controls.Add($keptLbl)
    $keptBox = New-Object System.Windows.Forms.TextBox; $keptBox.Multiline = $true; $keptBox.ReadOnly = $true; $keptBox.ScrollBars = 'Vertical'; $keptBox.WordWrap = $false
    $keptBox.Location = New-Object System.Drawing.Point(12, 402); $keptBox.Size = New-Object System.Drawing.Size(940, 80); $keptBox.Anchor = 'Bottom,Left,Right'
    $keptBox.Text = (@($pl.Kept | ForEach-Object { '{0}   {1}' -f $_.Label, $_.Path }) -join "`r`n")
    $f.Controls.Add($keptBox)
    $warn = New-Object System.Windows.Forms.Label; $warn.Location = New-Object System.Drawing.Point(12, 490); $warn.Size = New-Object System.Drawing.Size(940, 60); $warn.Anchor = 'Bottom,Left,Right'
    $warn.Font = New-Object System.Drawing.Font($f.Font, [System.Drawing.FontStyle]::Bold)
    if ($net) { $warn.Text = 'These files are on a network drive and will be PERMANENTLY deleted (unless Synology Recycle Bin is enabled for this shared folder). This cannot be undone from Renamr.' }
    else { $warn.Text = 'Files go to the Windows Recycle Bin; restore them from there if needed.' }
    $warn.Text += '  Folders left empty are removed.  Every deletion is logged to Logs\deleted_<date>.csv, and the library is rescanned afterwards.'
    $f.Controls.Add($warn)
    $bDel = New-Object System.Windows.Forms.Button; $bDel.Text = 'Delete'; $bDel.Size = New-Object System.Drawing.Size(110, 32); $bDel.Location = New-Object System.Drawing.Point(724, 558); $bDel.Anchor = 'Bottom,Right'
    $bCancel = New-Object System.Windows.Forms.Button; $bCancel.Text = 'Cancel'; $bCancel.Size = New-Object System.Drawing.Size(110, 32); $bCancel.Location = New-Object System.Drawing.Point(842, 558); $bCancel.Anchor = 'Bottom,Right'
    $bDel.DialogResult = 'Yes'; $bCancel.DialogResult = 'Cancel'
    $f.AcceptButton = $bCancel; $f.CancelButton = $bCancel   # Enter and Esc both cancel; Delete needs a deliberate click
    $f.Controls.Add($bDel); $f.Controls.Add($bCancel)
    # rows, grouped by group label (items are already in group order: video then its sidecars)
    $shade = @($t.Grid, $t.Alt); $gn = -1; $last = $null
    foreach ($it in $pl.Items) {
        if ($it.Group -ne $last) { $gn++; $last = $it.Group }
        $ri = $grid.Rows.Add([object[]]@([string]$it.Label, [string]$it.Kind, [string](PR-FormatSize $it.Size), [string]$it.Path))
        $grid.Rows[$ri].DefaultCellStyle.BackColor = [System.Drawing.Color]$shade[[int]($gn % 2)]; $grid.Rows[$ri].DefaultCellStyle.ForeColor = $t.InputFore
        if ($it.Kind -eq 'sidecar') { $grid.Rows[$ri].Cells['File'].Style.Padding = New-Object System.Windows.Forms.Padding(18, 0, 0, 0) }
    }
    foreach ($fd in $script:DupFolders) {
        $ri = $grid.Rows.Add([object[]]@('(empty after delete)', 'folder', '', [string]$fd))
        $grid.Rows[$ri].DefaultCellStyle.BackColor = [System.Drawing.Color]$t.Grid; $grid.Rows[$ri].DefaultCellStyle.ForeColor = $t.InputFore
    }
    # theme
    $f.BackColor = $t.Back; $f.ForeColor = $t.Fore
    Theme-Controls $f $t $dark @()
    $keptBox.BorderStyle = 'FixedSingle'
    if ($net) { if ($dark) { $warn.ForeColor = (C '#FF8A65') } else { $warn.ForeColor = (C '#C62828') } } else { $warn.ForeColor = $t.Fore }
    # danger button
    $bDel.FlatStyle = 'Flat'; $bDel.UseVisualStyleBackColor = $false; $bDel.BackColor = (C '#C62828'); $bDel.ForeColor = [System.Drawing.Color]::White
    $bDel.FlatAppearance.BorderColor = (C '#8E0000'); $bDel.FlatAppearance.MouseOverBackColor = (C '#D84343'); $bDel.FlatAppearance.MouseDownBackColor = (C '#A31515')
    $f.Add_HandleCreated({ Theme-Window $f $dark })
    $f.Add_Shown({ $bCancel.Focus() | Out-Null; $grid.CurrentCell = $null; $grid.ClearSelection() })
    $res = $f.ShowDialog($owner)
    $f.Dispose()
    return ($res -eq 'Yes')
}
function Show-DuplicatesDialog {
    $groups = @(Get-PRDuplicateGroups $script:Rows)
    if ($groups.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('No duplicate or multiple-version groups in the current plan.', 'Duplicates') | Out-Null; return }
    $allPaths = [string[]]@($script:Rows | ForEach-Object { $_.old_path })
    $scIndex = Get-PRSidecarIndex $allPaths
    $t = $Themes[$script:ThemeEff]; if (-not $t) { $t = $Themes['Light'] }; $dark = ($script:ThemeEff -eq 'Dark')
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Manage duplicates - Renamr v$AppVersion"; $dlg.Size = New-Object System.Drawing.Size(1150, 620); $dlg.StartPosition = 'CenterParent'
    $dlg.MinimumSize = New-Object System.Drawing.Size(800, 400); $dlg.Font = $form.Font; if ($form.Icon) { $dlg.Icon = $form.Icon }
    $info = New-Object System.Windows.Forms.Label; $info.Location = New-Object System.Drawing.Point(12, 8); $info.Size = New-Object System.Drawing.Size(1110, 50); $info.Anchor = 'Top,Left,Right'
    $info.Text = "Tick every file you want to KEEP (several per group allowed; default: only the best = highest resolution, then largest). 'Keep all' ticks the whole group; unticking it goes back to the default. Res ending in * was read from inside the video file (always, or because the name has no resolution). Unticked files and their subtitles/.nfo are deleted; groups where everything is kept are skipped. Each group must keep at least one file."
    $dlg.Controls.Add($info)
    $dg = New-Object System.Windows.Forms.DataGridView
    $dg.Location = New-Object System.Drawing.Point(12, 62); $dg.Size = New-Object System.Drawing.Size(1110, 456); $dg.Anchor = 'Top,Bottom,Left,Right'
    $dg.AllowUserToAddRows = $false; $dg.AllowUserToDeleteRows = $false; $dg.RowHeadersVisible = $false; $dg.SelectionMode = 'FullRowSelect'; $dg.MultiSelect = $false
    $colKeep = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn; $colKeep.Name = 'Keep'; $colKeep.HeaderText = 'Keep'; $colKeep.Width = 45
    $colAll  = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn; $colAll.Name = 'KeepAll'; $colAll.HeaderText = 'Keep all'; $colAll.Width = 60
    [void]$dg.Columns.Add($colKeep); [void]$dg.Columns.Add($colAll)
    foreach ($spec in @(@('Group', 150), @('File', 520), @('Size', 75), @('Modified', 120), @('Res', 55), @('Ext', 50))) {
        $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn; $c.Name = $spec[0]; $c.HeaderText = $spec[0]; $c.Width = $spec[1]; $c.ReadOnly = $true
        [void]$dg.Columns.Add($c)
    }
    Set-FillColumns $dg @('Group', 'File', 'Size', 'Modified', 'Res', 'Ext')
    $dlg.Controls.Add($dg)
    $sum = New-Object System.Windows.Forms.Label; $sum.Location = New-Object System.Drawing.Point(12, 530); $sum.Size = New-Object System.Drawing.Size(760, 40); $sum.Anchor = 'Bottom,Left,Right'
    $dlg.Controls.Add($sum)
    $btnDel = New-Object System.Windows.Forms.Button; $btnDel.Text = 'Delete others...'; $btnDel.Size = New-Object System.Drawing.Size(140, 30); $btnDel.Location = New-Object System.Drawing.Point(870, 534); $btnDel.Anchor = 'Bottom,Right'
    $btnClose = New-Object System.Windows.Forms.Button; $btnClose.Text = 'Close'; $btnClose.Size = New-Object System.Drawing.Size(100, 30); $btnClose.Location = New-Object System.Drawing.Point(1022, 534); $btnClose.Anchor = 'Bottom,Right'
    $btnClose.DialogResult = 'Cancel'; $dlg.CancelButton = $btnClose
    $dlg.Controls.Add($btnDel); $dlg.Controls.Add($btnClose)
    # double buffering (protected property) - avoids flicker/slow repaint
    try { $dg.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic,Instance').SetValue($dg, $true, $null) } catch { }
    # fill rows once: one block per group, groups shaded alternately. All per-file data (size, sidecars) is computed
    # here and cached in Row.Tag, so checkbox events never touch the disk.
    $shade = @($t.Grid, $t.Alt)
    $byGroup = @{}
    $dg.SuspendLayout()
    for ($gn = 0; $gn -lt $groups.Count; $gn++) {
        $g = $groups[$gn]; $gid = [int]$g.Id
        $files = @()
        foreach ($p in @($g.Paths)) {
            $fi = New-Object IO.FileInfo($p); $exists = $fi.Exists
            $size = 0; $mod = ''; if ($exists) { $size = $fi.Length; $mod = $fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm') }
            $rh = PR-ResHint (PR-Base $p)
            if ($exists -and ($rh.Rank -eq 0 -or $chkProbe.Checked)) { $pr = PR-ProbeRes $p; if ($pr) { $rh = @{ Label = ($pr.Label + '*'); Rank = $pr.Rank } } }
            $files += [pscustomobject]@{ Path = $p; Size = $size; Mod = $mod; Res = $rh.Label; Rank = $rh.Rank; Ext = (PR-SplitExt $p)[1].ToLowerInvariant(); Exists = $exists }
        }
        $keep = [int](Select-PRDefaultKeep $files)
        $label = '#{0} {1}' -f $gid, $g.Kind
        $list = New-Object System.Collections.Generic.List[object]; $byGroup[$gid] = $list
        for ($i = 0; $i -lt $files.Count; $i++) {
            $f = $files[$i]; $sz = PR-FormatSize $f.Size; if (-not $f.Exists) { $sz = 'missing' }
            $scs = @([string[]](Get-PRSidecarsFor $f.Path $allPaths $scIndex) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }); $scBytes = 0.0; $scSizes = @()
            foreach ($sc in $scs) { $z = 0.0; try { $sfi = New-Object IO.FileInfo($sc); if ($sfi.Exists) { $z = [double]$sfi.Length } } catch { }; $scSizes += $z; $scBytes += $z }
            $ri = $dg.Rows.Add(($i -eq $keep), $false, $label, $f.Path, $sz, $f.Mod, $f.Res, $f.Ext)
            $row = $dg.Rows[$ri]
            $row.Tag = [pscustomobject]@{ Group = $gid; Label = $label; Path = $f.Path; Bytes = [double]$f.Size; Default = ($i -eq $keep); Sidecars = [string[]]$scs; SideSizes = [double[]]$scSizes; SideBytes = $scBytes; Res = $f.Res }
            $row.DefaultCellStyle.BackColor = $shade[$gn % 2]
            $row.DefaultCellStyle.ForeColor = $t.InputFore
            if ($i -eq 0) { $row.Cells['Group'].ToolTipText = "Target: $($g.Target)" }
            $list.Add($row)
        }
    }
    $dg.ResumeLayout()
    $script:DupBusy = $false
    $getPlan = {
        # list of videos to delete (+ their cached sidecars) based on the ticks; groups keeping nothing are reported, not deleted
        $sel = New-Object System.Collections.Generic.List[object]; $tagOf = @{}
        foreach ($row in $dg.Rows) { $tg = $row.Tag; $tagOf[$tg.Path] = $tg; $sel.Add([pscustomobject]@{ Group = $tg.Group; Label = $tg.Label; Path = $tg.Path; Keep = [bool]$row.Cells['Keep'].Value }) }
        $dp = Get-PRDeletePlan $sel.ToArray()
        $items = New-Object System.Collections.Generic.List[object]; $bytes = 0.0
        foreach ($d in $dp.Delete) {
            $tg = $tagOf[$d.Path]
            $items.Add([pscustomobject]@{ Path = $d.Path; Group = $d.Group; Label = $tg.Label; Kind = 'video'; Size = $tg.Bytes }); $bytes += $tg.Bytes + $tg.SideBytes
            for ($k = 0; $k -lt $tg.Sidecars.Count; $k++) { if ([string]::IsNullOrWhiteSpace([string]$tg.Sidecars[$k])) { continue }; $items.Add([pscustomobject]@{ Path = $tg.Sidecars[$k]; Group = $d.Group; Label = $tg.Label; Kind = 'sidecar'; Size = $tg.SideSizes[$k] }) }
        }
        # files kept in the groups that are being acted on
        $act = @{}; foreach ($d in $dp.Delete) { $act[[string]$d.Group] = $true }
        $kept = New-Object System.Collections.Generic.List[object]
        foreach ($row in $dg.Rows) { if ([bool]$row.Cells['Keep'].Value -and $act.ContainsKey([string]$row.Tag.Group)) { $kept.Add($row.Tag) } }
        return @{ Items = $items; Bytes = $bytes; Invalid = $dp.Invalid; Skipped = $dp.Skipped; Kept = $kept }
    }
    $refresh = {
        # cheap: reads cached Tag data only (no disk access, no restyling)
        $v = 0; $sc = 0; $bytes = 0.0; $skipped = 0; $bad = New-Object System.Collections.Generic.List[string]
        foreach ($gid in $byGroup.Keys) {
            $kept = 0; $drop = @()
            foreach ($r in $byGroup[$gid]) { if ([bool]$r.Cells['Keep'].Value) { $kept++ } else { $drop += $r.Tag } }
            if ($kept -eq 0) { $bad.Add($byGroup[$gid][0].Tag.Label); continue }
            if ($drop.Count -eq 0) { $skipped++; continue }
            foreach ($tg in $drop) { $v++; $sc += $tg.Sidecars.Count; $bytes += $tg.Bytes + $tg.SideBytes }
        }
        $txt = "$($groups.Count) groups ($skipped keep everything and are skipped). To delete: $(if ($v -eq 1) { '1 video' } else { "$v videos" }) + $(if ($sc -eq 1) { '1 related subtitle/.nfo file' } else { "$sc related subtitle/.nfo files" }) ($(PR-FormatSize $bytes))."
        if ($bad.Count) { $txt += '  NOT ALLOWED - no file kept in: ' + ($bad -join ', ') }
        $sum.Text = $txt
        $btnDel.Enabled = ($v -gt 0 -or $bad.Count -gt 0)
    }
    $dg.Add_CurrentCellDirtyStateChanged({ if ($dg.IsCurrentCellDirty) { [void]$dg.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit) } })
    $dg.Add_CellValueChanged({
        param($sender, $e)
        if ($script:DupBusy -or $e.RowIndex -lt 0) { return }   # ignore cascades from our own programmatic changes
        $script:DupBusy = $true
        try {
            $col = $dg.Columns[$e.ColumnIndex].Name; $row = $dg.Rows[$e.RowIndex]
            $same = $byGroup[$row.Tag.Group]   # only rows of the affected group are touched
            if ($col -eq 'Keep') {
                $allKept = $true; foreach ($r in $same) { if (-not [bool]$r.Cells['Keep'].Value) { $allKept = $false; break } }
                foreach ($r in $same) { if ([bool]$r.Cells['KeepAll'].Value -ne $allKept) { $r.Cells['KeepAll'].Value = $allKept } }
            } elseif ($col -eq 'KeepAll') {
                # per-group convenience: tick = keep every file; untick = back to the default (best file only)
                $v = [bool]$row.Cells['KeepAll'].Value
                foreach ($r in $same) { $r.Cells['KeepAll'].Value = $v; $r.Cells['Keep'].Value = ($v -or $r.Tag.Default) }
            } else { return }
        } finally { $script:DupBusy = $false }
        & $refresh
    })
    $btnDel.Add_Click({
        $dg.EndEdit() | Out-Null
        $pl = & $getPlan
        if ($pl.Invalid.Count) {
            [System.Windows.Forms.MessageBox]::Show($dlg, "Every group must keep at least one file. Tick a file to keep in:`n`n  " + ($pl.Invalid -join "`n  ") + "`n`nNothing was deleted.", 'Duplicates', 'OK', 'Warning') | Out-Null
            return
        }
        if ($pl.Items.Count -eq 0) { return }
        $net = @($pl.Items | Where-Object { Test-PRNetworkPath $_.Path }).Count -gt 0
        $okDel = $false
        try { $okDel = Show-DeleteConfirm $dlg $pl $net $t $dark } catch { [System.Windows.Forms.MessageBox]::Show("Could not open the delete confirmation. Nothing was deleted.`n`n$($_.Exception.Message)`nLine $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())", 'Renamr', 'OK', 'Error') | Out-Null; return }
        if (-not $okDel) { return }
        $script:DupDelete = $pl.Items
        $dlg.DialogResult = 'OK'; $dlg.Close()
    })
    # theme
    $dlg.BackColor = $t.Back; $dlg.ForeColor = $t.Fore
    Theme-Controls $dlg $t $dark @($btnDel)
    $dlg.Add_HandleCreated({ Theme-Window $dlg $dark })
    & $refresh
    $script:DupDelete = $null
    $dlg.Add_Shown({ $dg.CurrentCell = $null; $dg.ClearSelection() })
    if ($dlg.ShowDialog($form) -eq 'OK' -and $script:DupDelete) {
        if (-not (Test-Path -LiteralPath $LogDir)) { [void](New-Item -ItemType Directory -Path $LogDir) }
        $logp = Join-Path $LogDir ("deleted_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        $delItems = New-Object System.Collections.ArrayList
        foreach ($x in $script:DupDelete) { if ($null -ne $x -and -not [string]::IsNullOrWhiteSpace([string]$x.Path)) { [void]$delItems.Add($x) } }
        Write-UiLog "Deleting $($delItems.Count) file(s)..."
        Start-Work 'delete' @{ Items = $delItems.ToArray(); LogPath = $logp; Folders = [string[]]@($script:DupFolders) } {
            param($r)
            [System.Windows.Forms.MessageBox]::Show("Deleted $($r.Deleted) file(s), $(PR-FormatSize $r.Bytes); removed $($r.Folders) empty folder(s). Failed: $($r.Failed).`n`nLog: $($r.Log)`n`nRescanning now.", 'Duplicates') | Out-Null
            $btnScan.PerformClick()
        }
    }
    # not deleting: reflect the user's Keep ticks in the main grid shading
    if ($dlg.DialogResult -ne 'OK') {
        try { foreach ($r in $dg.Rows) { if ($r.Tag) { $script:DupMark[([string]$r.Tag.Path).ToLowerInvariant()] = $(if ([bool]$r.Cells['Keep'].Value) { 'keep' } else { 'del' }) } }; Update-DupSortKeys; $grid.Invalidate() } catch { }
    }
    $dlg.Dispose()
}
$btnDups.Add_Click({
    if (-not $script:Rows -or $script:Mode -ne 'plan') { [System.Windows.Forms.MessageBox]::Show('Run Scan first.', 'Renamr') | Out-Null; return }
    Show-DuplicatesDialog
})

# ---------- start ----------
$st = Load-Settings
$txtMovies.Text = $st.MoviesRoot; $txtSeries.Text = $st.SeriesRoot; $chkHigh.Checked = $st.HighOnly; $txtKey.Text = $st.Key; $txtTvdb.Text = $st.TvdbKey; $txtPin.Text = $st.TvdbPin; $cmbSource.SelectedItem = $st.Source; $chkProbe.Checked = $st.ProbeAlways; $chkScanProbe.Checked = $st.ProbeScan
$chkSubStd.Checked = $st.SubsStd; $chkSubSdh.Checked = $st.SubsSdh; $chkSubs.Checked = $st.SubsEnable; $chkAutoSubs.Checked = $st.AutoSubs; $chkFolderLoose.Checked = $st.FolderLoose
Update-SubsUi
$cmbTheme.SelectedItem = $st.Theme
Apply-Theme $st.Theme
$script:SettingsLoaded = $true
Write-UiLog "Renamr v$AppVersion ready."
Write-UiLog '1) Choose your Movies and/or Series folder and enter your API keys in Setup.  2) Scan.  3) Review the results, then Full Run.'
$form.Add_FormClosing({ if ($btnCancel.Enabled) { $Sync.Cancel = $true } })
[void]$form.ShowDialog()
