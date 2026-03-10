#!/usr/bin/env bash
# mac-optimizer.sh — macOS disk cleanup and maintenance CLI tool
# Usage: ./mac-optimizer.sh [--dry-run] [--yes] [--help]
set -uo pipefail

VERSION="1.1.0"

# ============================================================================
# [B] GLOBAL STATE
# ============================================================================

DRY_RUN=0
AUTO_YES=0
SUDO_AVAILABLE=0
SUDO_CMD=""
SUDO_HEARTBEAT_PID=""

MODULE_NAMES=(
  "User Caches"
  "System Logs"
  "Temp Files"
  "Developer Junk"
  "Browser Data"
  "System Maintenance"
  "App Uninstaller"
  "Orphaned Data"
)
MODULE_SELECTED=(1 1 1 0 0 1 0 0)
MODULE_NEEDS_SUDO=(0 1 0 0 0 1 1 0)
MODULE_SIZES=("" "" "" "" "" "" "" "")

BYTES_FREED_TOTAL=0
declare -a CLEAN_LOG=()

# ============================================================================
# [C] UI PRIMITIVES
# ============================================================================

# ANSI colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
NC=$'\033[0m'

_in_menu=0
_terminal_modified=0

setup_terminal() {
  tput civis 2>/dev/null || true
  stty -echo 2>/dev/null || true
  _terminal_modified=1
}

restore_terminal() {
  if [[ $_terminal_modified -eq 1 ]]; then
    tput cnorm 2>/dev/null || true
    stty echo 2>/dev/null || true
    _terminal_modified=0
  fi
  if [[ $_in_menu -eq 1 ]]; then
    tput rmcup 2>/dev/null || true
    _in_menu=0
  fi
  if [[ -n "${SUDO_HEARTBEAT_PID:-}" ]]; then
    kill "$SUDO_HEARTBEAT_PID" 2>/dev/null || true
  fi
}

trap restore_terminal EXIT INT TERM

# Strip ANSI escape sequences for visual-length calculation
_strip_ansi() {
  printf '%s' "$1" | sed $'s/\x1b\\[[0-9;]*m//g'
}

# Get visual length of string (excluding ANSI codes)
_vlen() {
  local s
  s=$(_strip_ansi "$1")
  printf '%s' "${#s}"
}

# Print a box row: ║ content <padding> ║
# Usage: _box_row INNER_W CONTENT CONTENT_VLEN
_box_row() {
  local iw="$1" content="$2" vlen="$3"
  local pad=$(( iw - vlen ))
  [[ $pad -lt 0 ]] && pad=0
  printf "${CYAN}║${NC}%s%*s${CYAN}║${NC}\n" "$content" "$pad" ""
}

# Build a separator of = chars of given count
_sep() {
  local n="$1"
  local s=""
  local i
  for (( i=0; i<n; i++ )); do s+="═"; done
  printf '%s' "$s"
}

read_key() {
  local key=""
  IFS= read -rsn1 key || true
  if [[ "$key" == $'\x1b' ]]; then
    local seq=""
    IFS= read -rsn2 -t 1 seq || true
    case "$seq" in
      "[A") printf 'UP'    ;;
      "[B") printf 'DOWN'  ;;
      *)    printf 'ESC'   ;;
    esac
  elif [[ "$key" == " " ]]; then
    printf 'SPACE'
  elif [[ "$key" == "" || "$key" == $'\n' || "$key" == $'\r' ]]; then
    printf 'ENTER'
  elif [[ "$key" == "q" || "$key" == "Q" ]]; then
    printf 'QUIT'
  else
    printf 'OTHER'
  fi
}

# Box dimensions
BOX_W=46         # total visual width (including the two border chars)
BOX_IW=44        # inner width  (BOX_W - 2)
NAME_FIELD=20    # chars reserved for module name (padded)

