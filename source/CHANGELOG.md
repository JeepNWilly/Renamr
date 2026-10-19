# Changelog
The version in `VERSION` is major.minor.patch. `build_exe.ps1` adds a fourth part, the build number, which is stored in `BUILD_NUMBER` and goes up by one on every exe compile.

## 1.4.0
- **Loose movies get their own folder** even when the file name is already right, or when the rename itself is low confidence: the file is then only moved into its `Name (Year)` folder with its name kept ("folder-only" in the undo log). Its subtitles go with it.
- **Review and accept:** new **Accept** column and a **Low confidence - review** filter. Tick Accept to include a low-confidence movie or show in the Full Run. **Choose match...** (or double-click a row) opens a picker with the other candidates and a Title / Year search; the pick is applied to the whole movie or show and counts as accepted.
- **Accept all** / **Clear accepts** act on the rows the current Show filter and Search show (every row with a pending change can be ticked). The log says how many were accepted and how many were skipped because they have no match.
- **Full Run** always applies high-confidence rows plus any rows you ticked. New Setup option **Full Run applies only ticked rows** (off by default) applies only ticked rows.
- **Folder letter case:** a folder that differs only in letter case (e.g. `The matrix (1999)` vs `The Matrix (1999)`) is now really renamed (Windows needs a two-step rename). These rows have their own status "folder case" and Show filter **Folder case fixes**, one row per folder. Undo changes the case back.
- **Empty folders:** new Setup option **Remove empty folders after Full Run** (on by default). Only folders inside the Movies / Series folders that hold no files at all (hidden files count) are removed; hidden, system and recycle folders are never touched, nor is Z:. Scan lists the empty folders now; Undo recreates removed folders with their original times.
- **Orphan subtitles are re-attached** to their video (for example after the video was renamed earlier):
  - only video in the folder: renamed to `<video>.<tags>.srt`, keeping the tags as written (`eng.CC`, `fra.Canada`, `hin.sdh`); an untagged one becomes `<video>.srt`;
  - space-separated tags are cleaned up: `eng.CC eng` → `.en.sdh`, `fra.Canada fre` → `.fr-CA`, `spa.Latinoamérica spa` → `.es-419`;
  - `Subs\` folders: files such as `3_English.srt` or `Español (Latinoamérica).spa.srt` are moved up next to the video with the language from their name (English and native language names); unknown language → `.und`, low confidence;
  - several videos in a folder: matched by title and year, with `Part II` = `Part 2`; title only → low confidence;
  - left behind in an old folder with no video: matched to the movie elsewhere by title and year, always low confidence (review);
  - a loose subtitle with no video anywhere is left alone ("no video found").
- **Duplicate sidecars:** when the target name already exists and the file is the same (identical, or same language and size within 3%; a second .nfo always counts), it is skipped as DUPLICATE. A different track gets a numbered name (`.en.2.srt`) and is always low confidence, never applied automatically.
- **.nfo files:** new Setup option **Delete .nfo files during Full Run** (on by default). All `.nfo` files under the Movies / Series folders are sent to the Windows Recycle Bin (never deleted for good: on a drive without a Recycle Bin they are kept and logged). They show as "nfo: delete" with a Show filter **NFO files to delete**. Runs before the empty-folder clean-up. Logged in the undo log as `recycle`; Undo reports how many are in the Recycle Bin.
- **Clearer counts:** the scan summary, the review counts and the Full Run confirmation ("Full Run will do now: ...") list each kind of change: high-confidence renames, accepted renames, folder-only moves, folder case fixes, .nfo files and empty folders. The scan log adds "Unmatched: X movies, Y episodes, Z sidecars with no video" and suggests choosing a Series folder when episodes sit in the Movies folder.
- Running from source (`Renamr.Gui.ps1` in `source\`) uses the app folder's `settings.json`, cache and logs.
- New tests: `Test-FolderLoose`, `Test-Accept`, `Test-Folders`, `Test-Reattach`, `Test-Nfo`.

## 1.3.0
- Setup: new checkbox "Put movies that are not in a folder into their own \"Name (Year)\" folder" (ticked by default, which is how Renamr always behaved). Unticked, a movie sitting directly in the Movies folder is only renamed in place; movies already in a folder are still moved to their Name (Year) folder.
- Setup: new "Auto Get Subtitles" checkbox (under Get subtitles). When ticked, a Full Run that moved files is followed automatically by the English subtitle lookup and download for those videos, with no extra prompt; a note in Setup explains the service limits (about 200 downloads per hour; it stops cleanly and the next run continues).
- No row is selected (bright orange) after a scan or filter change until you click one.
- Remakes: when a file name has no year, the year in its folder name is used (e.g. "Dune (1984)\Dune.mkv"). If several films share the name and there is still no year, the file is marked AMBIGUOUS and stays a low-confidence guess. Popularity never decides: such a file is not renamed onto a name another file has (marked POSSIBLE REMAKE, left unchanged) and is not grouped as a duplicate of a file that has a year.
- Fix: a year that comes after an edition word is now read, e.g. "The Punisher - Extended Edition (2004)" or "Total Recall - Remastered (1990)". Before, the edition word ended the title early and hid the year, so remakes and originals got matched to the same film and were flagged as duplicates.
- Fix: a release/edition word before the year (for example "The Punisher - Extended Edition (2004)" or "Total Recall - Remastered (1990)") hid the year, so remakes were matched to the wrong film and flagged as duplicates of the original. The year after such a word is now read.
- Main table: after a Scan, duplicate / multiple-version copies are shaded. Green = the copy that would be kept (best resolution, then largest), orange = copies that would be deleted. The "Duplicates / collisions" filter now also shows the green keeper rows. The copies of a group are also kept together in the table, keeper first (you can still sort by any column header). Closing the Duplicates window without deleting updates the shading to your Keep ticks. Nothing is deleted until you use Delete others.
- Full Run confirmation now says: if a file with the new name already exists, that file is skipped.
- Fix: pressing Stop during a Scan no longer shows a "Cancelled" error box; the log just says "Stopped. Nothing was changed."
- The **Scan & Dry Run** button is now just **Scan** (it still changes nothing). The old Cancel button is now **Stop**: it halts a Full Run (and Scan, Undo, subtitle lookups) after the file in progress; a stopped Full Run says how many files were moved before stopping and keeps its undo log.
- **The program is now called Renamr** (it was PlexRenamer / Plex Renamer). The exe, scripts, icon, window titles, messages, README, tests and build scripts all use the new name; the project folder is now `C:\Projects\Renamr`. Settings, cache and logs are kept (they live next to the exe, which moved with the folder). It still renames to Plex naming.
- Renaming (Full Run and Undo) now keeps each file's created, modified and last-accessed times. A same-drive rename already does; the app also checks after each move and restores any time that changed.
- Cleaner log text: the scan summary and startup messages are plainer (no mention of Plex Versions or ROMS).
- Layout: the **Search** box moved up to the Name source row, right after **Only high-confidence**; the **Show** selector is right-justified on the button row.
- New: **Get subtitles...** button (main window, button row next to Duplicates...). It is hidden until you tick **Enable subtitle download (shows the Get subtitles button)** in Setup; the button appears or hides as soon as Setup closes (and is restored at startup). 
- New: subtitle source is The Subtitle Database (thesubtitledb.org): no account and no API key. English subtitles only; other languages (and mislabelled non-English files) are never saved.
- New: Setup options **Get standard subtitles** (default on) and **Also get SDH / HI subtitles when available** (default on). Both are remembered in `settings.json` (`SubsEnable`, `SubsStd`, `SubsSdh`).
- New flow: click Get subtitles... after Scan & Dry Run. It first does a lookup-only dry run (nothing is downloaded or written; the log lists each video as found / not found / already have for standard and SDH), then asks to confirm with the counts and an estimated time. Yes downloads with the usual progress bar and Cancel button.
- Files are saved next to the video as `<video name>.en.srt` (standard) and `<video name>.en.sdh.srt` (SDH/HI). They are picked up as sidecars by Full Run (they follow the video when it is renamed) and by Duplicates (they are deleted with the video). Existing files are never overwritten; a video that already has an English subtitle (`.en.srt`, `.eng.srt`, `.English.srt`, a bare `<name>.srt`, or `Subs\<name>\*English*`) gets no new standard one, and an existing SDH/HI one blocks a new SDH one.
- Selection: the best English SRT whose release name matches the video file name (resolution, source, codec, release group) and is not an SDH file = standard; the best one flagged hearing-impaired by TSDB or named SDH / HI / CC / hearing impaired = SDH. Commentary and forced tracks, very small files (under 100 cues for movies, 50 for episodes) are skipped. Each downloaded file is checked (readable text, English by common-word share) and up to 3 candidates are tried per file. Advertising lines (OpenSubtitles, VIP, "Subtitles by...", web addresses) are removed; files are saved as UTF-8.
- Ids: uses the TMDB id in the table. `tvdb:<id>` rows are mapped to TMDB through TMDB's find call (needs the TMDB key) or, without it, to an IMDb id through TVDB's remote ids (needs the TVDB key). Rows with no usable id are skipped and logged. Only high-confidence rows are used when **Only high-confidence** is ticked, like Full Run. Duplicate/collision rows are skipped.
- Limits: TSDB allows about 200 downloads per hour per IP. When the limit is reached the run stops cleanly with a clear message; run it again later and it continues, because files already saved are skipped. Lookups are paced and cached for 3 days in `subs_cache.json`.
- New: every attempt is written to `Logs\subtitles_<date>.csv` (downloaded_at, video_path, subtitle_path, kind, subtitle_id, release_name, cues, result) so downloaded files can be found and removed later.
- New tests: `tests\Test-Subtitles.ps1` (mocked HTTP) and `tests\Test-GuiSubs.ps1` (GUI state on a temp copy; `-Live` also runs the real worker against The Subtitle Database).

## 1.2.0
- Fixed: a year in the file name before " - S01E01" (e.g. "Lioness 2023 - S01E01 - ...") was not recognised as a year, so it was searched as part of the title and the wrong same-named show could be chosen. The year is now parsed and used to pick the right show.
- Fixed: a show on TVDB with the same name but a different first-air year (e.g. "Lioness" 2021 vs the 2023 show in the file name) is no longer accepted; the app now tries the other source and prefers the match whose year fits the file.
- Fixed: TVDB titles that already end in a year, like "Last Man Standing (2011)", no longer get the year twice in the new name.
- New: special characters in titles are made plain in new names (Alien³ becomes Alien3, ligatures and full-width forms are flattened, ™ ® © are dropped). Accented letters are kept.
- New: Setup window (button "Setup..." on the main window) holding the TMDB key, TVDB key and PIN, Theme, "Check real resolution on scan" and "Always read real resolution". Name source and Only high-confidence stay on the main window. Settings are saved when the Setup window is closed.
- New: checkbox "Check real resolution on scan" (main window, on by default, remembered). Untick it to skip reading video headers during Scan; names then keep whatever resolution tag the old name had.
- New: episode labels in new names are uppercase (S01E01 instead of s01e01).
- New: if the old file name has a resolution tag, the new name keeps it as a " - 1080p" suffix, and uses the real resolution read from the video when it differs (note: "resolution corrected 1080p -> 720p"). Names with no resolution tag are left without one.
- Main table: now shows only the old and new file names (not the full paths). Hover a name to see its full path; the Search box still matches the full path.
- Main table: status, confidence, media_type and tmdb_id columns now size to their content; old_path, new_path and note share the remaining width.
- New: table columns (main plan table and Duplicates) stretch to use extra width when the window is enlarged and shrink (down to a minimum width) when it is made smaller.
- New: checkbox "Always read real resolution" (main window, remembered). When ticked, Duplicates uses the resolution found inside each video file instead of the one in its name.
- New: Duplicates shows a resolution for files whose name has none, read from inside the video file (MKV, MP4/M4V/MOV, AVI). Those are marked with * (e.g. `720p*`) and also count for the default 'keep the best' choice.
- Faster: the Duplicates window opens much quicker on large libraries (sidecar lookup now uses a folder index instead of scanning every path for every duplicate file).
- New: TheTVDB (v4) support alongside TMDB. New fields: TVDB API key, optional PIN (only for user-supported keys), and a Name source dropdown (default "Movies: TMDB, TV: TVDB", plus TMDB first, TVDB first, TMDB only, TVDB only).
- By default movies use TMDB first and TV shows use TVDB first, each falling back to the other source. With "TMDB first" a title that TMDB cannot match with high confidence is retried on TVDB (and the other way round for "TVDB first"). Rows matched on TVDB show `tvdb:<id>` in the id column and a "TVDB" note.
- TVDB key and PIN are stored with DPAPI like the TMDB key. TVDB responses are cached in tmdb_cache.json under keys starting with `tvdb|`.
- Layout: new row for the TVDB settings; the rest moved down.

## 1.1.7
- Fixed: Duplicates now includes "COLLISION" rows (target already exists) grouped with the other copy of the same movie.
- Fixed: Duplicates missed the group when there was only one.
- Fixed: a video with several subtitles had them merged into one bogus path (caused the "path too long" error and the earlier blank rows); empty-folder list no longer shows a blank row.
- New: Delete others also removes folders left empty (never the Movies/Series roots); they are listed in the confirmation and logged.

## 1.1.6
- Fixed: Delete others no longer logs blank "missing (skipped)" entries; empty items are ignored.
- Fixed: the "Deleting N file(s)" log line now counts only real files.
- Fixed: delete confirmation no longer shows empty sidecar rows for videos without subtitles/.nfo.
- Fixed: Delete others crash ("Argument types do not match") on Windows PowerShell 5.1.

## 1.1.5
- Fixed "Argument types do not match" when clicking Delete others; any error opening the confirmation is now shown with details and nothing is deleted.

## 1.1.4
- **Fix: network detection.** Mapped NAS drives such as Z: are now detected as network drives. The check uses, in order:
  - kernel32 `GetDriveType` (remote = 4) and `DriveInfo`;
  - WMI `Win32_LogicalDisk` (DriveType 4 or a ProviderName);
  - the `HKCU\Network\<letter>` persistent mapping.
- Any drive that isn't a local fixed or removable disk counts as network. This includes a mapped drive that is invisible because the app runs elevated. Results are cached per drive letter.
- **New delete confirmation window** (themed), replacing the MessageBox:
  - The header separates videos from related files, e.g. "Delete 4 videos and 4 related subtitle/.nfo files - 8.49 GB".
  - A read-only list shows Group, Type (video/sidecar) and Size, with each video's sidecars indented under it.
  - "Keeping: N file(s)" lists the files kept in the affected groups.
  - The warning is red for network drives (permanent delete unless Synology Recycle Bin is enabled) and the Recycle Bin text for local drives.
  - Buttons: a red **Delete**, and **Cancel** as the default for Enter and Esc.
- The summary line now reads "To delete: 4 videos + 4 related subtitle/.nfo files".
- Engine: `Resolve-PRDriveIsNetwork`, `Get-PRDriveTypeCode`, `Get-PRDeleteSummary`, with tests.

## 1.1.3
- **Fix:** the Duplicates dialog showed every file in a single group ("#1 2 3 4 ...", "1 groups"). This is also what caused the earlier op_Modulus crash. `Get-PRDuplicateGroups` returned its array wrapped as one item, and the GUI's `@(...)` then turned the whole list into a single group. It now returns one `[pscustomobject]` per group with an int `Id`, and there are tests for this.
- The Group column shows a short label, e.g. "#3 multiple versions". Shading alternates per group (the `$gi` workaround was replaced by the loop index).
- **Performance:** checkbox clicks are fast now.
  - File sizes and sidecars are read once when the dialog opens and cached in each row's Tag.
  - A click only touches rows in its own group, and the guard flag stops event cascades.
  - The summary is recomputed from the cache without reading the disk.
  - The grid is double-buffered, and layout is suspended while rows are filled.

## 1.1.2
- Duplicates dialog: keep **several files per group**. Every file has its own Keep checkbox, and only the best file is ticked by default. Unticked files and their sidecars are deleted.
- "Keep all" is now a per-group shortcut. Ticking it keeps every file in the group; unticking it goes back to the default.
- Groups where every file is kept are skipped. "Delete others..." is blocked with a message naming any group that keeps no file.
- Checkbox clicks take effect immediately.
- Engine: new `Get-PRDeletePlan` with tests.

## 1.1.1
- Fixed crash when opening the Duplicates window ("op_Modulus" error).

## 1.1.0
- New **Duplicates...** dialog, available after a scan. It lists videos that are duplicates of the same target and movies that have multiple versions.
  - Each file shows its size, modified date, resolution hint and extension.
  - Pick one file to keep per group, or keep the whole group.
  - The files not kept, and their subtitles and `.nfo` files, go to the Recycle Bin. On network paths Windows deletes them permanently.
  - Every deletion is logged to `Logs\deleted_<ts>.csv`, and the library is rescanned automatically.
- Engine: `Get-PRDuplicateGroups`, `Get-PRSidecarsFor`, `Select-PRDefaultKeep`, `PR-ResHint`, `Remove-PRFiles`, with tests in `tests/Test-Duplicates.ps1`.
- The build version is shown in the window title, the footer and the exe's file Properties.

## 1.0.2
- Theme option (System, Light, Dark) with a dark title bar, saved in `settings.json`.
- Fix: `System.Drawing.ControlPaint` corrected to `System.Windows.Forms.ControlPaint`.

## 1.0.1
- Original app icon, used for the exe and the window.

## 1.0.0
- First version of the WinForms GUI: a port of plan.py, apply.ps1 and undo.ps1, with Scan & Dry Run, Full Run, Undo, plan CSV export, TMDB cache, and a DPAPI-protected key.
