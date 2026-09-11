#!/bin/bash
# لوحة تحكم البث
BASE="$HOME/quran-24-7"
case "$1" in
  start)
    echo "تشغيل البث..."
    systemctl --user daemon-reload
    if [ "$2" == "youtube" ]; then systemctl --user start quran-youtube.service; systemctl --user status quran-youtube.service --no-pager
    elif [ "$2" == "tiktok" ]; then systemctl --user start quran-tiktok.service; systemctl --user status quran-tiktok.service --no-pager
    elif [ "$2" == "dual" ]; then systemctl --user start quran-youtube.service quran-tiktok.service; systemctl --user status quran-youtube.service quran-tiktok.service --no-pager
    else systemctl --user start quran-youtube.service; echo "✓ تم تشغيل يوتيوب (افتراضي). للتيك توك: $0 start tiktok"; fi
    ;;
  stop)
    echo "ايقاف البث..."
    systemctl --user stop quran-youtube.service quran-tiktok.service 2>/dev/null; "$BASE/scripts/stop_ui.sh"; echo "✓ توقف"
    ;;
  restart)
    $0 stop; sleep 2; $0 start $2
    ;;
  status)
    systemctl --user status quran-youtube.service quran-tiktok.service --no-pager 2>&1 | head -n 80
    echo "--- ps ---"
    ps aux | grep ffmpeg | grep -v grep || echo "لا يوجد ffmpeg"
    echo "--- logs ---"
    tail -n 20 "$BASE/logs/stream_youtube.log" 2>&1 | tail -n 20
    ;;
  logs)
    tail -f "$BASE/logs/stream_${2:-youtube}.log"
    ;;
  enable)
    systemctl --user enable quran-youtube.service quran-tiktok.service; echo "✓ تشغيل تلقائي عند الاقلاع مفعل"
    systemctl --user enable --now quran-youtube.service 2>&1 | tail -n 5
    ;;
  disable)
    systemctl --user disable quran-youtube.service quran-tiktok.service; echo "✓ تم تعطيل التشغيل التلقائي"
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|logs|enable|disable} [youtube|tiktok|dual]"
    echo "  $0 start          # يشغل يوتيوب"
    echo "  $0 start tiktok   # يشغل تيك توك"
    echo "  $0 start dual     # يشغل الاثنين معا"
    echo "  $0 status         # حالة البث"
    echo "  $0 logs youtube   # متابعة سجل يوتيوب"
    ;;
esac