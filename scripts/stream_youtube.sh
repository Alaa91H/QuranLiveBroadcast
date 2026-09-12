#!/bin/bash
# ==============================================================================
# Quran Live Stream — YouTube 24/7 Adaptive Live Streamer
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

# Egress guard (soft-fail): when probe_egress.sh measured usable upload, clamp
# total bitrate to 90% of the 24/7-safe ceiling instead of stuttering into a
# congested uplink. Disabled by clearing runtime/net.env or EGRESS_GUARD=0.
to_kbit() {
  case "$1" in
    *[kK]) echo "${1%[kK]}" ;;
    *[mM]) echo "$((${1%[mM]} * 1000))" ;;
    ''|*[!0-9]*) echo 0 ;;
    *) echo "$1" ;;
  esac
}
if [ "${EGRESS_GUARD:-1}" = "1" ] && [ -f "$RUNTIME/net.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$RUNTIME/net.env" 2>/dev/null || true
  set +a
  SAFE_KBIT="$(awk "BEGIN{printf \"%.0f\", (${HOST_EGRESS_SAFE_MBPS:-0})*1000*0.9}")"
  NEED_KBIT="$(($(to_kbit "$VIDEO_BITRATE") + $(to_kbit "$AUDIO_BITRATE")))"
  if [ "$SAFE_KBIT" -gt 700 ] && [ "$NEED_KBIT" -gt "$SAFE_KBIT" ]; then
    NEW_VIDEO_KBIT="$((SAFE_KBIT - $(to_kbit "$AUDIO_BITRATE")))"
    [ "$NEW_VIDEO_KBIT" -lt 400 ] && NEW_VIDEO_KBIT=400
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] EGRESS: uplink safe ${SAFE_KBIT}kbit < needed ${NEED_KBIT}kbit, clamping video ${VIDEO_BITRATE} -> ${NEW_VIDEO_KBIT}k..." | tee -a "$LOG"
    VIDEO_BITRATE="${NEW_VIDEO_KBIT}k"
    MAX_BITRATE="$VIDEO_BITRATE"
  fi
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Preflight: verifying all inputs before starting..."
if ! "$BASE_DIR/scripts/preflight.sh" 2>&1 | tee -a "$LOG"; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Preflight HARD FAIL: refusing to start a broken stream. Fix items above." | tee -a "$LOG"
  exit 1
fi
set -a
# shellcheck disable=SC1091
source "$RUNTIME/preflight.env" 2>/dev/null || true
set +a
# Effective decisions for THIS run (preflight verdict wins over config).
# Live-only broadcast: no file loop, no local archive (removed by design).
EFF_AUDIO="${PREFLIGHT_AUDIO:-${AUDIO_MODE:-pulse}}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Effective run: live video, audio=$EFF_AUDIO profile=$PROFILE_NAME" | tee -a "$LOG"

# Hardware encoder: preflight-verified NVENC (3s smoke test) replaces libx264
# with identical res/fps/bitrate (preset p4, low-latency CBR). VAAPI/QSV stay
# CPU-gated behind HW_ALLOW_EXPERIMENTAL=1 (x11grab color/filter chains need
# staging per box). Fallback is automatic: any failure clears HW_OK for next run.
HW_OK=0
if [ "${PREFLIGHT_HW_OK:-}" = "nvenc" ]; then
  HW_OK=1
  VCODEC="h264_nvenc"
  FFMPEG_PRESET="p4"
  FFMPEG_TUNE="ll"
  X264_PARAMS=""
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] HW encode: h264_nvenc (verified), CPU encode offloaded." | tee -a "$LOG"
elif [ "${PREFLIGHT_HW_OK:-}" = "vaapi" ] && [ "${HW_ALLOW_EXPERIMENTAL:-0}" = "1" ]; then
  HW_OK=2
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] HW encode: h264_vaapi (experimental, enabled)." | tee -a "$LOG"
fi

# Encoder command assembly (arrays keep one command shape for all paths)
VAAPI_PRE=()
VAAPI_VF="format=yuv420p"
VCODEC_ARGS=(-c:v "$VCODEC" -preset "$FFMPEG_PRESET" -tune "$FFMPEG_TUNE" -threads "$FFMPEG_THREADS")
if [ -n "${X264_PARAMS:-}" ] && [ "$HW_OK" = "0" ]; then
  VCODEC_ARGS+=(-x264-params "$X264_PARAMS")
fi
if [ "$HW_OK" = "1" ]; then
  # NVENC: same res/fps/bitrate, near-zero CPU (preset p4, low-latency CBR)
  VCODEC_ARGS=(-c:v h264_nvenc -preset p4 -tune ll -rc cbr)
elif [ "$HW_OK" = "2" ]; then
  # VAAPI x11grab chain (needs /dev/dri + drivers; preflight smoke-tested)
  VAAPI_PRE=(-vaapi_device /dev/dri/renderD128)
  VAAPI_VF="format=nv12,hwupload"
  VCODEC_ARGS=(-c:v h264_vaapi -bf 2)