render_menu() {
  local cursor="$1"
  local total="${#MODULE_NAMES[@]}"
  local sep
  sep=$(_sep "$BOX_IW")

  tput cup 0 0

  # Top border
  printf "${CYAN}╔%s╗${NC}\n" "$sep"

  # Title
  local title="  mac-optimizer-cli  v${VERSION}"
  local title_vlen=$(( ${#VERSION} + 24 ))
  _box_row "$BOX_IW" "$title" "$title_vlen"

  # Middle separator
  printf "${CYAN}╠%s╣${NC}\n" "$sep"

  # Select header
  _box_row "$BOX_IW" " Select modules:" 16

  # Module rows
  local i
  for (( i=0; i<total; i++ )); do
    local name="${MODULE_NAMES[$i]}"
    local sel="${MODULE_SELECTED[$i]}"
    local size="${MODULE_SIZES[$i]}"

    # Pointer (2 visual chars)
    local ptr_raw ptr_vlen=2
    if [[ $i -eq $cursor ]]; then
      ptr_raw="${BOLD}${YELLOW}► ${NC}"
    else
      ptr_raw="  "
    fi

    # Checkbox (3 visual chars)
    local cb_raw
    if [[ $sel -eq 1 ]]; then
      cb_raw="${GREEN}[x]${NC}"
    else
      cb_raw="${DIM}[ ]${NC}"
    fi

    # Size suffix (variable)
    local sz_raw="" sz_vlen=0
    if [[ -n "$size" ]]; then
      sz_raw=" ${DIM}${size}${NC}"
      sz_vlen=$(( ${#size} + 1 ))
    fi

    # Name padded to NAME_FIELD
    local name_padded
    printf -v name_padded "%-${NAME_FIELD}s" "$name"

    # Full content: space(1) + ptr(2) + cb(3) + space(1) + name(NAME_FIELD) + sz
    local content=" ${ptr_raw}${cb_raw} ${name_padded}${sz_raw}"
    local vlen=$(( 1 + ptr_vlen + 3 + 1 + NAME_FIELD + sz_vlen ))

    _box_row "$BOX_IW" "$content" "$vlen"
  done

  # Bottom separator
  printf "${CYAN}╠%s╣${NC}\n" "$sep"

  # Footer
  local footer="  Space:toggle  Enter:run  q:quit"
  _box_row "$BOX_IW" "$footer" 34

  # Bottom border
  printf "${CYAN}╚%s╝${NC}\n" "$sep"
}

run_menu() {
  # Skip interactive menu when stdin/stdout is not a TTY
  if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
    echo "Running with default module selections (non-interactive)."
    return 0
  fi

  tput smcup 2>/dev/null || true
  _in_menu=1
  setup_terminal

  local cursor=0
  local total="${#MODULE_NAMES[@]}"

  render_menu "$cursor"

  while true; do
    local key
    key=$(read_key)

    case "$key" in
      UP)
        cursor=$(( (cursor - 1 + total) % total ))
        ;;
      DOWN)
        cursor=$(( (cursor + 1) % total ))
        ;;
      SPACE)
        local cur_val="${MODULE_SELECTED[$cursor]}"
        MODULE_SELECTED[$cursor]=$(( 1 - cur_val ))
        ;;
      ENTER)
        tput rmcup 2>/dev/null || true
        _in_menu=0
        tput cnorm 2>/dev/null || true
        stty echo 2>/dev/null || true
        _terminal_modified=0
        return 0
        ;;
      QUIT)
        tput rmcup 2>/dev/null || true
        _in_menu=0
        restore_terminal
        echo "Quit."
        exit 0
        ;;
    esac

    render_menu "$cursor"
  done
}

# --- Spinner state ---
_SPIN_PID=""
_SPIN_MSG=""

# Extended key reader — adds ALL / NONE on top of read_key
_read_pick_key() {
  local key=""
  IFS= read -rsn1 key || true
  if [[ "$key" == $'\x1b' ]]; then
    local seq=""
    IFS= read -rsn2 -t 1 seq || true
    case "$seq" in
      "[A") printf 'UP'   ;;
      "[B") printf 'DOWN' ;;
      *)    printf 'ESC'  ;;
    esac
  elif [[ "$key" == " " ]];                                      then printf 'SPACE'
  elif [[ "$key" == "" || "$key" == $'\n' || "$key" == $'\r' ]]; then printf 'ENTER'
  elif [[ "$key" == "q" || "$key" == "Q" ]];                     then printf 'QUIT'
  elif [[ "$key" == "a" || "$key" == "A" ]];                     then printf 'ALL'
  elif [[ "$key" == "n" || "$key" == "N" ]];                     then printf 'NONE'
  else printf 'OTHER'
  fi
}

