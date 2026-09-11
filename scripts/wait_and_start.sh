#!/bin/bash
# ينتظر حتى تضع المفتاح في .env ثم يشغل تلقائيا
BASE="$HOME/quran-24-7"
ENV="$BASE/.env"
echo "بانتظار مفتاح TikTok في $ENV ..."
echo "ضع المفتاح ثم شغل: ./scripts/control.sh start tiktok"
while true; do
  source "$ENV" 2>/dev/null
  if [[ "$TIKTOK_STREAM_KEY" != "" && "$TIKTOK_STREAM_KEY" != "ضع_المفتاح_هنا" && "$TIKTOK_STREAM_KEY" != "your_tiktok_key" && "$TIKTOK_STREAM_KEY" != "xxxx-xxxx-xxxx-xxxx-xxxx" ]]; then
    echo "[$(date)] تم العثور على المفتاح - بدء البث..."
    "$BASE/scripts/control.sh" start tiktok
    "$BASE/scripts/control.sh" status
    break
  fi
  sleep 10
done