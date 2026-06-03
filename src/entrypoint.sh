# ============================================================================
# [J] ENTRY POINT
# ============================================================================

print_help() {
  local cmd
  cmd="$(basename "$0")"
  cat <<EOF
mac-optimizer-cli v${VERSION}
Free up disk space on macOS through an interactive TUI checklist.

USAGE
  ${cmd} [OPTIONS]

HOW IT WORKS
  1. Sizes are calculated for each cleanup module.
  2. An interactive menu lets you toggle modules on/off with arrow keys
     and Space, then press Enter to confirm.
  3. sudo is acquired once (if needed) and kept alive for the run.
  4. Selected modules execute and log every deletion.
  5. A summary shows total space freed.

  Run with --dry-run to preview all deletions without touching anything.
  Defaults (which modules start ON) can be persisted in a config file —
  see --init-config below.

OPTIONS
  -n, --dry-run      Preview what would be deleted (no changes made)
  -y, --yes          Skip all confirmation prompts (use with --dry-run for CI)
  -h, --help         Show this help message
      --init-config  Write default config to ~/.config/mac-optimizer/config.toml
      --config-path  Print the config file path and exit

MODULES
  Default selection is shown in brackets. Toggle freely in the TUI, or set
  persistent defaults via the config file (--init-config).

  [ON]  0. User Caches         ~/Library/Caches
  [ON]  1. System Logs         ~/Library/Logs, /var/log rotated logs
  [ON]  2. Temp Files          /tmp, \$TMPDIR
  [OFF] 3. Developer Junk      Xcode DerivedData, npm/pip/gradle caches
  [OFF] 4. Browser Data        Safari/Chrome/Brave/Firefox caches, cookies, history
  [ON]  5. System Maintenance  Flush DNS, run periodic scripts, audit LaunchAgents
  [OFF] 6. App Uninstaller     Remove an app and all its associated data files
  [OFF] 7. Orphaned Data       Find leftovers from previously uninstalled apps

CONFIG
  Persistent defaults live in ~/.config/mac-optimizer/config.toml.
  CLI flags always override config values.

    ${cmd} --init-config          # scaffold the config file
    \$EDITOR \$(${cmd} --config-path)  # open it in your editor

EXAMPLES
  ${cmd}                    # Interactive TUI
  ${cmd} --dry-run          # Preview all changes, no deletions
  ${cmd} --dry-run --yes    # Non-interactive preview (safe for CI)
  ${cmd} --yes              # Run with defaults, skip confirmation prompts
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--dry-run)      DRY_RUN=1  ; shift ;;
      -y|--yes)          AUTO_YES=1 ; shift ;;
      -h|--help)         print_help ; exit 0 ;;
      --init-config)     config_init ; exit 0 ;;
      --config-path)     printf "%s\n" "$CONFIG_PATH" ; exit 0 ;;
      *)
        printf "${RED}Unknown option: %s${NC}\n" "$1" >&2
        print_help >&2
        exit 1 ;;
    esac
  done
}

main() {
  config_load   # apply ~/.config/mac-optimizer/config.toml first
  parse_args "$@"  # CLI flags win

  # macOS only
  if [[ "$(uname -s)" != "Darwin" ]]; then
    printf "${RED}Error: This script requires macOS.${NC}\n" >&2
    exit 1
  fi

  printf "${BOLD}mac-optimizer-cli v%s${NC}\n" "$VERSION"
  printf "${DIM}Calculating sizes, please wait...${NC}\n"
  calculate_all_sizes

  run_menu

  acquire_sudo

  run_selected_modules

  print_summary
}

main "$@"
