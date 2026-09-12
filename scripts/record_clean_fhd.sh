#!/bin/bash
# ==============================================================================
# Quran Live Broadcast — Clean FHD Preparation Recorder (NO streaming)
# Records the Quran stage FULLSCREEN (no right-side boxes via ?clean=1) in
# 1920x1080 to a file for later use. Runs on a SEPARATE display (:98), its own
# audio sink and chrome profile, so the live broadcast (:99) is untouched.
# Usage: record_clean_fhd.sh [minutes] [start_surah] [start_ayah]
#   e.g. record_clean_fhd.sh 120 36 1   # 2h starting at Ya-Sin
# =============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

MINUTES="${1:-60}"
Q_SURAH="${2:-}"
Q_AYAH="${3:-}"
W=1920
H=1080
FPS=15
DISP=98
SINK="quran_clean"

LOG_DIR="$BASE_DIR/logs"
RUNTIME="$BASE_DIR/runtime"
PREP_DIR="$BASE_DIR/episodes/prep"
PROF_DIR="$RUNTIME/chrome-clean"
mkdir -p "$LOG_DIR" "$RUNTIME" "$PREP_DIR" "$PROF_DIR"
LOG="$LOG_DIR/record_clean_fhd.log"
XVFB_PID="$RUNTIME/clean-xvfb.pid"
CHROME_PID="$RUNTIME/clean-chrome.pid"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CLEAN-FHD] $*" | tee -a "$LOG"
}

cleanup() {
  for p in "$CHROME_PID" "$XVFB_PID"; do
    if [ -f "$p" ]; then
      kill -9 "$(cat "$p" 2>/dev/null)" 2>/dev/null || true
      rm -f "$p"
    fi
  done
  pkill -9 -f "chrome-clean" 2>/dev/null || true
}

# --- Safety guards: FHD encode + 2nd chrome is heavy; never OOM the live box
LOAD1="$(awk '{print int($1)}' /proc/loadavg)"
SWAP_FREE_KB="$(awk '/SwapFree/{print $2}' /proc/meminfo)"
DISK_AVAIL_KB="$(df -k "$PREP_DIR" | awk 'NR==2{print $4}')"
NEED_KB=$((MINUTES * 40000 + 2000000))
if [ "$LOAD1" -ge 10 ]; then
  log "ABORT: load too high (${LOAD1}), try at night."
  exit 2
fi
if [ "$SWAP_FREE_KB" -lt 700000 ]; then
  log "ABORT: swap free too low ($((SWAP_FREE_KB / 1024))MB), restart stream first."
  exit 2
fi
if [ "$DISK_AVAIL_KB" -lt "$NEED_KB" ]; then
  log "ABORT: disk free too low ($((DISK_AVAIL_KB / 1024 / 1024))GB), need ~$((NEED_KB / 1024 / 1024))GB."
  exit 2
fi

STAMP="$(date '+%Y-%m-%d_%H%M')"
TMP_OUT="$PREP_DIR/clean-fhd-${STAMP}.tmp.mp4"
FINAL_OUT="$PREP_DIR/clean-fhd-${STAMP}.mp4"
log "=== Clean FHD ${W}x${H} recording ${MINUTES} min -> $(basename "$FINAL_OUT") ==="

trap cleanup EXIT INT TERM

# 1. Own virtual display
if ! kill -0 "$(cat "$XVFB_PID" 2>/dev/null)" 2>/dev/null; then
  Xvfb ":$DISP" -screen 0 "${W}x${H}x24" -nolisten tcp >"$LOG_DIR/clean-xvfb.log" 2>&1 & echo $! >"$XVFB_PID"
  sleep 2
fi

# 2. Own audio sink (isolated from the live quran_sink)
if command -v pactl >/dev/null 2>&1; then
  pactl load-module module-null-sink sink_name="$SINK" sink_properties=device.description="QuranClean" >/dev/null 2>&1 || true
  sleep 1
fi

# 3. Own chrome (own profile => own saved position; ?clean=1 hides side panel)
BROWSER_BIN="$(command -v google-chrome || command -v chromium-browser || command -v chromium || echo "chromium")"
URL="http://127.0.0.1:${QURAN_WEB_PORT:-4177}/?clean=1"
[ -n "$Q_SURAH" ] && URL="$URL&surah=$Q_SURAH"
[ -n "$Q_AYAH" ] && URL="$URL&ayah=$Q_AYAH"
if ! kill -0 "$(cat "$CHROME_PID" 2>/dev/null)" 2>/dev/null; then
  DISPLAY=":$DISP" PULSE_SINK="$SINK" "$BROWSER_BIN" \
    --no-sandbox --disable-gpu --disable-dev-shm-usage --disable-software-rasterizer \
    --renderer-process-limit=1 --disable-extensions --disable-background-networking \
    --disable-sync --disable-default-apps --no-first-run --no-default-browser-check \
    --hide-crash-restore-bubble --disable-features=Translate,TranslateUI \
    --autoplay-policy=no-user-gesture-required --allow-running-insecure-content \
    --disable-component-update --user-data-dir="$PROF_DIR" \
    --window-size="${W},${H}" --js-flags="--max-old-space-size=220" \
    --app="$URL" >"$LOG_DIR/clean-chromium.log" 2>&1 & echo $! >"$CHROME_PID"
  sleep 8
fi

# 4. Record (file only, no RTMP)
AUDIO_ARGS=(-thread_queue_size 2048 -f pulse -i "$SINK.monitor")
if ! pactl list short sources 2>/dev/null | grep -q "$SINK.monitor"; then
  AUDIO_ARGS=(-thread_queue_size 1024 -f lavfi -i "anullsrc=r=44100:cl=stereo")
fi

timeout "$((MINUTES * 60 + 180))" ffmpeg -hide_banner -loglevel warning -nostdin \
  -f x11grab -framerate "$FPS" -video_size "${W}x${H}" -draw_mouse 0 -use_shm 1 -thread_queue_size 64 -probesize 32k -analyzeduration 0 -i ":$DISP.0" \
  "${AUDIO_ARGS[@]}" \
  -map 0:v:0 -map 1:a:0 \
  -vf "format=yuv420p" \
  -c:v libx264 -preset ultrafast -tune zerolatency -threads 2 \
  -b:v 4200k -maxrate 4800k -bufsize 8400k \
  -g 30 -keyint_min 30 -sc_threshold 0 -r "$FPS" -fps_mode cfr \
  -c:a aac -aac_coder fast -b:a 128k -ar 44100 -ac 2 -af "aresample=44100:async=1:first_pts=0" \
  -movflags +faststart -t "$((MINUTES * 60))" \
  "$TMP_OUT" 2>&1 | tee -a "$LOG" || true

# 5. Validate: FHD dimensions + duration + size
VW="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$TMP_OUT" 2>/dev/null || echo 0)"
DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TMP_OUT" 2>/dev/null || echo 0)"
DUR_INT="${DUR%.*}"
SIZE="$(stat -c%s "$TMP_OUT" 2>/dev/null || echo 0)"
NEED="$((MINUTES * 60 * 90 / 100))"
if [ "$VW" != "1920" ] || [ "${DUR_INT:-0}" -lt "$NEED" ] || [ "$SIZE" -lt 20000000 ]; then
  log "ERROR: invalid output (width=$VW dur=${DUR_INT}s size=$SIZE), discarding."
  rm -f "$TMP_OUT"
  exit 1
fi

mv "$TMP_OUT" "$FINAL_OUT"
log "DONE: $(basename "$FINAL_OUT") (${DUR_INT}s, $((SIZE / 1024 / 1024))MB). Live broadcast untouched."
