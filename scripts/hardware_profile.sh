#!/bin/bash
# ==============================================================================
# Quran Live Broadcast — Hardware Profile & Adaptive Streaming Engine
# Automatically detects host CPU, RAM, and GPU to optimize streaming from 720p to 8K.
# Tailored for rock-solid stability on 1 vCPU / 1 GB RAM (e.g. Oracle Cloud Free Tier).
# ==============================================================================

# 1. Detect System Resources
TOTAL_RAM_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || grep MemTotal /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}' || echo 1024)
CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)
# Sanitize: empty/non-numeric detection (e.g. missing `free`) must not break
# the integer comparisons below; fall back to conservative 1GB/1CPU.
case "$TOTAL_RAM_MB" in ''|*[!0-9]*) TOTAL_RAM_MB=1024 ;; esac
case "$CPU_CORES" in ''|*[!0-9]*) CPU_CORES=1 ;; esac

# Detect Hardware Acceleration (NVENC, VAAPI)
HAS_NVENC=0
HAS_VAAPI=0
if command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -encoders 2>/dev/null | grep -q h264_nvenc && HAS_NVENC=1 || true
  ffmpeg -encoders 2>/dev/null | grep -q h264_vaapi && HAS_VAAPI=1 || true
fi

# 2. Determine Profile (Manual Override via $STREAM_PROFILE or Auto-detection)
# Options: micro (480p ultra-low), eco (720p), balanced (1080p),
#          high (2K/1440p), ultra (4K), extreme (8K)
if [ -n "${STREAM_PROFILE:-}" ]; then
  PROFILE="${STREAM_PROFILE,,}"
elif [ -n "${STREAM_RES:-}" ]; then
  case "${STREAM_RES,,}" in
    480p|sd|micro) PROFILE="micro" ;;
    720p|hd) PROFILE="eco" ;;
    1080p|fhd) PROFILE="balanced" ;;
    1440p|2k|qhd) PROFILE="high" ;;
    2160p|4k|uhd) PROFILE="ultra" ;;
    4320p|8k) PROFILE="extreme" ;;
    *) PROFILE="balanced" ;;
  esac
else
  # Auto-select based on hardware
  if [ "$TOTAL_RAM_MB" -le 1000 ] || [ "$CPU_CORES" -le 1 ]; then
    PROFILE="micro" # Ultra-Low Resource Quran Mode (<=1GB RAM or 1 vCPU)
  elif [ "$TOTAL_RAM_MB" -le 1500 ]; then
    PROFILE="eco" # Optimized for Oracle Free Tier (~1GB RAM)
  elif [ "$TOTAL_RAM_MB" -le 4096 ] && [ "$CPU_CORES" -le 3 ]; then
    PROFILE="balanced" # Standard 1080p VPS
  elif [ "$TOTAL_RAM_MB" -ge 16000 ] && [ "$HAS_NVENC" -eq 1 ]; then
    PROFILE="ultra" # 4K with GPU
  elif [ "$TOTAL_RAM_MB" -ge 8192 ] && [ "$CPU_CORES" -ge 6 ]; then
    PROFILE="high" # 2K 1440p
  else
    PROFILE="balanced"
  fi
fi

