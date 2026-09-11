#!/bin/bash
# بث 24/7 للقرآن - تيك توك (عمودي 720x1280)
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
cd "$BASE_DIR"
if [ -f ".env" ]; then set -a; source .env; set +a; fi
if [ -f "config/stream.conf" ]; then source config/stream.conf; fi
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/stream_tiktok.log"
AUDIO_DIR="$BASE_DIR/assets/audio/afasy"
VIDEO_DIR="$BASE_DIR/assets/backgrounds/videos"
RUNTIME="$BASE_DIR/runtime"
mkdir -p "$RUNTIME"
TIKTOK_WIDTH=${TIKTOK_WIDTH:-720}
TIKTOK_HEIGHT=${TIKTOK_HEIGHT:-1280}
FPS=${FPS:-30}
VIDEO_BITRATE_TT=${VIDEO_BITRATE_TT:-2000k}
AUDIO_BITRATE=${AUDIO_BITRATE:-128k}
PRESET=${PRESET:-ultrafast}
if [ -z "$TIKTOK_RTMP_URL" ] || [ -z "$TIKTOK_STREAM_KEY" ]; then
  echo "[$(date)] خطأ: TIKTOK_RTMP_URL او STREAM_KEY غير موجود في .env" | tee -a "$LOG"
  exit 1
fi
RTMP="${TIKTOK_RTMP_URL}/${TIKTOK_STREAM_KEY}"
if [ -z "$(ls -A "$AUDIO_DIR"/*.mp3 2>/dev/null)" ]; then
  echo "[$(date)] تحذير: لا يوجد صوت" | tee -a "$LOG"
  mkdir -p "$AUDIO_DIR"
  ffmpeg -y -f lavfi -i anullsrc=r=44100:cl=stereo -t 60 -c:a libmp3lame -q:a 2 "$AUDIO_DIR/000_test.mp3" 2>&1 | tail -n 3
fi
if [ -z "$(ls -A "$VIDEO_DIR"/*.mp4 2>/dev/null)" ]; then
  echo "[$(date)] تحذير: لا يوجد فيديو" | tee -a "$LOG"
  mkdir -p "$VIDEO_DIR"
  ffmpeg -y -f lavfi -i color=c=0x0a1628:s=${TIKTOK_WIDTH}x${TIKTOK_HEIGHT}:d=10 -f lavfi -i anullsrc -c:v libx264 -pix_fmt yuv420p -t 10 "$VIDEO_DIR/bg_test_vertical.mp4" 2>&1 | tail -n 3
fi
find "$AUDIO_DIR" -name "*.mp3" -exec echo "file {}" \; | sort > "$RUNTIME/audio_playlist.txt"
find "$VIDEO_DIR" -name "*.mp4" -exec echo "file {}" \; | sort > "$RUNTIME/video_playlist.txt"
echo "[$(date)] TikTok ${TIKTOK_WIDTH}x${TIKTOK_HEIGHT} ${VIDEO_BITRATE_TT}"
while true; do
  echo "[$(date)] بدء البث الى تيك توك ..." | tee -a "$LOG"
  ffmpeg -hide_banner -loglevel info \
    -re -stream_loop -1 -f concat -safe 0 -i "$RUNTIME/video_playlist.txt" \
    -re -stream_loop -1 -f concat -safe 0 -i "$RUNTIME/audio_playlist.txt" \
    -vf "scale=${TIKTOK_WIDTH}:${TIKTOK_HEIGHT}:force_original_aspect_ratio=increase,crop=${TIKTOK_WIDTH}:${TIKTOK_HEIGHT},setsar=1,fps=${FPS},drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='القرآن الكريم - العفاسي':fontcolor=white:fontsize=32:box=1:boxcolor=black@0.6:boxborderw=5:x=(w-text_w)/2:y=h-th-100,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Quran 24/7':fontcolor=gold:fontsize=24:box=1:boxcolor=black@0.5:boxborderw=3:x=(w-text_w)/2:y=60" \
    -c:v libx264 -preset $PRESET -b:v $VIDEO_BITRATE_TT -maxrate $VIDEO_BITRATE_TT -bufsize 4000k -g 60 -pix_fmt yuv420p -r $FPS \
    -c:a aac -b:a $AUDIO_BITRATE -ar 44100 -ac 2 \
    -f flv "$RTMP" 2>&1 | tee -a "$LOG"
  EC=$?
  echo "[$(date)] توقف $EC - اعادة بعد 5ث" | tee -a "$LOG"
  sleep 5
done