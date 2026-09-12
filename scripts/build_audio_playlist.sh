#!/bin/bash
# ==============================================================================
# Quran Live Broadcast — Recitation Playlist Builder (PulseAudio-free audio)
# Scans web/assets/audio/SSSAAA.mp3 (surah 1..114, ayah order — the same order
# the web UI plays) and writes an ffmpeg concat playlist. Only files >1KB are
# included. Run full download (scripts/download_all_recitations.sh) first for
# complete coverage; with partial coverage the loop simply repeats sooner.
# NOTE: display/audio sync relies on identical file order on both sides; any
# residual drift is cleared by the daily service restart. No PulseAudio used.
# ==============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

AUDIO_DIR="$BASE_DIR/web/assets/audio"
RUNTIME="$BASE_DIR/runtime"
mkdir -p "$RUNTIME"
PLAYLIST="$RUNTIME/audio_playlist.txt"

COUNT=0
BYTES=0
: > "$PLAYLIST.tmp"
for f in "$AUDIO_DIR"/[0-9][0-9][0-9][0-9][0-9][0-9].mp3; do
  [ -f "$f" ] || continue
  size=$(stat -c%s "$f" 2>/dev/null || echo 0)
  if [ "$size" -gt 1000 ]; then
    echo "file '$f'" >> "$PLAYLIST.tmp"
    COUNT=$((COUNT + 1))
    BYTES=$((BYTES + size))
  fi
done

if [ "$COUNT" -eq 0 ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [PLAYLIST] No local recitation audio found in $AUDIO_DIR" >&2
  rm -f "$PLAYLIST.tmp"
  exit 1
fi

mv "$PLAYLIST.tmp" "$PLAYLIST"
# ~128kbps CBR ≈ 16KB/s → rough loop length without probing thousands of files
EST_MIN=$((BYTES / 1024 / 16 / 60))
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [PLAYLIST] $COUNT files (~${EST_MIN} min loop) -> $PLAYLIST"
