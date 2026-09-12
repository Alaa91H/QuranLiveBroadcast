#!/bin/bash
# تحميل القرآن بصوت العفاسي - جودة 128k عالية
set -e
DIR="$HOME/quran-live-stream/assets/audio/afasy"
mkdir -p "$DIR"
cd "$DIR"
echo "=== تحميل العفاسي 114 سورة ==="
BASE="https://server8.mp3quran.net/afs"
for i in $(seq -w 001 114); do
  FILE="${i}.mp3"
  if [ -f "$FILE" ] && [ -s "$FILE" ]; then
    echo "✓ موجود $FILE"
  else
    echo "⬇ تحميل $FILE ..."
    curl -L -o "$FILE.tmp" "$BASE/$FILE" --retry 3 --connect-timeout 10 || echo "فشل $FILE"
    if [ -s "$FILE.tmp" ]; then mv "$FILE.tmp" "$FILE"; echo "✓ تم $FILE"; else rm -f "$FILE.tmp"; fi
    sleep 1
  fi
done
echo "=== اكتمل ==="
ls -lh | head -n 20
du -sh .
echo "عدد الملفات: $(ls -1 *.mp3 2>/dev/null | wc -l)/114"