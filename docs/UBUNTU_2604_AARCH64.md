# Deploying on Ubuntu 26.04 Minimal aarch64 (e.g. Oracle Ampere A1)

Tested research facts (Sep 2026), not guesses. Canonical name: **Resolute Raccoon**,
kernel 7.0, systemd 259, ffmpeg **8.0**, node 22, `universe` enabled by default,
`snapd` present even on minimal.

## 0. Pick the image (important)

Oracle Cloud **has no 26.04 image yet** (Sep 2026). Two supported paths:

- **A (recommended):** launch `Canonical-Ubuntu-24.04-Minimal-aarch64-*`, then
  `sudo do-release-upgrade` (upgrades to 26.04 opened at 26.04.1, ~Aug 2026).
- **B:** import `cloud-images.ubuntu.com/minimal/releases/resolute` manually.

Free tier note: Always-Free Ampere is now **2 OCPU + 12 GB** (halved Jun 2026),
still plenty (bottleneck is browser RAM, not x264 — verified against Ampere
x264 numbers; the first-boot benchmark self-calibrates anyway).

## 1. One-command setup

```bash
git clone https://github.com/Alaa91H/QuranLiveStream.git ~/quran-live-stream
cd ~/quran-live-stream
cp .env.example .env   # then fill YOUTUBE_STREAM_KEY
./scripts/setup_cron.sh   # installs cron + runs first_boot.sh automatically
```

`first_boot.sh` does, in order: **deps** (curl/ffmpeg/xvfb/node22/pulseaudio/
psmisc/unzip/cron — all missing on minimal) → **browser** (official Chrome
ARM64 `.deb` since Jul 2026, else distro chromium snap) → **provisioning**
(swap/zram/sysctl, container-aware) → **egress probe** → **encode benchmark**
→ static primer. Then:

```bash
./scripts/control.sh prepare   # full download + benchmark + preflight, no stream
./scripts/control.sh start     # preflight verifies, then streams
```

## 2. ARM64 specifics (handled automatically)

| Topic | Handling |
|---|---|
| Browser | `install_browser.sh`: official `google-chrome-stable_current_arm64.deb` → fallback `chromium-browser` (snap, arm64 published). Override: `CHROME_BIN=/path/to/chrome` in `.env` |
| x264 | Identical flags on NEON (no arch caveats); benchmark thresholds are measured, not assumed |
| Audio | `pulseaudio` installed by deps step; file-audio mode (micro default) avoids it entirely at runtime |
| Port free | `stop_ui.sh` uses `fuser` when present, `ss`-based fallback otherwise (psmisc absent on minimal) |
| NVENC/VAAPI/QSV | Auto-detected; NVENC used when smoke-tested, x86-only in practice |
| ffmpeg 8 | `fps_mode`/`aac_coder` probed with `-vsync`/plain-AAC fallback (also covers 22.04's ffmpeg 4.4) |
| BBR | Enabled only if the kernel offers `tcp_bbr`, else stays on cubic |

## 3. After boot

- `runtime/host.env` pins the measured profile; weekly 03:30 maintenance re-tunes.
- `runtime/status.json` has live speed/load/RAM for dashboards.
- Logs rotate at 5 MB; journald is volatile 16 MB.
