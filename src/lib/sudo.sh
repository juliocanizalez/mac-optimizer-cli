# ============================================================================
# [E] SUDO
# ============================================================================

# Returns 0 if any selected module needs sudo
needs_sudo() {
  local i
  for (( i=0; i<${#MODULE_SELECTED[@]}; i++ )); do
    if [[ "${MODULE_SELECTED[$i]}" -eq 1 && "${MODULE_NEEDS_SUDO[$i]}" -eq 1 ]]; then
      return 0
    fi
  done
  return 1
}

acquire_sudo() {
  needs_sudo || return 0

  printf "${BOLD}Some modules require elevated privileges.${NC}\n"

  if sudo -v 2>/dev/null; then
    SUDO_AVAILABLE=1
    SUDO_CMD="sudo"
    printf "${GREEN}✓ sudo access granted${NC}\n"

    # Keepalive heartbeat every 50 s
    (
      while true; do
        sleep 50
        sudo -n -v 2>/dev/null || exit 0
      done
    ) &
    SUDO_HEARTBEAT_PID=$!
  else
    SUDO_AVAILABLE=0
    SUDO_CMD=""
    printf "${YELLOW}Warning: sudo failed — deselecting modules that require it.${NC}\n"
    local i
    for (( i=0; i<${#MODULE_NEEDS_SUDO[@]}; i++ )); do
      if [[ "${MODULE_NEEDS_SUDO[$i]}" -eq 1 ]]; then
        MODULE_SELECTED[$i]=0
      fi
    done
  fi
}
