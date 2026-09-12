#!/bin/bash
# ==============================================================================
# Quran Live Stream — Encode Self-Benchmark (first boot)
# Measures sustained x264 ultrafast 480p10 fps on THIS box (~15-40s), discounts
# CPU steal, applies RAM caps, and writes the suggested profile to
# runtime/host.env. smptehdbars mimics still-text encode cost (~0.7-0.8x real);
# thresholds below already carry headroom for Chrome+capture+jitter.
# Usage: benchmark_host.sh [--force]   (skips when fresh host.env exists)
# ==============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="$BASE_DIR/runtime"
mkdir -p "$RUNTIME"
ENV_OUT="$RUNTIME/host.env"
LOG="$BASE_DIR/logs/benchmark.log"
mkdir -p "$(dirname "$LOG")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [BENCH] $*" | tee -a "$LOG"
}

if [ "${1:-}" != "--force" ] && [ -f "$ENV_OUT" ]; then
  MTIME="$(stat -c%Y "$ENV_OUT" 2>/dev/null || stat -f%m "$ENV_OUT" 2>/dev/null || echo 0)"
  case "$MTIME" in ''|*[!0-9]*) MTIME=0 ;; esac
  AGE=$(( $(date +%s) - MTIME ))
  if [ "$AGE" -lt "$((7 * 86400))" ]; then
    log "Fresh host.env ($((AGE / 3600))h old), skipping (use --force to re-run)."
    exit 0
  fi
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  log "ERROR: ffmpeg not found, cannot benchmark."
  exit 1
fi

MEM_MB="$(awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
case "$MEM_MB" in ''|*[!0-9]*) MEM_MB=0 ;; esac
# Host facts for the record (virt + confidential mode travel with the result)
eval "$("$BASE_DIR/scripts/detect_host.sh")" 2>/dev/null || true

W=854; H=480; FPS=10; DUR=12
BLOG="$RUNTIME/bench_tmp.log"
rm -f "$BLOG"

# Steal sampling runs concurrently with the encode
read -r _ u0 n0 s0 i0 w0 x0 y0 z0 st0 _rest < <(grep '^cpu ' /proc/stat)
T0=$((u0 + n0 + s0 + i0 + w0 + x0 + y0 + z0 + st0))

ffmpeg -hide_banner -nostdin -y \
  -f lavfi -i "smptehdbars=s=${W}x${H}:r=${FPS}:d=${DUR}" \
  -an -pix_fmt yuv420p \
  -c:v libx264 -preset ultrafast -tune zerolatency \
  -b:v 800k -maxrate 800k -bufsize 1600k \
  -g 20 -keyint_min 20 -sc_threshold 0 -bf 0 -refs 1 \
  -x264-params scenecut=0 \
  -f null - 2>"$BLOG" || log "WARNING: benchmark encode exited nonzero, using partial data."

read -r _ u1 n1 s1 i1 w1 x1 y1 z1 st1 _rest < <(grep '^cpu ' /proc/stat)
T1=$((u1 + n1 + s1 + i1 + w1 + x1 + y1 + z1 + st1))

# Portable parse (no grep -P): prefer speed= (reliable on ffmpeg 4..8; ffmpeg
# 7+ prints fps=0.0 on fast encodes), fall back to fps=. speed Nx at FPS input
# fps means NxFPS encoded frames per wall second.
BENCH_FPS="$(awk -v fps="$FPS" '{for (i=1;i<=NF;i++) {if ($i ~ /^speed=/) {split($i,a,"="); sub(/x$/,"",a[2]); if (a[2]+0>0) v=a[2]*fps} else if ($i ~ /^fps=/) {split($i,a,"="); if (a[2]+0>0 && v+0==0) v=a[2]}}} END{print v+0}' "$BLOG" 2>/dev/null || echo 0)"
BENCH_INT="${BENCH_FPS%.*}"
case "$BENCH_INT" in ''|*[!0-9]*) BENCH_INT=0 ;; esac
STEAL_PCT="$(awk "BEGIN{d=$((T1 - T0)); s=$((st1 - st0)); if (d>0) printf \"%.1f\", 100*s/d; else print 0}")"
# Discount steal explicitly (spikes later even if bench absorbed it)
EFF_FPS="$(awk "BEGIN{printf \"%.0f\", $BENCH_INT*(1-$STEAL_PCT/100)}")"
rm -f "$BLOG"

