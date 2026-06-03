# ---------- Module 2: Temp Files ----------
module_2_clean() {
  printf "${BOLD}== Temp Files ==${NC}\n"

  local entry
  for entry in /private/tmp/*; do
    [[ -e "$entry" ]] && safe_delete "$entry"
  done

  local td="${TMPDIR:-/tmp}"
  if [[ "$td" != "/tmp" && "$td" != "/private/tmp" ]]; then
    for entry in "$td"/*; do
      [[ -e "$entry" ]] && safe_delete "$entry"
    done
  fi
}
