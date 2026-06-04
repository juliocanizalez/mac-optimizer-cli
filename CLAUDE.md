# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

A single self-contained bash script (`mac-optimizer.sh`) that provides an interactive TUI for cleaning macOS disk space. No build step, no dependencies beyond bash 3.2 and standard macOS tools.

## Verification commands

```bash
bash -n mac-optimizer.sh                    # syntax check (no execution)
./mac-optimizer.sh --help                   # help output
./mac-optimizer.sh --dry-run --yes          # full non-interactive dry run
./mac-optimizer.sh --dry-run --yes 2>&1 | grep "Would remove"  # inspect planned deletions
bash -c 'source mac-optimizer.sh; is_blocked_path /etc && echo BLOCKED'  # test blocklist
```

## Script architecture

The file is divided into ten sections (A–J) in dependency order:

```
[A] Preamble         shebang, strict mode (set -uo pipefail), VERSION
[B] Global State     MODULE_NAMES[], MODULE_SIZES[], MODULE_SELECTED[], DRY_RUN, AUTO_YES,
                     BYTES_FREED_TOTAL, CLEAN_LOG, sudo state
[C] UI Primitives    ANSI colors, box rendering (_box_row, _sep), terminal setup/restore,
                     render_menu, run_menu (event loop), _pick_list (scrollable checkboxes),
                     _spin_start/_spin_stop (spinner), _scrollable_log
[D] Size Helpers     size_kb, human_size, calculate_all_sizes
[E] Sudo             needs_sudo, acquire_sudo (50s heartbeat background process)
[F] Safe Delete      is_blocked_path, safe_delete
[G] Module Functions module_0_clean … module_7_clean, find_app_files,
                     _build_installed_ids, _is_installed
[H] Execution        _confirm, run_selected_modules (dispatch loop)
[I] Summary          print_summary
[J] Entry Point      parse_args, print_help, main
```

`main()` flow: `parse_args` → `calculate_all_sizes` → `run_menu` → `acquire_sudo` → `run_selected_modules` → `print_summary`

## Key constraints

- **Bash 3.2 compatible** — no `declare -A`. Orphaned-data lookup uses a newline-separated string + `grep -qxF` instead of associative arrays.
- `safe_delete [sudo] PATH...` is the only deletion primitive — all modules must use it. It respects `DRY_RUN` and the path blocklist.
- `_terminal_modified` flag prevents `tput` calls in non-interactive paths (`--help`, piped output).
- Non-interactive detection: `[[ ! -t 0 ]] || [[ ! -t 1 ]]` in `run_menu` and `_pick_list`.
- Box layout constants: `BOX_W=46`, `BOX_IW=44`, `NAME_FIELD=20`. Visual lengths are pre-calculated to avoid subshell overhead in the render loop.

## Adding a new module

1. Add the display name to `MODULE_NAMES` in section B (index N).
2. Implement `module_N_clean()` in section G using `safe_delete` for all deletions.
3. Add a `N) module_N_clean ;;` case in `run_selected_modules` (section H).
4. Add a size calculation entry in `calculate_all_sizes` (section D) that writes to `MODULE_SIZES[N]`.
5. Set `MODULE_SELECTED[N]=0` (default off) or `1` (default on) in section B.