# _spin_start MSG
_spin_start() {
  _SPIN_MSG="$1"
  if [[ ! -t 1 ]]; then
    printf "  … %s\n" "$_SPIN_MSG"
    return
  fi
  set +m 2>/dev/null || true
  (
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local fi=0
    while true; do
      printf "\r  %s %s " "${frames[$fi]}" "$_SPIN_MSG"
      fi=$(( (fi + 1) % 10 ))
      sleep 0.1
    done
  ) &
  _SPIN_PID=$!
}

# _spin_stop 0|1 [LABEL]
_spin_stop() {
  local ok="$1" label="${2:-$_SPIN_MSG}"
  if [[ -n "${_SPIN_PID:-}" ]]; then
    kill "$_SPIN_PID" 2>/dev/null || true
    wait "$_SPIN_PID" 2>/dev/null || true
    _SPIN_PID=""
    printf "\r\033[2K"
  fi
  if [[ "$ok" -eq 0 ]]; then
    printf "  ${GREEN}✓${NC} %s\n" "$label"
  else
    printf "  ${RED}✗${NC} %s\n" "$label"
  fi
}

# _render_pick_list TITLE VP CURSOR OFFSET SEL_STR ITEM...
# Always prints exactly vp+4 lines.
_render_pick_list() {
  local title="$1" vp="$2" cursor="$3" offset="$4" sel_str="$5"
  shift 5
  local items=("$@")
  local count="${#items[@]}"
  local iw=$BOX_IW
  local j

  # Top border with embedded title
  local tpad=$(( iw - ${#title} - 4 ))
  [[ $tpad -lt 0 ]] && tpad=0
  local tline="─ ${title} "
  for (( j=0; j<tpad; j++ )); do tline+="─"; done
  printf "${CYAN}┌%s┐${NC}\n" "$tline"

  # Viewport layout
  local above=$offset
  local above_ind=0
  [[ $above -gt 0 ]] && above_ind=1
  local max_for_items=$(( vp - above_ind ))
  local items_avail=$(( count - offset ))
  [[ $items_avail -lt 0 ]] && items_avail=0
  local items_shown
  if [[ $items_avail -lt $max_for_items ]]; then
    items_shown=$items_avail
  else
    items_shown=$max_for_items
  fi
  local below=$(( count - offset - items_shown ))
  [[ $below -lt 0 ]] && below=0
  local below_ind=0
  if [[ $below -gt 0 ]]; then
    below_ind=1
    items_shown=$(( items_shown - 1 ))
    [[ $items_shown -lt 0 ]] && items_shown=0
    below=$(( count - offset - items_shown ))
    [[ $below -lt 0 ]] && below=0
  fi
  local empty_fill=$(( vp - above_ind - items_shown - below_ind ))
  [[ $empty_fill -lt 0 ]] && empty_fill=0

  # Above indicator
  if [[ $above_ind -eq 1 ]]; then
    local ind="  ▲ ${above} more above"
    local pad=$(( iw - ${#ind} ))
    [[ $pad -lt 0 ]] && pad=0
    printf "${CYAN}│${DIM}%s%*s${NC}${CYAN}│${NC}\n" "$ind" "$pad" ""
  fi

  # Item rows
  local i
  for (( i=offset; i<offset+items_shown; i++ )); do
    local item="${items[$i]}"
    local is_sel=0
    printf '%s\n' "$sel_str" | grep -qxF "$i" 2>/dev/null && is_sel=1 || true
    local ptr_raw="  "
    [[ $i -eq $cursor ]] && ptr_raw="${BOLD}${YELLOW}► ${NC}"
    local cb_raw
    if [[ $is_sel -eq 1 ]]; then
      cb_raw="${GREEN}[✓]${NC}"
    else
      cb_raw="${DIM}[ ]${NC}"
    fi
    local max_item=$(( iw - 7 ))
    [[ $max_item -lt 0 ]] && max_item=0
    local item_disp="${item:0:$max_item}"
    local content=" ${ptr_raw}${cb_raw} ${item_disp}"
    local vlen=$(( 1 + 2 + 3 + 1 + ${#item_disp} ))
    local pad=$(( iw - vlen ))
    [[ $pad -lt 0 ]] && pad=0
    printf "${CYAN}│${NC}%s%*s${CYAN}│${NC}\n" "$content" "$pad" ""
  done

  # Below indicator
  if [[ $below_ind -eq 1 ]]; then
    local ind="  ▼ ${below} more"
    local pad=$(( iw - ${#ind} ))
    [[ $pad -lt 0 ]] && pad=0
    printf "${CYAN}│${DIM}%s%*s${NC}${CYAN}│${NC}\n" "$ind" "$pad" ""
  fi

  # Empty fill to keep height fixed
  for (( j=0; j<empty_fill; j++ )); do
    printf "${CYAN}│${NC}%*s${CYAN}│${NC}\n" "$iw" ""
  done

  # Separator
  local hsep=""
  for (( j=0; j<iw; j++ )); do hsep+="─"; done
  printf "${CYAN}├%s┤${NC}\n" "$hsep"

  # Footer
  local footer="  ↑↓ move  Spc toggle  a all  n none  Enter ok  q cancel"
  local fvlen=${#footer}
  [[ $fvlen -gt $iw ]] && footer="${footer:0:$iw}" && fvlen=$iw
  local fpad=$(( iw - fvlen ))
  [[ $fpad -lt 0 ]] && fpad=0
  printf "${CYAN}│${NC}%s%*s${CYAN}│${NC}\n" "$footer" "$fpad" ""

  # Bottom border
  local bbot=""
  for (( j=0; j<iw; j++ )); do bbot+="─"; done
  printf "${CYAN}└%s┘${NC}\n" "$bbot"
}

# _pick_list TITLE VP ITEM...
# Sets _PICK_RESULT to newline-separated selected indices.
# Returns 1 if cancelled.
_PICK_RESULT=""
_pick_list() {
  local title="$1" vp="$2"
  shift 2
  local items=("$@")
  local count="${#items[@]}"
  local total_lines=$(( vp + 4 ))

  # Non-TTY fallback
  if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
    _PICK_RESULT=""
    local i
    for (( i=0; i<count; i++ )); do
      printf "  %3d. %s\n" "$(( i+1 ))" "${items[$i]}"
    done
    printf "  Enter numbers (space-separated), 'a' for all, Enter to skip: "
    local sel=""
    IFS= read -r sel || true
    [[ -z "$sel" ]] && return 0
    if [[ "$sel" == "a" || "$sel" == "A" ]]; then
      for (( i=0; i<count; i++ )); do _PICK_RESULT+="$i"$'\n'; done
    else
      local num
      for num in $sel; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le $count ]]; then
          _PICK_RESULT+="$(( num - 1 ))"$'\n'
        fi
      done
    fi
    return 0
  fi

  local cursor=0 offset=0 sel_str=""
  tput civis 2>/dev/null || true
  stty -echo 2>/dev/null || true

  _render_pick_list "$title" "$vp" "$cursor" "$offset" "$sel_str" "${items[@]}"

  local rc=0
  while true; do
    local key
    key=$(_read_pick_key)
    case "$key" in
      UP)
        [[ $cursor -gt 0 ]] && (( cursor-- )) || true
        [[ $cursor -lt $offset ]] && offset=$cursor
        ;;
      DOWN)
        [[ $cursor -lt $(( count - 1 )) ]] && (( cursor++ )) || true
        local safe_vp=$(( vp - 2 ))
        [[ $safe_vp -lt 1 ]] && safe_vp=1
        if [[ $cursor -ge $(( offset + safe_vp )) ]]; then
          offset=$(( cursor - safe_vp + 1 ))
          [[ $offset -lt 0 ]] && offset=0
        fi
        ;;
      SPACE)
        local new_sel="" found=0 idx
        while IFS= read -r idx; do
          [[ -z "$idx" ]] && continue
          if [[ "$idx" == "$cursor" ]]; then
            found=1
          else
            new_sel+="$idx"$'\n'
          fi
        done < <(printf '%s\n' "$sel_str")
        [[ $found -eq 0 ]] && new_sel+="$cursor"$'\n'
        sel_str="$new_sel"
        ;;
      ALL)
        sel_str=""
        local ii
        for (( ii=0; ii<count; ii++ )); do sel_str+="$ii"$'\n'; done
        ;;
      NONE)
        sel_str=""
        ;;
      ENTER)
        _PICK_RESULT="$sel_str"
        rc=0
        break
        ;;
      QUIT)
        _PICK_RESULT=""
        rc=1
        break
        ;;
    esac
    printf "\033[%dA" "$total_lines"
    _render_pick_list "$title" "$vp" "$cursor" "$offset" "$sel_str" "${items[@]}"
  done

  tput cnorm 2>/dev/null || true
  stty echo 2>/dev/null || true
  return $rc
}

# _render_log TITLE HEIGHT LOG_OFFSET — prints height+6 lines using CLEAN_LOG
_render_log() {
  local title="$1" height="$2" log_offset="$3"
  local count="${#CLEAN_LOG[@]}"
  local iw=$BOX_IW
  local j

  local sep=""
  for (( j=0; j<iw; j++ )); do sep+="═"; done

  local up_ind=""
  [[ $log_offset -gt 0 ]] && up_ind=" ↑"
  local title_content="  ${title} (${count})${up_ind}"
  local title_vlen=$(( ${#title} + ${#count} + 5 + ${#up_ind} ))

  printf "${CYAN}╔%s╗${NC}\n" "$sep"
  _box_row "$iw" "$title_content" "$title_vlen"
  printf "${CYAN}╠%s╣${NC}\n" "$sep"

  local visible_end=$(( log_offset + height ))
  [[ $visible_end -gt $count ]] && visible_end=$count
  local i
  for (( i=log_offset; i<visible_end; i++ )); do
    local entry="${CLEAN_LOG[$i]}"
    local trunc="${entry:0:$(( iw - 4 ))}"
    _box_row "$iw" "  ${DIM}${trunc}${NC}" $(( ${#trunc} + 2 ))
  done

  local shown=$(( visible_end - log_offset ))
  while [[ $shown -lt $height ]]; do
    _box_row "$iw" "" 0
    (( shown++ )) || true
  done

  printf "${CYAN}╠%s╣${NC}\n" "$sep"

  local max_off=$(( count - height ))
  [[ $max_off -lt 0 ]] && max_off=0
  local down_ind=""
  [[ $log_offset -lt $max_off ]] && down_ind=" ↓"
  local footer="  ↑↓ scroll   q / Enter to close${down_ind}"
  _box_row "$iw" "$footer" "${#footer}"

  printf "${CYAN}╚%s╝${NC}\n" "$sep"
}

# _scrollable_log TITLE HEIGHT — interactive CLEAN_LOG viewer
_scrollable_log() {
  local title="$1" height="$2"
  local count="${#CLEAN_LOG[@]}"
  [[ $count -eq 0 ]] && return 0

  local log_offset=0
  local total_lines=$(( height + 6 ))

  tput civis 2>/dev/null || true
  stty -echo 2>/dev/null || true

  _render_log "$title" "$height" "$log_offset"

  while true; do
    local key
    key=$(read_key)
    case "$key" in
      UP)
        [[ $log_offset -gt 0 ]] && (( log_offset-- )) || true
        ;;
      DOWN)
        local max_off=$(( count - height ))
        [[ $max_off -lt 0 ]] && max_off=0
        [[ $log_offset -lt $max_off ]] && (( log_offset++ )) || true
        ;;
      ENTER|QUIT)
        break
        ;;
    esac
    printf "\033[%dA" "$total_lines"
    _render_log "$title" "$height" "$log_offset"
  done

  tput cnorm 2>/dev/null || true
  stty echo 2>/dev/null || true
}

# ============================================================================
# [D] SIZE HELPERS
# ============================================================================

# Sum disk usage (KB) for given paths; silently skips non-existent
size_kb() {
  local total=0 path kb
  for path in "$@"; do
    [[ -e "$path" ]] || continue
    kb=$(du -sk "$path" 2>/dev/null | awk '{print $1}') || kb=0
    total=$(( total + ${kb:-0} ))
  done
  printf '%s' "$total"
}

# Convert KB to human-readable string
human_size() {
  local kb="${1:-0}"
  awk -v kb="$kb" 'BEGIN {
    if      (kb >= 1048576) printf "~%.1f GB", kb/1048576
    else if (kb >= 1024)    printf "~%.0f MB", kb/1024
    else                    printf "~%d KB",   kb
  }'
}

# Populate MODULE_SIZES[] — called before run_menu
calculate_all_sizes() {
  local i
  for (( i=0; i<8; i++ )); do
    local kb=0
    case $i in
      0)  # User Caches
          kb=$(size_kb "$HOME/Library/Caches/") ;;
      1)  # System Logs
          kb=$(size_kb "$HOME/Library/Logs/") ;;
      2)  # Temp Files
          kb=$(size_kb "/private/tmp" "${TMPDIR:-/tmp}") ;;
      3)  # Developer Junk
          local dev_paths=(
            "$HOME/Library/Developer/Xcode/DerivedData"
            "$HOME/Library/Developer/Xcode/Archives"
            "$HOME/Library/Developer/CoreSimulator/Caches"
            "$HOME/.npm/_cacache"
            "$HOME/Library/Caches/Yarn"
            "$HOME/.yarn/cache"
            "$HOME/Library/Caches/pip"
            "$HOME/.gradle/caches"
            "$HOME/Library/Caches/CocoaPods"
            "$HOME/.cocoapods/repos"
          )
          kb=$(size_kb "${dev_paths[@]}") ;;
      4)  # Browser Data (caches only for size estimate)
          kb=$(size_kb \
            "$HOME/Library/Caches/com.apple.Safari" \
            "$HOME/Library/Caches/Google/Chrome" \
            "$HOME/Library/Caches/BraveSoftware" \
            "$HOME/Library/Caches/Firefox/Profiles") ;;
      5|6|7)
          kb=0 ;;
    esac
    if [[ ${kb:-0} -gt 0 ]]; then
      MODULE_SIZES[$i]=$(human_size "$kb")
    else
      MODULE_SIZES[$i]=""
    fi
  done
}

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

