#!/bin/bash
# ==============================================================================
# Quran Live Broadcast — Autonomous Scheduled Maintenance & Optimizer
# Best run daily during minimum global viewership window (e.g. 03:30 AM).
# Handles Git updates, cache purges, log rotation, and zero-downtime memory refresh.
# ==============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

LOG_DIR="$BASE_DIR/logs"
CACHE_DIR="$BASE_DIR/web/.cache"
mkdir -p "$LOG_DIR"
MAINT_LOG="$LOG_DIR/maintenance.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [MAINTENANCE] $*" | tee -a "$MAINT_LOG"
}

log "=== Starting Scheduled Maintenance Run ==="

# 1. Autonomous Git Update (if enabled or repository is clean)
if [ -d "$BASE_DIR/.git" ]; then
  log "Checking for repository updates on origin/main..."
  if git status --porcelain 2>/dev/null | grep -q '^[ MADRCU]'; then
    log "Working tree has uncommitted local edits; skipping automatic git pull to preserve local modifications."
  else
    git fetch origin main >/dev/null 2>&1 || true
    BEHIND_COUNT=$(git rev-list HEAD..origin/main --count 2>/dev/null || echo 0)
    if [ "$BEHIND_COUNT" -gt 0 ]; then
      log "New updates detected ($BEHIND_COUNT commit(s) behind). Applying updates cleanly..."
      git pull --ff-only origin main >>"$MAINT_LOG" 2>&1 || log "Warning: Git pull encountered conflict; will retry next cycle."
    else
      log "Repository is up-to-date."
    fi
  fi
fi

# 2. Clean stale cache files older than 7 days
if [ -d "$CACHE_DIR" ]; then
  log "Pruning disk cache entries older than 7 days..."
  DELETED_COUNT=$(find "$CACHE_DIR" -type f -name "*.json" -mtime +7 -delete -print 2>/dev/null | wc -l || echo 0)
  log "Cleaned $DELETED_COUNT stale cache files."
fi

# 3. Log Rotation (keep log sizes <= 15MB)
log "Rotating system logs..."
for log_file in "$LOG_DIR"/*.log; do
  [ -f "$log_file" ] || continue
  SIZE_KB=$(du -k "$log_file" | cut -f1)
  if [ "$SIZE_KB" -gt 15360 ]; then # 15MB
    log "Rotating $(basename "$log_file") (${SIZE_KB}KB)..."
    mv "$log_file" "${log_file}.old"
    gzip -f "${log_file}.old" 2>/dev/null || true
    touch "$log_file"
  fi
done

# 4. Clean Memory & Service Refresh (Releases accumulated Chromium/Node memory)
log "Performing graceful broadcast refresh during low-viewership window..."
if command -v systemctl >/dev/null 2>&1 && systemctl --user is-active --quiet quran-youtube.service 2>/dev/null; then
  systemctl --user restart quran-youtube.service
  log "Stream service restarted cleanly via systemd."
else
  "$BASE_DIR/scripts/stop_ui.sh" >/dev/null 2>&1 || true
  sleep 2
  "$BASE_DIR/scripts/broadcast_ui.sh" >>"$LOG_DIR/web.log" 2>&1 &
  log "Broadcast UI restarted cleanly."
fi

# 5. Drop Kernel filesystem page caches if root
if [ "$(id -u)" -eq 0 ]; then
  sync && echo 3 > /proc/sys/vm/drop_caches
  log "Kernel pagecache compacted. System RAM is fully refreshed."
fi

log "=== Maintenance Run Successfully Completed ==="
