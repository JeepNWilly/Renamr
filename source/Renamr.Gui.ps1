# Copyright (C) 2026 JeepNWilly
# Renamr is free software: you can redistribute it and/or modify it under the terms of the
# GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, or (at your option) any later version. It comes with no warranty.
# See the LICENSE file in the repository root or <https://www.gnu.org/licenses/>.
# Renamr GUI (WinForms). Windows PowerShell 5.1. The engine runs in a background runspace so the UI stays responsive.
# In a built Renamr.ps1 / .exe, build_exe.ps1 inserts the engine source into $PR_EMBEDDED_ENGINE below.
$PR_EMBEDDED_ENGINE = $null  #@@ENGINE@@
$AppVersion = 'dev'  #@@VERSION@@
$AppName = 'Renamr Plus'   # the name shown to the user (the exe, files and folders keep the name Renamr)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------- locate app folder and engine ----------
$AppDir = $PSScriptRoot
if (-not $AppDir) { $AppDir = Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
# running from the source folder: use the app folder above it (settings, API key, cache, logs)
if ((Split-Path -Leaf $AppDir) -eq 'source' -and -not (Test-Path -LiteralPath (Join-Path $AppDir 'settings.json')) -and (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $AppDir) 'settings.json'))) { $AppDir = Split-Path -Parent $AppDir }
$EngineCode = $PR_EMBEDDED_ENGINE
if (-not $EngineCode) {
    foreach ($c in (Join-Path $AppDir 'Renamr.Engine.ps1'), (Join-Path $AppDir 'source\Renamr.Engine.ps1')) {
        if (Test-Path -LiteralPath $c) { $EngineCode = [IO.File]::ReadAllText($c); break }
    }
}
if (-not $EngineCode) { [System.Windows.Forms.MessageBox]::Show("Renamr.Engine.ps1 not found next to the app.", $AppName) | Out-Null; return }
. ([scriptblock]::Create($EngineCode))   # main thread uses CSV/export helpers

$SettingsPath = Join-Path $AppDir 'settings.json'
$CachePath    = Join-Path $AppDir 'tmdb_cache.json'
$LogDir       = Join-Path $AppDir 'Logs'
$SubsCachePath = Join-Path $AppDir 'subs_cache.json'
$OverridesPath = Join-Path $AppDir 'match_overrides.json'   # remembered Choose match picks
try { [void](Import-PROverrides $OverridesPath) } catch { }

