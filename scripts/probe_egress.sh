#!/bin/bash
# ==============================================================================
# Quran Live Stream — Egress Probe (first boot)
# Estimates USABLE upload to the internet for bitrate capping: median of 3x5MB
# POSTs to the nearest Cloudflare edge (~15MB, ~15-25s). Download is measured
# for asymmetry sanity ONLY and never sizes the stream (upload is what matters;
# cloud down is routinely 10-50% higher than up).
# Rule: 24/7 safe ceiling = median_up x 0.50 (prime-time dip + retrans + CBR
# keyframe spikes + audio/mux overhead). Writes runtime/net.env.
# Usage: probe_egress.sh [--force]
# ==============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="$BASE_DIR/runtime"
mkdir -p "$RUNTIME"
LOG="$BASE_DIR/logs/egress.log"
mkdir -p "$(dirname "$LOG")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [EGRESS] $*" | tee -a "$LOG"
}

if [ "${1:-}" != "--force" ] && [ -f "$RUNTIME/net.env" ]; then
  MTIME="$(stat -c%Y "$RUNTIME/net.env" 2>/dev/null || stat -f%m "$RUNTIME/net.env" 2>/dev/null || echo 0)"
  case "$MTIME" in ''|*[!0-9]*) MTIME=0 ;; esac
  AGE=$(( $(date +%s) - MTIME ))
  if [ "$AGE" -lt "$((7 * 86400))" ]; then
    log "Fresh net.env, skipping (use --force to re-run)."
    exit 0
  fi
fi

if ! command -v curl >/dev/null 2>&1; then
  log "ERROR: curl not found, cannot probe."
  exit 1
fi

F="$RUNTIME/up_probe_5m.bin"
dd if=/dev/urandom of="$F" bs=1M count=5 2>/dev/null || {
  log "ERROR: cannot create probe file."
  exit 1
}

log "RTT to ingest (info only, NOT bandwidth):"
for h in a.rtmp.youtube.com b.rtmp.youtube.com; do
  if RTCP="$(curl -sS -o /dev/null --connect-timeout 3 --max-time 5 -w '%{time_connect}' "https://$h" 2>/dev/null)"; then
    log "  $h tcp_connect=${RTCP}s"
  else
    log "  $h tcp_connect=unreachable"
  fi
done

UPS=""
for i in 1 2 3; do
  BPS="$(curl -sS -o /dev/null --connect-timeout 3 --max-time 15 -X POST \
    -H 'Content-Type: application/octet-stream' --data-binary "@$F" \
    -w '%{speed_upload}' 'https://speed.cloudflare.com/__up?bytes=5242880' 2>/dev/null || echo 0)"
  case "$BPS" in ''|*[!0-9]*) BPS=0 ;; esac
  MBPS="$(awk "BEGIN{printf \"%.2f\", $BPS*8/1000000}")"
  log "  sample $i: ${MBPS} Mbps"
  UPS="$UPS $BPS"
done
rm -f "$F"

MED_BPS="$(echo "$UPS" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -n | awk '{a[NR]=$1} END{if (NR==0) print 0; else if (NR%2) print a[(NR+1)/2]; else print (a[NR/2]+a[NR/2+1])/2}')"
MED_MBPS="$(awk "BEGIN{printf \"%.2f\", $MED_BPS*8/1000000}")"
SAFE_MBPS="$(awk "BEGIN{printf \"%.2f\", $MED_MBPS*0.5}")"
log "median_up=${MED_MBPS} Mbps -> safe_24x7=${SAFE_MBPS} Mbps"

{
  echo "HOST_EGRESS_MED_MBPS=$MED_MBPS"
  echo "HOST_EGRESS_SAFE_MBPS=$SAFE_MBPS"
  echo "HOST_EGRESS_TIME=$(date +%s)"
} > "$RUNTIME/net.env"
