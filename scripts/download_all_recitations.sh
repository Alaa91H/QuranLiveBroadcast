#!/bin/bash
# ==============================================================================
# Quran Live Broadcast - Autonomous Complete Recitation Downloader (Alafasy 128k)
# Downloads and caches all 6,236 Quran verse audio files to local disk
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
AUDIO_DIR="$ROOT_DIR/web/assets/audio"
mkdir -p "$AUDIO_DIR"

echo "=== بدء تحميل التلاوة الصوتية الكاملة بصوت الشيخ مشاري العفاسي (128kbps) ==="
echo "المجلد المستهدف: $AUDIO_DIR"

# Check if node is available to run high-performance concurrent downloader
if command -v node >/dev/null 2>&1; then
  echo "تشغيل محمل التلاوات الذكي عبر Node.js..."
  node "$SCRIPT_DIR/download_all_recitations.js" "$@"
  exit 0
fi

# Fallback shell-only downloader using curl and tar/unzip
BASE_URL="https://everyayah.com/data/Alafasy_128kbps/zips"
cd "$AUDIO_DIR"

for i in $(seq -w 001 114); do
  echo "⬇ فحص / تنزيل السورة $i ..."
  ZIP_FILE="${i}.zip"
  if curl -s -f -L -o "$ZIP_FILE" "$BASE_URL/$ZIP_FILE" --retry 3 --connect-timeout 10; then
    if command -v tar >/dev/null 2>&1; then
      tar -xf "$ZIP_FILE" && rm -f "$ZIP_FILE"
    elif command -v unzip >/dev/null 2>&1; then
      unzip -o -q "$ZIP_FILE" && rm -f "$ZIP_FILE"
    fi
    echo "✓ تم استخراج سورة $i"
  else
    rm -f "$ZIP_FILE"
    echo "تنبيه: تعذر تحميل الحزمة لسورة $i، سيتم التحميل التلقائي الفردي عند البث."
  fi
done

TOTAL_FILES=$(ls -1 *.mp3 2>/dev/null | wc -l)
echo "=== اكتملت عملية التنزيل بنجاح ==="
echo "إجمالي ملفات التلاوة الموجودة على القرص: $TOTAL_FILES / 6236"
