# Renamr user guide

## First run
1. Start `Renamr.exe` (or `Renamr.cmd`, which runs `Renamr.ps1` with Windows PowerShell). If Windows blocked a downloaded copy, right-click the file or zip, choose Properties, tick **Unblock**.
2. Set the **Movies folder** and/or **Series folder** (either may stay empty).
3. Click **Setup...** and paste your TMDB API key (v3). Add a TVDB key if you want TV lookups from TVDB. Keys are stored in `settings.json` next to the app, encrypted for your Windows account.
4. Choose a **Name source**: Movies: TMDB, TV: TVDB (default), TMDB first, TVDB first, TMDB only, or TVDB only.

## Daily use
- **Scan** reads the folders and builds a plan. Nothing is changed. Use **Show** and **Search** to filter. **Export plan CSV...** saves the plan.
- **Only high-confidence** (recommended) leaves low-confidence matches alone. Review those rows first; rows marked AMBIGUOUS or POSSIBLE REMAKE need a year in the file name.
- **Full Run** asks to confirm, then moves and renames. A file whose new name already exists is skipped. **Stop** halts the run after the current file. An undo log (`Logs\undo_<date>.csv`) and the plan (`Logs\plan_<date>.csv`) are written.
- **Undo...** lets you pick an undo log, preview it, and confirm. A file is only moved back if its original place is free.

## Duplicates
After a Scan, **Duplicates...** lists groups of copies. The main table shades the copy that would be kept (green: best resolution, then largest) and the ones that would be deleted (orange). Tick **Keep** for the files you want; nothing is deleted until you use **Delete others...**, and a log is written to `Logs\deleted_<date>.csv`.

## Subtitles (optional)
Tick **Enable subtitle download** in Setup to show **Get subtitles...**. It finds English subtitles (standard, and SDH/HI if ticked) on The Subtitle Database, asks to confirm, and saves them next to each video as `<name>.en.srt` and `<name>.en.sdh.srt`. Existing subtitle files are never overwritten.
**Auto Get Subtitles** does the same automatically after each Full Run that moved files. The free service allows about 200 downloads per hour and also limits lookups; when a limit is reached Renamr stops cleanly and the next run continues where it left off.

## Other settings
- **Put movies that are not in a folder into their own "Name (Year)" folder** (on by default). Off: a movie directly in the Movies folder is only renamed in place.
- **Check real resolution on scan**: reads the real resolution so names are accurate.
- **Theme**: System, Light or Dark.

## Files kept next to the app
`settings.json`, `tmdb_cache.json`, `subs_cache.json` and the `Logs` folder.
