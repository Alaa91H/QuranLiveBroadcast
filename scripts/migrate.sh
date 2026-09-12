#!/bin/bash
# ==============================================================================
# Quran Live Stream — Server Migrator (fast rebuild on a new box)
# export: packs NON-SECRET state into a 600-perm tarball.
#   - INCLUDES .env (stream keys!) -> transfer securely, chmod 600, delete after
# Usage: migrate.sh export [outdir] | migrate.sh import <tarball>
# ==============================================================================
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

cmd="${1:-help}"
if [ "$cmd" = "export" ]; then
  OUTDIR="${2:-$BASE_DIR}"
  STAMP="$(date '+%Y-%m-%d_%H%M')"
  TAR="$OUTDIR/quran-migrate-$STAMP.tar.gz"
  tar -czf "$TAR" \
    .env config/ \
    systemd/ \
    runtime/host.env runtime/net.env runtime/preflight.env \
    2>/dev/null || {
    echo "Export partially failed (missing files skipped above). Still wrote: $TAR"
  }
  chmod 600 "$TAR"
  echo "Exported (600 perms, CONTAINS SECRETS - move securely, delete after import):"
  echo "  $TAR"
  tar -tzf "$TAR"
elif [ "$cmd" = "import" ]; then
  TAR="${2:-}"
  [ -f "$TAR" ] || { echo "Usage: $0 import <tarball>"; exit 1; }
  tar -xzf "$TAR" -C "$BASE_DIR"
  chmod 600 "$BASE_DIR/.env" 2>/dev/null || true
  echo "Imported. Next: scripts/setup_cron.sh && scripts/control.sh prepare && scripts/control.sh start"
else
  echo "Usage: $0 {export [outdir]|import <tarball>}"
  exit 1
fi