# ---------- settings (TMDB key protected with Windows DPAPI for the current user) ----------
function Load-Settings {
    $s = @{ MoviesRoot = ''; SeriesRoot = ''; HighOnly = $true; Key = ''; Theme = 'System'; TvdbKey = ''; TvdbPin = ''; Source = 'Movies: TMDB, TV: TVDB'; ProbeAlways = $false; ProbeScan = $true; SubsEnable = $false; SubsStd = $true; SubsSdh = $true; AutoSubs = $false; FolderLoose = $true; RemoveEmpty = $true; OnlyTicked = $false; DeleteNfo = $true; RecycleDupSubs = $true; FixSeasons = $true; SeasonFormat = 'Season {NN}'; UsTitles = $true }
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
            if ($null -ne $j.RemoveEmpty) { $s.RemoveEmpty = [bool]$j.RemoveEmpty }
            if ($null -ne $j.OnlyTicked) { $s.OnlyTicked = [bool]$j.OnlyTicked }
            if ($null -ne $j.DeleteNfo) { $s.DeleteNfo = [bool]$j.DeleteNfo }   # older settings without the key: on
            if ($null -ne $j.RecycleDupSubs) { $s.RecycleDupSubs = [bool]$j.RecycleDupSubs }   # older settings without the key: on
            if ($null -ne $j.FixSeasons) { $s.FixSeasons = [bool]$j.FixSeasons }
            if ($null -ne $j.UsTitles) { $s.UsTitles = [bool]$j.UsTitles }   # older settings without the key: on   # older settings without the key: on
            if ($j.SeasonFormat -and -not (Test-PRSeasonFormat ([string]$j.SeasonFormat))) { $s.SeasonFormat = [string]$j.SeasonFormat }   # invalid or missing: the default
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
    $o = [ordered]@{ ProbeAlways = $chkProbe.Checked; ProbeScan = $chkScanProbe.Checked; SubsEnable = $chkSubs.Checked; SubsStd = $chkSubStd.Checked; SubsSdh = $chkSubSdh.Checked; AutoSubs = $chkAutoSubs.Checked; FolderLoose = $chkFolderLoose.Checked; RemoveEmpty = $chkRemoveEmpty.Checked; OnlyTicked = $chkOnlyTicked.Checked; DeleteNfo = $chkDeleteNfo.Checked; RecycleDupSubs = $chkRecycleDupSubs.Checked; FixSeasons = $chkFixSeasons.Checked; SeasonFormat = $txtSeasonFmt.Text.Trim(); UsTitles = $chkUsTitles.Checked; Source = [string]$cmbSource.SelectedItem; TvdbKeyProtected = $tk; TvdbPinProtected = $tp; MoviesRoot = $txtMovies.Text.Trim(); SeriesRoot = $txtSeries.Text.Trim(); HighOnly = $chkHigh.Checked; Theme = [string]$cmbTheme.SelectedItem; TmdbKeyProtected = $prot }
    [IO.File]::WriteAllText($SettingsPath, ($o | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
}

# ---------- form ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = "$AppName v$AppVersion"; $form.Size = New-Object System.Drawing.Size(1250, 820); $form.StartPosition = 'CenterScreen'
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
$chkHigh.Add_CheckedChanged({ if ($script:Rows -and $script:Mode -eq 'plan' -and (Get-Command Sync-AcceptColumn -ErrorAction SilentlyContinue)) { Sync-AcceptColumn } })
$btnSetup = New-Button 'Setup...' 1130 74 90; $btnSetup.Anchor = 'Top,Right'

# ---------- Setup window (API keys, PIN, theme, real-resolution options). Controls live here but are used exactly like before ----------
$setup = New-Object System.Windows.Forms.Form
$setup.Text = "$AppName - Setup"; $setup.ClientSize = New-Object System.Drawing.Size(560, 558); $setup.StartPosition = 'CenterParent'
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
$lblSubLimits = New-Label 'Service limits: the free service allows about 200 subtitle downloads per hour, and lookups are rate-limited too. When a limit is reached, Renamr Plus stops cleanly and tells you roughly when to try again; the next run continues where it left off. Existing subtitle files are never overwritten.' 40 416
$lblSubLimits.AutoSize = $true; $lblSubLimits.MaximumSize = New-Object System.Drawing.Size(500, 0)
$lblSetupNote = New-Label 'Keys are stored encrypted for your Windows user. Changes are saved when you close this window.' 16 498
foreach ($c in @($setup.Controls)) { if ($c.Top -ge 260) { $c.Top += 56 } }   # room for the empty-folders and ticked-rows options below the folder option
$setup.ClientSize = New-Object System.Drawing.Size(560, 614)
$chkOnlyTicked = New-Object System.Windows.Forms.CheckBox; $chkOnlyTicked.Text = 'Full Run applies only ticked rows (tick Accept, or Accept all per view)'; $chkOnlyTicked.Location = New-Object System.Drawing.Point(16, 282); $chkOnlyTicked.AutoSize = $true; $chkOnlyTicked.Checked = $false; $setup.Controls.Add($chkOnlyTicked)
$chkRemoveEmpty = New-Object System.Windows.Forms.CheckBox; $chkRemoveEmpty.Text = 'Remove empty folders after Full Run (only inside the Movies / Series folders; Undo recreates them)'; $chkRemoveEmpty.Location = New-Object System.Drawing.Point(16, 254); $chkRemoveEmpty.AutoSize = $true; $chkRemoveEmpty.Checked = $true; $setup.Controls.Add($chkRemoveEmpty)
foreach ($c in @($setup.Controls)) { if ($c.Top -ge 300) { $c.Top += 28 } }   # room for the .nfo option
$chkDeleteNfo = New-Object System.Windows.Forms.CheckBox; $chkDeleteNfo.Text = 'Delete .nfo files during Full Run (sent to the Recycle Bin; never on drives without one)'; $chkDeleteNfo.Location = New-Object System.Drawing.Point(16, 310); $chkDeleteNfo.AutoSize = $true; $chkDeleteNfo.Checked = $true; $setup.Controls.Add($chkDeleteNfo)
foreach ($c in @($setup.Controls)) { if ($c.Top -ge 328) { $c.Top += 28 } }   # room for the duplicate-subtitle option
$chkRecycleDupSubs = New-Object System.Windows.Forms.CheckBox; $chkRecycleDupSubs.Text = 'Recycle duplicate subtitles during Full Run (extra copies of a language already placed; Recycle Bin only)'; $chkRecycleDupSubs.Location = New-Object System.Drawing.Point(16, 338); $chkRecycleDupSubs.AutoSize = $true; $chkRecycleDupSubs.Checked = $true; $setup.Controls.Add($chkRecycleDupSubs)
foreach ($c in @($setup.Controls)) { if ($c.Top -ge 356) { $c.Top += 28 } }   # room for the season folder option
$chkFixSeasons = New-Object System.Windows.Forms.CheckBox; $chkFixSeasons.Text = 'Standardize season folder names (Season 1, S1, season1 ... renamed in place to the format below)'; $chkFixSeasons.Location = New-Object System.Drawing.Point(16, 366); $chkFixSeasons.AutoSize = $true; $chkFixSeasons.Checked = $true; $setup.Controls.Add($chkFixSeasons)
foreach ($c in @($setup.Controls)) { if ($c.Top -ge 384) { $c.Top += 30 } }   # room for the season folder format
$lblSeasonFmt = New-Object System.Windows.Forms.Label; $lblSeasonFmt.Text = 'Season folder format:'; $lblSeasonFmt.Location = New-Object System.Drawing.Point(34, 397); $lblSeasonFmt.AutoSize = $true; $setup.Controls.Add($lblSeasonFmt)
$txtSeasonFmt = New-Object System.Windows.Forms.TextBox; $txtSeasonFmt.Location = New-Object System.Drawing.Point(160, 394); $txtSeasonFmt.Width = 130; $txtSeasonFmt.Text = 'Season {NN}'; $setup.Controls.Add($txtSeasonFmt)
$lblSeasonPrev = New-Object System.Windows.Forms.Label; $lblSeasonPrev.Location = New-Object System.Drawing.Point(298, 397); $lblSeasonPrev.AutoSize = $true; $setup.Controls.Add($lblSeasonPrev)
$tipSeasonFmt = New-Object System.Windows.Forms.ToolTip; $tipSeasonFmt.SetToolTip($txtSeasonFmt, 'Tokens: {N} = 1, {NN} = 01, {NNN} = 001. Example: Season {NN} -> Season 01, S{NN} -> S01')
function Update-SeasonPreview {
    $why = Test-PRSeasonFormat $txtSeasonFmt.Text
    if ($why) { $lblSeasonPrev.Text = 'Invalid: ' + $why; $lblSeasonPrev.ForeColor = [System.Drawing.Color]::Firebrick }
    else { $lblSeasonPrev.Text = 'Preview: ' + (PR-FormatSeason 1 $txtSeasonFmt.Text) + ', ' + (PR-FormatSeason 12 $txtSeasonFmt.Text); $lblSeasonPrev.ForeColor = $chkFixSeasons.ForeColor }
}
$txtSeasonFmt.Add_TextChanged({ Update-SeasonPreview })
$chkFixSeasons.Add_CheckedChanged({ $txtSeasonFmt.Enabled = $chkFixSeasons.Checked })
foreach ($c in @($setup.Controls)) { if ($c.Top -ge 420) { $c.Top += 28 } }   # room for Use US titles
$chkUsTitles = New-Object System.Windows.Forms.CheckBox; $chkUsTitles.Text = 'Use US titles (search in US English and name films and shows by their US release title)'; $chkUsTitles.Location = New-Object System.Drawing.Point(16, 426); $chkUsTitles.AutoSize = $true; $chkUsTitles.Checked = $true; $setup.Controls.Add($chkUsTitles)
$chkUsTitles.Add_CheckedChanged({ $script:PR_US_TITLES = [bool]$chkUsTitles.Checked; $Sync.UsTitles = $script:PR_US_TITLES })
$setup.Add_FormClosing({
    $why = Test-PRSeasonFormat $txtSeasonFmt.Text
    if ($why) { [System.Windows.Forms.MessageBox]::Show("Season folder format '$($txtSeasonFmt.Text)' is not valid:`n$why`n`nThe default 'Season {NN}' is used instead.", $AppName, 'OK', 'Error') | Out-Null; $txtSeasonFmt.Text = 'Season {NN}' }
    else { $txtSeasonFmt.Text = $txtSeasonFmt.Text.Trim() }
})
$setup.ClientSize = New-Object System.Drawing.Size(560, 756)
$btnSetupClose = New-Button 'Close' 454 716 90; $setup.AcceptButton = $btnSetupClose; $setup.CancelButton = $btnSetupClose; $btnSetupClose.DialogResult = 'OK'
$script:UiHost = $form
$btnScan   = New-Button 'Scan' 12 112 130
$btnRun    = New-Button 'Full Run' 150 112 100
$btnUndo   = New-Button 'Undo...' 258 112 90
$btnExport = New-Button 'Export plan CSV...' 356 112 140
$btnCancel = New-Button 'Stop' 504 112 80; $btnCancel.Enabled = $false   # halts whatever is running (Scan, Full Run, Undo, subtitles) after the current file
$btnDups = New-Button 'Duplicates...' 592 112 100; $btnDups.Enabled = $false
$btnMatch = New-Button 'Choose match...' 828 112 120; $btnMatch.Enabled = $false   # pick the right movie/show for any movie or episode row (also: double-click the row); remembered in match_overrides.json
$btnAcceptAll = New-Button 'Accept all' 792 74 95; $btnAcceptAll.Enabled = $false   # ticks Accept on every low-confidence movie/show in the current view
$btnClearAcc = New-Button 'Clear accepts' 893 74 105; $btnClearAcc.Enabled = $false
$btnSubs = New-Button 'Get subtitles...' 700 112 120; $btnSubs.Visible = $false   # shown only when subtitle download is enabled in Setup (Update-SubsUi)

$lblShow = New-Label 'Show:' 996 118; $lblShow.Anchor = 'Top,Right'   # right-justified on the button row
$cmbFilter = New-Object System.Windows.Forms.ComboBox; $cmbFilter.DropDownStyle = 'DropDownList'; $cmbFilter.Location = New-Object System.Drawing.Point(1040, 114); $cmbFilter.Width = 180; $cmbFilter.Anchor = 'Top,Right'
@('All', 'Low confidence - review', 'Will move - high', 'Will move - low', 'Multiple versions', 'Duplicates / collisions', 'Unmatched / left in place', 'Already correctly named', 'Folder case fixes', 'NFO files to delete', 'Duplicate subtitles to recycle', 'Season folder fixes') | ForEach-Object { [void]$cmbFilter.Items.Add($_) }
$cmbFilter.SelectedIndex = 0; $form.Controls.Add($cmbFilter)
$lblSearch = New-Label 'Search:' 490 80; $txtSearch = New-Text 545 76 235; $txtSearch.Anchor = 'Top,Left'   # sits on the Name source row, right of 'Only high-confidence'

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(12, 150); $grid.Size = New-Object System.Drawing.Size(1208, 430); $grid.Anchor = 'Top,Bottom,Left,Right'
$grid.ReadOnly = $false; $grid.AllowUserToAddRows = $false; $grid.AllowUserToDeleteRows = $false; $grid.RowHeadersVisible = $false   # only the Accept column can be edited (set in Fill-Table)
$grid.SelectionMode = 'FullRowSelect'; $grid.AutoSizeColumnsMode = 'None'; $grid.AutoSizeRowsMode = 'None'; $grid.AllowUserToResizeRows = $false
try { $grid.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic,Instance').SetValue($grid, $true, $null) } catch { }   # less flicker and faster painting on big tables
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
[void]$table.Columns.Add('accept', [bool])
foreach ($c in 'status', 'confidence', 'media_type', 'old_name', 'new_name', 'note', 'tmdb_id', 'old_path', 'new_path', 'dup_sort', 'dup_flag', 'group_key', 'review', 'case_rep', 'tick') { [void]$table.Columns.Add($c) }
$grid.DataSource = $table
$script:Rows = $null; $script:Mode = 'plan'

function Get-Status($r) {
    $n = [string]$r.note
    if ($n.StartsWith('nfo: delete')) { return 'nfo: delete' }
    if ($n -like '*DUPLICATE*' -or $n -like '*COLLISION*') { return 'duplicate/collision' }
    if ($n.StartsWith('season folder:')) { return 'season folder' }
    if ($n -like '*already correctly named*') { return 'already named' }
    if (-not $r.new_path) { return 'unmatched/left' }
    if (Test-PRCaseOnly $r) { return 'folder case' }
    if ($n -like '*MULTIPLE VERSIONS*') { return 'move: multiple versions' }
    return 'move: ' + $r.confidence
}
function Get-RowNote($r) {
    # the note plus what Full Run will do differently: option off in Setup, or unticked by you
    $n = [string]$r.note; $off = Get-PROptionOff $r
    if ($off) { return "[not done: '$off' is off in Setup] " + $n }
    if (Test-PRSkipped $r) { return '[unticked: Full Run leaves this as is] ' + $n }
    return $n
}
function Get-RowCells($r, [bool]$hi) {
    # everything the grid shows for one plan row, in one pass (same results as Get-Status, Get-RowNote, Test-PRWillAct, Test-PRReviewable)
    $s4 = Get-PRRowState $r $hi; $n = [string]$r.note; $o = [string]$r.old_path; $nw = [string]$r.new_path
    if ($n.StartsWith('nfo: delete')) { $st = 'nfo: delete' }
    elseif ($n -like '*DUPLICATE*' -or $n -like '*COLLISION*') { $st = 'duplicate/collision' }
    elseif ($n.StartsWith('season folder:')) { $st = 'season folder' }
    elseif ($n -like '*already correctly named*') { $st = 'already named' }
    elseif (-not $r.new_path) { $st = 'unmatched/left' }
    elseif ($nw -and $o -ieq $nw -and $o -cne $nw -and $o.Substring($o.LastIndexOf('\') + 1) -ceq $nw.Substring($nw.LastIndexOf('\') + 1)) { $st = 'folder case' }
    elseif ($n -like '*MULTIPLE VERSIONS*') { $st = 'move: multiple versions' }
    else { $st = 'move: ' + $r.confidence }
    if ($s4[1]) { $note = "[not done: '$($s4[1])' is off in Setup] " + $n } elseif ($s4[3]) { $note = '[unticked: Full Run leaves this as is] ' + $n } else { $note = $n }
    $rev = ([bool]$r.group_key -and $r.media_type -ne 'sidecar' -and $r.confidence -ne 'high' -and ([bool]$r.new_path -or $n.StartsWith('unmatched')))
    return @($s4[2], $st, $note, $rev, [bool]($s4[0] -and -not $s4[1]))
}
function Leaf([string]$p) { if (-not $p) { return '' }; return [System.IO.Path]::GetFileName($p) }
function Fill-Table($rows, [string]$mode) {
    # fast fill: the grid is unbound while the rows load in one batch, the sort and filter are set before binding (one index build),
    # and no column measures its cells (the narrow columns are sized once from the few distinct values)
    $plan = ($mode -ne 'undo'); $hi = [bool]$chkHigh.Checked; $script:RowIdxOf = $null
    $rl = @($rows)
    $grid.SuspendLayout()
    try {
        $grid.DataSource = $null
        $dv = $table.DefaultView; $dv.RowFilter = ''; $dv.Sort = ''
        $table.BeginLoadData(); $table.Clear()
        # duplicate groups: every member takes the position of its first member, keeper first (see Update-DupSortKeys)
        $pos = @{}; $anchor = @{}
        if ($plan -and $script:Mode -eq 'plan' -and $script:DupGroup.Count -gt 0) {
            for ($i = 0; $i -lt $rl.Count; $i++) { $pos[([string]$rl[$i].old_path).ToLowerInvariant()] = $i }
            foreach ($k in $script:DupGroup.Keys) { if ($pos.ContainsKey($k)) { $g = $script:DupGroup[$k]; if (-not $anchor.ContainsKey($g) -or $pos[$k] -lt $anchor[$g]) { $anchor[$g] = $pos[$k] } } }
        }
        $wst = @{}; $wid = ''
        for ($i = 0; $i -lt $rl.Count; $i++) {
            $r = $rl[$i]
            if (-not $plan) { $vals = @($false, 'undo', '', '', (Leaf $r.new_path), (Leaf $r.old_path), "moved $($r.moved_at)", '', $r.new_path, $r.old_path, ('{0:D7}0{0:D7}' -f $i), '', '', '', '', '') }
            else {
                $rc = Get-RowCells $r $hi; $st = $rc[1]
                $lp = ([string]$r.old_path).ToLowerInvariant(); $a = $i; $rk = 0; $fl = ''
                if ($anchor.Count -gt 0 -and $script:DupGroup.ContainsKey($lp)) { $a = $anchor[$script:DupGroup[$lp]]; $fl = '1'; if ($script:DupMark[$lp] -eq 'del') { $rk = 1 } }
                $op = [string]$r.old_path; $np = [string]$r.new_path
                $vals = @($rc[0], $st, $(if ($st -eq 'already named') { '' } else { $r.confidence }), $r.media_type, $(if ($op) { [IO.Path]::GetFileName($op) } else { '' }), $(if ($np) { [IO.Path]::GetFileName($np) } else { '' }), $rc[2], $r.tmdb_id, $r.old_path, $r.new_path, ('{0:D7}{1}{2:D7}' -f $a, $rk, $i), $fl, [string]$r.group_key, $(if ($rc[3]) { '1' } else { '' }), [string]$r.case_rep, $(if ($rc[4]) { '1' } else { '' }))
                $wst[[string]$vals[1] + "`t" + [string]$vals[2] + "`t" + [string]$vals[3]] = 1
                if (([string]$r.tmdb_id).Length -gt $wid.Length) { $wid = [string]$r.tmdb_id }
            }
            [void]$table.LoadDataRow([object[]]$vals, $true)
        }
        $table.EndLoadData()
        $dv.Sort = 'dup_sort ASC'   # original order, but the copies of a duplicate group stay together (best first)
        try { $dv.RowFilter = (Get-FilterText) } catch { $dv.RowFilter = '' }
        $grid.DataSource = $table
        $w = @{ accept = 58; status = 140; confidence = 75; media_type = 70; old_name = 380; new_name = 380; note = 400; tmdb_id = 60; old_path = 100; new_path = 100 }
        foreach ($col in $grid.Columns) { $col.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::None; if ($w.ContainsKey($col.Name)) { $col.Width = $w[$col.Name] }; $col.SortMode = 'Automatic' }
        Set-FillColumns $grid @('old_name', 'new_name', 'note')
        foreach ($cn in 'old_path', 'new_path', 'dup_sort', 'dup_flag', 'group_key', 'review', 'case_rep', 'tick') { $grid.Columns[$cn].Visible = $false }
        foreach ($col in $grid.Columns) { $col.ReadOnly = ($col.Name -ne 'accept') }
        $grid.Columns['accept'].HeaderText = 'Accept'; $grid.Columns['accept'].Visible = $plan; $grid.Columns['accept'].ToolTipText = 'Ticked = Full Run will do this row (rename, move, recycle). Untick to leave that file / folder (or that movie / show with its subtitles) as is; tick a low-confidence match to accept it'
        # size the narrow columns once, to fit their header and the widest value (what AllCells did, without measuring 4000+ rows on every change)
        $vals = @{ status = @(); confidence = @(); media_type = @(); tmdb_id = @($wid) }
        if (-not $plan) { $vals.status = @('undo') }
        foreach ($k in $wst.Keys) { $p = $k.Split("`t"); $vals.status += $p[0]; $vals.confidence += $p[1]; $vals.media_type += $p[2] }
        $cf = $grid.DefaultCellStyle.Font; if (-not $cf) { $cf = $grid.Font }; $hf = $grid.ColumnHeadersDefaultCellStyle.Font; if (-not $hf) { $hf = $grid.Font }
        foreach ($cn in 'status', 'confidence', 'media_type', 'tmdb_id') {
            $mx = [System.Windows.Forms.TextRenderer]::MeasureText([string]$grid.Columns[$cn].HeaderText, $hf).Width + 22   # room for the sort arrow
            foreach ($v in $vals[$cn]) { if ($v) { $m = [System.Windows.Forms.TextRenderer]::MeasureText([string]$v, $cf).Width + 8; if ($m -gt $mx) { $mx = $m } } }
            $grid.Columns[$cn].Width = $mx
        }
    } finally { $grid.ResumeLayout() }
    $lblStatus.Text = "$($table.DefaultView.Count) of $($table.Rows.Count) rows shown"
    $grid.CurrentCell = $null; $grid.ClearSelection()
}
function Get-FilterText {
    $f = @()
    switch ($cmbFilter.SelectedItem) {
        'Low confidence - review'   { $f += "review = '1'" }
        'Will move - high'          { $f += "status = 'move: high'" }
        'Will move - low'           { $f += "status = 'move: low'" }
        'Multiple versions'         { $f += "status = 'move: multiple versions'" }
        'Duplicates / collisions'   { $f += "(status = 'duplicate/collision' OR dup_flag = '1')" }   # includes the green keeper rows of each group
        'Unmatched / left in place' { $f += "status = 'unmatched/left'" }
        'Already correctly named'   { $f += "status = 'already named'" }
        'Folder case fixes'         { $f += "status = 'folder case' AND case_rep = '1'" }   # one row per folder
        'NFO files to delete'       { $f += "status = 'nfo: delete'" }
        'Season folder fixes'       { $f += "status = 'season folder'" }   # one row per folder
        'Duplicate subtitles to recycle' { $f += "status = 'duplicate/collision' AND note LIKE '%will be recycled%'" }
    }
    $q = $txtSearch.Text.Trim()
    if ($q) {
        $e = ($q -replace "'", "''") -replace '([\[\]\*%])', '[$1]'
        $f += "(old_path LIKE '%$e%' OR new_path LIKE '%$e%' OR note LIKE '%$e%')"
    }
    return ($f -join ' AND ')
}
function Apply-Filter {
    # the DataView filters natively; the grid is only redrawn once (no column measures its cells)
    $ft = Get-FilterText
    if ($table.DefaultView.RowFilter -ne $ft) {
        $grid.SuspendLayout()
        try { try { $table.DefaultView.RowFilter = $ft } catch { $table.DefaultView.RowFilter = '' } } finally { $grid.ResumeLayout() }
        $grid.CurrentCell = $null; $grid.ClearSelection()
    }
    $lblStatus.Text = "$($table.DefaultView.Count) of $($table.Rows.Count) rows shown"
}
function Invoke-BulkTableEdit([scriptblock]$Edit) {
    # many cell changes on the bound table: one refresh at the end instead of one per cell; the scroll position and sort stay
    $top = -1; try { $top = $grid.FirstDisplayedScrollingRowIndex } catch { }
    $grid.SuspendLayout(); $table.BeginLoadData()
    try { & $Edit } finally {
        $table.EndLoadData(); $grid.ResumeLayout()
        if ($top -ge 0 -and $grid.Rows.Count -gt 0) { try { $grid.FirstDisplayedScrollingRowIndex = [math]::Min($top, $grid.Rows.Count - 1) } catch { } }
    }
}
# ---------- duplicate shading in the main grid ----------
# green = the copy that would be kept, orange = copies that would be deleted (nothing is deleted until Duplicates > Delete others)
$script:DupMark = @{}; $script:DupGroup = @{}
function Update-DupSortKeys {
    # key = original position, except that every member of a duplicate group takes the position of its first member, keeper first
    Invoke-BulkTableEdit {
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

# ---------- Accept / Choose match for low-confidence rows ----------
# Accept is unticked after every scan; ticking it on one row ticks the whole movie (with its subtitles) or the whole show
$script:AcceptBusy = $false
function Find-PlanRow([string]$oldPath) {
    # indexed: rebuilt when the plan list changes (Fill-Table clears it); first row with that path, as a plain search would find
    if (-not $script:Rows) { return $null }
    if (-not $script:RowIdxOf -or -not [object]::ReferenceEquals($script:RowIdxOf, $script:Rows)) {
        $ix = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($r in $script:Rows) { $k = [string]$r.old_path; if (-not $ix.ContainsKey($k)) { $ix[$k] = $r } }
        $script:RowIdx = $ix; $script:RowIdxOf = $script:Rows
    }
    $hit = $null; if ($script:RowIdx.TryGetValue($oldPath, [ref]$hit) -and $hit.old_path -eq $oldPath) { return $hit }
    foreach ($r in $script:Rows) { if ($r.old_path -eq $oldPath) { return $r } }; return $null
}
$grid.Add_CellBeginEdit({ param($s, $e)
    if ($grid.Columns[$e.ColumnIndex].Name -ne 'accept' -or $script:Mode -ne 'plan') { $e.Cancel = $true; return }
    $dv = $grid.Rows[$e.RowIndex].DataBoundItem
    if (-not $dv -or [string]$dv.Row['tick'] -ne '1') { $e.Cancel = $true; if ($dv -and [string]$dv.Row['review'] -eq '1') { Write-UiLog 'No match to accept for this file yet: use Choose match... (or double-click the row) to pick one.' } elseif ($dv -and ([string]$dv.Row['note']).StartsWith('[not done:')) { Write-UiLog 'This row depends on a Setup option that is off; turn it on in Setup to act on it.' }; return }   # any row Full Run can act on
})
$grid.Add_CurrentCellDirtyStateChanged({ if ($grid.IsCurrentCellDirty -and $grid.CurrentCell -and $grid.Columns[$grid.CurrentCell.ColumnIndex].Name -eq 'accept') { [void]$grid.CommitEdit('CurrentCellChange') } })
$grid.Add_CellValueChanged({ param($s, $e)
    if ($script:AcceptBusy -or $e.RowIndex -lt 0 -or $grid.Columns[$e.ColumnIndex].Name -ne 'accept') { return }
    $dv = $grid.Rows[$e.RowIndex].DataBoundItem; if (-not $dv) { return }
    $row = Find-PlanRow ([string]$dv.Row['old_path']); if (-not $row) { return }
    $on = [bool]$dv.Row['accept']
    $n = Set-PRRowAct $script:Rows $row $on ([bool]$chkHigh.Checked)
    Sync-AcceptColumn
    $gk = [string]$row.group_key
    if ($gk.StartsWith('show|') -and $n -gt 1) { Write-UiLog ("{0} all {1} files of this show." -f $(if ($on) { 'Ticked' } else { 'Unticked' }), $n) }
    elseif (-not $on -and $n -ge 1) { Write-UiLog "Unticked: Full Run leaves $([IO.Path]::GetFileName([string]$row.old_path))$(if ($n -gt 1) { " and its $($n - 1) related file(s)" }) as is." }
})
function Show-MatchPicker($row, [bool]$HasPick = $false) {
    $kind = 'movie'; if ([string]$row.group_key -like 'show|*') { $kind = 'show' }
    $q = ([string]$row.query).Split('|'); $qt = $q[0]; $qy = ''; if ($q.Count -gt 1) { $qy = $q[1] }
    $t = $Themes[$script:ThemeEff]; if (-not $t) { $t = $Themes['Light'] }; $dark = ($script:ThemeEff -eq 'Dark')
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "Choose match - $AppName"; $f.Size = New-Object System.Drawing.Size(900, 520); $f.StartPosition = 'CenterParent'
    $f.MinimumSize = New-Object System.Drawing.Size(640, 360); $f.Font = $form.Font; if ($form.Icon) { $f.Icon = $form.Icon }
    $f.MinimizeBox = $false; $f.ShowInTaskbar = $false
    $hdr = New-Object System.Windows.Forms.Label; $hdr.Location = New-Object System.Drawing.Point(12, 10); $hdr.Size = New-Object System.Drawing.Size(860, 36); $hdr.Anchor = 'Top,Left,Right'
    $what = 'File'; if ($kind -eq 'show') { $what = 'Show (applies to every episode)' }
    $hdr.Text = "${what}: $([IO.Path]::GetFileName([string]$row.old_path))"; $f.Controls.Add($hdr)
    $l1 = New-Object System.Windows.Forms.Label; $l1.Text = 'Title:'; $l1.AutoSize = $true; $l1.Location = New-Object System.Drawing.Point(12, 54); $f.Controls.Add($l1)
    $tT = New-Object System.Windows.Forms.TextBox; $tT.Location = New-Object System.Drawing.Point(60, 50); $tT.Width = 460; $tT.Text = $qt; $f.Controls.Add($tT)
    $l2 = New-Object System.Windows.Forms.Label; $l2.Text = 'Year:'; $l2.AutoSize = $true; $l2.Location = New-Object System.Drawing.Point(532, 54); $f.Controls.Add($l2)
    $tY = New-Object System.Windows.Forms.TextBox; $tY.Location = New-Object System.Drawing.Point(572, 50); $tY.Width = 60; $tY.Text = $qy; $f.Controls.Add($tY)
    $bS = New-Object System.Windows.Forms.Button; $bS.Text = 'Search'; $bS.Location = New-Object System.Drawing.Point(644, 48); $bS.Size = New-Object System.Drawing.Size(90, 28); $f.Controls.Add($bS)
    $g = New-Object System.Windows.Forms.DataGridView
    $g.Location = New-Object System.Drawing.Point(12, 86); $g.Size = New-Object System.Drawing.Size(860, 340); $g.Anchor = 'Top,Bottom,Left,Right'
    $g.ReadOnly = $true; $g.AllowUserToAddRows = $false; $g.AllowUserToDeleteRows = $false; $g.AllowUserToResizeRows = $false
    $g.RowHeadersVisible = $false; $g.SelectionMode = 'FullRowSelect'; $g.MultiSelect = $false
    foreach ($spec in @(@('Title', 260), @('Year', 50), @('Source', 60), @('Id', 70), @('Match', 50), @('Overview', 400))) {
        $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn; $c.Name = $spec[0]; $c.HeaderText = $spec[0]; $c.Width = $spec[1]; $c.SortMode = 'NotSortable'; [void]$g.Columns.Add($c)
    }
    $g.Columns['Overview'].AutoSizeMode = 'Fill'; $f.Controls.Add($g)
    $bOk = New-Object System.Windows.Forms.Button; $bOk.Text = 'Accept this match'; $bOk.Size = New-Object System.Drawing.Size(150, 32); $bOk.Location = New-Object System.Drawing.Point(604, 438); $bOk.Anchor = 'Bottom,Right'; $bOk.Enabled = $false
    $bC = New-Object System.Windows.Forms.Button; $bC.Text = 'Cancel'; $bC.Size = New-Object System.Drawing.Size(110, 32); $bC.Location = New-Object System.Drawing.Point(762, 438); $bC.Anchor = 'Bottom,Right'
    $bOk.DialogResult = 'OK'; $bC.DialogResult = 'Cancel'; $f.CancelButton = $bC; $f.AcceptButton = $bS
    $f.Controls.Add($bOk); $f.Controls.Add($bC)
    $bClr = New-Object System.Windows.Forms.Button; $bClr.Text = 'Clear pick'; $bClr.Size = New-Object System.Drawing.Size(120, 32); $bClr.Location = New-Object System.Drawing.Point(12, 438); $bClr.Anchor = 'Bottom,Left'; $bClr.Enabled = $HasPick; $bClr.DialogResult = 'Abort'; $f.Controls.Add($bClr)
    $tipPick = New-Object System.Windows.Forms.ToolTip
    $tipPick.SetToolTip($bClr, $(if ($HasPick) { 'Forget the match you picked for this file / show; the next Scan matches it automatically again' } else { 'No remembered pick for this file / show' }))
    $tipPick.SetToolTip($tT, 'A title, or an ID: 136418 or tmdb:136418 (TMDB), tvdb:1884 (TVDB)')
    $script:PickList = @()
    $fill = {
        $g.Rows.Clear(); $bOk.Enabled = $false
        $yy = $null; $yt = $tY.Text.Trim(); if ($yt -match '^\d{4}$') { $yy = [int]$yt }
        $f.Cursor = 'WaitCursor'
        try { $script:PickList = @(Invoke-MainPR { $db = New-UiDb; Get-PRCandidates $db $kind $tT.Text.Trim() $yy }) } catch { Write-UiLog "Search failed: $($_.Exception.Message)"; $script:PickList = @() } finally { $f.Cursor = 'Default' }
        foreach ($c in $script:PickList) { [void]$g.Rows.Add([object[]]@([string]$c.Title, [string]$c.Year, $(if ($c.Provider -eq 'tvdb') { 'TVDB' } else { 'TMDB' }), [string]$c.Id, ('{0:N2}' -f [double]$c.Sim), [string]$c.Overview)) }
        if ($script:PickList.Count -eq 0) { $hdr.Text = "${what}: $([IO.Path]::GetFileName([string]$row.old_path))   (nothing found - change the title or year and Search)" }
        $g.CurrentCell = $null; $g.ClearSelection()
    }
    $bS.Add_Click($fill)
    $g.Add_SelectionChanged({ $bOk.Enabled = ($g.SelectedRows.Count -eq 1) })
    $g.Add_CellDoubleClick({ param($s, $e) if ($e.RowIndex -ge 0) { $f.DialogResult = 'OK'; $f.Close() } })
    $f.BackColor = $t.Back; $f.ForeColor = $t.Fore; Theme-Controls $f $t $dark @()
    $f.Add_HandleCreated({ Theme-Window $f $dark })
    $f.Add_Shown({ & $fill })
    $res = $f.ShowDialog($form)
    $pick = $null; if ($res -eq 'Abort') { $f.Dispose(); return 'CLEAR' }
    if ($res -eq 'OK' -and $g.SelectedRows.Count -eq 1) { $pick = $script:PickList[$g.SelectedRows[0].Index] }
    $f.Dispose()
    return $pick
}
function New-UiDb { New-PRTmdb -Key $txtKey.Text.Trim() -CachePath $CachePath -TvdbKey $txtTvdb.Text.Trim() -TvdbPin $txtPin.Text.Trim() -Source ([string]$cmbSource.SelectedItem) }
function Invoke-MainPR([scriptblock]$sb) {
    # engine calls on the UI thread: route its log lines into the log box
    $script:PRSync = @{ Log = (New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'); Cancel = $false; Done = 0; Total = 0; Phase = '' }
    try { & $sb } finally { $m = $null; while ($script:PRSync.Log.TryDequeue([ref]$m)) { Write-UiLog $m }; $script:PRSync = $null }
}
function Start-ChooseMatch {
    if (-not $script:Rows -or $script:Mode -ne 'plan' -or $timer.Enabled) { return }
    if ($grid.SelectedRows.Count -ne 1) { [System.Windows.Forms.MessageBox]::Show('Select one movie or episode row first.', $AppName) | Out-Null; return }
    $dv = $grid.SelectedRows[0].DataBoundItem; if (-not $dv) { return }
    $row = Find-PlanRow ([string]$dv.Row['old_path']); if (-not $row) { return }
    if ($row.media_type -eq 'sidecar') {   # a subtitle / extra follows its video: open the video's match
        $vr = $null; if ([string]$row.group_key -like 'movie|*' -or [string]$row.group_key -like 'show|*') { foreach ($r in $script:Rows) { if ($r.group_key -eq $row.group_key -and $r.media_type -ne 'sidecar') { $vr = $r; break } } }
        if (-not $vr) { [System.Windows.Forms.MessageBox]::Show('This subtitle / extra file follows its video. Choose the match on the video''s row.', $AppName) | Out-Null; return }
        $row = $vr
    }
    $gk = [string]$row.group_key
    if (-not ($gk -like 'movie|*' -or $gk -like 'show|*')) { [System.Windows.Forms.MessageBox]::Show('Only movie and episode rows (inside the Movies or Series folder) can be matched by hand.', $AppName) | Out-Null; return }
    $mr = $txtMovies.Text.Trim().TrimEnd('\'); $sr = $txtSeries.Text.Trim().TrimEnd('\')
    $has = Test-PRHasOverride $script:Rows $gk $mr
    $pick = Show-MatchPicker $row $has; if (-not $pick) { return }
    $form.Cursor = 'WaitCursor'
    try {
        if ($pick -is [string] -and $pick -eq 'CLEAR') {
            $n = Remove-PROverride $script:Rows $gk $mr; Export-PROverrides $OverridesPath
            $script:Rows = Invoke-MainPR { $db = New-UiDb; Update-PRPlanGroup $script:Rows $gk $null $db $mr $sr ([bool]$chkScanProbe.Checked) ([bool]$chkFolderLoose.Checked) }
            Write-UiLog "Cleared your pick for $([IO.Path]::GetFileName([string]$row.old_path)) ($n remembered name(s) removed); matched automatically again."
        } else {
            $script:Rows = Invoke-MainPR { $db = New-UiDb; Update-PRPlanGroup $script:Rows $gk $pick $db $mr $sr ([bool]$chkScanProbe.Checked) ([bool]$chkFolderLoose.Checked) }
            [void](Set-PROverride $script:Rows $gk $pick $mr); Export-PROverrides $OverridesPath
            Write-UiLog "Accepted `"$($pick.Title)`" ($($pick.Year)) for $([IO.Path]::GetFileName([string]$row.old_path))$(if ($gk -like 'show|*') { ' and the rest of the show' }). Remembered for later scans (Choose match... > Clear pick to forget it)."
        }
        try { [void](Update-DupMarks) } catch { }
        Fill-Table $script:Rows 'plan'
    } catch { Write-UiLog "Could not apply the match: $($_.Exception.Message)" } finally { $form.Cursor = 'Default' }
}
$btnMatch.Add_Click({ Start-ChooseMatch })
function Sync-AcceptColumn {
    $script:AcceptBusy = $true
    try { $by = @{}; foreach ($r in $script:Rows) { $by[[string]$r.old_path] = $r }; $hi = [bool]$chkHigh.Checked
        $chg = New-Object System.Collections.Generic.List[object]   # only the cells that change are written, in one batch
        foreach ($tr in $table.Rows) { $r = $by[[string]$tr['old_path']]; if ($r) { $s4 = Get-PRRowState $r $hi; $a = $s4[2]; $n0 = [string]$r.note; $nt = $(if ($s4[1]) { "[not done: '$($s4[1])' is off in Setup] " + $n0 } elseif ($s4[3]) { '[unticked: Full Run leaves this as is] ' + $n0 } else { $n0 }); if ([bool]$tr['accept'] -ne $a -or [string]$tr['note'] -cne $nt) { $chg.Add(@($tr, $a, $nt)) } } }
        if ($chg.Count -gt 20) { Invoke-BulkTableEdit { foreach ($c in $chg) { $c[0]['accept'] = $c[1]; $c[0]['note'] = $c[2] } } }
        else { foreach ($c in $chg) { $c[0]['accept'] = $c[1]; $c[0]['note'] = $c[2] } } }
    finally { $script:AcceptBusy = $false }
    $grid.CurrentCell = $null; $grid.ClearSelection()
}
function Set-AcceptAll([bool]$On) {
    # acts only on the rows the current Show: filter and Search box show; the boxes then show what Full Run will do
    if (-not $script:Rows -or $script:Mode -ne 'plan' -or $timer.Enabled) { return }
    $vis = @(foreach ($v in $table.DefaultView) { $v.Row }); $hi = [bool]$chkHigh.Checked
    $todo = @($vis | Where-Object { [string]$_['tick'] -eq '1' -and ([bool]$_['accept'] -ne $On) } | ForEach-Object { Find-PlanRow ([string]$_['old_path']) } | Where-Object { $_ })
    $noMatch = @($vis | Where-Object { [string]$_['review'] -eq '1' -and -not [string]$_['new_path'] } | ForEach-Object { [string]$_['group_key'] } | Select-Object -Unique).Count
    if ($todo.Count -eq 0) { Write-UiLog $(if ($On) { "Nothing to tick in this view; $noMatch without a match (use Choose match...)." } else { 'Nothing is ticked in this view.' }); return }
    $q = $(if ($On) { "Tick $($todo.Count) row(s) shown in this view?`n`nFull Run will do them (low-confidence matches are accepted; subtitles and every episode of a show follow)." } else { "Untick $($todo.Count) row(s) shown in this view?`n`nFull Run will leave them as they are (no rename, move or recycle). Rows not shown are not changed." })
    if ([System.Windows.Forms.MessageBox]::Show($q, $(if ($On) { 'Accept all' } else { 'Clear accepts' }), 'YesNo', 'Question') -ne 'Yes') { return }
    $n = 0; foreach ($r in $todo) { if ((Test-PRWillAct $r $hi) -ne $On) { $n += (Set-PRRowAct $script:Rows $r $On $hi) } }
    Sync-AcceptColumn
    Write-UiLog $(if ($On) { "Ticked $n row(s) in this view; $noMatch without a match (use Choose match...)." } else { "Unticked $n row(s) in this view; Full Run leaves them as they are." })
}
$btnAcceptAll.Add_Click({ Set-AcceptAll $true })
$btnClearAcc.Add_Click({ Set-AcceptAll $false })
$grid.Add_CellDoubleClick({ param($s, $e) if ($e.RowIndex -ge 0 -and $grid.Columns[$e.ColumnIndex].Name -ne 'accept') { Start-ChooseMatch } })

# ---------- background worker (runspace) ----------
$Sync = [hashtable]::Synchronized(@{})
$script:PS = $null; $script:Handle = $null; $script:OnDone = $null
$worker = {
    param($EngineCode, $Sync, $Kind, $A)
    try {
        . ([scriptblock]::Create($EngineCode)); $script:PR_ENGINE_CODE = $EngineCode   # the parallel lookups load the same engine
        $script:PRSync = $Sync; $script:PR_DELETE_NFO = [bool]$Sync.DeleteNfo   # Setup: Delete .nfo files during Full Run
        $script:PR_RECYCLE_DUPSUBS = [bool]$Sync.RecycleDupSubs   # Setup: Recycle duplicate subtitles during Full Run
        $script:PR_US_TITLES = ($null -eq $Sync.UsTitles) -or [bool]$Sync.UsTitles; $script:PR_SEASON_FIX = [bool]$Sync.FixSeasons   # Setup: Standardize season folder names
        if ($Sync.SeasonFormat -and -not (Test-PRSeasonFormat ([string]$Sync.SeasonFormat))) { $script:PR_SEASON_FORMAT = [string]$Sync.SeasonFormat }
        switch ($Kind) {
            'scan' {
                $files = Get-PRFiles @($A.MoviesRoot, $A.SeriesRoot)
                PR-Log "Found $($files.Count) files."
                $db = New-PRTmdb -Key $A.Key -CachePath $A.CachePath -TvdbKey $A.TvdbKey -TvdbPin $A.TvdbPin -Source $A.Source
                $nPre = Invoke-PRPrefetch $db $files $A.MoviesRoot $A.SeriesRoot 8; if ($nPre) { PR-Log "Online lookups fetched in parallel: $nPre." }
                $nOv = Import-PROverrides $A.OverridesPath; if ($nOv) { PR-Log "Remembered picks: $nOv name(s)." }
                $rows = New-PRPlan -Paths $files -MoviesRoot $A.MoviesRoot -SeriesRoot $A.SeriesRoot -Db $db -ProbeReal ([bool]$A.ProbeReal) -FolderLoose ([bool]$A.FolderLoose)
                PR-Log ((Get-PRSummary $rows) + " Online lookups made: $($db.Calls).")
                PR-Log (Get-PRUnmatchedLine $rows)
                if ($script:PR_DELETE_NFO) { PR-Log (Get-PRNfoLine $rows) }
                if ($script:PR_RECYCLE_DUPSUBS) { PR-Log (Get-PRDupSubLine $rows) }
                if ($script:PR_SEASON_FIX) { PR-Log (Get-PRSeasonLine $rows) }
                $ef = @(Get-PREmptyFolders @($A.MoviesRoot, $A.SeriesRoot))
                PR-Log ("Empty folders right now: {0}{1}" -f $ef.Count, $(if ($A.RemoveEmpty) { ' (removed after the Full Run, together with any the run leaves empty)' } else { ' (kept: Remove empty folders is off in Setup)' }))
                $k = 0; foreach ($d in $ef) { if ($k -ge 200) { PR-Log "  ...and $($ef.Count - 200) more"; break }; PR-Log "  empty: $d"; $k++ }
                $Sync.Result = $rows
            }
            'apply' { $script:PR_ONLY_TICKED = [bool]$A.OnlyTicked; $Sync.Result = Invoke-PRApply -Rows $A.Rows -HighOnly:$A.HighOnly -UndoLog $A.UndoLog -Roots $A.Roots -RemoveEmpty:([bool]$A.RemoveEmpty) -DeleteNfo:([bool]$A.DeleteNfo) -RecycleDupSubs:([bool]$A.RecycleDupSubs) -FixSeasons:([bool]$A.FixSeasons) }
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
    $btnMatch.Enabled = $btnDups.Enabled; $btnAcceptAll.Enabled = $btnDups.Enabled; $btnClearAcc.Enabled = $btnDups.Enabled
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
    $Sync.DeleteNfo = [bool]$chkDeleteNfo.Checked   # the worker plans .nfo rows as 'nfo: delete' when on
    $Sync.RecycleDupSubs = [bool]$chkRecycleDupSubs.Checked   # the worker marks duplicate subtitles 'will be recycled' when on
    $Sync.FixSeasons = [bool]$chkFixSeasons.Checked   # the worker lists non-standard season folders when on
    $Sync.SeasonFormat = $txtSeasonFmt.Text.Trim()
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
        elseif ($Sync.Error) { Write-UiLog "ERROR: $($Sync.Error)"; [System.Windows.Forms.MessageBox]::Show($Sync.Error, $AppName, 'OK', 'Error') | Out-Null }
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
$btnSetup.Add_Click({ [void]$setup.ShowDialog($form)
    $script:PR_DELETE_NFO = [bool]$chkDeleteNfo.Checked; $Sync.DeleteNfo = $script:PR_DELETE_NFO
    $script:PR_RECYCLE_DUPSUBS = [bool]$chkRecycleDupSubs.Checked; $script:PR_SEASON_FIX = [bool]$chkFixSeasons.Checked; if (-not (Test-PRSeasonFormat $txtSeasonFmt.Text)) { $script:PR_SEASON_FORMAT = $txtSeasonFmt.Text.Trim() }
    if ($script:PR_ONLY_TICKED -ne [bool]$chkOnlyTicked.Checked) { $script:PR_ONLY_TICKED = [bool]$chkOnlyTicked.Checked; if ($script:Rows -and $script:Mode -eq 'plan') { Fill-Table $script:Rows 'plan' } }   # which rows can be ticked depends on it
    if ($script:Rows -and $script:Mode -eq 'plan') { Sync-AcceptColumn }   # ticks and notes follow the options
    try { Save-Settings } catch { Write-UiLog "Could not save settings: $($_.Exception.Message)" }; Update-SubsUi })
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
    if (-not $m -and -not $s) { [System.Windows.Forms.MessageBox]::Show('Choose a Movies and/or Series folder first.', $AppName) | Out-Null; return }
    foreach ($p in $m, $s) { if ($p -and -not (Test-Path -LiteralPath $p)) { [System.Windows.Forms.MessageBox]::Show("Folder not found:`n$p", $AppName) | Out-Null; return } }
    $src = [string]$cmbSource.SelectedItem
    if ($src -eq 'TVDB only' -and -not $txtTvdb.Text.Trim()) { [System.Windows.Forms.MessageBox]::Show('Enter your TVDB API key in Setup first, or change Name source.', $AppName) | Out-Null; return }
    if ($src -ne 'TVDB only' -and -not $txtKey.Text.Trim() -and -not (Test-Path -LiteralPath $CachePath)) {
        [System.Windows.Forms.MessageBox]::Show('Open Setup and enter your TMDB API key (v3) first. Get one free at themoviedb.org > Settings > API.', $AppName) | Out-Null; return
    }
    try { Save-Settings } catch { Write-UiLog "Could not save settings: $($_.Exception.Message)" }
    Write-UiLog "Scanning (dry run, nothing is changed)..."
    Start-Work 'scan' @{ OverridesPath = $OverridesPath; MoviesRoot = $m; SeriesRoot = $s; Key = $txtKey.Text.Trim(); CachePath = $CachePath; TvdbKey = $txtTvdb.Text.Trim(); TvdbPin = $txtPin.Text.Trim(); Source = $src; ProbeReal = $chkScanProbe.Checked; FolderLoose = $chkFolderLoose.Checked; RemoveEmpty = $chkRemoveEmpty.Checked } {
        param($rows)
        $script:Rows = $rows; $script:Mode = 'plan'
        $ng = 0; $form.Cursor = 'WaitCursor'; try { $ng = Update-DupMarks } catch { $script:DupMark = @{}; $script:DupGroup = @{} } finally { $form.Cursor = 'Default' }
        Fill-Table $rows 'plan'
        if ($ng -gt 0) { Write-UiLog "Duplicates: $ng group(s). Green rows = the copy that would be kept, orange rows = copies that would be deleted. Nothing is deleted unless you use Duplicates... > Delete others." }
        $btnDups.Enabled = $true; $btnMatch.Enabled = $true; $btnAcceptAll.Enabled = $true; $btnClearAcc.Enabled = $true
        $rv = Get-PRReviewCounts $rows
        if ($rv.Total -gt 0) { Write-UiLog "To review: $($rv.Total) movie(s)/show(s) ($($rv.Low) low-confidence matches, $($rv.NoMatch) with no match) (Show: Low confidence - review). Tick Accept to rename them in the Full Run, or use Choose match... to pick a different match." }
        Write-UiLog 'Dry run complete. Review the grid; nothing has been changed. Use Full Run to apply.'
    }
})
$btnExport.Add_Click({
    if (-not $script:Rows -or $script:Mode -ne 'plan') { [System.Windows.Forms.MessageBox]::Show('Run Scan first.', $AppName) | Out-Null; return }
    $d = New-Object System.Windows.Forms.SaveFileDialog; $d.Filter = 'CSV (*.csv)|*.csv'; $d.FileName = "plan_$(Get-Date -Format yyyyMMdd_HHmmss).csv"
    if ($d.ShowDialog($form) -eq 'OK') { Export-PRPlan $script:Rows $d.FileName; Write-UiLog "Plan exported to $($d.FileName)" }
})
$btnRun.Add_Click({
    if (-not $script:Rows -or $script:Mode -ne 'plan') { [System.Windows.Forms.MessageBox]::Show('Run Scan first, then review the plan.', $AppName) | Out-Null; return }
    $hi = $chkHigh.Checked
    $rc = Get-PRRunCounts $script:Rows $hi; $n = $rc.Total
    $roots = @(@($txtMovies.Text.Trim().TrimEnd('\'), $txtSeries.Text.Trim().TrimEnd('\')) | Where-Object { $_ })
    $nEmpty = 0; if ($chkRemoveEmpty.Checked) { try { $nEmpty = @(Get-PREmptyFolders $roots).Count } catch { } }
    $nNfo = 0; if ($chkDeleteNfo.Checked) { $nNfo = @($script:Rows | Where-Object { ([string]$_.note).StartsWith('nfo: delete') -and -not (Test-PRSkipped $_) }).Count }
    $nDup = 0; if ($chkRecycleDupSubs.Checked) { $nDup = @($script:Rows | Where-Object { (Test-PRDupSubRow $_) -and -not (Test-PRSkipped $_) }).Count }
    $nSeason = 0; if ($chkFixSeasons.Checked) { $nSeason = $rc.SeasonFolders }
    if ($n -eq 0 -and $nEmpty -eq 0 -and $rc.CaseFolders -eq 0 -and $nNfo -eq 0 -and $nDup -eq 0 -and $nSeason -eq 0) { [System.Windows.Forms.MessageBox]::Show('Nothing to move.', $AppName) | Out-Null; return }
    $what = "$($rc.High) " + $(if ($hi) { 'high-confidence' } else { 'planned' }) + " file(s) renamed`n$($rc.Accepted) low-confidence file(s) you accepted, renamed`n$($rc.Folder) file(s) only put into their own folder (name kept)`n$($rc.CaseFolders) folder name(s) fixed (letter case)"
    if ($chkDeleteNfo.Checked) { $what += "`n$nNfo .nfo file(s) sent to the Recycle Bin" }
    if ($chkFixSeasons.Checked) { $what += "`n$nSeason season folder(s) renamed to '$(PR-FormatSeason 1 $txtSeasonFmt.Text)'-style names (in place)" }
    if ($chkRecycleDupSubs.Checked) { $what += "`n$nDup duplicate subtitle(s) sent to the Recycle Bin (the copy already in place is kept)" }
    if ($chkRemoveEmpty.Checked) { $what += "`n$nEmpty empty folder(s) removed (plus any the run leaves empty; Undo recreates them)" } else { $what += "`n0 empty folders removed (turned off in Setup)" }
    $ok = [System.Windows.Forms.MessageBox]::Show("Full Run will do now$(if ($chkOnlyTicked.Checked) { ' (only ticked rows - Setup)' }):`n`n$what`n`nIf a file with the new name already exists, that file is skipped. An undo log will be written to the Logs folder.", 'Confirm Full Run', 'YesNo', 'Warning')
    if ($ok -ne 'Yes') { return }
    if (-not (Test-Path -LiteralPath $LogDir)) { [void](New-Item -ItemType Directory -Path $LogDir) }
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    Export-PRPlan $script:Rows (Join-Path $LogDir "plan_$ts.csv")
    $undo = Join-Path $LogDir "undo_$ts.csv"
    Write-UiLog "Applying... (plan saved as Logs\plan_$ts.csv)"
    Start-Work 'apply' @{ Rows = $script:Rows; HighOnly = $hi; UndoLog = $undo; Roots = $roots; RemoveEmpty = $chkRemoveEmpty.Checked; OnlyTicked = $chkOnlyTicked.Checked; DeleteNfo = $chkDeleteNfo.Checked; RecycleDupSubs = $chkRecycleDupSubs.Checked; FixSeasons = $chkFixSeasons.Checked } {
        param($r)
        if ($r.Cancelled) { $head = "Full Run STOPPED. Moved $($r.Moved) before stopping (skipped $($r.Skipped), failed $($r.Failed)); the rest were not touched."; $ttl = 'Full Run stopped' } else { $head = "Moved $($r.Moved), skipped $($r.Skipped), failed $($r.Failed)."; $ttl = 'Full Run finished' }
        $undoNote = ''; if ($r.NfoRecycled) { $head += " $($r.NfoRecycled) .nfo file(s) sent to the Recycle Bin." }; if ($r.DupRecycled) { $head += " $($r.DupRecycled) duplicate subtitle(s) sent to the Recycle Bin." }; if ($r.SeasonFixed) { $head += " $($r.SeasonFixed) season folder(s) renamed." }; if ($r.Moved -or $r.NfoRecycled -or $r.DupRecycled -or $r.SeasonFixed) { $undoNote = "`n`nUndo log: $($r.Log)" }
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
    if ($log.Count -eq 0 -or -not ($log[0].PSObject.Properties.Name -contains 'new_path')) { [System.Windows.Forms.MessageBox]::Show('That is not an undo log.', $AppName) | Out-Null; return }
    $script:Mode = 'undo'; $script:Rows = $null
    Fill-Table $log 'undo'
    Write-UiLog "Undo preview: $($log.Count) moves would be reversed (grid shows current -> original)."
    $ok = [System.Windows.Forms.MessageBox]::Show("Reverse $($log.Count) moves from`n$($d.FileName)?`n`nFiles are moved back only where the original path is free.", 'Confirm Undo', 'YesNo', 'Warning')
    if ($ok -ne 'Yes') { Write-UiLog 'Undo cancelled.'; return }
    Start-Work 'undo' @{ UndoLog = $d.FileName } {
        param($r)
        [System.Windows.Forms.MessageBox]::Show("Restored $($r.Restored), skipped $($r.Skipped)." + $(if ($r.Recycled) { "`n`n$($r.Recycled) .nfo file(s) are in the Recycle Bin - restore from there if needed." } else { '' }), 'Undo finished') | Out-Null
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
    if (-not $script:Rows -or $script:Mode -ne 'plan') { [System.Windows.Forms.MessageBox]::Show('Run Scan first, then use Get subtitles.', $AppName) | Out-Null; return }
    if (-not ($chkSubStd.Checked -or $chkSubSdh.Checked)) { [System.Windows.Forms.MessageBox]::Show('Tick "Get standard subtitles" and/or "Also get SDH / HI subtitles" in Setup first.', $AppName) | Out-Null; return }
    $withId = @($script:Rows | Where-Object { ($_.media_type -eq 'movie' -or $_.media_type -eq 'episode') -and [string]$_.tmdb_id }).Count
    if ($withId -eq 0) { [System.Windows.Forms.MessageBox]::Show('No scanned video has a movie/show id yet. Run Scan and check that titles were matched.', $AppName) | Out-Null; return }
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
    $f.Text = "Confirm delete - $AppName"; $f.Size = New-Object System.Drawing.Size(980, 640); $f.StartPosition = 'CenterParent'
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
    $dlg.Text = "Manage duplicates - $AppName v$AppVersion"; $dlg.Size = New-Object System.Drawing.Size(1150, 620); $dlg.StartPosition = 'CenterParent'
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
        try { $okDel = Show-DeleteConfirm $dlg $pl $net $t $dark } catch { [System.Windows.Forms.MessageBox]::Show("Could not open the delete confirmation. Nothing was deleted.`n`n$($_.Exception.Message)`nLine $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())", $AppName, 'OK', 'Error') | Out-Null; return }
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
    if (-not $script:Rows -or $script:Mode -ne 'plan') { [System.Windows.Forms.MessageBox]::Show('Run Scan first.', $AppName) | Out-Null; return }
    Show-DuplicatesDialog
})

# ---------- start ----------
$st = Load-Settings
$txtMovies.Text = $st.MoviesRoot; $txtSeries.Text = $st.SeriesRoot; $chkHigh.Checked = $st.HighOnly; $txtKey.Text = $st.Key; $txtTvdb.Text = $st.TvdbKey; $txtPin.Text = $st.TvdbPin; $cmbSource.SelectedItem = $st.Source; $chkProbe.Checked = $st.ProbeAlways; $chkScanProbe.Checked = $st.ProbeScan
$chkSubStd.Checked = $st.SubsStd; $chkSubSdh.Checked = $st.SubsSdh; $chkSubs.Checked = $st.SubsEnable; $chkAutoSubs.Checked = $st.AutoSubs; $chkFolderLoose.Checked = $st.FolderLoose; $chkRemoveEmpty.Checked = $st.RemoveEmpty; $chkOnlyTicked.Checked = $st.OnlyTicked; $script:PR_ONLY_TICKED = [bool]$st.OnlyTicked; $chkDeleteNfo.Checked = $st.DeleteNfo; $script:PR_DELETE_NFO = [bool]$st.DeleteNfo; $Sync.DeleteNfo = $script:PR_DELETE_NFO; $chkRecycleDupSubs.Checked = $st.RecycleDupSubs; $script:PR_RECYCLE_DUPSUBS = [bool]$st.RecycleDupSubs; $Sync.RecycleDupSubs = $script:PR_RECYCLE_DUPSUBS; $chkFixSeasons.Checked = $st.FixSeasons; $script:PR_SEASON_FIX = [bool]$st.FixSeasons; $Sync.FixSeasons = $script:PR_SEASON_FIX; $txtSeasonFmt.Text = $st.SeasonFormat; $chkUsTitles.Checked = [bool]$st.UsTitles; $script:PR_US_TITLES = [bool]$st.UsTitles; $Sync.UsTitles = $script:PR_US_TITLES; $script:PR_SEASON_FORMAT = $st.SeasonFormat; $Sync.SeasonFormat = $st.SeasonFormat; $txtSeasonFmt.Enabled = $chkFixSeasons.Checked; Update-SeasonPreview
Update-SubsUi
$cmbTheme.SelectedItem = $st.Theme
Apply-Theme $st.Theme
$script:SettingsLoaded = $true
Write-UiLog "$AppName v$AppVersion ready."
Write-UiLog '1) Choose your Movies and/or Series folder and enter your API keys in Setup.  2) Scan.  3) Review the results, then Full Run.'
$form.Add_FormClosing({ if ($btnCancel.Enabled) { $Sync.Cancel = $true } })
[void]$form.ShowDialog()