# 3. Configure Resolution, Bitrate, Encoding & Memory Limits
case "$PROFILE" in
  micro)
    # Ultra-Low Resource Quran Mode (<=1GB RAM or 1 vCPU, e.g. throttled free tier).
    # 854x480 @10fps: mostly-static Quran pages stay readable, CPU ~= 1/3 of eco.
    # File-based audio by default (no PulseAudio in the audio path).
    PROFILE_NAME="Micro (480p Ultra-Low - 1 CPU / <=1GB RAM)"
    STREAM_WIDTH=854
    STREAM_HEIGHT=480
    STREAM_FPS="${STREAM_FPS:-10}"
    VIDEO_BITRATE="${VIDEO_BITRATE:-800k}"
    MAX_BITRATE="${MAX_BITRATE:-1000k}"
    BUF_SIZE="1600k"
    AUDIO_BITRATE="${AUDIO_BITRATE:-128k}"
    AUDIO_SAMPLERATE=44100
    FFMPEG_PRESET="ultrafast"
    FFMPEG_TUNE="zerolatency"
    FFMPEG_THREADS=1
    # Extra 1-CPU x264 savings on top of ultrafast+zerolatency (fixed GOP saves
    # lookahead; the rest trims analysis thepreset still performs).
    X264_PARAMS="ref=1:mixed-refs=0:trellis=0:cabac=0:8x8dct=0:weightp=0:me=dia:subme=0:analyse=i4x4:scenecut=0:keyint=20:min-keyint=10"
    DEFAULT_AUDIO_MODE="file"
    NODE_MEM_MB=112
    CHROME_MEM_MB=160
    VCODEC="libx264"
    ;;

  eco)
    # Low-spec Cloud (Oracle Cloud Free Tier: 1 CPU, 1GB RAM)
    PROFILE_NAME="Eco (720p HD - 1 CPU / 1GB RAM optimized)"
    STREAM_WIDTH=1280
    STREAM_HEIGHT=720
    STREAM_FPS="${STREAM_FPS:-15}"
    VIDEO_BITRATE="${VIDEO_BITRATE:-1200k}"
    MAX_BITRATE="${MAX_BITRATE:-1500k}"
    BUF_SIZE="2400k"
    AUDIO_BITRATE="${AUDIO_BITRATE:-128k}"
    AUDIO_SAMPLERATE=44100
    FFMPEG_PRESET="ultrafast"
    FFMPEG_TUNE="zerolatency"
    FFMPEG_THREADS=1
    NODE_MEM_MB=140
    CHROME_MEM_MB=220
    VCODEC="libx264"
    ;;

  balanced)
    # Standard 1080p Broadcast (2-4 Cores, 2GB-4GB RAM)
    PROFILE_NAME="Balanced (1080p Full HD)"
    STREAM_WIDTH=1920
    STREAM_HEIGHT=1080
    STREAM_FPS=30
    VIDEO_BITRATE="${VIDEO_BITRATE:-4200k}"
    MAX_BITRATE="${MAX_BITRATE:-4800k}"
    BUF_SIZE="8400k"
    AUDIO_BITRATE="${AUDIO_BITRATE:-160k}"
    AUDIO_SAMPLERATE=48000
    FFMPEG_PRESET="veryfast"
    FFMPEG_TUNE="zerolatency"
    FFMPEG_THREADS=$((CPU_CORES > 2 ? 3 : CPU_CORES))
    NODE_MEM_MB=256
    CHROME_MEM_MB=384
    VCODEC="libx264"
    ;;

  high)
    # 2K Quad HD (4-8 Cores, 8GB+ RAM)
    PROFILE_NAME="High (1440p 2K QHD 60fps)"
    STREAM_WIDTH=2560
    STREAM_HEIGHT=1440
    STREAM_FPS=60
    VIDEO_BITRATE="${VIDEO_BITRATE:-8500k}"
    MAX_BITRATE="${MAX_BITRATE:-9500k}"
    BUF_SIZE="16000k"
    AUDIO_BITRATE="${AUDIO_BITRATE:-192k}"
    AUDIO_SAMPLERATE=48000
    FFMPEG_PRESET="faster"
    FFMPEG_TUNE="film"
    FFMPEG_THREADS=$((CPU_CORES > 4 ? 6 : CPU_CORES))
    NODE_MEM_MB=384
    CHROME_MEM_MB=512
    if [ "$HAS_NVENC" -eq 1 ]; then
      VCODEC="h264_nvenc"
      FFMPEG_PRESET="p4"
    else
      VCODEC="libx264"
    fi
    ;;

  ultra)
    # 4K Ultra HD (Dedicated Server / GPU, 16GB+ RAM)
    PROFILE_NAME="Ultra (2160p 4K UHD 60fps)"
    STREAM_WIDTH=3840
    STREAM_HEIGHT=2160
    STREAM_FPS=60
    VIDEO_BITRATE="${VIDEO_BITRATE:-16000k}"
    MAX_BITRATE="${MAX_BITRATE:-18000k}"
    BUF_SIZE="32000k"
    AUDIO_BITRATE="${AUDIO_BITRATE:-256k}"
    AUDIO_SAMPLERATE=48000
    FFMPEG_THREADS=$((CPU_CORES > 8 ? 8 : CPU_CORES))
    NODE_MEM_MB=512
    CHROME_MEM_MB=768
    if [ "$HAS_NVENC" -eq 1 ]; then
      VCODEC="h264_nvenc"
      FFMPEG_PRESET="p5"
    else
      VCODEC="libx264"
      FFMPEG_PRESET="fast"
    fi
    ;;

  extreme)
    # 8K Extreme Broadcast (Workstation / Data Center GPU)
    PROFILE_NAME="Extreme (4320p 8K Broadcast)"
    STREAM_WIDTH=7680
    STREAM_HEIGHT=4320
    STREAM_FPS=60
    VIDEO_BITRATE="${VIDEO_BITRATE:-36000k}"
    MAX_BITRATE="${MAX_BITRATE:-42000k}"
    BUF_SIZE="70000k"
    AUDIO_BITRATE="${AUDIO_BITRATE:-320k}"
    AUDIO_SAMPLERATE=48000
    FFMPEG_THREADS=$CPU_CORES
    NODE_MEM_MB=768
    CHROME_MEM_MB=1024
    if [ "$HAS_NVENC" -eq 1 ]; then
      VCODEC="hevc_nvenc"
      FFMPEG_PRESET="p5"
    else
      VCODEC="libx265"
      FFMPEG_PRESET="fast"
    fi
    ;;
