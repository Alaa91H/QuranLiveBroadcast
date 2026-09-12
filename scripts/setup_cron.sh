#!/bin/bash
# ==============================================================================
# Quran Live Broadcast — Crontab Installer for Autonomous Maintenance & Watchdog
# ==============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

WATCHDOG_SCRIPT="$BASE_DIR/scripts/watchdog.sh"
MAINTENANCE_SCRIPT="$BASE_DIR/scripts/maintenance.sh"
RECORD_SCRIPT="$BASE_DIR/scripts/record_episode.sh"
SPEED_SCRIPT="$BASE_DIR/scripts/monitor_speed.sh"

chmod +x "$BASE_DIR"/scripts/*.sh 2>/dev/null || true

# Prepare cron lines
CRON_WATCHDOG="* * * * * $WATCHDOG_SCRIPT >/dev/null 2>&1"
CRON_MAINTENANCE="30 3 * * * $MAINTENANCE_SCRIPT >/dev/null 2>&1"
# Nightly 2h slice for the 24h loop (build_loop.sh assembles; 03:30 maintenance
# restart switches the stream to fresh material automatically)
CRON_RECORD="0 1 * * * $RECORD_SCRIPT 120 >/dev/null 2>&1"
# Encode-speed monitor: restarts on sustained <0.8x + Telegram alert if configured
CRON_SPEED="*/3 * * * * $SPEED_SCRIPT >/dev/null 2>&1"

# Read existing crontab
CURRENT_CRON=$(crontab -l 2>/dev/null || true)

# Remove existing Quran cron entries if any
CLEANED_CRON=$(echo "$CURRENT_CRON" | grep -v "$BASE_DIR/scripts" || true)

# Append new entries
NEW_CRON=$(printf "%s\n# Quran Live Broadcast Autonomous Jobs\n%s\n%s\n%s\n%s\n" "$CLEANED_CRON" "$CRON_WATCHDOG" "$CRON_MAINTENANCE" "$CRON_RECORD" "$CRON_SPEED" | sed '/^$/N;/^\n$/D')

echo "$NEW_CRON" | crontab -

echo "=========================================================="
echo "✓ Quran Live Broadcast crontab successfully installed!"
echo "  - Watchdog    : Runs every 1 minute to ensure 100% uptime"
echo "  - Maintenance : Runs daily at 03:30 AM (updates, cleanup, RAM refresh)"
echo "  - Record      : 2h slice daily at 01:00 AM (24h loop material)"
echo "  - Speed check : Encode speed every 3 min (auto-restart + alert)"
echo "=========================================================="
crontab -l | grep "$BASE_DIR"

# First-boot adaptation (detect/provision/benchmark): once per install unless
# FIRST_BOOT=0. Takes ~2-5 min (swap/zram setup + egress probe + x264 bench).
if [ "${FIRST_BOOT:-1}" = "1" ]; then
  echo "Running first-boot host adaptation (detect/provision/benchmark)..."
  "$BASE_DIR/scripts/first_boot.sh" || echo " first-boot had warnings (see logs/), continuing."
fi
