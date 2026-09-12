#!/bin/bash
# ==============================================================================
# Quran Live Broadcast — 24h Loop Builder
# Concatenates nightly seg-*.mp4 slices (same codec/params, `-c copy`, no
# re-encode) into loop.mp4 and points current.mp4 at it. The file-loop stream
# picks it up on the next service restart (midnight alignment cron).
# Usage: build_loop.sh [min_hours]   (default: 6 -> builds once >= 6h exist)
# ==============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

EP_DIR="$BASE_DIR/episodes"
LOG="$BASE_DIR/logs/record_episode.log"
MIN_HOURS="${1:-6}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOOP] $*" | tee -a "$LOG"
}

exec 9>"$BASE_DIR/runtime/build_loop.lock"
flock -n 9 || { log "Another build is running, exiting."; exit 0; }

mapfile -t SEGS < <(ls "$EP_DIR"/seg-*.mp4 2>/dev/null | sort)
if [ "${#SEGS[@]}" -eq 0 ]; then
  log "No slices yet, nothing to build."
  exit 0
fi

# Total duration check
TOTAL=0
for f in "${SEGS[@]}"; do
  d="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null || echo 0)"
  TOTAL=$((TOTAL + ${d%.*}))
done
log "Slices: ${#SEGS[@]}, total $((TOTAL / 3600))h$((TOTAL % 3600 / 60))m."
if [ "$TOTAL" -lt "$((MIN_HOURS * 3600))" ]; then
  log "Below ${MIN_HOURS}h minimum, skipping build (loop grows nightly)."
  exit 0
fi

# Concat list + copy (identical encode params => seamless, fast)
LIST="$EP_DIR/concat.txt"
: > "$LIST"
for f in "${SEGS[@]}"; do
  echo "file '$f'" >> "$LIST"
done
NEW_LOOP="$EP_DIR/loop-new.mp4"
ffmpeg -hide_banner -loglevel warning -nostdin -f concat -safe 0 -i "$LIST" -c copy "$NEW_LOOP" 2>&1 | tail -n 5 >>"$LOG" || true

NEW_DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$NEW_LOOP" 2>/dev/null || echo 0)"
NEW_INT="${NEW_DUR%.*}"
# Accept if within 5% of the summed slices
LOW="$((TOTAL * 95 / 100))"
if [ "${NEW_INT:-0}" -lt "$LOW" ]; then
  log "ERROR: built loop too short (${NEW_INT}s vs ${TOTAL}s), discarding."
  rm -f "$NEW_LOOP"
  exit 1
fi

mv "$NEW_LOOP" "$EP_DIR/loop.mp4"
ln -sfn "$EP_DIR/loop.mp4" "$EP_DIR/current.mp4"
log "Loop ready: loop.mp4 (${NEW_INT}s = $((NEW_INT / 3600))h). Restart stream to switch/extend."
