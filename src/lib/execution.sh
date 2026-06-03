# ============================================================================
# [H] EXECUTION
# ============================================================================

# _confirm PROMPT — returns 0 for yes; respects AUTO_YES
_confirm() {
  local prompt="${1:-Are you sure?}"
  if [[ $AUTO_YES -eq 1 ]]; then
    printf "%s ${DIM}[auto: yes]${NC}\n" "$prompt"
    return 0
  fi
  local ans=""
  printf "%s [y/N] " "$prompt"
  IFS= read -r ans || true
  [[ "$ans" =~ ^[Yy]$ ]]
}

run_selected_modules() {
  local selected_count=0 i
  for (( i=0; i<${#MODULE_SELECTED[@]}; i++ )); do
    [[ "${MODULE_SELECTED[$i]}" -eq 1 ]] && (( selected_count++ )) || true
  done

  if [[ $selected_count -eq 0 ]]; then
    printf "${YELLOW}No modules selected. Exiting.${NC}\n"
    return
  fi

  printf "\n${BOLD}Selected modules:${NC}\n"
  for (( i=0; i<${#MODULE_SELECTED[@]}; i++ )); do
    [[ "${MODULE_SELECTED[$i]}" -eq 1 ]] && printf "  • %s\n" "${MODULE_NAMES[$i]}"
  done

  printf "\n"
  if [[ $DRY_RUN -eq 1 ]]; then
    printf "${YELLOW}=== DRY-RUN MODE — nothing will be deleted ===${NC}\n\n"
  fi

  _confirm "Proceed with optimization?" || { printf "Cancelled.\n"; exit 0; }
  printf "\n"

  for (( i=0; i<${#MODULE_SELECTED[@]}; i++ )); do
    [[ "${MODULE_SELECTED[$i]}" -eq 1 ]] || continue
    local fn="module_${i}_clean"
    if declare -f "$fn" > /dev/null 2>&1; then
      "$fn"
    else
      printf "${YELLOW}Warning: no handler for module %d${NC}\n" "$i"
    fi
    printf "\n"
  done
}
