# ---------- Module 4: Browser Data ----------
module_4_clean() {
  printf "${BOLD}== Browser Data ==${NC}\n"

  # --- Safari ---
  if [[ -d "$HOME/Library/Caches/com.apple.Safari" ]]; then
    printf "  ${BOLD}Safari${NC}\n"
    safe_delete "$HOME/Library/Caches/com.apple.Safari"

    if _confirm "  Delete Safari cookies?"; then
      [[ -f "$HOME/Library/Cookies/Cookies.binarycookies" ]] && \
        safe_delete "$HOME/Library/Cookies/Cookies.binarycookies"
    fi

    if _confirm "  Delete Safari history?"; then
      local f
      for f in "$HOME/Library/Safari/History.db" \
               "$HOME/Library/Safari/History.db-shm" \
               "$HOME/Library/Safari/History.db-wal"; do
        [[ -f "$f" ]] && safe_delete "$f"
      done
    fi
  fi

  # --- Chrome ---
  local chrome_base="$HOME/Library/Application Support/Google/Chrome"
  if [[ -d "$chrome_base" ]]; then
    printf "  ${BOLD}Chrome${NC}\n"
    local p
    for p in "$chrome_base"/*/Cache/; do
      [[ -d "$p" ]] && safe_delete "$p"
    done
    for p in "$HOME/Library/Caches/Google/Chrome"/*/; do
      [[ -d "$p" ]] && safe_delete "$p"
    done

    if _confirm "  Delete Chrome cookies?"; then
      for p in "$chrome_base"/*/; do
        [[ -f "${p}Cookies" ]] && safe_delete "${p}Cookies"
      done
    fi

    if _confirm "  Delete Chrome history?"; then
      for p in "$chrome_base"/*/; do
        [[ -f "${p}History" ]] && safe_delete "${p}History"
      done
    fi
  fi

  # --- Brave ---
  local brave_base="$HOME/Library/Application Support/BraveSoftware/Brave-Browser"
  if [[ -d "$brave_base" ]]; then
    printf "  ${BOLD}Brave${NC}\n"
    local p
    for p in "$HOME/Library/Caches/BraveSoftware"/*/; do
      [[ -d "$p" ]] && safe_delete "$p"
    done

    if _confirm "  Delete Brave cookies?"; then
      for p in "$brave_base"/*/; do
        [[ -f "${p}Cookies" ]] && safe_delete "${p}Cookies"
      done
    fi

    if _confirm "  Delete Brave history?"; then
      for p in "$brave_base"/*/; do
        [[ -f "${p}History" ]] && safe_delete "${p}History"
      done
    fi
  fi

  # --- Firefox ---
  local ff_profiles="$HOME/Library/Application Support/Firefox/Profiles"
  if [[ -d "$ff_profiles" ]]; then
    printf "  ${BOLD}Firefox${NC}\n"
    local p
    for p in "$ff_profiles"/*/; do
      local prof_name
      prof_name=$(basename "$p")
      local cache_p="$HOME/Library/Caches/Firefox/Profiles/$prof_name"
      [[ -d "$cache_p" ]] && safe_delete "$cache_p"
    done

    if _confirm "  Delete Firefox cookies?"; then
      for p in "$ff_profiles"/*/; do
        [[ -f "${p}cookies.sqlite" ]] && safe_delete "${p}cookies.sqlite"
      done
    fi

    if _confirm "  Delete Firefox history? ${RED}Warning: also deletes bookmarks!${NC}"; then
      for p in "$ff_profiles"/*/; do
        [[ -f "${p}places.sqlite" ]] && safe_delete "${p}places.sqlite"
      done
    fi
  fi
}
