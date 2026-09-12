#!/bin/bash
# خلفيات HQ عمودية محسنة - بدون gradients (يستخدم color+noise فقط)
set -e
DIR="$HOME/quran-live-stream/assets/backgrounds/videos"
mkdir -p "$DIR"
echo "انشاء خلفيات HQ..."
rm -f "$DIR/bg1.mp4" "$DIR/bg2.mp4" "$DIR/bg3.mp4" 2>/dev/null || true
echo "bg1 midnight..."
ffmpeg -y -f lavfi -i color=c=0x0a1628:s=720x1280:d=30:r=30 -vf "noise=alls=12:allf=t,format=yuv420p" -c:v libx264 -preset ultrafast -tune stillimage -b:v 2500k -pix_fmt yuv420p -t 30 "$DIR/bg1_midnight.mp4" 2>&1 | tail -n 2
echo "bg2 emerald..."
ffmpeg -y -f lavfi -i color=c=0x0a2e1a:s=720x1280:d=30:r=30 -vf "noise=alls=10:allf=t,format=yuv420p" -c:v libx264 -preset ultrafast -tune stillimage -b:v 2500k -pix_fmt yuv420p -t 30 "$DIR/bg2_emerald.mp4" 2>&1 | tail -n 2
echo "bg3 golden..."
ffmpeg -y -f lavfi -i color=c=0x2c1810:s=720x1280:d=30:r=30 -vf "noise=alls=10:allf=t,format=yuv420p" -c:v libx264 -preset ultrafast -tune stillimage -b:v 2500k -pix_fmt yuv420p -t 30 "$DIR/bg3_golden.mp4" 2>&1 | tail -n 2
ls -lh "$DIR/" 2>&1
echo "تم HQ"