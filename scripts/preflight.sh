#!/bin/bash
# ==============================================================================
# Quran Live Stream — Preflight (verify BEFORE streaming)
# Synchronous, fast (<30s), zero background work. Checks every input the stream
# needs and writes the effective decision to runtime/preflight.env:
#   PREFLIGHT_AUDIO=pulse|file   (file only when coverage is sufficient)
#   PREFLIGHT_VIDEO=live|file    (file only when the episode is fresh+valid)
#   PREFLIGHT_RTMP_OK=1|0        (TCP 1935 reachable within 5s; 0 = HARD stop)
#   PREFLIGHT_VERDICT=READY|DEGRADED
# Exit codes: 0 = stream may start (READY or DEGRADED), 1 = do not start.
# Small missing items (fonts) are fetched inline (KBs). The GB-scale audio
# download is NEVER started here: that belongs to `control.sh prepare` and
# first_boot, never to the streaming path (no background drain by design).
# ==============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

[ -f .env ] && { set -a; source .env 2>/dev/null; set +a; } || true
source "$BASE_DIR/scripts/hardware_profile.sh" 2>/dev/null || true
# Host facts (GPU presence etc.); fast and side-effect free
eval "$("$BASE_DIR/scripts/detect_host.sh")" 2>/dev/null || true

LOG_DIR="$BASE_DIR/logs"
RUNTIME="$BASE_DIR/runtime"
mkdir -p "$LOG_DIR" "$RUNTIME"
LOG="$LOG_DIR/preflight.log"
OUT="$RUNTIME/preflight.env"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [PREFLIGHT] $*" | tee -a "$LOG"
}

FAIL=0
WARN=0
AUDIO="pulse"
VIDEO="live"

# --- 1. Binaries ---------------------------------------------------------------
command -v ffmpeg >/dev/null 2>&1 || { log "HARD FAIL: ffmpeg missing (run scripts/install_deps.sh)."; FAIL=1; }
command -v node >/dev/null 2>&1 || { log "HARD FAIL: node missing (run scripts/install_deps.sh)."; FAIL=1; }
BROWSER_HIT=""
for cand in "${CHROME_BIN:-}" google-chrome chromium-browser chromium; do
  [ -z "$cand" ] && continue
  if command -v "$cand" >/dev/null 2>&1 || [ -x "$cand" ]; then BROWSER_HIT="$cand"; break; fi
done
if [ -z "$BROWSER_HIT" ]; then
  log "HARD FAIL: no chrome/chromium binary (run scripts/install_browser.sh)."; FAIL=1
else
  log "Browser: $BROWSER_HIT ($("$BROWSER_HIT" --version 2>/dev/null || echo version-unknown))."
fi
command -v Xvfb >/dev/null 2>&1 || { log "HARD FAIL: Xvfb missing (run scripts/install_deps.sh)."; FAIL=1; }

# --- 2. Stream keys --------------------------------------------------------------
if [ -z "${YOUTUBE_RTMP_URL:-}" ] || [ -z "${YOUTUBE_STREAM_KEY:-}" ]; then
  log "HARD FAIL: YOUTUBE_RTMP_URL / YOUTUBE_STREAM_KEY unset in .env."; FAIL=1
fi

# --- 3. Disk + memory floors (warn-only: swap/zram cover shortfalls) ------------
DISK_MB="$(df -kP . 2>/dev/null | awk 'NR==2{print int($4/1024)}' || true)"
case "$DISK_MB" in ''|*[!0-9]*) DISK_MB=0 ;; esac
[ "$DISK_MB" -lt 2048 ] && { log "WARN: only ${DISK_MB}MB free on / (want 2GB+)."; WARN=1; }
AVAIL_MB="$(free -m 2>/dev/null | awk '/^Mem:/{print $7}' || true)"
case "$AVAIL_MB" in ''|*[!0-9]*) AVAIL_MB=9999 ;; esac
[ "$AVAIL_MB" -lt 100 ] && { log "WARN: only ${AVAIL_MB}MB RAM available."; WARN=1; }

# --- 4. RTMP reachability (HARD: no route to ingest = no stream) ------------------
RTMP_HOST="$(echo "${YOUTUBE_RTMP_URL:-rtmp://a.rtmp.youtube.com/live2}" | sed 's|rtmp[s]*://||; s|/.*||')"
if [ -n "$RTMP_HOST" ] && command -v timeout >/dev/null 2>&1; then
  if timeout 5 bash -c "(echo > /dev/tcp/$RTMP_HOST/1935) 2>/dev/null"; then
    RTMP_OK=1
    log "RTMP $RTMP_HOST:1935 reachable."
  else
    RTMP_OK=0
    log "HARD FAIL: $RTMP_HOST:1935 unreachable (5s)."; FAIL=1
  fi
else
  RTMP_OK=1
  log "WARN: cannot test RTMP route (no timeout/bash-tcp), assuming reachable."; WARN=1
fi

# --- 5. Fonts: fetch inline when missing (KBs, seconds) ---------------------------
if [ ! -f "$BASE_DIR/web/assets/fonts/fonts.css" ]; then
  log "Fonts missing, fetching inline (small)..."
  if command -v node >/dev/null 2>&1 && node "$BASE_DIR/scripts/download_fonts.js" >>"$LOG" 2>&1; then
    log "Fonts ready."
  else
    log "WARN: font fetch failed, browser falls back to CDN/system fonts."; WARN=1
  fi
fi

# --- 6. Audio coverage decides the effective audio path ---------------------------
MP3_COUNT="$(find "$BASE_DIR/web/assets/audio" -maxdepth 1 -name '*.mp3' -size +1000c 2>/dev/null | wc -l)"
MP3_COUNT="$(echo "$MP3_COUNT" | tr -d ' ')"
case "$MP3_COUNT" in ''|*[!0-9]*) MP3_COUNT=0 ;; esac
if [ "${AUDIO_MODE:-pulse}" = "file" ]; then
  if [ "$MP3_COUNT" -ge 2000 ]; then
    AUDIO="file"
    log "Audio: file mode OK ($MP3_COUNT local mp3s)."
  else
    AUDIO="pulse"
    log "WARN: file audio requested but only $MP3_COUNT mp3s on disk -> pulse for this run (run control.sh prepare for full set)."; WARN=1
  fi
