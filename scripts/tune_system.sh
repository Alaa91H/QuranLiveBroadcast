#!/bin/bash
# ==============================================================================
# Quran Live Stream — Portable Host Tuner (run once as a sudoer, idempotent)
# Works on: Ubuntu/Debian/RHEL-clones/Fedora/Arch/Alpine, full VMs and bare
# metal. Inside containers (Docker/LXC/OpenVZ) privileged steps are SKIPPED
# gracefully (never aborts): no swapon/modprobe, no vm.* sysctl writes.
#   1. fstype-aware swapfile (xfs->dd, btrfs nocow sequence, overlay/tmpfs skip)
#   2. zram: systemd generator -> manual sysfs -> skip (lzo-rle on weak CPUs)
#   3. sysctl tunables (test-write first; containers keep host values)
#   4. tiny volatile journald (systemd only)
#   5. safe service audit (systemd only; ssh/cloud-init/console NEVER touched)
#   6. SSH OOM protection
# NEVER fails the boot: every privileged step is guarded; check logs/tune_system.log
# ==============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$BASE_DIR/logs/tune_system.log"
mkdir -p "$(dirname "$LOG")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [TUNE] $*" | tee -a "$LOG"
}

eval "$("$BASE_DIR/scripts/detect_host.sh")" || true
log "Host: virt=$HOST_VIRT container=$HOST_CONTAINER systemd=$HOST_SYSTEMD mem=${HOST_MEM_MB}MB cpu=$HOST_CPU_N fstype=$HOST_ROOT_FSTYPE"

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo -n"
  if ! sudo -n true 2>/dev/null; then
    log "ERROR: need passwordless sudo (or run as root). Aborting."
    exit 1
  fi
fi

# --- Swap sizing table (realtime-encode: OOM avoidance, no hibernate) ---------
if [ "$HOST_MEM_MB" -le 768 ]; then SWAP_MB=2048; ZRAM_MB=256
elif [ "$HOST_MEM_MB" -le 1536 ]; then SWAP_MB=2048; ZRAM_MB=512
elif [ "$HOST_MEM_MB" -le 3072 ]; then SWAP_MB=4096; ZRAM_MB=1024
elif [ "$HOST_MEM_MB" -le 6144 ]; then SWAP_MB=4096; ZRAM_MB=2048
elif [ "$HOST_MEM_MB" -gt 0 ]; then SWAP_MB=4096; ZRAM_MB=4096
else SWAP_MB=2048; ZRAM_MB=512
fi

# --- 0. Disk-space guard (need swap + 20% headroom) ---------------------------
FREE_MB="$(df -kP / 2>/dev/null | awk 'NR==2{print int($4/1024)}' || true)"
case "$FREE_MB" in ''|*[!0-9]*) FREE_MB=0 ;; esac
if [ "$FREE_MB" -lt "$((SWAP_MB + SWAP_MB / 5))" ]; then
  log "WARNING: only ${FREE_MB}MB free on /, want $((SWAP_MB + SWAP_MB / 5))MB. Swapfile may be skipped below."
fi