esac

export PROFILE
export PROFILE_NAME
export STREAM_WIDTH
export STREAM_HEIGHT
export STREAM_FPS
export VIDEO_BITRATE
export MAX_BITRATE
export BUF_SIZE
export AUDIO_BITRATE
export AUDIO_SAMPLERATE
export FFMPEG_PRESET
export FFMPEG_TUNE
export FFMPEG_THREADS
export NODE_MEM_MB
export CHROME_MEM_MB
export VCODEC

# Extra x264 tuning (micro profile only; empty = preset defaults elsewhere)
X264_PARAMS="${X264_PARAMS:-}"
export X264_PARAMS

# Audio path: "pulse" = capture browser via PulseAudio sink (synced, heavier),
# "file" = concat local recitation mp3s (no PulseAudio; needs downloaded audio,
# playlist order matches UI surah 1..114 order; tiny drift possible, daily
# restart resyncs). Explicit $AUDIO_MODE in .env always wins.
DEFAULT_AUDIO_MODE="${DEFAULT_AUDIO_MODE:-pulse}"
AUDIO_MODE="${AUDIO_MODE:-$DEFAULT_AUDIO_MODE}"
export AUDIO_MODE

if [ "${1:-}" == "--show" ]; then
  echo "=========================================================="
  echo "Quran Live Broadcast — Auto-Configured Streaming Profile"
  echo "=========================================================="
  echo "Detected Specs : ${CPU_CORES} CPU Core(s), ${TOTAL_RAM_MB} MB RAM (NVENC: $HAS_NVENC, VAAPI: $HAS_VAAPI)"
  echo "Active Profile : $PROFILE_NAME"
  echo "Resolution     : ${STREAM_WIDTH}x${STREAM_HEIGHT} @ ${STREAM_FPS}fps"
  echo "Video Encoding : $VCODEC (Preset: $FFMPEG_PRESET, Bitrate: $VIDEO_BITRATE, Max: $MAX_BITRATE)"
  echo "Audio Encoding : AAC ($AUDIO_BITRATE @ ${AUDIO_SAMPLERATE}Hz, source: $AUDIO_MODE)"
  echo "Memory Budget  : Node.js max ${NODE_MEM_MB}MB | Chromium max ${CHROME_MEM_MB}MB"
  echo "=========================================================="
fi
