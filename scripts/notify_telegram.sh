#!/bin/bash
# ==============================================================================
# Quran Live Broadcast — Telegram Notifier (graceful when unconfigured)
# Sends an alert via Telegram Bot API. Does nothing (exit 0) when
# TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID is empty: reliability features keep
# working locally, alerts simply stay in the log until credentials are added.
# Usage: notify_telegram.sh "message text" [silent]
# ==============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

[ -f .env ] && { set -a; source .env 2>/dev/null; set +a; } || true

MSG="${1:-QuranLive: (empty message)}"
SILENT="${2:-}"

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [TELEGRAM] not configured, alert kept local: $MSG" >>"$BASE_DIR/logs/telegram.log" 2>/dev/null || true
  exit 0
fi

DISABLE_NOTIFICATION=""
[ "$SILENT" = "silent" ] && DISABLE_NOTIFICATION="&disable_notification=true"

if curl -sS --max-time 10 --retry 2 \
  --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${MSG}" \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage?parse_mode=HTML${DISABLE_NOTIFICATION}" \
  >>"$BASE_DIR/logs/telegram.log" 2>&1; then
  echo "" >>"$BASE_DIR/logs/telegram.log" 2>/dev/null || true
  exit 0
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [TELEGRAM] send FAILED: $MSG" >>"$BASE_DIR/logs/telegram.log" 2>/dev/null || true
  exit 1
fi
