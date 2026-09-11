#!/bin/bash
# ==============================================================================
# Quran Live Broadcast — Crontab Installer for Autonomous Maintenance & Watchdog
# ==============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

WATCHDOG_SCRIPT="$BASE_DIR/scripts/watchdog.sh"
MAINTENANCE_SCRIPT="$BASE_DIR/scripts/maintenance.sh"

chmod +x "$BASE_DIR"/scripts/*.sh 2>/dev/null || true

# Prepare cron lines
CRON_WATCHDOG="* * * * * $WATCHDOG_SCRIPT >/dev/null 2>&1"
CRON_MAINTENANCE="30 3 * * * $MAINTENANCE_SCRIPT >/dev/null 2>&1"

# Read existing crontab
CURRENT_CRON=$(crontab -l 2>/dev/null || true)

# Remove existing Quran cron entries if any
CLEANED_CRON=$(echo "$CURRENT_CRON" | grep -v "$BASE_DIR/scripts" || true)

# Append new entries
NEW_CRON=$(printf "%s\n# Quran Live Broadcast Autonomous Jobs\n%s\n%s\n" "$CLEANED_CRON" "$CRON_WATCHDOG" "$CRON_MAINTENANCE" | sed '/^$/N;/^\n$/D')

echo "$NEW_CRON" | crontab -

echo "=========================================================="
echo "✓ Quran Live Broadcast crontab successfully installed!"
echo "  - Watchdog    : Runs every 1 minute to ensure 100% uptime"
echo "  - Maintenance : Runs daily at 03:30 AM (updates, cleanup, RAM refresh)"
echo "=========================================================="
crontab -l | grep "$BASE_DIR"
