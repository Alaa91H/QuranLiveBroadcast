#!/bin/bash
# ==============================================================================
# Quran Live Stream — Autonomous Self-Healing Watchdog
# Runs periodically (or via cron/systemd) to detect drops, zombie processes,
# or network stalls, and instantly recovers the live broadcast without human intervention.
# ==============================================================================
set -euo pipefail
# Single-instance guard: cron runs every minute and loaded hosts are slow, so
# overlapping runs must exit instead of relaunching a healthy stack twice.
exec 9>/tmp/quran-watchdog.lock
flock -n 9 || exit 0
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

# 1. Health check Web Server (generous timeout: 3s is too short under CPU steal
# and causes false "down" detections followed by needless restarts = stutter)
WEB_OK=0
if curl -s --max-time 10 --retry 2 --retry-delay 2 "$HEALTH_URL" | grep -q '"ok":true'; then
  WEB_OK=1
fi

# Helper: wait until 127.0.0.1:$PORT is free (after stop_ui) before relaunching,
# avoiding EADDRINUSE crashes.
wait_port_free() {
  local i
  for i in $(seq 1 15); do
    (echo >/dev/tcp/127.0.0.1/$PORT) >/dev/null 2>&1 || break
    sleep 1
  done
}

if [ "$WEB_OK" -eq 0 ]; then
  log "WARNING: Quran web server not responding on $HEALTH_URL. Triggering auto-recovery..."
  "$BASE_DIR/scripts/stop_ui.sh" >/dev/null 2>&1 || true
  wait_port_free
  "$BASE_DIR/scripts/broadcast_ui.sh" >>"$LOG_DIR/web.log" 2>&1
  log "Web server and UI re-launched."
fi

# 2. Check Xvfb and Chromium processes
CHROME_PIDFILE="$RUNTIME/quran-chrome.pid"
XVFB_PIDFILE="$RUNTIME/quran-xvfb.pid"

if [ -f "$XVFB_PIDFILE" ] && ! kill -0 "$(cat "$XVFB_PIDFILE" 2>/dev/null)" 2>/dev/null; then
  log "WARNING: Xvfb process died. Restarting UI..."
  "$BASE_DIR/scripts/broadcast_ui.sh" >>"$LOG_DIR/web.log" 2>&1
fi

if [ -f "$CHROME_PIDFILE" ] && ! kill -0 "$(cat "$CHROME_PIDFILE" 2>/dev/null)" 2>/dev/null; then
  log "WARNING: Chromium browser process died. Re-launching..."
  "$BASE_DIR/scripts/broadcast_ui.sh" >>"$LOG_DIR/web.log" 2>&1
fi

# 3. Check Streaming Process (FFmpeg)
if pgrep -f "ffmpeg.*x11grab" >/dev/null 2>&1; then
  : # FFmpeg is actively transmitting
else
  # Check if stream was enabled
  if [ -f "$RUNTIME/stream_active.flag" ] || systemctl --user is-active --quiet quran-live-youtube.service 2>/dev/null; then
    log "WARNING: FFmpeg streaming process is down while stream is flagged active. Restarting YouTube stream..."
    if command -v systemctl >/dev/null 2>&1 && systemctl --user is-enabled --quiet quran-live-youtube.service 2>/dev/null; then
      systemctl --user restart quran-live-youtube.service
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
  # Drop OS caches if running as root or with passwordless sudo (cron runs as ubuntu)
  if [ "$(id -u)" -eq 0 ]; then
    sync && echo 3 > /proc/sys/vm/drop_caches
    log "Kernel cache dropped. Available RAM now: $(free -m | awk '/^Mem:/{print $4+$7}')MB"
  elif sudo -n true 2>/dev/null; then
    sync && echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
    log "Kernel cache dropped via sudo. Available RAM now: $(free -m | awk '/^Mem:/{print $4+$7}')MB"
  fi
fi
