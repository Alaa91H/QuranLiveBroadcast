#!/bin/bash
# ==============================================================================
# Quran Live Stream — Host Detector
# Fast (<2s), no network, no side effects. Prints KEY=VALUE lines describing
# the machine so first_boot/benchmark/provision can adapt to ANY server:
# bare metal, KVM/Xen/VMware VM, LXC/OpenVZ, Docker/Podman, any distro.
# Usage: eval "$(scripts/detect_host.sh)"   or   scripts/detect_host.sh
# ==============================================================================
set -euo pipefail

VIRT="unknown"; CONT="no"; IS_SYSTEMD="no"
[ -d /run/systemd/system ] && [ "$(cat /proc/1/comm 2>/dev/null || echo ?)" = "systemd" ] && IS_SYSTEMD="yes"

# Ordered cascade: cheap files first; systemd-detect-virt LAST (misses Docker,
# and --vm pierces containers by design).
if [ -f /.dockerenv ]; then VIRT="docker"; CONT="yes"
elif [ -f /run/.containerenv ]; then
  CONT="yes"
  if grep -qa "podman" /run/.containerenv 2>/dev/null; then VIRT="podman"; else VIRT="docker"; fi
elif [ -n "${container:-}" ]; then
  CONT="yes"; VIRT="$container"
elif [ -f /proc/vz/veinfo ] || [ -d /proc/vz ] || [ -f /proc/bc/0 ]; then VIRT="openvz"; CONT="yes"
elif grep -qaE "docker|kubepods|containerd" /proc/1/cgroup 2>/dev/null; then VIRT="docker"; CONT="yes"
elif grep -qaE "/lxc/|machine.slice.*lxc|lxc-libvirt" /proc/1/cgroup 2>/dev/null; then VIRT="lxc"; CONT="yes"
elif grep -qaE "vz|virtuozzo|openvz" /proc/1/cgroup 2>/dev/null; then VIRT="openvz"; CONT="yes"
elif [ "$(cat /proc/1/comm 2>/dev/null || echo ?)" != "systemd" ] && [ "$(cat /proc/1/comm 2>/dev/null || echo ?)" != "init" ]; then
  CONT="yes"
  if grep -qa "docker" /proc/self/cgroup 2>/dev/null; then VIRT="docker"; else VIRT="unknown-container"; fi
elif command -v systemd-detect-virt >/dev/null 2>&1; then
  if systemd-detect-virt --container >/dev/null 2>&1; then CONT="yes"; VIRT="$(systemd-detect-virt --container 2>/dev/null || echo unknown-container)"
  elif systemd-detect-virt --vm >/dev/null 2>&1; then VIRT="$(systemd-detect-virt --vm 2>/dev/null || echo unknown)"; CONT="no"
  else VIRT="bare"; CONT="no"; fi
fi
if { [ "$CONT" = "no" ] && [ "$VIRT" = "bare" ]; } || [ "$VIRT" = "unknown" ]; then
  PROD="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo) $(cat /sys/class/dmi/id/product_name 2>/dev/null || echo)"
  case "$PROD" in
    *KVM*|*QEMU*|*Bochs*|*Google*|*Amazon*EC2*) VIRT="kvm" ;;
    *VMware*) VIRT="vmware" ;;
    *Xen*) VIRT="xen" ;;
    *Microsoft*Hyper-V*) VIRT="hyperv" ;;
    *VirtualBox*) VIRT="vbox" ;;
  esac
fi

# Resources (POSIX-safe, numeric-sanitized)
MEM_MB="$(awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
case "$MEM_MB" in ''|*[!0-9]*) MEM_MB=0 ;; esac
CPU_N="$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 0)"
case "$CPU_N" in ''|*[!0-9]*) CPU_N=0 ;; esac
DISK_AVAIL_MB="$(df -kP / 2>/dev/null | awk 'NR==2{print int($4/1024)}' || true)"
case "$DISK_AVAIL_MB" in ''|*[!0-9]*) DISK_AVAIL_MB=0 ;; esac
ROOT_FSTYPE="$(stat -f -c %T / 2>/dev/null || echo unknown)"
KERNEL="$(uname -r 2>/dev/null || echo unknown)"
ARCH="$(uname -m 2>/dev/null || echo unknown)"

# Hardware encoders (presence only; runtime smoke-test decides usability)
HW_NVENC=0; HW_VAAPI=0; HW_QSV=0
if command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -hide_banner -encoders 2>/dev/null | grep -q ' h264_nvenc ' && HW_NVENC=1 || true
  ffmpeg -hide_banner -encoders 2>/dev/null | grep -q ' h264_vaapi ' && HW_VAAPI=1 || true
  ffmpeg -hide_banner -encoders 2>/dev/null | grep -q ' h264_qsv ' && HW_QSV=1 || true