# ============================================================================
# [G] MODULE FUNCTIONS
# ============================================================================

# ---------- Module 0: User Caches ----------
module_0_clean() {
  printf "${BOLD}== User Caches ==${NC}\n"
  local cache_dir="$HOME/Library/Caches"
  [[ -d "$cache_dir" ]] || { echo "  No cache directory found."; return; }

  local ALLOWLIST=("com.apple.AppleMultitouchTrackpad" "com.apple.findmydeviced")
  local entry basename skip allowed

  for entry in "$cache_dir"/*/; do
    [[ -e "$entry" ]] || continue
    basename=$(basename "$entry")
    skip=0
    for allowed in "${ALLOWLIST[@]}"; do
      [[ "$basename" == "$allowed" ]] && skip=1 && break
    done
    if [[ $skip -eq 1 ]]; then
      printf "${DIM}  Skipping (allowlisted): %s${NC}\n" "$basename"
      continue
    fi
    safe_delete "$entry"
  done

  # Also clean loose files directly in Caches
  for entry in "$cache_dir"/*.db "$cache_dir"/*.sqlite; do
    [[ -f "$entry" ]] && safe_delete "$entry"
  done
}

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

# ---------- Module 6: App Uninstaller ----------

# Echo all leftover paths for a given bundle ID / app name
find_app_files() {
  local bundle_id="$1" app_name="$2"
  local dir entry

  local user_dirs=(
    "$HOME/Library/Application Support"
    "$HOME/Library/Preferences"
    "$HOME/Library/Caches"
    "$HOME/Library/Logs"
    "$HOME/Library/Saved Application State"
    "$HOME/Library/Containers"
    "$HOME/Library/Group Containers"
    "$HOME/Library/LaunchAgents"
  )

  for dir in "${user_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    # Exact bundle-id match
    for entry in \
        "$dir/$bundle_id" \
        "$dir/$bundle_id.plist"; do
      [[ -e "$entry" ]] && printf '%s\n' "$entry"
    done
    # Prefix match (e.g. com.foo.bar.helper)
    for entry in "$dir/${bundle_id}"*/; do
      [[ -e "$entry" ]] && printf '%s\n' "$entry"
    done
    # App-name match
    for entry in "$dir/$app_name" "$dir/$app_name.plist"; do
      [[ -e "$entry" ]] && printf '%s\n' "$entry"
    done
  done

  # Sudo paths
  local sudo_dirs=(
    "/Library/LaunchDaemons"
    "/Library/Application Support"
    "/Library/Preferences"
  )
  for dir in "${sudo_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    for entry in \
        "$dir/$bundle_id" \
        "$dir/$bundle_id.plist" \
        "$dir/$app_name" \
        "$dir/$app_name.plist"; do
      [[ -e "$entry" ]] && printf 'sudo:%s\n' "$entry"
    done
    for entry in "$dir/${bundle_id}"*/; do
      [[ -e "$entry" ]] && printf 'sudo:%s\n' "$entry"
    done
  done
}

