#!/bin/bash
# ==============================================================================
# Quran Live Broadcast — First-Boot Orchestrator
# One command to adapt ANY fresh server: detect -> provision (swap/zram/sysctl)
# -> probe egress -> benchmark encode -> write runtime/host.env + net.env.
# Afterwards hardware_profile.sh auto-selects the right quality, and the stream
# clamps bitrate to the measured uplink. Idempotent: each stage has its own
# freshness guard; re-run with --force to redo everything.
# Usage: first_boot.sh [--force]   (provisioning needs passwordless sudo/root)
# ==============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"
FORCE="${1:-}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [FIRSTBOOT] $*"
}

log "=== Quran first-boot adaptation started ==="
if [ -z "${BASH_VERSION:-}" ]; then
  log "ERROR: bash 4+ required (Alpine: apk add bash). Aborting."
  exit 1
fi
eval "$("$BASE_DIR/scripts/detect_host.sh")" || true
log "Host: virt=${HOST_VIRT:-?} mem=${HOST_MEM_MB:-?}MB cpu=${HOST_CPU_N:-?} disk=${HOST_DISK_AVAIL_MB:-?}MB gpu(nv=${HOST_HW_NVENC:-0},vaapi=${HOST_HW_VAAPI:-0},qsv=${HOST_HW_QSV:-0})"

log "--- [1/4] provisioning (swap/zram/sysctl/services) ---"
"$BASE_DIR/scripts/tune_system.sh" $FORCE >>"$BASE_DIR/logs/tune_system.log" 2>&1 || log "WARNING: provisioning had failures (see logs/tune_system.log), continuing."

log "--- [2/4] egress probe (~20s, ~15MB) ---"
"$BASE_DIR/scripts/probe_egress.sh" $FORCE || log "WARNING: egress probe failed, stream runs uncapped."

log "--- [3/4] encode benchmark (~15-40s, 100% CPU briefly) ---"
"$BASE_DIR/scripts/benchmark_host.sh" $FORCE || log "WARNING: benchmark failed, auto-detect fallback applies."

log "--- [4/4] static primer kickoff (background) ---"
"$BASE_DIR/scripts/prime_static_cache.sh" >>"$BASE_DIR/logs/prime_static.log" 2>&1 || log "WARNING: primer failed to start."

log "=== Decision summary ==="
if [ -f "$BASE_DIR/runtime/host.env" ]; then
  # shellcheck disable=SC1091
  source "$BASE_DIR/runtime/host.env"
  log "Suggested profile: ${HOST_BENCH_PROFILE:-auto} (bench ${HOST_BENCH_EFF_FPS:-?}fps eff, steal ${HOST_STEAL_PCT:-?}%)"
else
  log "No benchmark result: hardware auto-detect applies."
fi
if [ -f "$BASE_DIR/runtime/net.env" ]; then
  # shellcheck disable=SC1091
  source "$BASE_DIR/runtime/net.env"
  log "Uplink safe ceiling: ${HOST_EGRESS_SAFE_MBPS:-unknown} Mbps"
fi
"$BASE_DIR/scripts/hardware_profile.sh" --show 2>/dev/null | tail -n 8 || true
log "=== first-boot done. Start the stream: scripts/control.sh start ==="
