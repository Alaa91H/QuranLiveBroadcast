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
# Free port 4177: fuser (psmisc, MISSING on Ubuntu 26.04 minimal) with an
# ss-based fallback (iproute2 is present even on minimal).
if command -v fuser >/dev/null 2>&1; then
  fuser -k 4177/tcp 2>/dev/null || true
elif command -v ss >/dev/null 2>&1; then
  # Portable pid extraction (BRE sed works on gawk/mawk/busybox alike)
  for pid in $(ss -ltnp 2>/dev/null | grep ':4177 ' | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p'); do
    kill -9 "$pid" 2>/dev/null || true
  done
fi

# Give the kernel a moment to release the port so the next start does not hit
# EADDRINUSE (common under high load).
PORT="${QURAN_WEB_PORT:-4177}"
for i in $(seq 1 10); do
  (echo > /dev/tcp/127.0.0.1/$PORT) >/dev/null 2>&1 || break
  sleep 1
done
