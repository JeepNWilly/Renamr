# Security and privacy

- API keys (TMDB, TVDB, optional TVDB PIN) are stored in `settings.json` next to the app, encrypted with Windows DPAPI for the current Windows user. Never commit `settings.json`; it is git-ignored.
- The app sends only titles, years and ids to TMDB, TheTVDB and The Subtitle Database. File contents are never uploaded.
- Scan is read-only. Files are only moved by Full Run, only renamed to a name that does not yet exist, and every run is logged so it can be undone.
- Duplicate deletion only happens for files you choose, and is logged.
- Report a security problem privately to the repository owner.