# --- 1. Portable swapfile ------------------------------------------------------
SWAPFILE="/swapfile"
create_swapfile() {
  case "$HOST_ROOT_FSTYPE" in
    tmpfs|overlay*|overlayfs|aufs|zfs|fuse*) log "SKIP disk swap: fstype=$HOST_ROOT_FSTYPE (container/overlay)."; return 77 ;;
  esac
  if [ "$HOST_CONTAINER" = "yes" ]; then
    # Try once (privileged LXC may allow); failure is cleaned and skipped.
    log "Container detected: attempting swapon once, will skip on denial."
  fi
  $SUDO swapoff "$SWAPFILE" 2>/dev/null || true
  $SUDO rm -f "$SWAPFILE"
  if [ "$HOST_ROOT_FSTYPE" = "btrfs" ]; then
    KMAJ="$(uname -r | cut -d. -f1)"
    if [ "${KMAJ:-0}" -lt 5 ] || ! btrfs filesystem df / 2>/dev/null | grep -q "Data, single"; then
      log "SKIP btrfs swap: needs kernel>=5.0 single-device single profile."; return 77
    fi
    $SUDO touch "$SWAPFILE" && $SUDO chattr +C "$SWAPFILE" || return 1
    $SUDO chattr +m "$SWAPFILE" 2>/dev/null || true
    $SUDO fallocate -l "${SWAP_MB}M" "$SWAPFILE" 2>/dev/null || $SUDO dd if=/dev/zero "of=$SWAPFILE" bs=1M "count=$SWAP_MB" status=none || return 1
  elif [ "$HOST_ROOT_FSTYPE" = "xfs" ]; then
    $SUDO dd if=/dev/zero "of=$SWAPFILE" bs=1M "count=$SWAP_MB" status=none || return 1
  else
    $SUDO fallocate -l "${SWAP_MB}M" "$SWAPFILE" 2>/dev/null || $SUDO dd if=/dev/zero "of=$SWAPFILE" bs=1M "count=$SWAP_MB" status=none || return 1
  fi
  $SUDO chmod 600 "$SWAPFILE"
  $SUDO mkswap -f "$SWAPFILE" >/dev/null || { $SUDO rm -f "$SWAPFILE"; return 1; }
  if ! $SUDO swapon "$SWAPFILE" 2>/tmp/quran_swapon.err; then
    if grep -q "holes\|Invalid argument" /tmp/quran_swapon.err 2>/dev/null; then
      log "swapfile has holes (fallocate artifact), retrying once with dd..."
      $SUDO rm -f "$SWAPFILE"
      $SUDO dd if=/dev/zero "of=$SWAPFILE" bs=1M "count=$SWAP_MB" status=none && $SUDO chmod 600 "$SWAPFILE" && $SUDO mkswap -f "$SWAPFILE" >/dev/null && $SUDO swapon "$SWAPFILE" || { $SUDO rm -f "$SWAPFILE"; return 1; }
    else
      log "SKIP disk swap: swapon denied (container/seccomp?)."; $SUDO rm -f "$SWAPFILE"; return 77
    fi
  fi
  grep -qF "$SWAPFILE" /etc/fstab 2>/dev/null || echo "$SWAPFILE none swap sw 0 0" | $SUDO tee -a /etc/fstab >/dev/null
  log "Swapfile ready: ${SWAP_MB}MB at $SWAPFILE."
}
if [ "$HOST_SWAP_MB" -ge "$SWAP_MB" ]; then
  log "Swap already sufficient (${HOST_SWAP_MB}MB >= ${SWAP_MB}MB), skipping creation."
else
  create_swapfile || log "Disk swap unavailable here; continuing with RAM+zram only."
fi

# --- 2. zram (generator -> manual sysfs -> skip) --------------------------------
setup_zram() {
  if [ "$HOST_CONTAINER" = "yes" ]; then log "SKIP zram: container (no CAP_SYS_MODULE/ADMIN)."; return 77; fi
  if [ "$HOST_HAVE_ZRAM" = "1" ]; then log "zram: /dev/zram0 already present."; return 0; fi
  if ! $SUDO modprobe zram num_devices=1 2>/tmp/quran_modprobe.err; then
    log "SKIP zram: $(head -1 /tmp/quran_modprobe.err 2>/dev/null || echo modprobe failed)"; return 77
  fi
  [ -e /sys/block/zram0/disksize ] || { log "SKIP zram: no sysfs node after modprobe."; return 77; }
  # lzo-rle: lowest swap-fault stall on stolen CPUs (zstd only if idle CPU proven)
  if [ "$HOST_SYSTEMD" = "yes" ] && { command -v zram-generator >/dev/null 2>&1 || [ -x /usr/lib/systemd/zram-generator ]; }; then
    $SUDO mkdir -p /etc/systemd
    $SUDO tee /etc/systemd/zram-generator.conf >/dev/null <<EOF
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = lzo-rle
swap-priority = 100
EOF
    $SUDO systemctl daemon-reload >>"$LOG" 2>&1 || true
    $SUDO systemctl restart systemd-zram-setup@zram0.service >>"$LOG" 2>&1 || /usr/lib/systemd/zram-generator >>"$LOG" 2>&1 || true
    swapon --show 2>/dev/null | grep -q zram && { log "zram: generator path active."; return 0; }
  fi
  if command -v rc-service >/dev/null 2>&1 && [ -f /etc/conf.d/zram-init ]; then
    $SUDO sed -i 's/^num_devices=.*/num_devices=1/; s/^type0=.*/type0=swap/' /etc/conf.d/zram-init 2>/dev/null || true
    grep -q "^size0=" /etc/conf.d/zram-init 2>/dev/null || echo "size0=${ZRAM_MB}" | $SUDO tee -a /etc/conf.d/zram-init >/dev/null
    $SUDO rc-service zram-init start >>"$LOG" 2>&1 && $SUDO rc-update add zram-init boot >>"$LOG" 2>&1 && { log "zram: OpenRC path active."; return 0; }
  fi
  # Manual sysfs: no packages needed, any init
  $SUDO swapoff /dev/zram0 2>/dev/null || true
  echo 1 | $SUDO tee /sys/block/zram0/reset >/dev/null 2>&1 || true
  if grep -q lzo-rle /sys/block/zram0/comp_algorithm 2>/dev/null; then
    echo "lzo-rle" | $SUDO tee /sys/block/zram0/comp_algorithm >/dev/null 2>&1 || true
  fi
  if echo "${ZRAM_MB}M" | $SUDO tee /sys/block/zram0/disksize >/dev/null 2>&1 && $SUDO mkswap -U clear /dev/zram0 >/dev/null 2>&1 && $SUDO swapon --discard --priority 100 /dev/zram0 >>"$LOG" 2>&1; then
    log "zram: manual sysfs path active (${ZRAM_MB}MB lzo-rle, prio 100)."
  else
    log "SKIP zram: manual sysfs path failed."; return 77
  fi
}
setup_zram || log "Continuing without zram (disk swap / RAM only)."
swapon --show --output=NAME,TYPE,SIZE,USED,PRIO 2>/dev/null | tee -a "$LOG" || true

