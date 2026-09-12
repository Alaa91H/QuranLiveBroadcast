#!/bin/bash
# فحص صحة البث
BASE="$HOME/quran-live-stream"
LOG="$BASE/logs/health.log"
mkdir -p "$(dirname "$LOG")"
check() {
  SERVICE=$1
  NAME=$2
  if systemctl --user is-active --quiet "$SERVICE"; then
    if pgrep -f "$NAME" > /dev/null; then
      echo "[$(date)] OK $NAME يعمل" | tee -a "$LOG"
      return 0
    else
      echo "[$(date)] FAIL $NAME متوقف - اعادة تشغيل" | tee -a "$LOG"
      systemctl --user restart "$SERVICE"
      return 1
    fi
  else
    echo "[$(date)] - $NAME غير نشط" | tee -a "$LOG"
    return 0
  fi
}
check quran-live-youtube.service "stream_youtube"
check quran-live-tiktok.service "stream_tiktok"
FREE=$(free -m | awk '/Mem:/ {print $7}')
if [ "$FREE" -lt 100 ]; then
  echo "[$(date)] تحذير ذاكرة قليلة ${FREE}M" | tee -a "$LOG"
fi