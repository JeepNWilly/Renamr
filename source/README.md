# Renamr – source

Windows GUI that renames movie and TV files to Plex naming using TMDB and/or TheTVDB lookups.
- Movies: `<Movies>\Title (Year)\Title (Year).ext`
- Episodes: `<Series>\Show (Year)\Season 01\Show (Year) - S01E01 - Title.ext`

It is pure Windows PowerShell 5.1 with WinForms, so it runs on stock Windows 10/11 with nothing to install.

## Layout
| File | Purpose |
|---|---|
| `Renamr.Engine.ps1` | All logic, no UI. Filename parsing, TMDB client and cache, planning (duplicates, multiple versions, specials, Subs folders, ROMS/Plex Versions exclusion, confidence), apply and undo. A faithful port of `reference/plan.py`. |
| `Renamr.Gui.ps1` | WinForms UI. It runs the engine in a background runspace; a timer pumps progress and log lines into the UI. |
| `Renamr.ico` | App icon (16–256 px, original design: orange clapper with rename arrow on charcoal). It's embedded in the exe via `-iconFile` and also used as the window icon. |
| `VERSION`, `BUILD_NUMBER`, `CHANGELOG.md` | `VERSION` is the single source of truth for major.minor.patch. `BUILD_NUMBER` is bumped automatically by every exe compile. `CHANGELOG.md` records the history. |
| `build_exe.ps1` / `BUILD.cmd` | Embeds the engine (Base64) into the GUI and writes `..\Renamr.ps1`, then compiles `..\Renamr.exe` with PS2EXE. It installs the ps2exe module for the current user if it's missing. Use `-NoCompile` to write only the .ps1. Both modes copy `Renamr.ico` to the output folder. |
| `tests/Test-Engine.ps1` | Builds a plan from a text file of Windows paths, offline against a cache file or live with `-Key`. |
| `tests/Test-Duplicates.ps1` | Tests duplicate grouping, sidecar lookup, the default keep choice, multi-keep delete planning, resolution hints, and the deletion log (permanent-delete mode in a temporary folder). |
| `tests/Test-Subtitles.ps1` | Offline (mocked HTTP) tests of the subtitle feature: candidate choice (standard vs SDH, commentary and non-English rejected), file naming, skipping existing files, ad-line stripping, the 3-candidate fallback, the 429 stop, id mapping and rename/Duplicates compatibility. |
| `tests/Test-GuiSubs.ps1` | Windows-only GUI check of the Get subtitles feature on a temp copy of the app: button/checkbox visibility, layout overlap, settings, busy state, themes. With `-Live` it also runs the real background worker (lookup + download of one movie into a temp folder). |
| `tests/Test-ApplyUndo.ps1` | Creates a temporary fake library, then checks apply, HighOnly, no-overwrite, bracket names, undo and folder cleanup. |
| `tests/sample_paths.txt` | 40 sample paths for the test above. |
| `reference/` | The original command-line tools (`plan.py`, `apply.ps1`, `undo.ps1`) that the app was ported from. |

## Modify and rebuild
1. Edit `Renamr.Engine.ps1` (logic) or `Renamr.Gui.ps1` (UI). Don't edit the generated `..\Renamr.ps1`.
2. Quick test without the GUI:
   `powershell -ExecutionPolicy Bypass -File tests\Test-ApplyUndo.ps1`
   `powershell -ExecutionPolicy Bypass -File tests\Test-Engine.ps1 -PathsFile tests\sample_paths.txt -Cache ..\tmdb_cache.json -Out out.csv`
3. Rebuild: double-click `BUILD.cmd`, or run `powershell -ExecutionPolicy Bypass -File build_exe.ps1`.
   Output goes to the parent folder (`..\Renamr.ps1`, `..\Renamr.exe`).
4. You can also run the GUI straight from source: `powershell -STA -ExecutionPolicy Bypass -File Renamr.Gui.ps1`. It loads the engine file that sits next to it.

