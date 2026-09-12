#!/bin/bash
# ==============================================================================
# Quran Live Stream — Browser Installer (arch-aware, idempotent)
# Ensures a working Chromium-family browser for the kiosk capture:
#   1. Reuses any working binary (CHROME_BIN override, google-chrome,
#      chromium-browser, chromium) after a --version smoke test.
#   2. aarch64/x86_64: official Google Chrome .deb (ARM64 builds exist since
#      Jul 2026: google-chrome-stable_current_arm64.deb).
#   3. Fallback: distro chromium (Ubuntu: transitional snap package).
#   4. Verifies with --headless --dump-dom (no X server needed for the test).
# Needs root/sudo for installation. Skips install attempts in containers
# without a package manager; still verifies existing binaries there.
# Usage: install_browser.sh
# ==============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$BASE_DIR/logs/install_browser.log"
mkdir -p "$(dirname "$LOG")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [BROWSER] $*" | tee -a "$LOG"
}

smoke() {
  # $1 = binary; true when it reports a version AND headless dump-dom works
  [ -n "${1:-}" ] || return 1
  command -v "$1" >/dev/null 2>&1 || [ -x "$1" ] || return 1
  "$1" --version >>"$LOG" 2>&1 || return 1
  timeout 30 "$1" --headless --no-sandbox --disable-gpu --dump-dom about:blank >>"$LOG" 2>&1 || return 1
  return 0
}

# 1. Existing binary (explicit override wins for snap/playwright paths)
for cand in "${CHROME_BIN:-}" google-chrome chromium-browser chromium; do
  [ -z "$cand" ] && continue
  if smoke "$cand"; then
    log "Usable browser already present: $cand ($("$cand" --version 2>/dev/null))."
    exit 0
  fi
done

# Need installation from here on
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo -n"
  sudo -n true 2>/dev/null || { log "ERROR: need root or passwordless sudo to install a browser."; exit 1; }
fi
command -v curl >/dev/null 2>&1 || { log "ERROR: curl missing (run install_deps.sh first)."; exit 1; }

ARCH="$(uname -m 2>/dev/null || echo unknown)"
TMPDEB="/tmp/quran-chrome.deb"

# 2. Official Google Chrome .deb (amd64 + arm64 since Jul 2026)
CHROME_URL=""
case "$ARCH" in
  x86_64|amd64) CHROME_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" ;;
  aarch64|arm64) CHROME_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_arm64.deb" ;;
  *) log "Unsupported arch for official .deb: $ARCH, trying distro chromium." ;;
esac
if [ -n "$CHROME_URL" ]; then
  log "Downloading official Chrome ($ARCH)..."
  if curl -sSL --connect-timeout 10 --max-time 120 -o "$TMPDEB" "$CHROME_URL" >>"$LOG" 2>&1 \
    && [ "$(stat -c%s "$TMPDEB" 2>/dev/null || stat -f%z "$TMPDEB" 2>/dev/null || echo 0)" -gt 50000000 ]; then
    log "Installing $TMPDEB (adds Google apt repo for updates)..."
    if command -v apt-get >/dev/null 2>&1; then
      $SUDO apt-get install -y "$TMPDEB" >>"$LOG" 2>&1 || $SUDO dpkg -i "$TMPDEB" >>"$LOG" 2>&1 || true
      $SUDO apt-get install -f -y >>"$LOG" 2>&1 || true
    elif command -v dnf >/dev/null 2>&1; then
      $SUDO dnf install -y "$TMPDEB" >>"$LOG" 2>&1 || true
    fi
    rm -f "$TMPDEB"
    if smoke google-chrome; then
      log "Official Chrome installed and verified: $(google-chrome --version)."
      exit 0
    fi
    log "Official .deb did not yield a working binary, falling back to distro chromium."
  else
    log "Chrome .deb download failed, falling back to distro chromium."
    rm -f "$TMPDEB"
  fi
fi

# 3. Distro chromium (Ubuntu 19.10+: transitional snap package, arm64 OK)
log "Installing distro chromium..."
if command -v apt-get >/dev/null 2>&1; then
  $SUDO apt-get install -y chromium-browser >>"$LOG" 2>&1 || true
  # Snap seeding can lag on first boot; wait for it briefly (apt path only)
  if command -v snap >/dev/null 2>&1; then
    for i in $(seq 1 12); do
      snap list chromium >>"$LOG" 2>&1 && break
      sleep 10
    done
  fi
elif command -v dnf >/dev/null 2>&1; then
  $SUDO dnf install -y chromium >>"$LOG" 2>&1 || true
elif command -v yum >/dev/null 2>&1; then
  $SUDO yum install -y chromium >>"$LOG" 2>&1 || true
elif command -v apk >/dev/null 2>&1; then
  $SUDO apk add --no-cache chromium >>"$LOG" 2>&1 || true
elif command -v pacman >/dev/null 2>&1; then
  $SUDO pacman -Sy --noconfirm --needed chromium >>"$LOG" 2>&1 || true
fi

for cand in google-chrome chromium-browser chromium; do
  if smoke "$cand"; then
    log "Browser ready: $cand ($("$cand" --version 2>/dev/null))."
    exit 0
  fi
done

log "ERROR: no working browser after all methods. Last resort: set CHROME_BIN to a manual install (e.g. Playwright chromium) and re-run."
exit 1
