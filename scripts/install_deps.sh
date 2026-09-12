#!/bin/bash
# ==============================================================================
# Quran Live Stream — Dependency Installer (any distro, idempotent)
# Installs the broadcast stack: curl, ffmpeg, Xvfb, node, pulseaudio, psmisc
# (fuser), unzip, cron. Ubuntu 26.04 minimal notably LACKS curl/unzip/cron/
# pulseaudio/psmisc out of the box — this fills exactly those gaps.
# Package manager is detected by command (apt-get/dnf/yum/apk/pacman/zypper),
# never by distro name. Safe to re-run; needs root or passwordless sudo.
# Usage: install_deps.sh
# ==============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$BASE_DIR/logs/install_deps.log"
mkdir -p "$(dirname "$LOG")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEPS] $*" | tee -a "$LOG"
}

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo -n"
  sudo -n true 2>/dev/null || { log "ERROR: need root or passwordless sudo."; exit 1; }
fi

install_pkgs() {
  # $1 = manager tag for logging, rest = packages
  local tag="$1"; shift
  log "Installing via $tag: $*"
  # shellcheck disable=SC2086
  case "$tag" in
    apt) $SUDO apt-get update -qq >>"$LOG" 2>&1 || true
         $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@" >>"$LOG" 2>&1 || log "WARNING: some apt packages failed." ;;
    dnf) $SUDO dnf install -y "$@" >>"$LOG" 2>&1 || log "WARNING: some dnf packages failed." ;;
    yum) $SUDO yum install -y "$@" >>"$LOG" 2>&1 || log "WARNING: some yum packages failed." ;;
    apk) $SUDO apk add --no-cache "$@" >>"$LOG" 2>&1 || log "WARNING: some apk packages failed." ;;
    pacman) $SUDO pacman -Sy --noconfirm --needed "$@" >>"$LOG" 2>&1 || log "WARNING: some pacman packages failed." ;;
    zypper) $SUDO zypper --non-interactive install -y "$@" >>"$LOG" 2>&1 || log "WARNING: some zypper packages failed." ;;
  esac
}

# Downloader first (everything else may need fetching)
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || {
  log "No curl/wget: bootstrapping a downloader..."
  if command -v apt-get >/dev/null 2>&1; then install_pkgs apt curl
  elif command -v dnf >/dev/null 2>&1; then install_pkgs dnf curl
  elif command -v yum >/dev/null 2>&1; then install_pkgs yum curl
  elif command -v apk >/dev/null 2>&1; then install_pkgs apk curl
  elif command -v pacman >/dev/null 2>&1; then install_pkgs pacman curl
  elif command -v zypper >/dev/null 2>&1; then install_pkgs zypper curl
  else log "ERROR: no supported package manager found."; exit 1; fi
}

# Stack packages per manager family (names verified for 26.04/Debian13/RHEL9+/Alpine/Arch)
if command -v apt-get >/dev/null 2>&1; then
  install_pkgs apt curl ffmpeg xvfb nodejs pulseaudio pulseaudio-utils psmisc unzip cron gpgv
elif command -v dnf >/dev/null 2>&1; then
  install_pkgs dnf curl ffmpeg xorg-x11-server-Xvfb nodejs pulseaudio pulseaudio-utils psmisc unzip cronie tar
elif command -v yum >/dev/null 2>&1; then
  install_pkgs yum curl ffmpeg xorg-x11-server-Xvfb nodejs pulseaudio pulseaudio-utils psmisc unzip cronie tar
elif command -v apk >/dev/null 2>&1; then
  install_pkgs apk curl ffmpeg xvfb nodejs pulseaudio pulseaudio-utils psmisc unzip dcron tar bash
elif command -v pacman >/dev/null 2>&1; then
  install_pkgs pacman curl ffmpeg xorg-server-xvfb nodejs pulseaudio pulseaudio-utils psmisc unzip cronie tar
elif command -v zypper >/dev/null 2>&1; then
  install_pkgs zypper curl ffmpeg xvfb nodejs pulseaudio pulseaudio-utils psmisc unzip cron tar
fi

# Linger so user services (pulseaudio, systemd --user units) survive logout
if command -v loginctl >/dev/null 2>&1; then
  $SUDO loginctl enable-linger "$(id -un)" >>"$LOG" 2>&1 || log "linger not enabled (non-systemd?), continuing."
fi

log "--- dependency report ---"
for c in curl ffmpeg Xvfb node pactl fuser unzip cron; do
  if command -v "$c" >/dev/null 2>&1; then
    log "  OK: $c ($("$c" --version 2>/dev/null | head -1))"
  else
    log "  MISSING: $c"
  fi
done
log "install_deps finished."
