# Contributing to mac-optimizer-cli

Thank you for your interest in contributing!

## Prerequisites

- macOS (the script is macOS-only)
- Bash 3.2+ (ships with macOS)
- No build toolchain required

## Development workflow

```bash
# Edit sources in src/
# Rebuild the distributable
bash build.sh

# Syntax check
bash -n mac-optimizer.sh

# Full non-interactive dry run
./mac-optimizer.sh --dry-run --yes

# Or use make
make check   # build + syntax check
make test    # build + dry run
```

## Project structure

Sources live in `src/` and are concatenated by `build.sh` into `mac-optimizer.sh`. **Never edit `mac-optimizer.sh` directly** — edit the relevant `src/` file and rebuild.

```
src/
  lib/            # Core libraries (globals, UI, utils, sudo, delete, execution, summary)
  modules/        # One file per cleanup module (module_0_caches.sh … module_7_orphans.sh)
  entrypoint.sh   # parse_args, print_help, main()
```

## Adding a new module

1. Add the display name to `MODULE_NAMES` in [`src/lib/globals.sh`](src/lib/globals.sh).
2. Create `src/modules/module_N_<name>.sh` with a `module_N_clean()` function. Use `safe_delete` for all deletions — never call `rm` directly.
3. Add the file to the concatenation list in [`build.sh`](build.sh) (between module 7 and `src/lib/execution.sh`).
4. Add a size entry in `calculate_all_sizes` in [`src/lib/utils.sh`](src/lib/utils.sh).
5. Set `MODULE_SELECTED[N]=0` (default off) or `1` (default on) and `MODULE_NEEDS_SUDO[N]=0|1` in [`src/lib/globals.sh`](src/lib/globals.sh).

The dispatch loop calls `module_N_clean` by name automatically — no `case` entry needed.

## Coding constraints

- **Bash 3.2 compatible** — no `declare -A`, no `mapfile`/`readarray`.
- `safe_delete [sudo] PATH...` is the only permitted deletion primitive.
- All new code must pass `bash -n mac-optimizer.sh` and `./mac-optimizer.sh --dry-run --yes`.
- Keep `_terminal_modified` and non-interactive detection patterns in place.

## Pull request checklist

- [ ] `make check` passes
- [ ] `make test` passes (dry run produces expected output)
- [ ] Blocklist unit test passes: `bash -c 'source src/lib/globals.sh; source src/lib/ui.sh; source src/lib/utils.sh; source src/lib/delete.sh; is_blocked_path /private/etc && echo BLOCKED'`
- [ ] New module follows the 6-step checklist above
- [ ] CHANGELOG.md entry added under `[Unreleased]`

## Commit style

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add module 8 for Docker volume cleanup
fix: prevent false positive in orphan scanner
docs: clarify --dry-run behavior in README
chore: bump version to 1.3.0
```

## Reporting issues

Use the [GitHub issue templates](.github/ISSUE_TEMPLATE/) — they ask for macOS version, Bash version, and reproduction steps.
