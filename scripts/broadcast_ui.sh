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

# 0. Light static primer (SYNCHRONOUS, seconds): fonts + backgrounds only.
# Policy: nothing bulk downloads while the broadcast runs. The GB-scale audio
# fetch belongs to `control.sh prepare` / first_boot, never to the hot path.
if [ "${PRIME_STATIC:-1}" != "0" ]; then
  "$BASE_DIR/scripts/prime_static_cache.sh" --light-only >>"$LOG_DIR/prime_static.log" 2>&1 || true
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
    # File-audio mode: page is video-only. --mute-audio keeps the media
    # timeline (ayah sync preserved); --disable-audio-output lets the audio
    # service idle instead of opening a (muted) output stream.
    local CHROME_AUDIO_FLAGS=()
    local CHROME_SINK_ENV=""
    if [ "${AUDIO_MODE:-pulse}" = "file" ]; then
      CHROME_AUDIO_FLAGS=(--mute-audio --disable-audio-output)
    else
      CHROME_SINK_ENV="PULSE_SINK=quran_sink"
    fi
    # Micro profile: calm the page itself (?lowfx=1 kills decorative
    # animations, ?cities=N shrinks the rotating city DOM).
    local APP_QUERY=""
    if [ "${PROFILE:-}" = "micro" ]; then
      APP_QUERY="?lowfx=1&cities=3"
    fi
    # NOTE: --disable-software-rasterizer is deliberately NOT used: with
    # --disable-gpu on Xvfb, software raster is the only paint path and
    # disabling it blanks or destabilizes capture on Chrome 120+.
    # NOTE: --single-process/--no-zygote are deliberately NOT used: they save
    # RAM but one renderer crash kills the whole 24/7 browser.
    # shellcheck disable=SC2086
    # CPU pinning (empty array = disabled; bash>=4.4 safe with set -u)
    local TASKSET_PRE=()
    if [ -n "${TASKSET_CHROME:-}" ] && command -v taskset >/dev/null 2>&1; then
      TASKSET_PRE=(taskset -c "$TASKSET_CHROME")
    fi
    DISPLAY=":$DISPLAY_NUM" $CHROME_SINK_ENV "${TASKSET_PRE[@]}" "$BROWSER_BIN" \
      --no-sandbox \
      --disable-gpu \
      --in-process-gpu \
      --enable-low-end-device-mode \
      --disable-dev-shm-usage \
      --renderer-process-limit=1 \
      --disable-extensions \
      --disable-background-networking \
      --disable-sync \
      --disable-default-apps \
      --no-first-run \
      --no-default-browser-check \
      --hide-crash-restore-bubble \
      --noerrdialogs \
      --disable-logging --log-level=3 \
      --disable-crash-reporter --no-crash-upload \
      --disable-breakpad \
      --disable-hang-monitor --disable-gpu-watchdog \
      --disable-client-side-phishing-detection --disable-domain-reliability --no-pings \
      --disable-notifications --block-new-web-contents --deny-permission-prompts \
      --disable-features=Translate,TranslateUI,MediaRouter,DialMediaRouteProvider,OptimizationHints,InterestFeedContentSuggestions,PrivacySandboxSettings4,AutofillServerCommunication,CertificateTransparencyComponentUpdater,GlobalMediaControls,HeavyAdPrivacyMitigations,CalculateNativeWinOcclusion,DestroyProfileOnBrowserClose,PaintHolding \
      --disable-component-update \
      --disable-component-extensions-with-background-pages \
      --disable-background-timer-throttling \
      --disable-renderer-backgrounding \
      --disable-backgrounding-occluded-windows \
      --aggressive-cache-discard \
      --disk-cache-size=1048576 \
      --media-cache-size=1048576 \
      --password-store=basic \
      --force-color-profile=srgb \
      --disable-lcd-text \
      --hide-scrollbars \
      --disable-smooth-scrolling \
      --autoplay-policy=no-user-gesture-required \
      --allow-running-insecure-content \
      --kiosk \
      --window-size="${STREAM_WIDTH},${STREAM_HEIGHT}" \
      --window-position=0,0 \
      --js-flags="--max-old-space-size=${CHROME_MEM_MB} --optimize-for-size" \
      "${CHROME_AUDIO_FLAGS[@]}" \
      --app="http://127.0.0.1:$PORT/$APP_QUERY" >"$LOG_DIR/chromium.log" 2>&1 & echo $! >"$CHROME_PIDFILE"
    echo "$want_sig" >"$RUNTIME/chrome-audio.sig"
    sleep 3
  fi
}

setup_audio_sink
start_web
start_x
start_browser

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Quran UI ready on DISPLAY=:$DISPLAY_NUM, http://127.0.0.1:$PORT/ (Profile: $PROFILE_NAME)"
