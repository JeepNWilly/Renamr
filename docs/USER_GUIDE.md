# Renamr Plus user guide

Renamr Plus (formerly just Renamr; the program file is still `Renamr.exe`) renames and sorts your movie and TV files into Plex-style names, using TMDB and TheTVDB to identify them:

```
Movies:   <Movies>\Title (Year)\Title (Year) - 1080p.ext
Episodes: <Series>\Show (Year)\Season 01\Show (Year) - S01E01 - Episode Title.ext
```

Scan never changes anything. Only **Full Run** moves files, it never overwrites a file, and every run can be undone.

## First run
1. Start `Renamr.exe` (or `Renamr.cmd`). If Windows blocked a downloaded copy, right-click it, choose Properties and tick **Unblock**.
2. Set the **Movies folder** and/or **Series folder** with **Browse...** (either may stay empty).
3. Click **Setup...** and paste your TMDB API key (v3). Add a TVDB key (and PIN, if you have one) for TV lookups from TVDB.
4. Pick a **Name source**: Movies: TMDB, TV: TVDB (default), TMDB first, TVDB first, TMDB only or TVDB only.

## Setup
Changes are saved when you close Setup.
- **TMDB API key**, **TVDB API key**, **TVDB PIN**: stored encrypted for your Windows user. **Show keys** reveals them.
- **Theme**: System, Light or Dark.
- **Check real resolution on scan**: reads the resolution from the file so names are right.
- **Always read real resolution (Duplicates window)**.
- **Put movies that are not in a folder into their own "Name (Year)" folder** (on). Off: a movie directly in the Movies folder is only renamed in place.
- **Remove empty folders after Full Run** (on). See Empty folders.
- **Full Run applies only ticked rows** (off). See Full Run.
- **Delete .nfo files during Full Run** (on). See .nfo files.
- **Recycle duplicate subtitles during Full Run** (on). See Duplicate subtitles.
- **Standardize season folder names** (on) with a **Season folder format** such as `Season {NN}` (a preview shows the result). See Season folders.
- **Use US titles** (on): searches in US English and names films and shows by their main US title. See US titles.
- **Enable subtitle download**, **Get standard subtitles**, **Also get SDH / HI subtitles**, **Auto Get Subtitles**. See Subtitles.

## Scan
**Scan** reads the folders and builds the plan in the table. Nothing is changed. The log shows a summary: files ready to rename, folder names to fix, movies/shows to review, files left as they are, the "Unmatched: X movies, Y episodes, Z sidecars with no video" line, the number of .nfo files and the empty folders.
If episodes are found in the Movies folder and no Series folder is set, the log suggests setting one; those episodes are not moved.

