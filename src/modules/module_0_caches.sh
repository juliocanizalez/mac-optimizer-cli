# ---------- Module 0: User Caches ----------
module_0_clean() {
  printf "${BOLD}== User Caches ==${NC}\n"
  local cache_dir="$HOME/Library/Caches"
  [[ -d "$cache_dir" ]] || { echo "  No cache directory found."; return; }

  local ALLOWLIST=("com.apple.AppleMultitouchTrackpad" "com.apple.findmydeviced")
  local entry basename skip allowed

  for entry in "$cache_dir"/*/; do
    [[ -e "$entry" ]] || continue
    basename=$(basename "$entry")
    skip=0
    for allowed in "${ALLOWLIST[@]}"; do
      [[ "$basename" == "$allowed" ]] && skip=1 && break
    done
    if [[ $skip -eq 1 ]]; then
      printf "${DIM}  Skipping (allowlisted): %s${NC}\n" "$basename"
      continue
    fi
    safe_delete "$entry"
  done

  # Also clean loose files directly in Caches
  for entry in "$cache_dir"/*.db "$cache_dir"/*.sqlite; do
    [[ -f "$entry" ]] && safe_delete "$entry"
  done
}