module_6_clean() {
  printf "${BOLD}== App Uninstaller ==${NC}\n"

  local apps=() display_names=() app
  for app in /Applications/*.app "$HOME/Applications"/*.app; do
    [[ -d "$app" ]] || continue
    apps+=("$app")
    local name kb sz
    name=$(basename "$app" .app)
    kb=$(du -sk "$app" 2>/dev/null | awk '{print $1}') || kb=0
    sz=$(human_size "$kb")
    display_names+=("$(printf '%-30s (%s)' "$name" "$sz")")
  done

  if [[ ${#apps[@]} -eq 0 ]]; then
    printf "  No applications found.\n"
    return
  fi

  printf "\n"
  _PICK_RESULT=""
  if ! _pick_list "Select apps to uninstall" 10 "${display_names[@]}"; then
    printf "  Cancelled.\n"
    return
  fi

  [[ -z "$_PICK_RESULT" ]] && { printf "  Nothing selected.\n"; return; }

  local removed=0
  while IFS= read -r idx; do
    [[ -z "$idx" ]] && continue
    local selected_app="${apps[$idx]}"
    local app_name
    app_name=$(basename "$selected_app" .app)

    if [[ $DRY_RUN -eq 1 ]]; then
      printf "${YELLOW}  [DRY-RUN] Would uninstall: %s${NC}\n" "$app_name"
      (( removed++ )) || true
      continue
    fi

    _spin_start "Uninstalling $app_name..."
    { safe_delete "$selected_app"; } >/dev/null 2>&1
    _spin_stop 0 "Uninstalled $app_name"
    (( removed++ )) || true
  done < <(printf '%s\n' "$_PICK_RESULT")

  printf "  Removed %d app(s).\n" "$removed"
}

# ---------- Module 7: Orphaned Data ----------

# Build newline-separated list of installed bundle IDs (global, reused)
_INSTALLED_IDS=""

_build_installed_ids() {
  _INSTALLED_IDS=""
  local app bid
  for app in /Applications/*.app "$HOME/Applications"/*.app; do
    [[ -d "$app" ]] || continue
    bid=$(defaults read "$app/Contents/Info.plist" CFBundleIdentifier 2>/dev/null) || continue
    _INSTALLED_IDS+="${bid}"$'\n'
  done
}

_is_installed() {
  local bid="$1"
  printf '%s' "$_INSTALLED_IDS" | grep -qxF "$bid"
}

module_7_clean() {
  printf "${BOLD}== Orphaned Data ==${NC}\n"
  printf "  Building installed-app list...\n"

  _build_installed_ids
  local app_count
  app_count=$(printf '%s' "$_INSTALLED_IDS" | grep -c '.' 2>/dev/null || echo 0)
  printf "  Found %s installed apps.\n" "$app_count"
  printf "  Scanning for orphaned data...\n"

  local scan_dirs=(
    "$HOME/Library/Application Support"
    "$HOME/Library/Caches"
    "$HOME/Library/Saved Application State"
    "$HOME/Library/Containers"
    "$HOME/Library/Group Containers"
  )

  local orphans=()
  local dir entry basename

  for dir in "${scan_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    for entry in "$dir"/*/; do
      [[ -d "$entry" ]] || continue
      basename=$(basename "$entry")
      # Skip entries that don't look like bundle IDs (no dot)
      [[ "$basename" != *.* ]] && continue
      # Keep Apple system entries — they are managed by macOS
      [[ "$basename" == com.apple.* ]] && continue
      _is_installed "$basename" || orphans+=("$entry")
    done
  done

  # Preferences plists
  for entry in "$HOME/Library/Preferences"/*.plist; do
    [[ -f "$entry" ]] || continue
    basename=$(basename "$entry" .plist)
    [[ "$basename" != *.* ]]      && continue
    [[ "$basename" == com.apple.* ]] && continue
    _is_installed "$basename" || orphans+=("$entry")
  done

  # LaunchAgents — check Label key
  for entry in "$HOME/Library/LaunchAgents"/*.plist; do
    [[ -f "$entry" ]] || continue
    local label=""
    label=$(defaults read "$entry" Label 2>/dev/null) || continue
    [[ "$label" == com.apple.* ]] && continue
    _is_installed "$label" || orphans+=("$entry")
  done

  if [[ ${#orphans[@]} -eq 0 ]]; then
    printf "${GREEN}  No orphaned data found!${NC}\n"
    return
  fi

  # Build display items with sizes
  local display_items=() e ekb
  for e in "${orphans[@]}"; do
    ekb=$(du -sk "$e" 2>/dev/null | awk '{print $1}') || ekb=0
    display_items+=("$(printf '%-45s (%s)' "$(basename "$e")" "$(human_size "$ekb")")")
  done

  printf "\n"
  _PICK_RESULT=""
  if ! _pick_list "Select orphaned data to remove" 10 "${display_items[@]}"; then
    printf "  Cancelled.\n"
    return
  fi

  [[ -z "$_PICK_RESULT" ]] && { printf "  Nothing selected.\n"; return; }

  local removed=0
  while IFS= read -r idx; do
    [[ -z "$idx" ]] && continue
    local target="${orphans[$idx]}"

    if [[ $DRY_RUN -eq 1 ]]; then
      printf "${YELLOW}  [DRY-RUN] Would remove: %s${NC}\n" "$target"
      (( removed++ )) || true
      continue
    fi

    _spin_start "Removing $(basename "$target")..."
    { safe_delete "$target"; } >/dev/null 2>&1
    _spin_stop 0 "Removed $(basename "$target")"
    (( removed++ )) || true
  done < <(printf '%s\n' "$_PICK_RESULT")

  printf "  Removed %d item(s).\n" "$removed"
}

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
    case $i in
      0) module_0_clean ;;
      1) module_1_clean ;;
      2) module_2_clean ;;
      3) module_3_clean ;;
      4) module_4_clean ;;
      5) module_5_clean ;;
      6) module_6_clean ;;
      7) module_7_clean ;;
    esac
    printf "\n"
  done
}

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

# ============================================================================
# [J] ENTRY POINT
# ============================================================================

print_help() {
  cat <<EOF
mac-optimizer-cli v${VERSION}
A CLI optimizer for macOS

Usage: $(basename "$0") [OPTIONS]

Options:
  -n, --dry-run   Preview what would be deleted (no changes made)
  -y, --yes       Skip all confirmation prompts
  -h, --help      Show this help message

Modules (default selections shown):
  [ON]  0. User Caches         ~/Library/Caches
  [ON]  1. System Logs         ~/Library/Logs, /var/log rotated logs
  [ON]  2. Temp Files          /tmp, \$TMPDIR
  [OFF] 3. Developer Junk      Xcode DerivedData, npm/pip/gradle caches
  [OFF] 4. Browser Data        Safari/Chrome/Brave/Firefox caches, cookies, history
  [ON]  5. System Maintenance  Flush DNS, periodic scripts, LaunchAgents audit
  [OFF] 6. App Uninstaller     Remove apps and all associated data files
  [OFF] 7. Orphaned Data       Find leftovers from uninstalled apps

Examples:
  $(basename "$0")                 # Interactive mode
  $(basename "$0") --dry-run       # Preview all changes
  $(basename "$0") --dry-run --yes # Non-interactive preview
  $(basename "$0") --yes           # Run with defaults, no prompts
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--dry-run) DRY_RUN=1 ; shift ;;
      -y|--yes)     AUTO_YES=1 ; shift ;;
      -h|--help)    print_help ; exit 0 ;;
      *)
        printf "${RED}Unknown option: %s${NC}\n" "$1" >&2
        print_help >&2
        exit 1 ;;
    esac
  done
}

main() {
  parse_args "$@"

  # macOS only
  if [[ "$(uname -s)" != "Darwin" ]]; then
    printf "${RED}Error: This script requires macOS.${NC}\n" >&2
    exit 1
  fi

  printf "${BOLD}mac-optimizer-cli v%s${NC}\n" "$VERSION"
  printf "${DIM}Calculating sizes, please wait...${NC}\n"
  calculate_all_sizes

  run_menu

  acquire_sudo

  run_selected_modules

  print_summary
}

main "$@"