else
  log "Audio: pulse mode ($MP3_COUNT local mp3s cached)."
fi
# Silence guard: pulse path without pactl AND no usable local audio at all
# would broadcast dead air (anullsrc fallback). Refuse instead of going silent.
if [ "$AUDIO" = "pulse" ] && ! command -v pactl >/dev/null 2>&1 && [ "$MP3_COUNT" -eq 0 ]; then
  log "HARD FAIL: pulse audio requested but pactl missing and zero local mp3s (would stream silence). Install pulseaudio or run control.sh prepare."; FAIL=1
fi

# --- 7. Video source: always live capture (file-loop recording removed) -----------
VIDEO="live"
log "Video: live capture mode."

# --- 8. Port: free, or owned by a healthy web server -------------------------------
PORT="${QURAN_WEB_PORT:-4177}"
if (echo > /dev/tcp/127.0.0.1/$PORT) >/dev/null 2>&1; then
  if curl -s --max-time 5 "http://127.0.0.1:$PORT/api/health" 2>/dev/null | grep -q '"ok":true'; then
    log "Port $PORT: healthy web server already answering."
  else
    log "WARN: port $PORT busy but unhealthy; stop_ui will clear it at start."; WARN=1
  fi
else
  log "Port $PORT: free."
fi

# --- 9. Hardware encoder smoke test (3s null-output; decides HW offload) --------
# Detection (ffmpeg -encoders) is not proof: drivers/BIOS often break runtime.
# Only a passing smoke test sets PREFLIGHT_HW_OK. VAAPI additionally needs
# /dev/dri. NVENC is used automatically; VAAPI/QSV need HW_ALLOW_EXPERIMENTAL=1.
HW_OK=""
if command -v ffmpeg >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
  if [ "${HOST_HW_NVENC:-0}" = "1" ] || ffmpeg -hide_banner -encoders 2>/dev/null | grep -q ' h264_nvenc '; then
    if timeout 20 ffmpeg -hide_banner -loglevel error -nostdin -y \
      -f lavfi -i "nullsrc=s=320x240:r=10:d=2" \
      -c:v h264_nvenc -preset p1 -b:v 500k -f null - >>"$LOG" 2>&1; then
      HW_OK="nvenc"
      log "HW encoder verified: h264_nvenc (CPU encode will be offloaded)."
    fi
  fi
  if [ -z "$HW_OK" ] && ls /dev/dri/renderD* >/dev/null 2>&1; then
    if timeout 20 ffmpeg -hide_banner -loglevel error -nostdin -y -vaapi_device /dev/dri/renderD128 \
      -f lavfi -i "nullsrc=s=320x240:r=10:d=2" \
      -vf 'format=nv12,hwupload' -c:v h264_vaapi -b:v 500k -f null - >>"$LOG" 2>&1; then
      HW_OK="vaapi"
      log "HW encoder verified: h264_vaapi (used only with HW_ALLOW_EXPERIMENTAL=1)."
    fi
  fi
fi
[ -z "$HW_OK" ] && log "HW encode: none verified, CPU encode (x264)."

# --- Verdict -----------------------------------------------------------------------
VERDICT="READY"
[ "$WARN" = "1" ] && VERDICT="DEGRADED"
[ "$FAIL" = "1" ] && VERDICT="BLOCKED"
{
  echo "PREFLIGHT_AUDIO=$AUDIO"
  echo "PREFLIGHT_VIDEO=$VIDEO"
  echo "PREFLIGHT_RTMP_OK=${RTMP_OK:-0}"
  echo "PREFLIGHT_HW_OK=$HW_OK"
  echo "PREFLIGHT_VERDICT=$VERDICT"
  echo "PREFLIGHT_MP3=$MP3_COUNT"
  echo "PREFLIGHT_TS=$(date +%s)"
} > "$OUT"

if [ "$FAIL" = "1" ]; then
  log "VERDICT: HARD FAIL - not starting. Fix items above."
  exit 1
fi
log "VERDICT: $VERDICT (audio=$AUDIO video=$VIDEO). All inputs verified, ready to stream."
exit 0
