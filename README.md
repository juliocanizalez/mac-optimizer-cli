# mac-optimizer-cli

A single self-contained bash script for macOS disk cleanup and system maintenance.
It presents an interactive arrow-key checkbox menu, calculates reclaimable disk
space before showing that menu, and either previews or performs the chosen operations.

---

## Table of Contents

1. [Requirements](#requirements)
2. [Quick Start](#quick-start)
3. [CLI Flags](#cli-flags)
4. [Interactive Menu](#interactive-menu)
5. [Script Architecture](#script-architecture)
6. [Global State Reference](#global-state-reference)
7. [Module Reference](#module-reference)
8. [Core Function Reference](#core-function-reference)
9. [Terminal Management](#terminal-management)
10. [ANSI and Box Rendering](#ansi-and-box-rendering)
11. [Sudo Management](#sudo-management)
12. [Path Blocklist and Safety Model](#path-blocklist-and-safety-model)
13. [Non-Interactive Mode](#non-interactive-mode)
14. [Adding a New Module](#adding-a-new-module)
15. [Testing and Verification](#testing-and-verification)
16. [Known Limitations](#known-limitations)

---

## Requirements

- macOS (the script exits immediately on any other OS via `uname -s` check)
- Bash 3.2 or later — the default `/bin/bash` shipped with macOS is sufficient; no Homebrew bash
  required
- Standard POSIX utilities: `du`, `awk`, `sed`, `grep`, `defaults`, `launchctl`, `tput`, `stty`
- `sudo` access is optional; modules that require it are skipped gracefully when unavailable

---

## Quick Start

```bash
# Clone or copy the script
chmod +x mac-optimizer.sh

# Interactive mode — shows the checkbox menu
./mac-optimizer.sh

# Preview everything, answer nothing, delete nothing
./mac-optimizer.sh --dry-run --yes

# Run default selections without any confirmation prompts
./mac-optimizer.sh --yes
```

---

## CLI Flags

| Flag | Short | Effect |
|------|-------|--------|
| `--dry-run` | `-n` | Print every action that would be taken; perform no deletions and run no system commands |
| `--yes` | `-y` | Auto-answer "yes" to every `_confirm` prompt; interactive module sub-flows still accept typed input unless stdin is not a TTY |
| `--help` | `-h` | Print usage and exit |

Flags may be combined freely: `--dry-run --yes` is the standard non-interactive preview mode used
for CI or debugging.

---

## Interactive Menu

When stdout and stdin are both TTYs the script enters the alternate screen buffer and renders a
bordered checkbox list. Sizes calculated just before the menu appears are shown inline.

```
╔════════════════════════════════════════════╗
║  mac-optimizer-cli  v1.0.0                 ║
╠════════════════════════════════════════════╣
║ Select modules:                            ║
║  ► [x] User Caches          ~5.3 GB       ║
║    [x] System Logs           ~340 MB      ║
║    [x] Temp Files             ~89 MB      ║
║    [ ] Developer Junk        ~4.1 GB      ║
║    [ ] Browser Data          ~210 MB      ║
║    [x] System Maintenance                 ║
║    [ ] App Uninstaller                    ║
║    [ ] Orphaned Data         ~890 MB      ║
╠════════════════════════════════════════════╣
║  Space:toggle  Enter:run  q:quit          ║
╚════════════════════════════════════════════╝
```

### Key bindings

| Key | Action |
|-----|--------|
| Arrow Up / Arrow Down | Move the cursor |
| Space | Toggle the module under the cursor on or off |
| Enter | Accept selections and proceed |
| q / Q | Quit without making any changes |

The menu is rendered entirely inside the alternate screen buffer (`tput smcup`). When the user
presses Enter or q, the buffer is discarded (`tput rmcup`) and the normal terminal is restored
before any cleaning output begins.

---

## Script Architecture

The file is divided into ten labeled sections (A through J) that appear in dependency order. Lower
sections depend on higher ones; the entry point at J calls everything above it.

```
[A] Preamble         shebang, strict mode, VERSION constant
[B] Global State     all mutable runtime variables and module arrays
[C] UI Primitives    ANSI constants, terminal helpers, menu renderer, event loop,
                     pick-list widget (_pick_list), spinner (_spin_start/_spin_stop),
                     scrollable log viewer (_scrollable_log)
[D] Size Helpers     size_kb, human_size, calculate_all_sizes
[E] Sudo             needs_sudo, acquire_sudo, heartbeat background process
[F] Safe Delete      is_blocked_path, safe_delete
[G] Module Functions module_N_clean for modules 0-7, plus helpers find_app_files,
                     _build_installed_ids, _is_installed
[H] Execution        _confirm, run_selected_modules (dispatch loop)
[I] Summary          print_summary (boxed results display)
[J] Entry Point      parse_args, print_help, main
```

### Execution flow inside `main()`

```
parse_args "$@"
  |
  +-- set DRY_RUN, AUTO_YES; print help or error
  |
calculate_all_sizes          -- populates MODULE_SIZES[] via du
  |
run_menu                     -- interactive checkbox UI (skipped if not a TTY)
  |
acquire_sudo                 -- prompts once; starts heartbeat background process
  |
run_selected_modules         -- global confirm, then dispatches each enabled module
  |
print_summary                -- boxed total freed + log
```

---

## Global State Reference

All mutable state lives as plain shell variables at the top of the file (section B). No subshells
or files are used for state; everything is passed through globals.

### Runtime flags

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `DRY_RUN` | int | `0` | Set to `1` by `--dry-run`; all destructive steps are skipped |
| `AUTO_YES` | int | `0` | Set to `1` by `--yes`; `_confirm` always returns success |

### Sudo state

| Variable | Type | Description |
|----------|------|-------------|
| `SUDO_AVAILABLE` | int | `1` after a successful `sudo -v`, `0` otherwise |
| `SUDO_CMD` | string | Either `"sudo"` or `""` — prepended to privileged `rm` calls in `safe_delete` |
| `SUDO_HEARTBEAT_PID` | string | PID of the background keepalive process; killed by the EXIT trap |

### Module parallel arrays

All four arrays are indexed by module number (0–7) and must remain aligned.

| Array | Values | Description |
|-------|--------|-------------|
| `MODULE_NAMES` | strings | Display name shown in the menu |
| `MODULE_SELECTED` | 0 or 1 | Whether the module is currently checked |
| `MODULE_NEEDS_SUDO` | 0 or 1 | Whether the module requires elevated privileges |
| `MODULE_SIZES` | string or `""` | Pre-calculated human-readable size shown next to the name |

Default selection state (`MODULE_SELECTED`):

```
Index  Name                 Default
  0    User Caches          ON
  1    System Logs          ON
  2    Temp Files           ON
  3    Developer Junk       OFF
  4    Browser Data         OFF
  5    System Maintenance   ON
  6    App Uninstaller      OFF
  7    Orphaned Data        OFF
```

### Accounting

| Variable | Type | Description |
|----------|------|-------------|
| `BYTES_FREED_TOTAL` | int | Running byte total of all successfully deleted content |
| `CLEAN_LOG` | array | One string entry per deletion or action for the summary box |

---

## Module Reference

Each module has a `module_N_clean` function in section G that performs the actual work. Size
estimation for the menu is handled by `calculate_all_sizes` (section D) using independent `size_kb`
calls; the two code paths are intentionally separate so size estimation never breaks cleaning.

### Module 0 — User Caches

Sudo required: no. Default: ON.

Iterates over every subdirectory inside `~/Library/Caches/` and deletes each one except entries
present in a hardcoded allowlist:

- `com.apple.AppleMultitouchTrackpad` — trackpad gesture data that would be re-learned
- `com.apple.findmydeviced` — Find My device location cache

Also removes loose `.db` and `.sqlite` files placed directly in `~/Library/Caches/`.

### Module 1 — System Logs

Sudo required: yes (for system paths). Default: ON.

User-level targets (no sudo):
- All subdirectories under `~/Library/Logs/`
- `~/Library/Logs/*.log` and `~/Library/Logs/*.crash`

System-level targets (requires `SUDO_CMD`):
- `/private/var/log/*.gz` — gzip-rotated system logs only, not active log files
- `/private/var/log/asl/*.asl` — Apple System Log archive segments

### Module 2 — Temp Files

Sudo required: no. Default: ON.

- `/private/tmp/*` — system-wide temporary directory
- `$TMPDIR/*` — per-user per-session temporary directory (typically a path under
  `/private/var/folders/`). Skipped if `$TMPDIR` resolves to `/tmp` or `/private/tmp` to avoid
  double-counting.

### Module 3 — Developer Junk

Sudo required: no. Default: OFF.

Targets in order:

1. `~/Library/Developer/Xcode/DerivedData` — unconditional deletion
2. `~/Library/Developer/Xcode/Archives` — shown a warning first ("may contain App Store
   submissions"); requires an explicit confirmation even under `--yes`
3. `~/Library/Developer/CoreSimulator/Caches`
4. `$(brew --cache)/downloads` — Homebrew download cache (only if `brew` is on `$PATH`)
5. `~/.npm/_cacache` — npm content-addressable cache
6. `~/Library/Caches/Yarn` and `~/.yarn/cache` — Yarn (v1 and v2/Berry)
7. `~/Library/Caches/pip/http` and `~/Library/Caches/pip/wheels` — pip HTTP and wheel caches
8. `~/.gradle/caches` — Gradle module cache
9. `~/Library/Caches/CocoaPods` and `~/.cocoapods/repos` — CocoaPods spec repos
10. `~/Library/Caches/JetBrains/*/` — one subdirectory per JetBrains IDE

### Module 4 — Browser Data

Sudo required: no. Default: OFF.

The module detects which browsers are installed by checking for their profile directories. For each
present browser it handles three data categories with different confirmation requirements:

| Category | Behavior |
|----------|----------|
| Caches | Deleted unconditionally once the module runs |
| Cookies | Requires a per-browser confirmation prompt |
| History | Requires a per-browser confirmation prompt |

Browsers and their data paths:

**Safari**
- Cache: `~/Library/Caches/com.apple.Safari/`
- Cookies: `~/Library/Cookies/Cookies.binarycookies`
- History: `~/Library/Safari/History.db` (plus `-shm` and `-wal` WAL files)

**Chrome**
- Cache: `~/Library/Caches/Google/Chrome/*/` + `~/Library/Application Support/Google/Chrome/*/Cache/`
- Cookies: `~/Library/Application Support/Google/Chrome/*/Cookies`
- History: `~/Library/Application Support/Google/Chrome/*/History`

**Brave**
- Cache: `~/Library/Caches/BraveSoftware/*/`
- Cookies: `~/Library/Application Support/BraveSoftware/Brave-Browser/*/Cookies`
- History: `~/Library/Application Support/BraveSoftware/Brave-Browser/*/History`

**Firefox**
- Cache: `~/Library/Caches/Firefox/Profiles/<profile-name>/` (matched by profile directory name)
- Cookies: `~/Library/Application Support/Firefox/Profiles/*/cookies.sqlite`
- History: `~/Library/Application Support/Firefox/Profiles/*/places.sqlite` — note: this SQLite
  database also stores bookmarks; the prompt explicitly warns the user of this

### Module 5 — System Maintenance

Sudo required: yes. Default: ON.

This module performs three tasks in sequence:

1. **DNS flush** — runs `sudo killall -HUP mDNSResponder`. In dry-run mode the command is printed
   but not executed.

2. **Periodic scripts** — runs `sudo periodic daily weekly monthly`. If the `periodic` binary is
   absent (removed in macOS Sequoia and later) this step is silently skipped with an explanatory
   message.

3. **LaunchAgents audit** — lists every `.plist` file in `~/Library/LaunchAgents/` with a
   `loaded`/`unloaded` status obtained from `launchctl list`. The user may enter a single number to
   unload and disable that agent via `launchctl unload -w`.

### Module 6 — App Uninstaller

Sudo required: no. Default: OFF.

1. Enumerate all `.app` bundles under `/Applications/` and `~/Applications/`, showing each with
   its disk size.
2. A scrollable checkbox list (`_pick_list`) lets the user select zero or more apps with arrow
   keys and Space; `a` selects all, `n` deselects all, Enter confirms, `q` cancels.
3. For each selected app a spinner animates while `safe_delete` removes the `.app` bundle.
4. A summary line reports how many apps were removed.

In non-TTY mode the list falls back to the same number-entry prompt used in v1.0.

### Module 7 — Orphaned Data

Sudo required: no. Default: OFF.

Identifies data left behind by applications that are no longer installed.

**Step 1 — Build the installed-app set.**
`_build_installed_ids` reads `CFBundleIdentifier` from every `.app` in `/Applications/` and
`~/Applications/` using `defaults read`. The result is stored as a newline-separated string in
`_INSTALLED_IDS`. The lookup function `_is_installed BUNDLE_ID` uses `grep -qxF` against this
string, which avoids the need for associative arrays and keeps the code compatible with bash 3.2.

**Step 2 — Scan for orphans.**
For each of the following locations, entries whose name looks like a bundle identifier (contains a
dot) and is not in the installed set are collected:
- `~/Library/Application Support/`
- `~/Library/Caches/`
- `~/Library/Saved Application State/`
- `~/Library/Containers/`
- `~/Library/Group Containers/`
- `~/Library/Preferences/*.plist` (stem = bundle ID)
- `~/Library/LaunchAgents/*.plist` (the `Label` key is compared, not the filename)

Entries matching `com.apple.*` are always skipped; macOS manages those entries itself.

**Step 3 — Interactive selection.**
Found orphans are shown in a scrollable checkbox list (`_pick_list`) with sizes. The user
navigates with arrow keys, toggles items with Space, and confirms with Enter. A spinner animates
per-item deletion. In non-TTY mode the list falls back to the number-entry prompt.

---

## Core Function Reference

### `safe_delete [sudo] PATH...`

The single primitive used for every deletion in the script. Accepts an optional literal string
`sudo` as the first argument to indicate the path requires elevated privileges.

For each path:
1. Skips silently if the path does not exist.
2. Calls `is_blocked_path` and prints `BLOCKED` if the path is protected (see
   [Path Blocklist](#path-blocklist-and-safety-model)).
3. Measures the current disk usage with `du -sk`.
4. If `DRY_RUN=1`: prints `[DRY-RUN] Would remove: PATH (SIZE)` and stops.
5. If `use_sudo=1` but `SUDO_CMD` is empty: prints `Skipping (no sudo): PATH` and stops.
6. Otherwise executes `rm -rf -- "$path"` (optionally prepended with `$SUDO_CMD`). On success,
   adds the KB count to `BYTES_FREED_TOTAL` and appends to `CLEAN_LOG`. On failure, appends a
   `FAILED:` entry to `CLEAN_LOG`.

The `--` before the path prevents paths starting with `-` from being treated as flags.

### `_confirm PROMPT`

Prints the prompt and waits for a single line of input. Returns 0 (success/yes) only when the
user types `y` or `Y`.

When `AUTO_YES=1` the function prints the prompt with `[auto: yes]` appended and returns 0
immediately without reading from stdin.

### `size_kb PATH...`

Accepts one or more paths. For each path that exists, runs `du -sk` and accumulates the total.
All errors from `du` are suppressed; missing paths are skipped silently. Prints the integer KB
total to stdout.

### `human_size KB`

Converts an integer kilobyte count to a human-readable approximation using awk:
- >= 1,048,576 KB: displayed as `~N.N GB`
- >= 1,024 KB: displayed as `~N MB`
- otherwise: displayed as `~N KB`

### `calculate_all_sizes`

Loops over all eight module indices and calls `size_kb` with the appropriate paths for each.
Modules 5, 6, and 7 report size `0` because they perform actions (system commands, interactive
flows) rather than simple file deletions. The result is stored in `MODULE_SIZES[$i]` as a
human-readable string, or as an empty string if the size is zero.

Called once from `main()` before `run_menu` so the menu can display sizes immediately.

### `needs_sudo`

Returns 0 (success) if at least one selected module has `MODULE_NEEDS_SUDO[$i]=1`. Used by
`acquire_sudo` to decide whether to prompt for a password at all.

### `is_blocked_path PATH`

Returns 0 (true, meaning blocked) for paths that must never be deleted:
- Exact matches: `/`, `/System`, `/usr`, `/bin`, `/sbin`, `/private/etc`, `/Library`, `$HOME`
- Prefix matches: `/System/*`, `/usr/*`, `/bin/*`, `/sbin/*`, `/private/etc/*`

Trailing slashes are stripped before comparison. Any path not matching a blocked pattern returns 1
(not blocked) and is allowed to proceed through `safe_delete`.

### `_pick_list TITLE VIEWPORT_HEIGHT ITEM...`

Renders a scrollable, keyboard-driven checkbox list inside a `┌─┐` bordered box of fixed height
(`VIEWPORT_HEIGHT + 4` lines). Keys: ↑↓ move cursor, Space toggles, `a` selects all, `n`
deselects all, Enter confirms, `q` cancels (returns exit code 1).

On return, the selected indices are available as newline-separated integers in `_PICK_RESULT`.
When stdin or stdout is not a TTY the function falls back to the existing number-entry prompt.

### `_spin_start MSG` / `_spin_stop 0|1 [LABEL]`

`_spin_start` launches a Braille-spinner (`⠋⠙⠹…`) in a background subshell that overwrites the
current line at 10 fps. `_spin_stop` kills the spinner, clears the line, and prints `✓ LABEL` or
`✗ LABEL` depending on the exit-code argument. In non-TTY mode `_spin_start` prints a plain
`… MSG` line and `_spin_stop` prints the result on the next line.

### `_scrollable_log TITLE HEIGHT`

Renders an interactive `╔═╗` box of fixed height that scrolls through `CLEAN_LOG` with ↑↓ arrow
keys. Shown by `print_summary` after a run completes (TTY only); falls back to a plain list in
non-TTY mode.

### `find_app_files BUNDLE_ID APP_NAME`

Searches a fixed set of standard macOS data directories for files and directories whose name
matches the bundle ID or application name. Paths within system-level directories are prefixed with
`sudo:` in the output so the caller can pass them to `safe_delete sudo`. The function prints one
path per line to stdout and is consumed with a `while IFS= read -r line` loop.

### `_build_installed_ids` / `_is_installed BUNDLE_ID`

`_build_installed_ids` populates the global `_INSTALLED_IDS` string by reading
`CFBundleIdentifier` from every `.app` in the standard application directories. Each bundle ID is
appended as a newline-terminated line.

`_is_installed` performs a `grep -qxF` (exact whole-line fixed-string) search against
`_INSTALLED_IDS`. This approach was chosen instead of a bash associative array (`declare -A`) to
maintain compatibility with the bash 3.2 that ships with macOS.

---

## Terminal Management

The script keeps track of two distinct state flags to avoid spurious terminal escape codes when
running in non-interactive contexts (e.g., when `--help` exits early or when stdout is redirected):

| Flag | Set by | Cleared by |
|------|--------|------------|
| `_in_menu` | `run_menu` before `tput smcup` | `run_menu` ENTER/QUIT branch; `restore_terminal` |
| `_terminal_modified` | `setup_terminal` (hides cursor, disables echo) | `run_menu` ENTER branch; `restore_terminal` |

`restore_terminal` is registered as the handler for `EXIT`, `INT`, and `TERM` signals via `trap`.
It checks both flags before issuing `tput cnorm`, `stty echo`, or `tput rmcup`, which means the
trap is safe to call multiple times and produces no output when the terminal was never modified.

The sequence within `run_menu`:

```
tput smcup      -- save screen, switch to alternate buffer
setup_terminal  -- tput civis (hide cursor), stty -echo
  ...event loop...
tput rmcup      -- restore saved screen (menu disappears cleanly)
tput cnorm      -- show cursor
stty echo       -- restore echo
```

`tput cup 0 0` (move cursor to row 0, column 0) is issued at the start of each call to
`render_menu`. Since the alternate screen is fixed in size and the number of menu lines never
changes, drawing over the existing content is sufficient — no `tput clear` is needed and there is
no visible flicker.

---

## ANSI and Box Rendering

### Color constants

Defined as escape sequences at the top of section C:

| Constant | Code | Effect |
|----------|------|--------|
| `RED` | `\033[0;31m` | Error messages, blocked paths |
| `GREEN` | `\033[0;32m` | Success messages, selected checkboxes |
| `YELLOW` | `\033[1;33m` | Warnings, dry-run messages, active cursor pointer |
| `CYAN` | `\033[0;36m` | Box borders |
| `BOLD` | `\033[1m` | Section headers, selected items |
| `DIM` | `\033[2m` | Unselected checkboxes, size annotations, skipped items |
| `NC` | `\033[0m` | Reset — must follow every colored sequence |

### Box primitives

**`_sep N`** — builds a string of `N` Unicode double-horizontal-bar characters (`═`, U+2550) used
for the top, middle, and bottom border lines.

**`_box_row INNER_W CONTENT CONTENT_VLEN`** — prints a single bordered row. The caller is
responsible for providing `CONTENT_VLEN`, the visual character count of `CONTENT` *excluding* ANSI
escape sequences. The function computes `pad = INNER_W - CONTENT_VLEN` and appends that many
spaces before the closing border character.

This design avoids a subshell call to `_vlen` / `_strip_ansi` inside the hot render loop (eight
calls per keypress). Instead, visual lengths are pre-calculated arithmetically in `render_menu`:

```bash
# Fixed layout for a module row:
# space(1) + pointer(2) + checkbox(3) + space(1) + name(NAME_FIELD) + size_vlen
local vlen=$(( 1 + ptr_vlen + 3 + 1 + NAME_FIELD + sz_vlen ))
```

**`_strip_ansi`** and **`_vlen`** are available for one-off calculations elsewhere in the script
(e.g., for the summary box) where the subshell overhead is acceptable.

### Box dimensions

| Constant | Value | Meaning |
|----------|-------|---------|
| `BOX_W` | 46 | Total visual width of the menu box including the two border characters |
| `BOX_IW` | 44 | Inner content width (`BOX_W - 2`) |
| `NAME_FIELD` | 20 | Characters reserved for the module name column (padded with spaces) |

The longest module name, "System Maintenance" (18 characters), fits within `NAME_FIELD=20`.

---

## Sudo Management

`acquire_sudo` runs after `run_menu` returns and before modules execute. This sequencing means the
password prompt appears on the clean normal screen, not inside the alternate-screen menu.

If `needs_sudo` returns false (no selected module requires sudo), `acquire_sudo` returns immediately
without prompting.

On success (`sudo -v` exits 0), the script:
1. Sets `SUDO_AVAILABLE=1` and `SUDO_CMD="sudo"`.
2. Spawns a background subshell that runs `sudo -n -v` every 50 seconds to prevent the credential
   cache from expiring during a long run. The PID is stored in `SUDO_HEARTBEAT_PID` and the
   process is killed by the EXIT trap via `restore_terminal`.

On failure, the script:
1. Keeps `SUDO_AVAILABLE=0` and `SUDO_CMD=""`.
2. Iterates over `MODULE_NEEDS_SUDO` and sets `MODULE_SELECTED[$i]=0` for every sudo-requiring
   module, preventing them from executing with missing privileges.

Within `safe_delete`, a path tagged for sudo but with an empty `SUDO_CMD` prints
`Skipping (no sudo): PATH` and moves on instead of attempting an unprivileged deletion.

---

## Path Blocklist and Safety Model

`is_blocked_path` enforces a hardcoded set of paths that the script will never delete regardless
of which module requests it. The check happens inside `safe_delete` before any `rm` is issued.

Blocked prefixes and exact paths:

```
/                  (filesystem root)
/System            and everything under /System/*
/usr               and everything under /usr/*
/bin               and everything under /bin/*
/sbin              and everything under /sbin/*
/private/etc       and everything under /private/etc/*
/Library           (top-level system library — but NOT ~/Library)
$HOME              (the home directory itself, not its contents)
```

Paths that are explicitly allowed even though they might appear related to blocked directories:
- `/private/var/log/*.gz` and `/private/var/log/asl/*.asl` — these are under `/private/var`, not
  under any blocked prefix
- `/Library/Application Support/...`, `/Library/LaunchDaemons/...` — accessed only from the App
  Uninstaller with `safe_delete sudo` and only for specific bundle-ID-matched paths
- `~/Library/...` — the user's home Library is a target, not a blocked path

---

## Non-Interactive Mode

The script auto-detects a non-TTY environment at three points:

1. **`run_menu`** — checks `[[ ! -t 0 ]] || [[ ! -t 1 ]]`. If either stdin or stdout is not a
   terminal, the menu is skipped entirely and the default `MODULE_SELECTED` values are used. A
   single informational line is printed instead of the interactive UI.

2. **`_pick_list`** — same TTY check. Falls back to a numbered list with a single-line
   number-entry prompt (`1 3 5`, `a` for all, Enter to skip). Modules 6 and 7 use this path
   automatically when running non-interactively.

3. **`_confirm`** — when `AUTO_YES=1` the function never reads from stdin. When combined with a
   non-TTY stdin, this ensures the script runs to completion without blocking on any read.

The combination of `--dry-run --yes` with piped or redirected output is the recommended approach
for automated testing:

```bash
./mac-optimizer.sh --dry-run --yes 2>&1 | grep "Would remove"
```

---

## Adding a New Module

1. **Choose an index.** Module indices are 0–7. To add module 8, append to all four parallel arrays
   in section B:

   ```bash
   MODULE_NAMES+=("My New Module")
   MODULE_SELECTED+=(0)           # OFF by default
   MODULE_NEEDS_SUDO+=(0)         # adjust as needed
   MODULE_SIZES+=("")
   ```

2. **Write the clean function** in section G:

   ```bash
   module_8_clean() {
     printf "${BOLD}== My New Module ==${NC}\n"
     # Use safe_delete for all deletions
     [[ -d "$HOME/some/path" ]] && safe_delete "$HOME/some/path"
   }
   ```

3. **Add a size estimate** to `calculate_all_sizes` in section D:

   ```bash
   8) kb=$(size_kb "$HOME/some/path") ;;
   ```

4. **Add a dispatch case** to the `case` statement in `run_selected_modules` (section H):

   ```bash
   8) module_8_clean ;;
   ```

5. **Document the module** in `print_help` (section J).

Rules to follow:
- All deletions must go through `safe_delete`; never call `rm` directly.
- Ask for confirmation via `_confirm` for any data that could be irreplaceable (archives, cookies,
  history, etc.).
- If the module requires sudo, pass `sudo` as the first argument to `safe_delete` for those paths
  and set `MODULE_NEEDS_SUDO[$i]=1`.
- Wrap all path tests with `[[ -e ... ]]` or `[[ -d ... ]]` before acting; missing paths are
  normal and must not be errors.

---

## Testing and Verification

### Syntax check (no execution required)

```bash
bash -n mac-optimizer.sh
```

### Help output

```bash
./mac-optimizer.sh --help
```

Should print usage and exit cleanly with no stray escape sequences in the output.

### Full non-interactive dry run

```bash
./mac-optimizer.sh --dry-run --yes
```

Runs with default selections (modules 0, 1, 2, 5). Every action is printed as
`[DRY-RUN] Would remove: PATH (SIZE)` with no actual deletions. The summary box shows
`[DRY-RUN] No changes were made.`

### Verify blocklist

```bash
# Should print BLOCKED and not attempt deletion
safe_delete /usr/bin/env
safe_delete /System/Library/something
```

These can be tested by sourcing the script in a subshell (with `DRY_RUN=0`) and calling
`safe_delete` directly.

### Developer Junk dry run

```bash
./mac-optimizer.sh --dry-run
# In the menu: navigate to Developer Junk, toggle ON, press Enter
# Answer any Xcode Archives prompt
```

### Browser Data confirmation flow

```bash
./mac-optimizer.sh --dry-run
# Toggle Browser Data ON; confirm or decline each browser prompt
```

### App Uninstaller and Orphaned Data (dry run)

```bash
./mac-optimizer.sh --dry-run
# Toggle App Uninstaller or Orphaned Data ON
# Work through the interactive prompts; no files will be touched
```

---

## Known Limitations

**Size estimates are approximations.**
`calculate_all_sizes` uses `du -sk` which includes filesystem overhead and hard-linked files. The
sizes shown in the menu may differ from the space actually reclaimed after deletion.

**Modules 5, 6, and 7 show no pre-calculated size.**
System Maintenance performs system commands rather than file deletions. App Uninstaller and
Orphaned Data require runtime discovery to know what exists, so no estimate is available before
the module runs.

**`launchctl unload -w` behaviour varies by macOS version.**
On macOS Ventura and later, `launchctl unload -w` is deprecated in favour of `launchctl bootout`.
The current implementation uses the older form for broader compatibility; it may print warnings on
recent systems but still functions.

**`periodic` is absent on macOS Sequoia+.**
Apple removed the `periodic` binary in macOS Sequoia. The script detects this with
`command -v periodic` and skips that step with an explanatory message.

**Orphaned Data produces false positives.**
The detection algorithm treats any directory or plist whose name looks like a bundle ID (contains
a dot) and is not matched to an installed app as orphaned. Third-party software that uses
non-bundle-ID-style directory names will be missed. Conversely, system daemons and frameworks that
use bundle-ID-style names but are not directly associated with a `.app` bundle may appear as
orphaned even though they are still needed.

**No undo.**
Deletions are permanent. The `--dry-run` flag should always be used to review planned changes
before running without it.

**Single-module selection only in LaunchAgents audit.**
The LaunchAgents audit inside Module 5 accepts only a single number; it does not support
multi-select. This is a deliberate conservative choice given the irreversibility of disabling
agents.
