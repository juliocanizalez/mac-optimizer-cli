# ============================================================================
# [I] SUMMARY
# ============================================================================

print_summary() {
  local total_human
  total_human=$(human_size $(( BYTES_FREED_TOTAL / 1024 )))

  local W=52
  local IW=$(( W - 2 ))
  local sep
  sep=$(_sep "$IW")

  printf "\n"
  printf "${CYAN}╔%s╗${NC}\n" "$sep"
  _box_row "$IW" "  Optimization Complete" 22
  printf "${CYAN}╠%s╣${NC}\n" "$sep"

  if [[ $DRY_RUN -eq 0 ]]; then
    local freed_content="  Space freed: ${GREEN}${BOLD}${total_human}${NC}"
    local freed_vlen=$(( 16 + ${#total_human} ))
    _box_row "$IW" "$freed_content" "$freed_vlen"
  else
    _box_row "$IW" "  [DRY-RUN] No changes were made." 34
  fi

  printf "${CYAN}╚%s╝${NC}\n" "$sep"

  if [[ ${#CLEAN_LOG[@]} -gt 0 ]]; then
    printf "\n"
    if [[ -t 1 ]]; then
      _scrollable_log "Actions taken" 8
    else
      printf "Actions taken:\n"
      local entry
      for entry in "${CLEAN_LOG[@]}"; do
        printf "  %s\n" "$entry"
      done
    fi
  fi

  printf "\n"
}
