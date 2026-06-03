# ============================================================================
# [B2] CONFIG
# ============================================================================

CONFIG_PATH="${HOME}/.config/mac-optimizer/config.toml"

# _cfg_get KEY FILE — print the raw value for a TOML key, or empty string
_cfg_get() {
  local key="$1" file="$2"
  grep -E "^\s*${key}\s*=" "$file" 2>/dev/null \
    | sed 's/[^=]*=\s*//' | tr -d '"' | tr -d "'" | tr -d ' ' | head -1
}

# _cfg_bool KEY FILE — echo 1 if true/yes/1, echo 0 if false/no/0, echo "" if absent
_cfg_bool() {
  local val
  val=$(_cfg_get "$1" "$2")
  case "$val" in
    true|yes|1)  echo 1 ;;
    false|no|0)  echo 0 ;;
    *)           echo "" ;;
  esac
}

# config_load — read ~/.config/mac-optimizer/config.toml and apply values.
# Hard-coded defaults (globals.sh) are applied first; this overrides them;
# CLI flags (parse_args) will override this in turn.
config_load() {
  [[ -f "$CONFIG_PATH" ]] || return 0

  local val

  # [defaults] section
  val=$(_cfg_bool "dry_run"  "$CONFIG_PATH"); [[ -n "$val" ]] && DRY_RUN=$val
  val=$(_cfg_bool "auto_yes" "$CONFIG_PATH"); [[ -n "$val" ]] && AUTO_YES=$val

  # [modules] section — map names to MODULE_SELECTED indices
  local -a _MODULE_KEYS=(
    user_caches
    system_logs
    temp_files
    developer_junk
    browser_data
    system_maintenance
    app_uninstaller
    orphaned_data
  )
  local i
  for (( i=0; i<${#_MODULE_KEYS[@]}; i++ )); do
    val=$(_cfg_bool "${_MODULE_KEYS[$i]}" "$CONFIG_PATH")
    [[ -n "$val" ]] && MODULE_SELECTED[$i]=$val
  done
}

# config_init — write a default config.toml (errors if it already exists)
config_init() {
  if [[ -f "$CONFIG_PATH" ]]; then
    printf "Config already exists: %s\n" "$CONFIG_PATH"
    printf "Delete it first to regenerate.\n"
    exit 1
  fi
  mkdir -p "$(dirname "$CONFIG_PATH")"
  cat > "$CONFIG_PATH" <<'EOF'
# mac-optimizer configuration
# Edit to set your defaults. CLI flags always take precedence.
# Location: ~/.config/mac-optimizer/config.toml

[modules]
# Modules enabled by default when the TUI opens
user_caches        = true
system_logs        = true
temp_files         = true
developer_junk     = false
browser_data       = false
system_maintenance = true
app_uninstaller    = false
orphaned_data      = false

[defaults]
dry_run  = false
auto_yes = false
EOF
  printf "Config written to: %s\n" "$CONFIG_PATH"
}