# --- 2b. Swap priority ladder: zram (100) > disk files (10) --------------------
# Guarantees the kernel fills compressed RAM before touching disk (this is what
# cuts the 12-20% iowait). Re-applies on every run: existing disk swaps created
# earlier with default prio get demoted once zram is confirmed active.
if swapon --show=NAME,PRIO 2>/dev/null | awk '$1 ~ /^\/dev\/zram/ {found=1} END{exit !found}'; then
  while read -r name _prio; do
    case "$name" in
      NAME|/dev/zram*) continue ;;
      /swapfile|/swap.img|/dev/*)
        $SUDO swapoff "$name" >>"$LOG" 2>&1 || continue
        $SUDO swapon -p 10 "$name" >>"$LOG" 2>&1 || $SUDO swapon "$name" >>"$LOG" 2>&1 || true
        log "swap: $name demoted to prio 10 (zram first)."
        ;;
    esac
  done < <(swapon --show=NAME,PRIO 2>/dev/null | tail -n +2)
fi

# --- 3. sysctl (test-write WITH sudo; containers keep host values) ------------------
# NOTE: the writability test itself must run privileged: an unprivileged
# [ -w ... ] check is always false even when sudo would succeed.
$SUDO cp "$BASE_DIR/config/99-quran-rt.conf" /etc/sysctl.d/99-quran-rt.conf 2>/dev/null || log "sysctl: cannot write /etc/sysctl.d (read-only?), trying live keys only."
if $SUDO sysctl -w vm.swappiness=20 >/dev/null 2>&1; then
  $SUDO sysctl --system >>"$LOG" 2>&1 || $SUDO sysctl -p /etc/sysctl.d/99-quran-rt.conf >>"$LOG" 2>&1 || true
  log "sysctl: 99-quran-rt.conf applied."
else
  log "SKIP sysctl vm.*: denied (container/seccomp?) - leaving host values."
fi
$SUDO sysctl -w net.core.somaxconn=1024 >/dev/null 2>&1 || true

# --- 3a. IPv4 preference on IPv4-only hosts --------------------------------------
# Cloud VCNs are often IPv4-only (no global ::/0 route): getaddrinfo then
# returns AAAA first and every connect burns timeouts/fails (seen live with
# YouTube RTMP ingest). Detect and pin IPv4-first via gai.conf.
if command -v ip >/dev/null 2>&1 && ! ip -6 route show 2>/dev/null | grep -qv '^fe80'; then
  printf '# Prefer IPv4: no global IPv6 route on this host (IPv4-only network)\nprecedence ::ffff:0:0/96  100\n' | $SUDO tee /etc/gai.conf >/dev/null
  log "Network: no global IPv6, pinned IPv4-first (gai.conf)."
else
  log "Network: global IPv6 present (or ip(8) missing), leaving resolver order."
fi

# --- 3b. BBR congestion control (lossy-path RTMP stability) ----------------------# Applied ONLY when the running kernel offers it (cloud kernels usually do).
# fq qdisc is required for BBR pacing; both guarded, reverted silently if absent.
if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
  $SUDO sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 || true
  $SUDO sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || true
  $SUDO mkdir -p /etc/sysctl.d
  printf '[QuranLive BBR]\nnet.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n' | $SUDO tee /etc/sysctl.d/98-quran-bbr.conf >/dev/null
  log "BBR+FQ enabled for uplink stability."
else
  log "SKIP BBR: kernel lacks tcp_bbr (keeping cubic)."
fi

# --- 4. journald tiny+volatile (systemd only) ------------------------------------
if [ "$HOST_SYSTEMD" = "yes" ]; then
  $SUDO mkdir -p /etc/systemd/journald.conf.d
  $SUDO tee /etc/systemd/journald.conf.d/00-quran-tiny.conf >/dev/null <<'EOF'
[Journal]
Storage=volatile
RuntimeMaxUse=16M
RuntimeMaxFileSize=8M
RuntimeKeepFree=64M
SystemMaxUse=16M
SystemMaxFileSize=8M
RateLimitIntervalSec=30s
RateLimitBurst=200
Compress=yes
ForwardToSyslog=no
ForwardToWall=no
MaxRetentionSec=2day
EOF
  $SUDO rm -rf /var/log/journal
  $SUDO systemctl restart systemd-journald >>"$LOG" 2>&1 || true
  log "journald: volatile 16M applied."
else
  log "SKIP journald: no systemd."
fi

# --- 5. Safe service audit (systemd only; ssh/cloud-init/console untouched) ------
if [ "$HOST_SYSTEMD" = "yes" ]; then
  for unit in multipathd.service multipathd.socket apport.service whoopsie.service \
    motd-news.timer apt-daily.timer apt-daily-upgrade.timer \
    update-notifier-download.timer update-notifier-motd.timer apt-news.service esm-cache.service \
    irqbalance.service thermald.service power-profiles-daemon.service bluetooth.service \
    ModemManager.service cups.service cups-browsed.service avahi-daemon.service udisks2.service \
    fwupd-refresh.timer packagekit.service smartd.service atd.service; do
    $SUDO systemctl disable --now "$unit" >>"$LOG" 2>&1 || true
  done
  $SUDO systemctl mask motd-news.timer apt-daily.timer apt-daily-upgrade.timer update-notifier-download.timer update-notifier-motd.timer >>"$LOG" 2>&1 || true
  $SUDO sed -i 's/^ENABLED=.*/ENABLED=0/' /etc/default/motd-news 2>/dev/null || true
  $SUDO tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<'EOF'
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
EOF
  log "services: audit pass finished (ssh/cloud-init/console units untouched)."
else
  log "SKIP service audit: no systemd (use your init's tools if needed)."
fi

# --- 6. SSH OOM protection -------------------------------------------------------
if [ "$HOST_SYSTEMD" = "yes" ]; then
  $SUDO mkdir -p /etc/systemd/system/ssh.service.d /etc/systemd/system/sshd.service.d
  printf '[Service]\nOOMScoreAdjust=-900\n' | $SUDO tee /etc/systemd/system/ssh.service.d/oom.conf >/dev/null
  printf '[Service]\nOOMScoreAdjust=-900\n' | $SUDO tee /etc/systemd/system/sshd.service.d/oom.conf >/dev/null
  $SUDO systemctl daemon-reload >>"$LOG" 2>&1 || true
  $SUDO systemctl restart ssh.service >>"$LOG" 2>&1 || $SUDO systemctl restart sshd.service >>"$LOG" 2>&1 || log "services: ssh restart skipped (protected on next restart)."
  log "ssh: OOMScoreAdjust=-900 installed."
else
  log "SKIP ssh OOM unit: no systemd."
fi

log "=== tune_system finished (virt=$HOST_VIRT). Verify: swapon --show; sysctl vm.swappiness ==="
