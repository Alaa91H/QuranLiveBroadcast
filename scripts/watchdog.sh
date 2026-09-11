#!/bin/bash
# ==============================================================================
# Quran Live Broadcast — Autonomous Self-Healing Watchdog
# Runs periodically (or via cron/systemd) to detect drops, zombie processes,
# or network stalls, and instantly recovers the live broadcast without human intervention.
# ==============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

LOG_DIR="$BASE_DIR/logs"
RUNTIME="$BASE_DIR/runtime"
mkdir -p "$LOG_DIR" "$RUNTIME"
WATCHDOG_LOG="$LOG_DIR/watchdog.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WATCHDOG] $*" | tee -a "$WATCHDOG_LOG"
}

PORT="${QURAN_WEB_PORT:-4177}"
HEALTH_URL="http://127.0.0.1:$PORT/api/health"

# 1. Health check Web Server
WEB_OK=0
if curl -s --max-time 3 "$HEALTH_URL" | grep -q '"ok":true'; then
  WEB_OK=1
fi

if [ "$WEB_OK" -eq 0 ]; then
  log "WARNING: Quran web server not responding on $HEALTH_URL. Triggering auto-recovery..."
  "$BASE_DIR/scripts/stop_ui.sh" >/dev/null 2>&1 || true
  sleep 2
  "$BASE_DIR/scripts/broadcast_ui.sh" >>"$LOG_DIR/web.log" 2>&1 &
  log "Web server and UI re-launched."
fi

# 2. Check Xvfb and Chromium processes
CHROME_PIDFILE="$RUNTIME/quran-chrome.pid"
XVFB_PIDFILE="$RUNTIME/quran-xvfb.pid"

if [ -f "$XVFB_PIDFILE" ] && ! kill -0 "$(cat "$XVFB_PIDFILE" 2>/dev/null)" 2>/dev/null; then
  log "WARNING: Xvfb process died. Restarting UI..."
  "$BASE_DIR/scripts/broadcast_ui.sh" >>"$LOG_DIR/web.log" 2>&1 &
fi

if [ -f "$CHROME_PIDFILE" ] && ! kill -0 "$(cat "$CHROME_PIDFILE" 2>/dev/null)" 2>/dev/null; then
  log "WARNING: Chromium browser process died. Re-launching..."
  "$BASE_DIR/scripts/broadcast_ui.sh" >>"$LOG_DIR/web.log" 2>&1 &
fi

# 3. Check Streaming Process (FFmpeg)
if pgrep -f "ffmpeg.*x11grab" >/dev/null 2>&1; then
  : # FFmpeg is actively transmitting
else
  # Check if stream was enabled
  if [ -f "$RUNTIME/stream_active.flag" ] || systemctl --user is-active --quiet quran-youtube.service 2>/dev/null; then
    log "WARNING: FFmpeg streaming process is down while stream is flagged active. Restarting YouTube stream..."
    if command -v systemctl >/dev/null 2>&1 && systemctl --user is-enabled --quiet quran-youtube.service 2>/dev/null; then
      systemctl --user restart quran-youtube.service
    else
      nohup "$BASE_DIR/scripts/stream_youtube.sh" >>"$LOG_DIR/stream_youtube.log" 2>&1 &
    fi
    log "Stream restarted successfully."
  fi
fi

# 4. Memory pressure protection for 1GB VPS
FREE_RAM_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $4+$7}' || echo 500)
if [ "$FREE_RAM_MB" -lt 60 ]; then
  log "CAUTION: Available memory very low (${FREE_RAM_MB}MB). Triggering memory compaction..."
  # Clean old temporary browser cache if accessible
  rm -rf ~/.cache/chromium/Default/Cache/* 2>/dev/null || true
  # Drop OS caches if running as root or with sudo
  if [ "$(id -u)" -eq 0 ]; then
    sync && echo 3 > /proc/sys/vm/drop_caches
    log "Kernel cache dropped. Available RAM now: $(free -m | awk '/^Mem:/{print $4+$7}')MB"
  fi
fi
