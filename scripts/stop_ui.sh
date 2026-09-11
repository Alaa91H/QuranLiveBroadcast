#!/bin/bash
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"; RUNTIME="$BASE_DIR/runtime"
for f in quran-chrome.pid quran-xvfb.pid quran-web.pid; do
  p="$RUNTIME/$f"; if [ -f "$p" ]; then pid=$(cat "$p" 2>/dev/null || true); kill "$pid" 2>/dev/null || true; rm -f "$p"; fi
done
pkill -f "chromium.*127.0.0.1:4177" 2>/dev/null || true
