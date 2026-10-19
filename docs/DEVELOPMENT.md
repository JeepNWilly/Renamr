# Development guide

Renamr is Windows PowerShell 5.1 + WinForms, compiled to an exe with ps2exe. There is no other toolchain.

## Layout
- `source/Renamr.Engine.ps1`: all logic, no UI (parsing, TMDB/TVDB clients, planning, apply/undo, duplicates, subtitles).
- `source/Renamr.Gui.ps1`: the WinForms UI; runs the engine in a background runspace.
- `source/build_exe.ps1`, `source/BUILD.cmd`: embed the engine into the GUI, write `Renamr.ps1` and compile `Renamr.exe` (both one level up, both git-ignored).
- `source/tests/`: tests. `source/reference/`: the original command-line tools the app was ported from.
- `source/VERSION` is major.minor.patch; `source/BUILD_NUMBER` goes up by one on every compile (this file changes on every build, so commit it with the change or leave it out of the commit).

Full details: [source/README.md](../source/README.md).

## Workflow
1. Edit the engine or GUI. Never edit the generated `Renamr.ps1`.
2. Run the tests from `source` with Windows PowerShell 5.1, for example:
   `powershell -ExecutionPolicy Bypass -File tests\Test-Remake.ps1`
   Offline tests: `Test-Parse`, `Test-Remake`, `Test-Duplicates`, `Test-ApplyUndo`, `Test-Tvdb`, `Test-Subtitles`, `Test-FolderLoose`, `Test-Accept`, `Test-Folders`, `Test-Reattach`, `Test-Nfo`. Run them all with `Get-ChildItem tests\Test-*.ps1 | ? Name -ne Test-Engine.ps1 | % { powershell -NoProfile -ExecutionPolicy Bypass -File $_.FullName }`. `Test-GuiSubs` opens the GUI on a temp copy. `Test-Engine` needs a cache file or a live key.
3. Rebuild with `BUILD.cmd` and start the exe to check it opens.
4. Add a line to `source/CHANGELOG.md` under the current version, and update the docs if behavior changed.

## Gotchas (Windows PowerShell 5.1)
- `-and` and `-or` have equal precedence: parenthesize mixed conditions.
- `$Host` is read-only; functions that return lists may need unwrapping with `@(... | ForEach-Object { $_ })`.
- Run moves from a neutral folder (`Set-Location C:\`) so a folder can be removed.
- Close the running exe before rebuilding; Windows locks it.
- Variable names are case-insensitive: a parameter `$Existing` and a local `$existing` are the same variable.
- `return ,$list` keeps a list as one object; do not wrap such a call in `@()` again.