## Where things live
- **Tags stripped from names:** `$PR_TAGS`. Add release words there.
- **Video and sidecar extensions:** `$PR_VIDEO` and `$PR_SIDECAR`.
- **Excluded folders:** `$PR_SKIP` (`ROMS`, `Plex Versions`, `@eaDir`, `#recycle`).
- **Subtitle language names:** `$PR_LANG`.
- **Confidence rules:** `PR-MatchMovie`, `PR-MatchShow`, and the confidence line in `New-PRPlan`.

## Data files next to the app
- `settings.json`: folders, the HighOnly option, and the TMDB and TVDB keys (plus optional TVDB PIN) encrypted with DPAPI. Only the same Windows user on the same PC can decrypt the key.
- `tmdb_cache.json`: trimmed TMDB responses stored as `[{"k":..., "v":...}]`, using the same keys as plan.py. Delete it to force fresh lookups.
- `subs_cache.json`: cached The Subtitle Database lookups (3 days).
- `Logs\plan_*.csv` and `Logs\undo_*.csv`: one pair per Full Run. `Logs\deleted_*.csv`: Duplicates deletions. `Logs\subtitles_*.csv`: every subtitle download attempt.

## Safety
- Scan is read-only.
- Moves use .NET `File.Move`, which never overwrites. Targets that already exist are skipped and logged.
- The undo log is written after every move, so it stays usable if a run is interrupted.
- Undo only moves a file back when its original path is free. It removes only the folders the run created, and only once they're empty.

## Movie folders
Setup has a checkbox **Put movies that are not in a folder into their own "Name (Year)" folder** (ticked by default). Unticked, a movie sitting directly in the Movies folder is only renamed in place. Movies already inside a folder are always moved to their `Name (Year)` folder. Code: the `-FolderLoose` parameter of `New-PRPlan`.

## Subtitles (Get subtitles...)
Tick **Enable subtitle download** in Setup to show the **Get subtitles...** button on the main window. Run **Scan** first; the button works on the scanned rows.
1. Click it. The app looks up English subtitles on The Subtitle Database (no key or account) using the TMDB id (or an IMDb id for TVDB-sourced rows) and the season/episode number. Nothing is downloaded yet; the log shows what was found for each video.
2. A confirmation shows how many standard and SDH/HI files would be downloaded and the estimated time. Yes starts the download (Stop halts it).
3. Files are written next to each video: `<name>.en.srt` and `<name>.en.sdh.srt`. They are never overwritten, and a video that already has an English subtitle gets no new standard one.

**Auto Get Subtitles:** tick it in Setup (it needs *Enable subtitle download*) and every Full Run that moved files is followed by the same lookup and download for those videos, without asking again. Cancelled runs do nothing. The service allows about 200 downloads per hour and also rate-limits lookups; when a limit is hit, it stops cleanly and the next run continues, skipping subtitles already downloaded.
- Downloads are limited to about 200 per hour per IP by the site. At the limit the run stops with a message; click the button again later and it continues (finished files are skipped).
- Each file is validated (English, enough cues) with up to 3 candidates tried, ad lines are removed, and every attempt is logged to `Logs\subtitles_<date>.csv`.
- Code: `PR-Sub*` functions, `Get-PRSubsPlan` (dry run) and `Invoke-PRSubsDownload` in the engine; `Start-SubsDownload`, `Update-SubsUi` and the `subsplan` / `subsget` worker kinds in the GUI.
- The Subtitle Database has no title-name search, so rows without a TMDB id (or a TVDB id that cannot be mapped because no TMDB/TVDB key is set) are skipped.

