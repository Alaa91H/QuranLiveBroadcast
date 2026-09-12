#!/bin/bash
# ==============================================================================
# Quran Live Broadcast — Daily Episode Recorder
# Records the live UI (synced ayahs + prayer times + weather) to a video file.
# Records one 2h slice of the 24/7 playback. Slices accumulate over nights
# (each night captures DIFFERENT recitation because playback advances 24/7)
# and build_loop.sh concatenates them into the 24h loop.
# Usage: record_episode.sh [minutes]   (default: 120)
# ==============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

[ -f .env ] && { set -a; source .env; set +a; }
[ -f config/stream.conf ] && source config/stream.conf
source "$BASE_DIR/scripts/hardware_profile.sh"

MINUTES="${1:-120}"
LOG_DIR="$BASE_DIR/logs"
RUNTIME="$BASE_DIR/runtime"
EP_DIR="$BASE_DIR/episodes"
mkdir -p "$LOG_DIR" "$RUNTIME" "$EP_DIR"
LOG="$LOG_DIR/record_episode.log"
FLAG="$RUNTIME/record_active.flag"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [RECORD] $*" | tee -a "$LOG"
}

# Single-instance guard (cron + manual runs must never overlap)
exec 9>"$RUNTIME/record_episode.lock"
flock -n 9 || { log "Another recording is already running, exiting."; exit 0; }

touch "$FLAG"
trap 'rm -f "$FLAG"' EXIT INT TERM

DISPLAY_NUM="${QURAN_DISPLAY:-99}"
STAMP="$(date '+%Y-%m-%d_%H%M')"
TMP_OUT="$EP_DIR/seg-${STAMP}.tmp.mp4"
FINAL_OUT="$EP_DIR/seg-${STAMP}.mp4"

log "=== Recording ${MINUTES} min episode to $(basename "$FINAL_OUT") ==="

# 1. Ensure UI stack is up (needed as capture source in any stream mode)
"$BASE_DIR/scripts/broadcast_ui.sh" >>"$LOG" 2>&1 || true

# 2. Wait for web health + pulse sink (up to 60s)
for i in $(seq 1 60); do
  if curl -s --max-time 2 "http://127.0.0.1:${QURAN_WEB_PORT:-4177}/api/health" 2>/dev/null | grep -q '"ok":true'; then
    break
  fi
  sleep 1
done
if command -v pactl >/dev/null 2>&1; then
  for i in $(seq 1 30); do
    pactl list short sources 2>/dev/null | grep -q "quran_sink.monitor" && break
    sleep 1
  done
fi

# 3. Record (same quality as live stream so the file can be `-c copy` streamed)
AUDIO_ARGS=(-thread_queue_size 2048 -f pulse -i "quran_sink.monitor")
if ! command -v pactl >/dev/null 2>&1 || ! pactl list short sources 2>/dev/null | grep -q "quran_sink.monitor"; then
  AUDIO_ARGS=(-thread_queue_size 1024 -f lavfi -i "anullsrc=r=${AUDIO_SAMPLERATE}:cl=stereo")
fi

timeout "$((MINUTES * 60 + 120))" ffmpeg -hide_banner -loglevel warning -nostdin \
  -use_wallclock_as_timestamps 1 -thread_queue_size 1024 -f x11grab -draw_mouse 0 -framerate "$STREAM_FPS" -video_size "${STREAM_WIDTH}x${STREAM_HEIGHT}" -i ":$DISPLAY_NUM.0" \
  "${AUDIO_ARGS[@]}" \
  -map 0:v:0 -map 1:a:0 \
  -vf "format=yuv420p" \
  -c:v "$VCODEC" -preset "$FFMPEG_PRESET" -tune "$FFMPEG_TUNE" -threads "$FFMPEG_THREADS" \
  -b:v "$VIDEO_BITRATE" -maxrate "$MAX_BITRATE" -bufsize "$BUF_SIZE" \
  -g "$((STREAM_FPS * 2))" -keyint_min "$STREAM_FPS" -r "$STREAM_FPS" \
  -c:a aac -b:a "$AUDIO_BITRATE" -ar "$AUDIO_SAMPLERATE" -ac 2 -af "aresample=${AUDIO_SAMPLERATE}:async=1:first_pts=0" \
  -movflags +faststart -t "$((MINUTES * 60))" \
  "$TMP_OUT" 2>&1 | tee -a "$LOG" || true

# 4. Validate: size + playable duration >= 90% requested
MIN_BYTES=50000000
if [ ! -f "$TMP_OUT" ] || [ "$(stat -c%s "$TMP_OUT" 2>/dev/null || echo 0)" -lt "$MIN_BYTES" ]; then
  log "ERROR: recording too small or missing, discarding."
  rm -f "$TMP_OUT"
  exit 1
fi
DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TMP_OUT" 2>/dev/null || echo 0)"
DUR_INT="${DUR%.*}"
NEED="$((MINUTES * 60 * 90 / 100))"
if [ "${DUR_INT:-0}" -lt "$NEED" ]; then
  log "ERROR: recording too short (${DUR_INT}s < ${NEED}s), discarding."
  rm -f "$TMP_OUT"
  exit 1
fi

mv "$TMP_OUT" "$FINAL_OUT"

# Keep the 14 newest slices (~15GB max at 1200k); build_loop.sh assembles
# the 24h loop from them. current.mp4 is managed by build_loop.sh only.
ls -t "$EP_DIR"/seg-*.mp4 2>/dev/null | tail -n +15 | xargs -r rm -f
log "Slice ready: $(basename "$FINAL_OUT") (${DUR_INT}s). Run build_loop.sh to extend the 24h loop."
