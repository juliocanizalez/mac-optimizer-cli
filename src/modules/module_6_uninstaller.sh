# ---------- Module 6: App Uninstaller ----------

# Echo all leftover paths for a given bundle ID / app name
find_app_files() {
  local bundle_id="$1" app_name="$2"
  local dir entry

  local user_dirs=(
    "$HOME/Library/Application Support"
    "$HOME/Library/Preferences"
    "$HOME/Library/Caches"
    "$HOME/Library/Logs"
    "$HOME/Library/Saved Application State"
    "$HOME/Library/Containers"
    "$HOME/Library/Group Containers"
    "$HOME/Library/LaunchAgents"
  )

  for dir in "${user_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    # Exact bundle-id match
    for entry in \
        "$dir/$bundle_id" \
        "$dir/$bundle_id.plist"; do
      [[ -e "$entry" ]] && printf '%s\n' "$entry"
    done
    # Prefix match (e.g. com.foo.bar.helper)
    for entry in "$dir/${bundle_id}"*/; do
      [[ -e "$entry" ]] && printf '%s\n' "$entry"
    done
    # App-name match
    for entry in "$dir/$app_name" "$dir/$app_name.plist"; do
      [[ -e "$entry" ]] && printf '%s\n' "$entry"
    done
  done

  # Sudo paths
  local sudo_dirs=(
    "/Library/LaunchDaemons"
    "/Library/Application Support"
    "/Library/Preferences"
  )
  for dir in "${sudo_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    for entry in \
        "$dir/$bundle_id" \
        "$dir/$bundle_id.plist" \
        "$dir/$app_name" \
        "$dir/$app_name.plist"; do
      [[ -e "$entry" ]] && printf 'sudo:%s\n' "$entry"
    done
    for entry in "$dir/${bundle_id}"*/; do
      [[ -e "$entry" ]] && printf 'sudo:%s\n' "$entry"
    done
  done
}

module_6_clean() {
  printf "${BOLD}== App Uninstaller ==${NC}\n"

  local apps=() display_names=() app
  for app in /Applications/*.app "$HOME/Applications"/*.app; do
    [[ -d "$app" ]] || continue
    apps+=("$app")
    local name kb sz
    name=$(basename "$app" .app)
    kb=$(du -sk "$app" 2>/dev/null | awk '{print $1}') || kb=0
    sz=$(human_size "$kb")
    display_names+=("$(printf '%-30s (%s)' "$name" "$sz")")
  done

  if [[ ${#apps[@]} -eq 0 ]]; then
    printf "  No applications found.\n"
    return
  fi

  printf "\n"
  _PICK_RESULT=""
  if ! _pick_list "Select apps to uninstall" 10 "${display_names[@]}"; then
    printf "  Cancelled.\n"
    return
  fi

  [[ -z "$_PICK_RESULT" ]] && { printf "  Nothing selected.\n"; return; }

  local removed=0
  while IFS= read -r idx; do
    [[ -z "$idx" ]] && continue
    local selected_app="${apps[$idx]}"
    local app_name
    app_name=$(basename "$selected_app" .app)

    if [[ $DRY_RUN -eq 1 ]]; then
      printf "${YELLOW}  [DRY-RUN] Would uninstall: %s${NC}\n" "$app_name"
      (( removed++ )) || true
      continue
    fi

    _spin_start "Uninstalling $app_name..."
    { safe_delete "$selected_app"; } >/dev/null 2>&1
    _spin_stop 0 "Uninstalled $app_name"
    (( removed++ )) || true
  done < <(printf '%s\n' "$_PICK_RESULT")

  printf "  Removed %d app(s).\n" "$removed"
}
