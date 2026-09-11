#!/bin/bash
# تحميل خلفيات عالية الجودة - فيديو وصور اسلامية
set -e
VID_DIR="$HOME/quran-24-7/assets/backgrounds/videos"
IMG_DIR="$HOME/quran-24-7/assets/backgrounds/images"
mkdir -p "$VID_DIR" "$IMG_DIR"
echo "=== تحميل خلفيات ==="
# اذا لم توجد خلفيات، ننشئ فيديوهات اختبارية عالية الجودة عبر ffmpeg
if [ -z "$(ls -A "$VID_DIR" 2>/dev/null)" ]; then
  echo "انشاء خلفيات اختبارية..."
  # خلفية 1: تدرج ازرق اسلامي
  ffmpeg -y -f lavfi -i color=c=0x0a1628:s=1920x1080:d=30 -f lavfi -i anullsrc -c:v libx264 -pix_fmt yuv420p -t 30 "$VID_DIR/bg1_night.mp4" 2>&1 | tail -n 5
  # خلفية 2: تدرج ذهبي
  ffmpeg -y -f lavfi -i color=c=0x1a3a2a:s=1920x1080:d=30 -f lavfi -i anullsrc -c:v libx264 -pix_fmt yuv420p -t 30 "$VID_DIR/bg2_green.mp4" 2>&1 | tail -n 5
  # خلفية 3: كعبة - تدرج بني
  ffmpeg -y -f lavfi -i color=c=0x2c1810:s=1920x1080:d=30 -f lavfi -i anullsrc -c:v libx264 -pix_fmt yuv420p -t 30 "$VID_DIR/bg3_kaaba.mp4" 2>&1 | tail -n 5
  echo "✓ تم انشاء 3 خلفيات اختبارية"
  echo "يمكنك اضافة فيديوهات حقيقية 1080p الى $VID_DIR"
  echo "مصادر مقترحة:"
  echo " - pexels.com/search/islamic"
  echo " - coverr.co"
  echo " - pixabay.com/videos/search/mosque"
fi
ls -lh "$VID_DIR" 2>&1 | head -n 20
ls -lh "$IMG_DIR" 2>&1 | head -n 20
du -sh "$VID_DIR" "$IMG_DIR" 2>&1