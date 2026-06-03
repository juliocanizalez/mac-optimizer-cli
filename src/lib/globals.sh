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
