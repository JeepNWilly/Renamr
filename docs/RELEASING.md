# Releases and uploading to GitHub

The repository is public. The exe is published as a release asset.

## What goes in the repo
Source, tests, docs, `Renamr.cmd` and `Renamr.ico`. The built `Renamr.exe`/`Renamr.ps1`, settings, caches and logs are git-ignored. Publish the exe as a **GitHub Release asset**, not in the repo.

## When to upload
Decided later: either manually after a change you are happy with, or automatically every few revisions. Until then, upload manually:
1. Test and rebuild (see the development guide).
2. Update `source/CHANGELOG.md`.
3. `git add -A && git commit -m "Describe the change (v1.4.0.NN)" && git push`.

## Cutting a release
1. Tag the commit: `git tag v<version> && git push --tags`.
2. Create a release from the tag and attach `Renamr.exe` (and a zip with `Renamr.cmd`, `Renamr.ico` and the exe if you like). Paste the matching CHANGELOG section as the notes.

## Before making the repo public
- License: GPL v3 is chosen and in `LICENSE`. If you ever change it, update `LICENSE` and the README License section; copies already shared stay under the old terms.
- Confirm no keys, personal paths or logs are in the history: `git log -p | grep -i -E "api|key|token"` and review `git ls-files`.
- Decide how the app should credit TMDB, TheTVDB and The Subtitle Database (their terms ask for attribution when used publicly).
- Remove or keep `source/reference/` (the original Python/PowerShell tools).
