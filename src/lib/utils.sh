# ============================================================================
# [D] SIZE HELPERS
# ============================================================================

# Sum disk usage (KB) for given paths; silently skips non-existent
size_kb() {
  local total=0 path kb
  for path in "$@"; do
    [[ -e "$path" ]] || continue
    kb=$(du -sk "$path" 2>/dev/null | awk '{print $1}') || kb=0
    total=$(( total + ${kb:-0} ))
  done
  printf '%s' "$total"
}

# Convert KB to human-readable string
human_size() {
  local kb="${1:-0}"
  awk -v kb="$kb" 'BEGIN {
    if      (kb >= 1048576) printf "~%.1f GB", kb/1048576
    else if (kb >= 1024)    printf "~%.0f MB", kb/1024
    else                    printf "~%d KB",   kb
  }'
}

# Populate MODULE_SIZES[] — called before run_menu
calculate_all_sizes() {
  local i
  for (( i=0; i<8; i++ )); do
    local kb=0
    case $i in
      0)  # User Caches
          kb=$(size_kb "$HOME/Library/Caches/") ;;
      1)  # System Logs
          kb=$(size_kb "$HOME/Library/Logs/") ;;
      2)  # Temp Files
          kb=$(size_kb "/private/tmp" "${TMPDIR:-/tmp}") ;;
      3)  # Developer Junk
          local dev_paths=(
            "$HOME/Library/Developer/Xcode/DerivedData"
            "$HOME/Library/Developer/Xcode/Archives"
            "$HOME/Library/Developer/CoreSimulator/Caches"
            "$HOME/.npm/_cacache"
            "$HOME/Library/Caches/Yarn"
            "$HOME/.yarn/cache"
            "$HOME/Library/Caches/pip"
            "$HOME/.gradle/caches"
            "$HOME/Library/Caches/CocoaPods"
            "$HOME/.cocoapods/repos"
          )
          kb=$(size_kb "${dev_paths[@]}") ;;
      4)  # Browser Data (caches only for size estimate)
          kb=$(size_kb \
            "$HOME/Library/Caches/com.apple.Safari" \
            "$HOME/Library/Caches/Google/Chrome" \
            "$HOME/Library/Caches/BraveSoftware" \
            "$HOME/Library/Caches/Firefox/Profiles") ;;
      5|6|7)
          kb=0 ;;
    esac
    if [[ ${kb:-0} -gt 0 ]]; then
      MODULE_SIZES[$i]=$(human_size "$kb")
    else
      MODULE_SIZES[$i]=""
    fi
  done
}
