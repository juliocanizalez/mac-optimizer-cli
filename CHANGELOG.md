# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-03-09

### Added

- **Interactive TUI menu** — arrow-key navigation with toggleable modules and live size estimates
- **8 cleanup modules:**
  - `[0] Trash` (default: on) — empties `~/.Trash`
  - `[1] System Caches` (default: on) — clears `~/Library/Caches`
  - `[2] User Logs` (default: on) — removes `~/Library/Logs`
  - `[3] Xcode DerivedData` (default: on) — deletes `~/Library/Developer/Xcode/DerivedData`
  - `[4] Homebrew Cache` (default: on) — runs `brew cleanup` and removes stale downloads
  - `[5] npm/pnpm/yarn Caches` (default: on) — clears Node package manager caches
  - `[6] Docker Images & Volumes` (default: off) — prunes unused Docker resources
  - `[7] Orphaned App Data` (default: off) — removes `~/Library/Application Support` folders
    whose parent application is no longer installed
- **`--dry-run` flag** — previews all deletions without touching the filesystem
- **`--yes` flag** — skips interactive menu and runs all default-on modules non-interactively
- **`--help` flag** — prints usage and module descriptions
- **Path blocklist** — hard-coded guard that refuses to delete critical system paths
- **sudo heartbeat** — refreshes sudo credentials every 50 s during long-running operations
- **Human-readable summary** — reports total bytes freed per module and overall total
- **Bash 3.2+ compatible** — works on stock macOS without installing a newer shell