## Icon
`Renamr.ico` is an original design: an orange (#E5A00D) clapper with a rename arrow on dark charcoal. It doesn't use the Plex logo. The 16 and 24 px frames are separately simplified drawings so they stay legible. The GUI loads the window icon from `Renamr.ico` in the app folder or in `source\`; when it runs as the exe, it falls back to the icon embedded in the exe. If no icon is found, the window uses the default. To change it, replace the .ico (multi-size, up to 256 px) and rebuild.

## Theme
The Theme dropdown offers System, Light and Dark, and is saved in `settings.json` as `Theme`. It applies at startup and immediately when you change it.
- **System** reads `HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\AppsUseLightTheme`. If the value is missing, it uses Light.
- **Dark** uses flat controls with border colors, a dark grid with alternating rows and custom headers, and a dark log pane.
- **Dark title bar** is set through `DwmSetWindowAttribute` (attribute 20, with 19 as a fallback for older Windows 10). Failures are ignored.
- **Accent orange** (#E5A00D) is used only for the Scan and Full Run buttons and for row selection.

All colors are in the `$Themes` table in `Renamr.Gui.ps1`.

## Versioning
- Edit `VERSION` (for example `1.2.0`) for a release, and add an entry to `CHANGELOG.md`.
- `build_exe.ps1`:
  - reads `VERSION`;
  - on a compile, adds 1 to `BUILD_NUMBER` and builds `1.2.0.<N>`;
  - writes that into the generated `Renamr.ps1` as `$AppVersion`;
  - passes it to PS2EXE with `-version`, `-title`, `-product` and `-description`, so it appears in the exe's Properties > Details.
- `-NoCompile` reuses the current build number without increasing it.
- The app shows the version in its window title (`Renamr v1.1.0.N`) and in the footer.
- When the GUI runs straight from source, the version shows as `dev`.

## Duplicates
After a scan, the **Duplicates...** button opens a dialog. It lists video groups that are either DUPLICATE rows (same target) or MULTIPLE VERSIONS (same movie folder); groups that are both are merged.

In the main table, rows in those groups are shaded after a scan: **green** is the copy that would be kept (highest resolution, then largest) and **orange** are the copies that would be deleted. Nothing is deleted until you use **Delete others...**. If you close the dialog without deleting, the shading follows your Keep ticks.

**Remakes and same-name films:** if a file name has no year, Renamr uses the year in the folder name. If several films share the name and no year can be found, the row is marked AMBIGUOUS (low confidence). If it would land on a name another file already has, it is marked POSSIBLE REMAKE and left alone - add the year to the file name and scan again.
- **What each row shows:** path, size, modified date, resolution hint from the name (2160p/4K/UHD, 1080p, 720p and so on) and extension.
- **Choosing what to keep:** tick **Keep** for every file you want to keep. You can keep several per group. By default only the best file is ticked (highest resolution, then largest).
  - **Keep all** ticks the whole group. Unticking it goes back to the default.
  - Groups where everything is kept are skipped.
  - A group with nothing kept blocks **Delete others...**, with a message naming the group.
- **Delete others...** shows a confirmation with the file list and total size.
  - It deletes the unkept videos plus their sidecars: same folder and same base name (`.srt`, `.en.srt`, `.nfo` and so on), or `Subs\<video name>\*`. Sidecars that belong to a longer-named video in the same folder are left alone.
  - Local drives: files go to the Windows Recycle Bin, via `Microsoft.VisualBasic.FileIO.FileSystem.DeleteFile` with `SendToRecycleBin`.
  - Network drives and NAS shares: Windows has no Recycle Bin there, so deletion is **permanent**, unless the Synology share has its Recycle Bin enabled, in which case files go to `#recycle`. The confirmation warns about this.
  - Deletions can't be undone from the app.
- Every deletion is logged to `Logs\deleted_<ts>.csv`, and the library is rescanned automatically afterwards.
- **Confirming:** **Delete others...** opens a confirmation window.
  - It lists each video and its subtitle/.nfo files with type and size, and the files you are keeping.
  - **Cancel** is the default button.
- **Network drives:** a mapped NAS drive such as Z: is detected through `GetDriveType`, `DriveInfo`, WMI and the `HKCU\Network` key.
  - Any drive that isn't a local fixed or removable disk counts as network.
  - Deletes there are permanent unless the Synology shared folder has its Recycle Bin enabled.
- **Code location:** grouping and sidecar logic are in the engine (`Get-PRDuplicateGroups`, `Get-PRSidecarsFor`, `Select-PRDefaultKeep`, `Get-PRDeletePlan`, `Get-PRDeleteSummary`, `Test-PRNetworkPath`, `Remove-PRFiles`). The dialog is `Show-DuplicatesDialog` in the GUI.
