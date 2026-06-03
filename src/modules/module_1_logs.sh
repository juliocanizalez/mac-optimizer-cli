# ---------- Module 1: System Logs ----------
module_1_clean() {
  printf "${BOLD}== System Logs ==${NC}\n"

  if [[ -d "$HOME/Library/Logs" ]]; then
    local entry
    for entry in "$HOME/Library/Logs"/*/; do
      [[ -e "$entry" ]] && safe_delete "$entry"
    done
    for entry in "$HOME/Library/Logs"/*.log; do
      [[ -f "$entry" ]] && safe_delete "$entry"
    done
    for entry in "$HOME/Library/Logs"/*.crash; do
      [[ -f "$entry" ]] && safe_delete "$entry"
    done
  fi

  if [[ -n "$SUDO_CMD" ]]; then
    local f
    for f in /private/var/log/*.gz; do
      [[ -f "$f" ]] && safe_delete sudo "$f"
    done
    for f in /private/var/log/asl/*.asl; do
      [[ -f "$f" ]] && safe_delete sudo "$f"
    done
  fi
}
