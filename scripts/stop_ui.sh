#!/bin/bash
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="$BASE_DIR/runtime"

for f in quran-chrome.pid quran-xvfb.pid quran-web.pid; do
  p="$RUNTIME/$f"
  if [ -f "$p" ]; then
    pid=$(cat "$p" 2>/dev/null || true)
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$p"
  fi
done

pkill -9 -f "node.*server.js" 2>/dev/null || true
pkill -9 -f "chrome.*127.0.0.1:4177" 2>/dev/null || true
pkill -9 -f "chromium.*127.0.0.1:4177" 2>/dev/null || true
fuser -k 4177/tcp 2>/dev/null || true
