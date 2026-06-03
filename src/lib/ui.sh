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
