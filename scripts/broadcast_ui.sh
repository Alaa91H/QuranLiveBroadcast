#!/bin/bash
# ==============================================================================
# Quran Live Broadcast — Headless UI & Virtual Display Launcher
# ==============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$BASE_DIR/scripts/hardware_profile.sh"

PORT="${QURAN_WEB_PORT:-4177}"
DISPLAY_NUM="${QURAN_DISPLAY:-99}"
LOG_DIR="$BASE_DIR/logs"
RUNTIME="$BASE_DIR/runtime"
mkdir -p "$LOG_DIR" "$RUNTIME"

PIDFILE="$RUNTIME/quran-web.pid"
XVFB_PIDFILE="$RUNTIME/quran-xvfb.pid"
CHROME_PIDFILE="$RUNTIME/quran-chrome.pid"

# 1. Setup Virtual Audio Sink (PulseAudio) for synchronized audio capture
setup_audio_sink() {
  if command -v pactl >/dev/null 2>&1; then
    pactl load-module module-null-sink sink_name=quran_sink sink_properties=device.description="QuranSink" >/dev/null 2>&1 || true
  fi
}

# 2. Start Web Server with adaptive Node memory bounds
start_web() {
  if ! kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Quran Web Server on port $PORT (Node max-old-space: ${NODE_MEM_MB}MB)..."
    (cd "$BASE_DIR/web" && PORT="$PORT" node --max-old-space-size="${NODE_MEM_MB}" server.js >>"$LOG_DIR/web.log" 2>&1 & echo $! >"$PIDFILE")
    sleep 1
  fi
}

# 3. Start Virtual X Server (Xvfb) with dynamic resolution
start_x() {
  if ! kill -0 "$(cat "$XVFB_PIDFILE" 2>/dev/null)" 2>/dev/null; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Xvfb on :$DISPLAY_NUM (${STREAM_WIDTH}x${STREAM_HEIGHT}x24)..."
    Xvfb ":$DISPLAY_NUM" -screen 0 "${STREAM_WIDTH}x${STREAM_HEIGHT}x24" -nolisten tcp >"$LOG_DIR/xvfb.log" 2>&1 & echo $! >"$XVFB_PIDFILE"
    sleep 1
  fi
}

# 4. Start Browser (Chromium) optimized for low memory and unmuted autoplay
start_browser() {
  if ! kill -0 "$(cat "$CHROME_PIDFILE" 2>/dev/null)" 2>/dev/null; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Chromium (${STREAM_WIDTH}x${STREAM_HEIGHT}, memory cap ${CHROME_MEM_MB}MB)..."
    DISPLAY=":$DISPLAY_NUM" PULSE_SINK=quran_sink chromium \
      --no-sandbox \
      --disable-gpu \
      --disable-dev-shm-usage \
      --disable-software-rasterizer \
      --single-process \
      --disable-extensions \
      --disable-background-networking \
      --disable-sync \
      --disable-default-apps \
      --kiosk \
      --window-size="${STREAM_WIDTH},${STREAM_HEIGHT}" \
      --autoplay-policy=no-user-gesture-required \
      --js-flags="--max-old-space-size=${CHROME_MEM_MB}" \
      --app="http://127.0.0.1:$PORT/" >"$LOG_DIR/chromium.log" 2>&1 & echo $! >"$CHROME_PIDFILE"
    sleep 3
  fi
}

setup_audio_sink
start_web
start_x
start_browser

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Quran UI ready on DISPLAY=:$DISPLAY_NUM, http://127.0.0.1:$PORT/ (Profile: $PROFILE_NAME)"
