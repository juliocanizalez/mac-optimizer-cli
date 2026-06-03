# mac-optimizer-cli

[![CI](https://github.com/juliocanizalez/mac-optimizer-cli/actions/workflows/release.yml/badge.svg)](https://github.com/juliocanizalez/mac-optimizer-cli/actions/workflows/release.yml)
[![Latest Release](https://img.shields.io/github/v/release/juliocanizalez/mac-optimizer-cli?color=orange)](https://github.com/juliocanizalez/mac-optimizer-cli/releases/latest)
[![Homebrew Tap](https://img.shields.io/badge/homebrew-juliocanizalez%2Ftap-blue?logo=homebrew)](https://github.com/juliocanizalez/homebrew-tap)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey?logo=apple)](https://www.apple.com/macos)
[![Shell](https://img.shields.io/badge/built%20with-bash-89e051?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)

Your Mac is slow. Disk is full. You have no idea why. Xcode left 14 GB of derived data from a project you deleted two years ago. Safari cached the entire internet. There are apps in `/Applications` you genuinely don't remember installing.

`mac-optimizer` fixes all of that through a checkbox menu. You pick what to clean, it shows you how much space you'll get back, you press Enter. That's it.

Written in bash because it ships with your Mac and you don't need to install anything.

---

## Installation

**Via Homebrew (recommended):**

```bash
brew tap juliocanizalez/tap
brew install mac-optimizer
```

**Manual:**

```bash
curl -fsSL https://github.com/juliocanizalez/mac-optimizer-cli/releases/latest/download/mac-optimizer.sh \
  -o mac-optimizer.sh
chmod +x mac-optimizer.sh
./mac-optimizer.sh
```

---

## Usage

```bash
mac-optimizer               # interactive TUI — pick modules, press Enter
mac-optimizer --dry-run     # preview everything, delete nothing
mac-optimizer --dry-run --yes  # non-interactive preview (good for CI)
mac-optimizer --yes         # run defaults without any confirmation prompts
```

The menu opens, shows each cleanup module with its estimated size, and waits for you to confirm before touching anything.

---

## Modules

| # | Module | Default | Needs sudo |
|---|--------|---------|------------|
| 0 | User Caches | ON | no |
| 1 | System Logs | ON | yes |
| 2 | Temp Files | ON | no |
| 3 | Developer Junk | OFF | no |
| 4 | Browser Data | OFF | no |
| 5 | System Maintenance | ON | yes |
| 6 | App Uninstaller | OFF | no |
| 7 | Orphaned Data | OFF | no |

**Developer Junk** covers Xcode DerivedData, Simulator caches, npm, pip, Yarn, Gradle, CocoaPods, and JetBrains caches — the usual suspects.

**Browser Data** detects which browsers you have installed and handles Safari, Chrome, Brave, and Firefox. Caches are deleted automatically; cookies and history require a per-browser confirmation.

**App Uninstaller** shows a scrollable list of everything in `/Applications`. Select one or more, press Enter, they're gone along with their associated support files and preferences.

**Orphaned Data** finds `~/Library` entries whose bundle ID no longer matches any installed app — the junk that app uninstallers leave behind.

---

## Options

| Flag | Short | What it does |
|------|-------|--------------|
| `--dry-run` | `-n` | Print every action, perform none |
| `--yes` | `-y` | Skip confirmation prompts |
| `--help` | `-h` | Show help and exit |
| `--init-config` | | Write a default config file and exit |
| `--config-path` | | Print the config file path and exit |

---

## Configuration

`mac-optimizer` reads `~/.config/mac-optimizer/config.toml` on startup. The file is optional — built-in defaults apply if it doesn't exist. CLI flags always override config values.

```bash
mac-optimizer --init-config                    # create the file
$EDITOR $(mac-optimizer --config-path)         # open it
```

```toml
# ~/.config/mac-optimizer/config.toml

[modules]
# Which modules start checked in the TUI
user_caches        = true
system_logs        = true
temp_files         = true
developer_junk     = false
browser_data       = false
system_maintenance = true
app_uninstaller    = false
orphaned_data      = false

[defaults]
dry_run  = false
auto_yes = false
```

---

## Safety

Every deletion goes through `safe_delete`, which enforces a hardcoded blocklist of paths that will never be touched regardless of what a module requests: `/`, `/System`, `/usr`, `/bin`, `/sbin`, `/private/etc`, `/Library`, and `$HOME` itself.

`--dry-run` is always a safe way to review what would happen before committing to it.

There is no undo. Deletions are permanent.

---

## How it works

1. Sizes are calculated for each module via `du`.
2. The interactive menu renders in the alternate screen buffer — your terminal history is untouched.
3. `sudo` is acquired once (if any selected module needs it) and kept alive via a background heartbeat for the duration of the run.
4. Selected modules execute sequentially, logging every action.
5. A summary box shows total space freed and a scrollable log.

---

## Adding a module

1. Append to the four parallel arrays in `src/lib/globals.sh`.
2. Implement `module_N_clean()` in `src/modules/`.
3. Add a size calculation entry in `src/lib/utils.sh` → `calculate_all_sizes`.
4. Add the module to the `--help` output in `src/entrypoint.sh`.

The dispatch loop picks up `module_N_clean` by name automatically — no wiring needed.

---

## Development

```bash
make build    # assemble mac-optimizer.sh from src/
make check    # build + syntax check
make test     # build + dry-run smoke test
make release  # tag and push (triggers GitHub Actions)
```

Bump the version first:

```bash
make bump-patch   # 1.2.0 → 1.2.1
make bump-minor   # 1.2.0 → 1.3.0
make bump-major   # 1.2.0 → 2.0.0
```

The release workflow builds the script, creates a GitHub Release with the artifact, and updates the Homebrew formula in `juliocanizalez/homebrew-tap` automatically.

---

## Uninstalling

```bash
brew uninstall mac-optimizer
```

Or just delete the script if you installed manually.

---

## License

MIT. See [LICENSE](LICENSE).
