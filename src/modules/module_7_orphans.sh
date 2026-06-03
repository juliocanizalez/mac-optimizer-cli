# ---------- Module 7: Orphaned Data ----------

# Build newline-separated list of installed bundle IDs (global, reused)
_INSTALLED_IDS=""

_build_installed_ids() {
  _INSTALLED_IDS=""
  local app bid
  for app in /Applications/*.app "$HOME/Applications"/*.app; do
    [[ -d "$app" ]] || continue
    bid=$(defaults read "$app/Contents/Info.plist" CFBundleIdentifier 2>/dev/null) || continue
    _INSTALLED_IDS+="${bid}"$'\n'
  done
}

_is_installed() {
  local bid="$1"
  printf '%s' "$_INSTALLED_IDS" | grep -qxF "$bid"
}

module_7_clean() {
  printf "${BOLD}== Orphaned Data ==${NC}\n"
  printf "  Building installed-app list...\n"

  _build_installed_ids
  local app_count
  app_count=$(printf '%s' "$_INSTALLED_IDS" | grep -c '.' 2>/dev/null || echo 0)
  printf "  Found %s installed apps.\n" "$app_count"
  printf "  Scanning for orphaned data...\n"

  local scan_dirs=(
    "$HOME/Library/Application Support"
    "$HOME/Library/Caches"
    "$HOME/Library/Saved Application State"
    "$HOME/Library/Containers"
    "$HOME/Library/Group Containers"
  )

  local orphans=()
  local dir entry basename

  for dir in "${scan_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    for entry in "$dir"/*/; do
      [[ -d "$entry" ]] || continue
      basename=$(basename "$entry")
      # Skip entries that don't look like bundle IDs (no dot)
      [[ "$basename" != *.* ]] && continue
      # Keep Apple system entries — they are managed by macOS
      [[ "$basename" == com.apple.* ]] && continue
      _is_installed "$basename" || orphans+=("$entry")
    done
  done

  # Preferences plists
  for entry in "$HOME/Library/Preferences"/*.plist; do
    [[ -f "$entry" ]] || continue
    basename=$(basename "$entry" .plist)
    [[ "$basename" != *.* ]]      && continue
    [[ "$basename" == com.apple.* ]] && continue
    _is_installed "$basename" || orphans+=("$entry")
  done

  # LaunchAgents — check Label key
  for entry in "$HOME/Library/LaunchAgents"/*.plist; do
    [[ -f "$entry" ]] || continue
    local label=""
    label=$(defaults read "$entry" Label 2>/dev/null) || continue
    [[ "$label" == com.apple.* ]] && continue
    _is_installed "$label" || orphans+=("$entry")
  done

  if [[ ${#orphans[@]} -eq 0 ]]; then
    printf "${GREEN}  No orphaned data found!${NC}\n"
    return
  fi

  # Build display items with sizes
  local display_items=() e ekb
  for e in "${orphans[@]}"; do
    ekb=$(du -sk "$e" 2>/dev/null | awk '{print $1}') || ekb=0
    display_items+=("$(printf '%-45s (%s)' "$(basename "$e")" "$(human_size "$ekb")")")
  done

  printf "\n"
  _PICK_RESULT=""
  if ! _pick_list "Select orphaned data to remove" 10 "${display_items[@]}"; then
    printf "  Cancelled.\n"
    return
  fi

  [[ -z "$_PICK_RESULT" ]] && { printf "  Nothing selected.\n"; return; }

  local removed=0
  while IFS= read -r idx; do
    [[ -z "$idx" ]] && continue
    local target="${orphans[$idx]}"

    if [[ $DRY_RUN -eq 1 ]]; then
      printf "${YELLOW}  [DRY-RUN] Would remove: %s${NC}\n" "$target"
      (( removed++ )) || true
      continue
    fi

    _spin_start "Removing $(basename "$target")..."
    { safe_delete "$target"; } >/dev/null 2>&1
    _spin_stop 0 "Removed $(basename "$target")"
    (( removed++ )) || true
  done < <(printf '%s\n' "$_PICK_RESULT")

  printf "  Removed %d item(s).\n" "$removed"
}
