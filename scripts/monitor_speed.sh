#!/bin/bash
# ==============================================================================
# Quran Live Stream — Encode Speed Monitor (run every 3 min via cron)
# Reads the last ffmpeg "speed=" from logs/stream_youtube.log. Sustained speed
# below SPEED_MIN (default 0.8x) means the encoder cannot keep realtime: after
# SPEED_HITS consecutive low readings the stream service is restarted and (if
# configured) a Telegram alert is sent. Missing speed data (UNKNOWN) never
# triggers a restart, only a log line: with -loglevel warning the status line
# may be absent, and a blind restart would flap the broadcast.
# Knobs (.env): SPEED_MIN=0.8  SPEED_HITS=3  SPEED_MONITOR=0 (disable)
# State: runtime/speed_state ("<hits> <last_epoch>")
# ==============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

[ -f .env ] && { set -a; source .env 2>/dev/null; set +a; } || true

LOG_DIR="$BASE_DIR/logs"
RUNTIME="$BASE_DIR/runtime"
mkdir -p "$LOG_DIR" "$RUNTIME"
MON_LOG="$LOG_DIR/speed_monitor.log"
STATE="$RUNTIME/speed_state"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SPEED] $*" | tee -a "$MON_LOG"
}

# --- Disk guard: keep / use under 90% (logs + cache, never media) -----------------
# Live-only broadcast keeps no episode library; guard log/cache growth instead.
disk_pct() {
  local p
  p="$(df -P "$BASE_DIR" 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')"
  case "$p" in ''|*[!0-9]*) p=0 ;; esac
  echo "$p"
}
if [ "$(disk_pct)" -ge 90 ]; then
  log "DISK OVER 90%: pruning rotated logs (*.old.gz) and web cache..."
  rm -f "$LOG_DIR"/*.old.gz 2>/dev/null || true
  find "$BASE_DIR/web/.cache" -type f -name '*.json' -mtime +3 -delete 2>/dev/null || true
  ALERT_MARKER="$RUNTIME/disk_alert_day"
  if [ "$(date +%F)" != "$(cat "$ALERT_MARKER" 2>/dev/null)" ]; then
    date +%F > "$ALERT_MARKER"
    "$BASE_DIR/scripts/notify_telegram.sh" "⚠️ QuranLive: disk over 90%, rotated logs pruned automatically." || true
  fi
fi

# --- Observability: machine-readable status for dashboards ----------------------
write_status() {
  # $1 = speed (may be empty), $2 = note
  local load mem_avail ff_up cc
  load="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo ?)"
  mem_avail="$(free -m 2>/dev/null | awk '/^Mem:/{print $7}' || echo ?)"
  # Never fatal: busybox ps lacks -C/-o (this is observability, not control)
  ff_up="$(ps -o etime= -C ffmpeg 2>/dev/null | head -1 | tr -d ' ' || true)"
  cc=""
  [ -f "$BASE_DIR/runtime/host.env" ] && cc="$(grep -E '^HOST_CC=' "$BASE_DIR/runtime/host.env" 2>/dev/null | cut -d= -f2)"
  printf '{"ts":%s,"speed":"%s","load":"%s","mem_avail_mb":"%s","ffmpeg_uptime":"%s","cc":"%s","note":"%s"}\n' \
    "$(date +%s)" "${1:-?}" "$load" "$mem_avail" "${ff_up:-none}" "${cc:-?}" "${2:-ok}" > "$RUNTIME/status.json"
}

if [ "${SPEED_MONITOR:-1}" = "0" ]; then
  exit 0
fi

SPEED_MIN="${SPEED_MIN:-0.8}"
SPEED_HITS="${SPEED_HITS:-3}"

# Only meaningful while the youtube service is supposed to be up
if command -v systemctl >/dev/null 2>&1 && ! systemctl --user is-active --quiet quran-live-youtube.service 2>/dev/null; then
  write_status "" "service-inactive"
  exit 0
fi
if ! pgrep -f "ffmpeg.*x11grab" >/dev/null 2>&1; then
  write_status "" "no-ffmpeg"
  exit 0
fi

# Last reported speed in the recent log tail (portable awk, no grep -P)
LAST_SPEED="$(tail -n 400 "$LOG_DIR/stream_youtube.log" 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i ~ /^speed=/) {split($i,a,"="); sub(/x$/,"",a[2]); v=a[2]}} END{print v+0}')"
if [ -z "$LAST_SPEED" ] || [ "$LAST_SPEED" = "0" ]; then
  log "UNKNOWN: no speed= data in recent log (status line suppressed?). Skipping cycle, no restart."
  write_status "" "no-speed-data"
  exit 0
fi

HITS=0
[ -f "$STATE" ] && HITS="$(cut -d' ' -f1 "$STATE" 2>/dev/null || echo 0)"
case "$HITS" in ''|*[!0-9]*) HITS=0 ;; esac

SLOW="$(awk "BEGIN{print ($LAST_SPEED < $SPEED_MIN)}")"
write_status "$LAST_SPEED" "ok"
if [ "$SLOW" = "1" ]; then
  HITS=$((HITS + 1))
  echo "$HITS $(date +%s)" > "$STATE"
  log "LOW speed=${LAST_SPEED}x < ${SPEED_MIN}x (hit $HITS/$SPEED_HITS)."
  if [ "$HITS" -ge "$SPEED_HITS" ]; then
    log "Sustained slow encode, restarting quran-live-youtube.service..."
    echo "0 $(date +%s)" > "$STATE"
    if systemctl --user restart quran-live-youtube.service 2>/dev/null; then
      log "Restart issued."
    else
      log "Restart via systemd failed, killing ffmpeg to trigger supervisor loop..."
      pkill -f "ffmpeg.*x11grab" 2>/dev/null || true
    fi
    "$BASE_DIR/scripts/notify_telegram.sh" "⚠️ QuranLive: encoder speed ${LAST_SPEED}x below ${SPEED_MIN}x — stream restarted automatically." || true
  fi
else
  if [ "$HITS" -gt 0 ]; then
    log "Recovered: speed=${LAST_SPEED}x, resetting counter."
  fi
  echo "0 $(date +%s)" > "$STATE"
fi
