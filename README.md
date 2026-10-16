# Renamr

Renamr is a portable Windows app that renames and organizes your movie and TV files into clean, consistent names, using [TMDB](https://www.themoviedb.org/) and [TheTVDB](https://thetvdb.com/) to identify them. Nothing to install: it is a single `Renamr.exe` (or the same thing as a PowerShell script).

```
Movies:   <Movies>\Title (Year)\Title (Year) - 1080p.ext
Episodes: <Series>\Show (Year)\Season 01\Show (Year) - S01E01 - Episode Title.ext
```

## Features
- **Scan first, change later.** Scan is a dry run. Review every row, filter and search, export the plan to CSV, then run it.
- **Safe by design.** Existing files are never overwritten, every Full Run writes an undo log, and Undo puts files back. File timestamps (created, modified, last accessed) are preserved.
- **Two data sources.** Movies from TMDB and TV from TVDB by default, each falling back to the other. Confidence ratings let you apply only the high-confidence matches.
- **Duplicates and multiple versions.** Finds duplicate copies, shades the copy it would keep (green) and the ones it would delete (orange), and lets you choose what to keep. Nothing is deleted unless you choose it.
- **Remake aware.** Uses the year in the file or folder name; never guesses between same-name films by popularity.
- **Real resolution** in names, read from the file itself.
- **English subtitles** (optional): standard and SDH/HI, from The Subtitle Database, with an optional automatic mode after each Full Run.
- Light, dark or system theme. Stop button halts any run cleanly.

## Quick start
1. Get the app: build it from source (below) or download `Renamr.exe` from a release.
2. Open it, pick your Movies and/or Series folder, and open **Setup** to paste your free [TMDB API key](https://www.themoviedb.org/settings/api) (and, for TV, a TVDB key).
3. **Scan**, review, then **Full Run**. Use **Undo...** with the log in the `Logs` folder to reverse a run.

More detail: [User guide](docs/USER_GUIDE.md).

## Build from source
Requires Windows 10/11 with the built-in Windows PowerShell 5.1. From the `source` folder run `BUILD.cmd`. It writes `Renamr.ps1` and `Renamr.exe` one folder up (the exe is compiled with the [ps2exe](https://github.com/MScholtes/PS2EXE) module, which the script installs for the current user if needed). See [Development](docs/DEVELOPMENT.md).

## License
Copyright (C) 2026 JeepNWilly. Renamr is free software under the GNU General Public License, version 3 or (at your option) any later version. It comes with no warranty. See [LICENSE](LICENSE).

Renamr uses data from TMDB and TheTVDB and subtitles from The Subtitle Database, which have their own terms. This product uses the TMDB API but is not endorsed or certified by TMDB.

## Documentation
- [User guide](docs/USER_GUIDE.md)
- [Development guide](docs/DEVELOPMENT.md) and [source layout](source/README.md)
- [Releases and uploading to GitHub](docs/RELEASING.md)
- [Security and privacy](docs/SECURITY.md)
- [Changelog](source/CHANGELOG.md)

## Status
Private project, version in [`source/VERSION`](source/VERSION) (the build number is added at compile time). Licensed under the [GNU General Public License v3.0](LICENSE) (GPL-3.0-or-later). You may use, study, change and share Renamr, and any version you share must also be open source under the same license.
