# ============================================================================
# [F] SAFE DELETE
# ============================================================================

# Returns 0 (true) if path should be blocked
is_blocked_path() {
  local path="${1%/}"   # strip trailing slash
  case "$path" in
    /|/System|/usr|/bin|/sbin|/private/etc|/Library)
      return 0 ;;
    /System/*|/usr/*|/bin/*|/sbin/*|/private/etc/*)
      return 0 ;;
  esac
  [[ "$path" == "$HOME" ]] && return 0
  return 1
}

# safe_delete [sudo] PATH...
safe_delete() {
  local use_sudo=0
  if [[ "${1:-}" == "sudo" ]]; then
    use_sudo=1
    shift
  fi

  local path
  for path in "$@"; do
    [[ -e "$path" || -L "$path" ]] || continue

    if is_blocked_path "$path"; then
      printf "${RED}  BLOCKED: %s${NC}\n" "$path"
      continue
    fi

    local kb=0 size_str
    kb=$(du -sk "$path" 2>/dev/null | awk '{print $1}') || kb=0
    size_str=$(human_size "${kb:-0}")

    if [[ $DRY_RUN -eq 1 ]]; then
      printf "${YELLOW}  [DRY-RUN] Would remove: %s (%s)${NC}\n" "$path" "$size_str"
    elif [[ $use_sudo -eq 1 && -z "$SUDO_CMD" ]]; then
      printf "${DIM}  Skipping (no sudo): %s${NC}\n" "$path"
    else
      local ok=0
      if [[ $use_sudo -eq 1 ]]; then
        $SUDO_CMD rm -rf -- "$path" 2>/dev/null && ok=1 || true
      else
        rm -rf -- "$path" 2>/dev/null && ok=1 || true
      fi
      if [[ $ok -eq 1 ]]; then
        BYTES_FREED_TOTAL=$(( BYTES_FREED_TOTAL + kb * 1024 ))
        CLEAN_LOG+=("Removed: $path ($size_str)")
        printf "${GREEN}  ✓ Removed: %s (%s)${NC}\n" "$path" "$size_str"
      else
        printf "${RED}  ✗ Failed:  %s${NC}\n" "$path"
        CLEAN_LOG+=("FAILED: $path")
      fi
    fi
  done
}