# Thresholds on steal-discounted ultrafast-480p10 fps (conservative static-text)
if [ "$EFF_FPS" -lt 12 ]; then BENCH_PROFILE="nano"
elif [ "$EFF_FPS" -le 70 ]; then BENCH_PROFILE="micro"
elif [ "$EFF_FPS" -le 200 ]; then BENCH_PROFILE="eco"
else BENCH_PROFILE="balanced"
fi
# RAM caps override CPU optimism (Chrome+capture need resident MBs)
if [ "$MEM_MB" -gt 0 ] && [ "$MEM_MB" -lt 700 ]; then BENCH_PROFILE="nano"
elif [ "$MEM_MB" -gt 0 ] && [ "$MEM_MB" -lt 900 ]; then
  [ "$BENCH_PROFILE" = "balanced" ] || [ "$BENCH_PROFILE" = "eco" ] && BENCH_PROFILE="micro" || true
elif [ "$MEM_MB" -gt 0 ] && [ "$MEM_MB" -lt 1800 ]; then
  [ "$BENCH_PROFILE" = "balanced" ] && BENCH_PROFILE="eco" || true
fi
# Heavy steal (>20%) pins to 480p regardless: host is overcommitted
STEAL_INT="${STEAL_PCT%.*}"
if [ "${STEAL_INT:-0}" -gt 20 ]; then
  case "$BENCH_PROFILE" in balanced|eco) BENCH_PROFILE="micro" ;; esac
fi

log "bench=${BENCH_FPS}fps eff=${EFF_FPS}fps steal=${STEAL_PCT}% mem=${MEM_MB}MB cc=${HOST_CC:-none} -> $BENCH_PROFILE"
# NOTE: on confidential-computing hosts (SEV-SNP/TDX/SME, 0-7% mem-bandwidth
# overhead) thresholds are intentionally NOT adjusted: the measurement already
# includes the overhead, so the selected profile is correct by construction.

# Hardware offload smoke test (3s null-output): encoder presence is NOT proof
# (drivers/BIOS often break runtime). A pass sets HOST_HW_OK and lifts the CPU
# benchmark floor to balanced/1080p-NVENC (RAM caps below still apply).
HOST_HW_OK="cpu"
if command -v timeout >/dev/null 2>&1; then
  if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q ' h264_nvenc '; then
    if timeout 20 ffmpeg -hide_banner -loglevel error -nostdin -y \
      -f lavfi -i "nullsrc=s=320x240:r=10:d=2" \
      -c:v h264_nvenc -preset p1 -b:v 500k -f null - >/dev/null 2>&1; then
      HOST_HW_OK="nvenc"
      log "HW smoke: h264_nvenc WORKS, lifting floor to balanced/1080p."
    else
      log "HW smoke: h264_nvenc present but broken at runtime, staying CPU."
    fi
  fi
fi
if [ "$HOST_HW_OK" = "nvenc" ] && [ "$MEM_MB" -ge 1800 ]; then
  case "$BENCH_PROFILE" in nano|micro|eco) BENCH_PROFILE="balanced" ;; esac
  log "HW floor applied -> $BENCH_PROFILE"
fi

{
  echo "HOST_BENCH_FPS=$BENCH_FPS"
  echo "HOST_BENCH_EFF_FPS=$EFF_FPS"
  echo "HOST_STEAL_PCT=$STEAL_PCT"
  echo "HOST_BENCH_PROFILE=$BENCH_PROFILE"
  echo "HOST_HW_OK=$HOST_HW_OK"
  echo "HOST_VIRT=${HOST_VIRT:-unknown}"
  echo "HOST_CC=${HOST_CC:-none}"
  echo "HOST_BENCH_TIME=$(date +%s)"
} > "$ENV_OUT"