fi
# ffmpeg-version compat (Ubuntu 22.04 ships 4.4 without these): probe once.
FPSMODE_ARGS=(-fps_mode cfr)
ffmpeg -hide_banner -h full 2>/dev/null | grep -q -- '-fps_mode' || FPSMODE_ARGS=(-vsync cfr)
AACENC_ARGS=(-c:a aac -aac_coder fast)
ffmpeg -hide_banner -h encoder=aac 2>/dev/null | grep -q 'aac_coder' || AACENC_ARGS=(-c:a aac)
# Output: single RTMP publish (live-only; archive/file-loop removed by design).
MAP_ARGS=(-map 0:v:0 -map 1:a:0)
OUT_ARGS=(-rw_timeout 10000000 -f flv "$RTMP_TARGET")
# CPU pinning (empty array = disabled; bash>=4.4 safe with set -u)
TASKSET_PRE=()
if [ -n "${TASKSET_FFMPEG:-}" ] && command -v taskset >/dev/null 2>&1; then
  TASKSET_PRE=(taskset -c "$TASKSET_FFMPEG")
fi
GOP="$((STREAM_FPS * 2))"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Launching Quran UI environment with profile: $PROFILE_NAME..."
"$BASE_DIR/scripts/broadcast_ui.sh" >>"$LOG" 2>&1
trap '"$BASE_DIR/scripts/stop_ui.sh" >/dev/null 2>&1 || true' EXIT INT TERM

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting YouTube 24/7 stream: ${STREAM_WIDTH}x${STREAM_HEIGHT} @ ${STREAM_FPS}fps (${VIDEO_BITRATE}, audio: ${EFF_AUDIO}, hw: ${HW_OK})..." | tee -a "$LOG"

# Extra 1-CPU x264 tuning (micro profile; empty elsewhere = preset defaults)
X264_ARGS=()
if [ -n "${X264_PARAMS:-}" ]; then
  X264_ARGS=(-x264-params "$X264_PARAMS")
fi

while true; do
  # Effective audio path for THIS run (preflight verdict wins over config):
  # 1) "file": concat of local recitation mp3s, same surah 1..114 order the UI
  #    plays, so display stays in sync (tiny drift possible; daily restart
  #    resyncs). Browser is muted; no pulse sink is created or read.
  # 2) "pulse": capture the browser via the quran_sink.monitor (default).
  if [ "$EFF_AUDIO" = "file" ]; then
    "$BASE_DIR/scripts/build_audio_playlist.sh" >>"$LOG" 2>&1 || true
    if [ -f "$RUNTIME/audio_playlist.txt" ] && [ -s "$RUNTIME/audio_playlist.txt" ]; then
      AUDIO_INPUT_ARGS=(-re -stream_loop -1 -f concat -safe 0 -probesize 50k -analyzeduration 0 -thread_queue_size 64 -fflags +genpts -i "$RUNTIME/audio_playlist.txt")
    else
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: no local recitation audio yet, falling back to PulseAudio for this cycle..." | tee -a "$LOG"
      AUDIO_INPUT_ARGS=(-thread_queue_size 128 -f pulse -i "quran_sink.monitor")
    fi
  else
    AUDIO_INPUT_ARGS=(-thread_queue_size 128 -f pulse -i "quran_sink.monitor")
    if ! command -v pactl >/dev/null 2>&1 || ! pactl list short sources 2>/dev/null | grep -q "quran_sink.monitor"; then
      # Fallback to local audio loop or anullsrc if virtual sink is unavailable
      if [ -f "$RUNTIME/audio_playlist.txt" ] && [ -s "$RUNTIME/audio_playlist.txt" ]; then
        AUDIO_INPUT_ARGS=(-re -stream_loop -1 -f concat -safe 0 -probesize 50k -analyzeduration 0 -thread_queue_size 64 -fflags +genpts -i "$RUNTIME/audio_playlist.txt")
      else
        AUDIO_INPUT_ARGS=(-thread_queue_size 64 -f lavfi -i "anullsrc=r=${AUDIO_SAMPLERATE}:cl=stereo")
      fi
    fi
  fi

  # Fixed 2s GOP (YouTube-friendly, no I-frame spikes). -fps_mode cfr keeps
  # exact CFR without the duplicate frames -use_wallclock_as_timestamps caused
  # on x11grab. -rw_timeout aborts a stalled RTMP socket (supervisor restarts).
  "${TASKSET_PRE[@]}" ffmpeg -hide_banner -loglevel warning -nostdin \
    "${VAAPI_PRE[@]}" -f x11grab -framerate "$STREAM_FPS" -video_size "${STREAM_WIDTH}x${STREAM_HEIGHT}" -draw_mouse 0 -thread_queue_size 64 -probesize 32k -analyzeduration 0 -i ":$DISPLAY_NUM.0" \
    "${AUDIO_INPUT_ARGS[@]}" \
    "${MAP_ARGS[@]}" \
    -vf "$VAAPI_VF" \
    "${VCODEC_ARGS[@]}" \
    -b:v "$VIDEO_BITRATE" -maxrate "$MAX_BITRATE" -bufsize "$BUF_SIZE" \
    -g "$GOP" -keyint_min "$GOP" -sc_threshold 0 -r "$STREAM_FPS" "${FPSMODE_ARGS[@]}" \
    "${AACENC_ARGS[@]}" -b:a "$AUDIO_BITRATE" -ar "$AUDIO_SAMPLERATE" -ac "$AUDIO_CHANNELS" -af "aresample=${AUDIO_SAMPLERATE}:async=1:first_pts=0" \
    -flvflags no_duration_filesize \
    "${OUT_ARGS[@]}" 2>&1 | tee -a "$LOG"

  EXIT_CODE=$?
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stream exited with code $EXIT_CODE. Restarting in 3 seconds..." | tee -a "$LOG"
  sleep 3
done
