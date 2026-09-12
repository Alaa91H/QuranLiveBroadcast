# Confidential Computing shapes (Oracle) — full auto support

No configuration needed: `detect_host.sh` identifies the mode, `benchmark_host.sh`
stores it in `runtime/host.env` (`HOST_CC`), and the encode benchmark **already
includes** the encryption overhead — so the selected profile is correct by
construction. Thresholds are intentionally NOT adjusted for CC.

## The three shapes

| Offering | CPU / RAM | Confidential mode | Notes |
|---|---|---|---|
| Canonical Ubuntu 26.04, BM Confidential | E5/E6 EPYC Genoa/Turin, up to 256 OCPU / 3 TB | AMD TSME host (+ customer SEV-SNP VMs) | Whole-machine transparent encryption |
| Canonical Ubuntu 26.04 Minimal, BM Confidential | Same E5/E6 BM family | AMD TSME host | Same, minimal image |
| Canonical Ubuntu 26.04 Minimal aarch64, BM Confidential | Ampere Altra/One BM (A1/A4) | None on OCI (AMD-only offering) | Runs the standard ARM path |

VM flavors (`VM.Standard.E5/E6.Flex` confidential) appear as `sev-snp` guests;
E3/E4 confidential VMs appear as `sev`. Detection values: `none | sme |
sev | sev-es | sev-snp | tdx | cca`.

## What "Free" means (honest note)

There is **no free bare-metal shape**. Always-Free compute = `VM.Standard.E2.1.Micro`
(AMD 1/8 OCPU, 1 GB) + `VM.Standard.A1.Flex` (Arm, 2 OCPU / 12 GB total).
"Free" in these listings = the **Canonical Ubuntu OS image** (free license vs
paid Marketplace/Windows), or trial credits. BM confidential shapes are billed.

## Images on OCI (status Sep 2026)

26.04 images are **not published on OCI yet**. Use the 24.04 equivalents, then
`sudo do-release-upgrade` (opened at 26.04.1):

- `Canonical-Ubuntu-24.04-2026.07.17-0` (x86_64 server)
- `Canonical-Ubuntu-24.04-Minimal-2026.07.17-0`
- `Canonical-Ubuntu-24.04-Minimal-aarch64-2026.07.17-0`

List current availability any time:

```bash
oci compute image list --all --compartment-id <ocid> \
  --operating-system "Canonical Ubuntu" --operating-system-version "26.04"
```

Expected 26.04 names follow the same pattern
(`Canonical-Ubuntu-26.04-…`, `…-Minimal-…`, `…-Minimal-aarch64-…`).

## Overhead (measured, not feared)

- x264 software encode on SEV-SNP: **~0-5%** steady-state (CPU/vector-bound,
  streaming access), up to ~7% memory-random cases.
- TSME-only BM host: **~0-2%**.
- RMP bookkeeping: ~0.4% of RAM (e.g. ~9 GB on a 2.3 TB E5) — `MemTotal`
  already excludes it, so all RAM caps stay correct automatically.

## What does NOT work (so you don't try)

Nested KVM inside an SEV/SNP guest fails; kexec/kdump are unreliable under SNP;
hibernation is disabled under TDX. **None of this affects the broadcast stack**
(ffmpeg, Chromium, Xvfb, Node, PulseAudio, systemd, cron all run in userspace
unchanged). Confidential shapes cannot be enabled after launch and cannot be
live-migrated — choose at creation.

## Attestation

E5/E6 support bring-your-own attestation (`SNP_GET_REPORT` via `/dev/sev-guest`).
A media app needs nothing: boot confidential and ignore it, unless you gate
secret release on attestation (out of scope for streaming).
