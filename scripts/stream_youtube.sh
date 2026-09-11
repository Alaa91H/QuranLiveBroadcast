#!/bin/bash
# ==============================================================================
# Quran Live Broadcast — YouTube 24/7 Adaptive Live Streamer
# Automatically scales from 720p HD up to 8K based on host hardware capabilities.
# ==============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

[ -f .env ] && { set -a; source .env; set +a; }
[ -f config/stream.conf ] && source config/stream.conf
source "$BASE_DIR/scripts/hardware_profile.sh"

LOG_DIR="$BASE_DIR/logs"
RUNTIME="$BASE_DIR/runtime"
mkdir -p "$LOG_DIR" "$RUNTIME"
LOG="$LOG_DIR/stream_youtube.log"

DISPLAY_NUM="${QURAN_DISPLAY:-99}"

if [[ -z "${YOUTUBE_RTMP_URL:-}" || -z "${YOUTUBE_STREAM_KEY:-}" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: YOUTUBE_RTMP_URL or YOUTUBE_STREAM_KEY not configured in .env" | tee -a "$LOG"
  exit 1
fi

RTMP_TARGET="${YOUTUBE_RTMP_URL}/${YOUTUBE_STREAM_KEY}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Launching Quran UI environment with profile: $PROFILE_NAME..."
"$BASE_DIR/scripts/broadcast_ui.sh" >>"$LOG" 2>&1
trap '"$BASE_DIR/scripts/stop_ui.sh" >/dev/null 2>&1 || true' EXIT INT TERM

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting YouTube 24/7 stream: ${STREAM_WIDTH}x${STREAM_HEIGHT} @ ${STREAM_FPS}fps (${VIDEO_BITRATE})..." | tee -a "$LOG"

while true; do
  # Determine audio input source: prefer synchronized PulseAudio virtual sink
  AUDIO_INPUT_ARGS=(-thread_queue_size 1024 -f pulse -i "quran_sink.monitor")
  if ! command -v pactl >/dev/null 2>&1 || ! pactl list short sources 2>/dev/null | grep -q "quran_sink.monitor"; then
    # Fallback to local audio loop or anullsrc if virtual sink is unavailable
    if [ -f "$RUNTIME/audio_playlist.txt" ] && [ -s "$RUNTIME/audio_playlist.txt" ]; then
      AUDIO_INPUT_ARGS=(-thread_queue_size 1024 -re -stream_loop -1 -f concat -safe 0 -i "$RUNTIME/audio_playlist.txt")
    else
      AUDIO_INPUT_ARGS=(-thread_queue_size 1024 -f lavfi -i "anullsrc=r=${AUDIO_SAMPLERATE}:cl=stereo")
    fi
  fi

  ffmpeg -hide_banner -loglevel warning -nostdin \
    -thread_queue_size 1024 -f x11grab -draw_mouse 0 -framerate "$STREAM_FPS" -video_size "${STREAM_WIDTH}x${STREAM_HEIGHT}" -i ":$DISPLAY_NUM.0" \
    "${AUDIO_INPUT_ARGS[@]}" \
    -map 0:v:0 -map 1:a:0 \
    -vf "format=yuv420p" \
    -c:v "$VCODEC" -preset "$FFMPEG_PRESET" -tune "$FFMPEG_TUNE" -threads "$FFMPEG_THREADS" \
    -b:v "$VIDEO_BITRATE" -maxrate "$MAX_BITRATE" -bufsize "$BUF_SIZE" \
    -g "$((STREAM_FPS * 2))" -keyint_min "$STREAM_FPS" -r "$STREAM_FPS" \
    -c:a aac -b:a "$AUDIO_BITRATE" -ar "$AUDIO_SAMPLERATE" -ac 2 \
    -flvflags no_duration_filesize \
    -f flv "$RTMP_TARGET" 2>&1 | tee -a "$LOG"

  EXIT_CODE=$?
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stream exited with code $EXIT_CODE. Restarting in 3 seconds..." | tee -a "$LOG"
  sleep 3
done
