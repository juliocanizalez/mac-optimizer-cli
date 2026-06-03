#!/usr/bin/env bash
# build.sh — assembles mac-optimizer.sh from src/ modules
set -euo pipefail

VERSION=$(cat VERSION)
OUT="mac-optimizer.sh"
TMP=$(mktemp)

cat > "$TMP" <<HEADER
#!/usr/bin/env bash
# mac-optimizer.sh — macOS disk cleanup and maintenance CLI tool
# Usage: ./mac-optimizer.sh [--dry-run] [--yes] [--help]
set -uo pipefail

VERSION="${VERSION}"
HEADER

for file in \
  src/lib/globals.sh \
  src/lib/config.sh \
  src/lib/ui.sh \
  src/lib/utils.sh \
  src/lib/sudo.sh \
  src/lib/delete.sh \
  src/modules/module_0_caches.sh \
  src/modules/module_1_logs.sh \
  src/modules/module_2_temp.sh \
  src/modules/module_3_dev.sh \
  src/modules/module_4_browser.sh \
  src/modules/module_5_maintenance.sh \
  src/modules/module_6_uninstaller.sh \
  src/modules/module_7_orphans.sh \
  src/lib/execution.sh \
  src/lib/summary.sh \
  src/entrypoint.sh; do
  printf '\n' >> "$TMP"
  cat "$file" >> "$TMP"
done

mv "$TMP" "$OUT"
chmod +x "$OUT"
printf "Built %s (v%s)\n" "$OUT" "$VERSION"