fi
HAVE_DRI=0
ls /dev/dri/renderD* >/dev/null 2>&1 && HAVE_DRI=1 || true
HAVE_NVIDIA=0
command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1 && HAVE_NVIDIA=1 || true

# Existing swap/zram (informational; provisioner acts)
SWAP_TOTAL_MB="$(awk '/^SwapTotal:/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
HAVE_ZRAM=0
[ -b /dev/zram0 ] && HAVE_ZRAM=1 || true

# Confidential computing mode (memory encryption). Ordered cascade, best
# effort (dmesg may be restricted for unprivileged users; every step guarded).
# Values: none | sme (BM host transparent encryption) | sev | sev-es | sev-snp
# | tdx | cca. On OCI: AMD-only (E3/E4 SEV, E5/E6 SEV-SNP, BM TSME/SME).
CC_MODE="none"; CC_DETAIL=""
if command -v systemd-detect-virt >/dev/null 2>&1; then
  CC_DET="$(systemd-detect-virt --cvm 2>/dev/null || true)"
  case "$CC_DET" in
    sev-snp) CC_MODE="sev-snp"; CC_DETAIL="detect-virt" ;;
    sev-es) CC_MODE="sev-es"; CC_DETAIL="detect-virt" ;;
    sev) CC_MODE="sev"; CC_DETAIL="detect-virt" ;;
    tdx) CC_MODE="tdx"; CC_DETAIL="detect-virt" ;;
    cca) CC_MODE="cca"; CC_DETAIL="detect-virt" ;;
  esac
fi
if [ "$CC_MODE" = "none" ]; then
  if [ -e /dev/sev-guest ]; then CC_MODE="sev-snp"; CC_DETAIL="/dev/sev-guest"
  elif [ -e /dev/tdx_guest ] || [ -e /dev/tdx-guest ]; then CC_MODE="tdx"; CC_DETAIL="tdx device node"
  fi
fi
if [ "$CC_MODE" = "none" ]; then
  KMSG="$(dmesg 2>/dev/null | grep -iE 'Memory Encryption Features active|SEV:|tdx: Guest|sev-guest|Secure Encrypted Virtualization' | head -5 || true)"
  case "$KMSG" in
    *SEV-SNP*|*sev-snp*) CC_MODE="sev-snp"; CC_DETAIL="dmesg" ;;
    *SEV-ES*|*sev-es*) CC_MODE="sev-es"; CC_DETAIL="dmesg" ;;
    *SEV*|*sev*) CC_MODE="sev"; CC_DETAIL="dmesg" ;;
    *TDX*|*tdx*) CC_MODE="tdx"; CC_DETAIL="dmesg" ;;
    *SME*|*TSME*) CC_MODE="sme"; CC_DETAIL="dmesg" ;;
  esac
fi
if [ "$CC_MODE" = "none" ]; then
  CPUFLAGS="$(grep -o -m1 'sme\|sev_snp\|sev_es\|tdx_guest' /proc/cpuinfo 2>/dev/null | head -1 || true)"
  case "$CPUFLAGS" in
    sev_snp) CC_MODE="sev-snp"; CC_DETAIL="cpuinfo" ;;
    sev_es) CC_MODE="sev-es"; CC_DETAIL="cpuinfo" ;;
    tdx_guest) CC_MODE="tdx"; CC_DETAIL="cpuinfo" ;;
    sme) CC_MODE="sme"; CC_DETAIL="cpuinfo" ;;
  esac
fi

# Distro (best-effort; command-existence wins in provisioner)
DISTRO="unknown"; DISTRO_LIKE=""
if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release 2>/dev/null || true
  DISTRO="${ID:-unknown}"; DISTRO_LIKE="${ID_LIKE:-}"
fi

cat <<EOF
HOST_VIRT=$VIRT
HOST_CONTAINER=$CONT
HOST_SYSTEMD=$IS_SYSTEMD
HOST_MEM_MB=$MEM_MB
HOST_CPU_N=$CPU_N
HOST_DISK_AVAIL_MB=$DISK_AVAIL_MB
HOST_ROOT_FSTYPE=$ROOT_FSTYPE
HOST_KERNEL=$KERNEL
HOST_ARCH=$ARCH
HOST_HW_NVENC=$HW_NVENC
HOST_HW_VAAPI=$HW_VAAPI
HOST_HW_QSV=$HW_QSV
HOST_HAVE_DRI=$HAVE_DRI
HOST_HAVE_NVIDIA=$HAVE_NVIDIA
HOST_SWAP_MB=$SWAP_TOTAL_MB
HOST_HAVE_ZRAM=$HAVE_ZRAM
HOST_DISTRO=$DISTRO
HOST_CC=$CC_MODE
HOST_CC_DETAIL=$CC_DETAIL
EOF
