# ---------- Module 5: System Maintenance ----------
module_5_clean() {
  printf "${BOLD}== System Maintenance ==${NC}\n"

  # DNS flush
  printf "  Flushing DNS cache...\n"
  if [[ $DRY_RUN -eq 1 ]]; then
    printf "${YELLOW}  [DRY-RUN] Would run: sudo killall -HUP mDNSResponder${NC}\n"
  else
    if sudo killall -HUP mDNSResponder 2>/dev/null; then
      printf "${GREEN}  ✓ DNS cache flushed${NC}\n"
      CLEAN_LOG+=("DNS cache flushed")
    else
      printf "${RED}  ✗ DNS flush failed (requires sudo)${NC}\n"
    fi
  fi

  # Periodic scripts
  if ! command -v periodic &>/dev/null; then
    printf "${DIM}  Periodic scripts skipped (not available on this macOS version)${NC}\n"
  elif [[ $DRY_RUN -eq 1 ]]; then
    printf "  Running periodic maintenance scripts...\n"
    printf "${YELLOW}  [DRY-RUN] Would run: sudo periodic daily weekly monthly${NC}\n"
  else
    printf "  Running periodic maintenance scripts...\n"
    if sudo periodic daily weekly monthly 2>/dev/null; then
      printf "${GREEN}  ✓ Periodic scripts completed${NC}\n"
      CLEAN_LOG+=("Periodic maintenance scripts run")
    else
      printf "${RED}  ✗ Periodic scripts failed${NC}\n"
    fi
  fi

  # LaunchAgents audit
  printf "\n  ${BOLD}LaunchAgents Audit:${NC}\n"
  local plist_files=() f
  for f in "$HOME/Library/LaunchAgents"/*.plist; do
    [[ -f "$f" ]] && plist_files+=("$f")
  done

  if [[ ${#plist_files[@]} -eq 0 ]]; then
    printf "${DIM}  No LaunchAgents found.${NC}\n"
    return
  fi

  local i=0
  for f in "${plist_files[@]}"; do
    local label status
    label=$(basename "$f" .plist)
    if launchctl list "$label" &>/dev/null; then
      status="${GREEN}loaded${NC}"
    else
      status="${DIM}unloaded${NC}"
    fi
    printf "  ${BOLD}%2d.${NC} %-48s [%b]\n" "$(( i+1 ))" "$label" "$status"
    (( i++ )) || true
  done

  printf "\n  Enter number to unload (or Enter to skip): "
  local sel=""
  IFS= read -r sel || true

  if [[ -n "$sel" && "$sel" =~ ^[0-9]+$ ]]; then
    local idx=$(( sel - 1 ))
    if [[ $idx -ge 0 && $idx -lt ${#plist_files[@]} ]]; then
      local target="${plist_files[$idx]}"
      if [[ $DRY_RUN -eq 1 ]]; then
        printf "${YELLOW}  [DRY-RUN] Would unload: %s${NC}\n" "$target"
      else
        if launchctl unload -w "$target" 2>/dev/null; then
          printf "${GREEN}  ✓ Unloaded: %s${NC}\n" "$target"
          CLEAN_LOG+=("Unloaded LaunchAgent: $(basename "$target")")
        else
          printf "${RED}  ✗ Failed to unload: %s${NC}\n" "$target"
        fi
      fi
    fi
  fi
}
