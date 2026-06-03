# ---------- Module 3: Developer Junk ----------
module_3_clean() {
  printf "${BOLD}== Developer Junk ==${NC}\n"

  # Xcode DerivedData
  [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]] && \
    safe_delete "$HOME/Library/Developer/Xcode/DerivedData"

  # Xcode Archives — warn first
  if [[ -d "$HOME/Library/Developer/Xcode/Archives" ]]; then
    printf "${YELLOW}  Warning: Xcode Archives may contain App Store submissions!${NC}\n"
    if _confirm "  Delete Xcode Archives?"; then
      safe_delete "$HOME/Library/Developer/Xcode/Archives"
    fi
  fi

  # CoreSimulator Caches
  [[ -d "$HOME/Library/Developer/CoreSimulator/Caches" ]] && \
    safe_delete "$HOME/Library/Developer/CoreSimulator/Caches"

  # Homebrew download cache
  if command -v brew &>/dev/null; then
    local brew_cache=""
    brew_cache=$(brew --cache 2>/dev/null) || true
    if [[ -n "$brew_cache" && -d "$brew_cache/downloads" ]]; then
      safe_delete "$brew_cache/downloads"
    fi
  fi

  # npm
  [[ -d "$HOME/.npm/_cacache" ]] && safe_delete "$HOME/.npm/_cacache"

  # Yarn
  [[ -d "$HOME/Library/Caches/Yarn" ]] && safe_delete "$HOME/Library/Caches/Yarn"
  [[ -d "$HOME/.yarn/cache" ]]          && safe_delete "$HOME/.yarn/cache"

  # pip
  [[ -d "$HOME/Library/Caches/pip/http"    ]] && safe_delete "$HOME/Library/Caches/pip/http"
  [[ -d "$HOME/Library/Caches/pip/wheels"  ]] && safe_delete "$HOME/Library/Caches/pip/wheels"

  # Gradle
  [[ -d "$HOME/.gradle/caches" ]] && safe_delete "$HOME/.gradle/caches"

  # CocoaPods
  [[ -d "$HOME/Library/Caches/CocoaPods" ]] && safe_delete "$HOME/Library/Caches/CocoaPods"
  [[ -d "$HOME/.cocoapods/repos"          ]] && safe_delete "$HOME/.cocoapods/repos"

  # JetBrains
  local jb
  for jb in "$HOME/Library/Caches/JetBrains"/*/; do
    [[ -d "$jb" ]] && safe_delete "$jb"
  done
}
