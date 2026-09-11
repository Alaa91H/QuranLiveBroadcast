#!/bin/bash
# بث مزدوج 24/7 - يوتيوب + تيك توك معا
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
cd "$BASE_DIR"
echo "=== بدء البث المزدوج ==="
echo "تحذير: يتطلب 2x ترميز - قد يستهلك CPU/RAM عالية على سيرفر 1GB"
echo "اذا حدث تقطيع، شغل كل منصة لوحدها"
# شغل الاثنين في الخلفية
"$SCRIPT_DIR/stream_youtube.sh" &
PID_YT=$!
echo "YouTube PID $PID_YT"
"$SCRIPT_DIR/stream_tiktok.sh" &
PID_TT=$!
echo "TikTok PID $PID_TT"
echo "البث المزدوج يعمل - YT:$PID_YT TT:$PID_TT"
echo "للمراقبة: tail -f logs/stream_*.log"
echo "للايقاف: kill $PID_YT $PID_TT"
wait