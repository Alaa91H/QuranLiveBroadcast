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

# 0. First-run static primer (fonts/audio/backgrounds, marker-gated, detached):
# downloads everything static once so runtime serves from disk; dynamic data
# (clock/prayer/weather) keeps fetching live and is never primed.
if [ "${PRIME_STATIC:-1}" != "0" ]; then
  nohup "$BASE_DIR/scripts/prime_static_cache.sh" >>"$LOG_DIR/prime_static.log" 2>&1 &
  disown 2>/dev/null || true
fi

# 1. Setup Virtual Audio Sink (PulseAudio) for synchronized audio capture.
# Skipped entirely in file-audio mode: nothing reads the sink, so PulseAudio
# stays out of the audio path (browser is muted, ffmpeg uses mp3 files).
setup_audio_sink() {
  if [ "${AUDIO_MODE:-pulse}" = "file" ]; then
    return 0
  fi
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

# 4. Start Browser (Chromium) on a strict low-memory diet.
# In file-audio mode the page is video-only: --mute-audio skips decode output
# (playback/timing continue, so ayah sync is preserved) and no PULSE_SINK is
# exported, keeping PulseAudio out of the loop.
start_browser() {
  # Restart chrome when the audio-mode flag changes (pid alive but stale mode)
  local want_sig="audio=${AUDIO_MODE:-pulse}"
  if kill -0 "$(cat "$CHROME_PIDFILE" 2>/dev/null)" 2>/dev/null; then
    if [ "$(cat "$RUNTIME/chrome-audio.sig" 2>/dev/null)" != "$want_sig" ]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Audio mode changed, restarting Browser ($want_sig)..."
      kill -9 "$(cat "$CHROME_PIDFILE")" 2>/dev/null || true
      rm -f "$CHROME_PIDFILE" "$RUNTIME/chrome-audio.sig"
      sleep 1
    fi
  fi
  if ! kill -0 "$(cat "$CHROME_PIDFILE" 2>/dev/null)" 2>/dev/null; then
    local BROWSER_BIN
    BROWSER_BIN="$(command -v google-chrome || command -v chromium-browser || command -v chromium || echo "chromium")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Browser ($BROWSER_BIN, ${STREAM_WIDTH}x${STREAM_HEIGHT}, memory cap ${CHROME_MEM_MB}MB, audio: ${AUDIO_MODE:-pulse})..."
    local CHROME_AUDIO_FLAGS=()
    local CHROME_SINK_ENV=""
    if [ "${AUDIO_MODE:-pulse}" = "file" ]; then
      CHROME_AUDIO_FLAGS=(--mute-audio)
    else
      CHROME_SINK_ENV="PULSE_SINK=quran_sink"
    fi
    # shellcheck disable=SC2086
    DISPLAY=":$DISPLAY_NUM" $CHROME_SINK_ENV "$BROWSER_BIN" \
      --no-sandbox \
      --disable-gpu \
      --disable-dev-shm-usage \
      --disable-software-rasterizer \
      --renderer-process-limit=1 \
      --disable-extensions \
      --disable-background-networking \
      --disable-sync \
      --disable-default-apps \
      --no-first-run \
      --no-default-browser-check \
      --hide-crash-restore-bubble \
      --disable-features=Translate,TranslateUI,MediaRouter,OptimizationHints \
      --disable-component-update \
      --disable-component-extensions-with-background-pages \
      --disable-background-timer-throttling \
      --disable-renderer-backgrounding \
      --disable-backgrounding-occluded-windows \
      --disable-application-cache \
      --aggressive-cache-discard \
      --disk-cache-size=1048576 \
      --media-cache-size=1048576 \
      --autoplay-policy=no-user-gesture-required \
      --allow-running-insecure-content \
      --kiosk \
      --window-size="${STREAM_WIDTH},${STREAM_HEIGHT}" \
      --js-flags="--max-old-space-size=${CHROME_MEM_MB}" \
      "${CHROME_AUDIO_FLAGS[@]}" \
      --app="http://127.0.0.1:$PORT/" >"$LOG_DIR/chromium.log" 2>&1 & echo $! >"$CHROME_PIDFILE"
    echo "$want_sig" >"$RUNTIME/chrome-audio.sig"
    sleep 3
  fi
}

setup_audio_sink
start_web
start_x
start_browser

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Quran UI ready on DISPLAY=:$DISPLAY_NUM, http://127.0.0.1:$PORT/ (Profile: $PROFILE_NAME)"