Online lookups run several at a time (staying within TMDB's rate limit) and are saved in `tmdb_cache.json`, so a second Scan of the same library takes seconds. The table fills in about a second even with thousands of rows.

### How TV shows are matched
- An episode inside a show folder (`Series\Supernatural\Season 03\...` or `Series\Supernatural (2005)\...`) takes the show name, and the year if the folder has one, from the folder. The file name is used only for files loose in the Series folder, or when the folder is clearly about something else.
- A year in the file name counts as the show's year only when every episode has the same one. Years that change per season (`Supernatural (2007) - S03E01`, `(2011) - S07E01`) are season years and are ignored; the note says so.
- All episodes of a folder share one match, so seasons can't end up under different shows.
- The match must have your episodes: if it lacks most of them and another top result has them, that one is used (the note says "picked by episodes").
- An exact title ("Supernatural") beats a partial one ("Neuro - Supernatural Detective"), even with another year.

## Show filters and Search
- **All**
- **Low confidence - review**: guesses and files with no match. Check these before a Full Run.
- **Will move - high** / **Will move - low**
- **Multiple versions**, **Duplicates / collisions**
- **Unmatched / left in place**, **Already correctly named**
- **Folder case fixes**: one row per folder whose name only differs in letter case.
- **NFO files to delete**
- **Duplicate subtitles to recycle**
- **Season folder fixes**: one row per season folder to rename.

**Search** narrows the table further. **Export plan CSV...** saves the plan.

## Accept, Accept all and Choose match
The **Accept** tick shows exactly what Full Run will do: every row it will act on is ticked (high-confidence renames, folder case and season folder fixes, .nfo files and duplicate subtitles to recycle, and low-confidence rows you accepted).
- Tick a low-confidence row to accept it. Untick any row to leave it as it is: a movie or show is left out with its subtitles; a recycle, .nfo or season folder row skips just that file or folder. The note then starts with "[unticked: Full Run leaves this as is]".
- Rows that depend on a Setup option that is off are unticked, with the note "[not done: '<option>' is off in Setup]".
- **Accept all** ticks every row in the current view (Show filter + Search). Rows with no match are skipped; the log says how many. **Clear accepts** unticks the view.
- **Choose match...** (or double-click a row) works on every movie or episode row, also high-confidence ones. It shows the other possible matches and a **Title** / **Year** **Search**; you can also type an ID: `136418` or `tmdb:136418` (TMDB), `tvdb:1884` (TVDB). **Accept this match** applies it to the whole movie or show and ticks it.
- Your pick is remembered in `match_overrides.json` and used by later Scans, also after the file has been renamed. **Clear pick** in the same window forgets it.

## Full Run
**Full Run** shows "Full Run will do now:" with the counts: high-confidence renames, low-confidence files you accepted, files only put into their own folder (name kept), folder names fixed, .nfo files sent to the Recycle Bin and empty folders removed. Yes starts it; **Stop** halts it after the current file.
- It applies every high-confidence row plus every row you ticked. With **Full Run applies only ticked rows** on, only ticked rows.
- **Only high-confidence** (main window, recommended) keeps unticked low-confidence matches out.
- A file whose new name already exists is skipped.
- A loose movie whose rename is not applied is still put into its own folder, with its name kept.

## US titles
With **Use US titles** on, files are named by the film's or show's main US English title. An alternative title is only used when your file is named exactly as one of its US/UK alternative titles (for example `Redemption (2013)` for the film TMDB lists as *Hummingbird*).

## Season folders
With **Standardize season folder names** on, season folders such as `season 1`, `S1` or `Season1` are renamed in place to the format you set (`Season {NN}` → `Season 01`). A folder whose new name already exists is left alone (never merged). They are listed under **Season folder fixes**; Undo renames them back.

## Duplicate subtitles
With **Recycle duplicate subtitles during Full Run** on, extra copies of a subtitle language that is already placed next to its video are sent to the Recycle Bin (only on drives that have one). They are listed under **Duplicate subtitles to recycle**; the kept copy and the videos are never touched.

## Folder letter case
Windows treats `The matrix (1999)` and `The Matrix (1999)` as the same folder, so a plain rename never fixes it. Renamr Plus renames such folders properly during the Full Run. They are listed under **Folder case fixes**, and Undo changes them back.

## Empty folders
With **Remove empty folders after Full Run** on, folders inside your Movies / Series folders that hold no files at all are removed after the run (including ones the run emptied). Hidden and system folders, the Recycle Bin, `#recycle`, `@eaDir`, `#snapshot` and the folders you picked are never removed. Undo recreates them.

## Subtitles that follow their video
Subtitles move with their video. A subtitle whose video was renamed earlier is re-attached:
- only video in the folder: `<video>.eng.srt`, `<video>.srt` (no language tag) and so on;
- tags written with spaces are cleaned up (`eng.CC eng` → `.en.sdh`, `fra.Canada fre` → `.fr-CA`);
- files in a `Subs` folder move up next to the video, with the language from the name (`3_English.srt` → `.en.srt`);
- several videos in a folder: matched by title and year (`Part II` = `Part 2`);
- left behind in an old folder: matched to the movie elsewhere; these are low confidence, so tick them to apply.

If the same subtitle is already there, the extra copy is skipped as a duplicate. A different one gets a numbered name (`.en.2.srt`) and must be ticked.

## Getting subtitles (optional)
Tick **Enable subtitle download** in Setup to show **Get subtitles...**. After a Scan it looks up English subtitles on The Subtitle Database (no account), shows what it found, asks to confirm, and saves `<name>.en.srt` and `<name>.en.sdh.srt`. Existing files are never overwritten. **Auto Get Subtitles** does this after each Full Run that moved files. The free service allows about 200 downloads per hour; at the limit Renamr Plus stops cleanly and the next run continues.

## .nfo files
With **Delete .nfo files during Full Run** on, every `.nfo` file under your Movies / Series folders is sent to the Windows Recycle Bin during the Full Run (before empty folders are removed). On a drive with no Recycle Bin, such as a network share, they are kept, never deleted for good. Turn the option off to keep .nfo files; they are then renamed with their video.

## Duplicates
After a Scan, **Duplicates...** lists copies of the same movie or episode. Green rows are the copy that would be kept, orange the ones that would be deleted. Tick **Keep** for the files you want; nothing is deleted until **Delete others...** (local drives: Recycle Bin; network drives: permanent, with a warning).

## Undo
**Undo...** asks for an undo log from the `Logs` folder, shows what it will reverse and asks to confirm. Files go back only where the original place is free; removed empty folders are recreated and folder case changes are reversed. .nfo files cannot be restored by Undo: it tells you how many are in the Recycle Bin, so restore them from there.

## Files kept next to the app
`settings.json`, `tmdb_cache.json`, `subs_cache.json`, `match_overrides.json` (your Choose match picks) and the `Logs` folder: `plan_<date>.csv` and `undo_<date>.csv` for each Full Run, `deleted_<date>.csv` for Duplicates, `subtitles_<date>.csv` for downloads.

## Troubleshooting
- **SmartScreen warning:** the exe is not code-signed. Choose More info, then Run anyway.
- **Nothing found or wrong match:** add the year to the file or folder name, or use **Choose match...** (a title or a TMDB/TVDB ID). For TV, keep each show in its own folder named after the show. AMBIGUOUS and POSSIBLE REMAKE rows need a year.
- **A file was skipped:** a file with the new name already exists. Check the Duplicates view.
- **Episodes not renamed:** set the Series folder in the main window.
- **A subtitle shows as numbered or low confidence:** check it, then tick Accept to apply it.
- **No API key message:** open Setup and paste the TMDB key.
- **Run seems stuck:** press **Stop**; files moved so far stay in the undo log.
