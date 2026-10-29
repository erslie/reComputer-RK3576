#!/usr/bin/env bash
# verify-blobs.sh - compare boot-region dumps / blobs against known-good reference hashes.
# Usage:
#   ./scripts/verify-blobs.sh                 # print the reference table and re-check blobs in data/downloads
#   ./scripts/verify-blobs.sh <file> [file..] # hash the given files and compare against the reference
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Known-good reference hashes (taken from armbian/rkbin master; see the OSINT report)
KNOWN_NAMES=(
  "rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.12.bin"
  "rk3576_bl31_v1.24.elf"
)
KNOWN_HASHES=(
  "17f54933f87d22f72a7c7c548b1d0c79cf804824064c626be25d42d6863b831f"
  "e2cf4e0e920dfe1daa6412c05f49dc7e5c0f9888d3a3e8eecc85fbe1e86a23d1"
)

sha() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }
known_hash() {
  local i
  for i in "${!KNOWN_NAMES[@]}"; do
    [ "${KNOWN_NAMES[$i]}" = "$1" ] && { echo "${KNOWN_HASHES[$i]}"; return 0; }
  done
  return 0
}

echo "===== Known-good reference hashes (for L2 comparison) ====="
for i in "${!KNOWN_NAMES[@]}"; do printf '  %-48s %s\n' "${KNOWN_NAMES[$i]}" "${KNOWN_HASHES[$i]}"; done

check_one() {
  local f="$1" base h known status
  base="$(basename "$f")"
  [ -f "$f" ] || { printf '  [?] %s (file not found)\n' "$f"; return; }
  h="$(sha "$f")"
  known="$(known_hash "$base")"
  if [ -n "$known" ]; then
    if [ "$h" = "$known" ]; then status="[OK match = unchanged from distribution]"; else status="[!! MISMATCH = investigate]"; fi
    printf '  %s %s\n      got=%s\n' "$status" "$base" "$h"
  else
    printf '  [i] %s (not in reference table) sha256=%s\n' "$base" "$h"
  fi
}

echo
if [ $# -ge 1 ]; then
  echo "===== Checking given files ====="
  for f in "$@"; do check_one "$f"; done
else
  echo "===== Re-checking reference blobs in data/downloads ====="
  for base in "${KNOWN_NAMES[@]}"; do check_one "$REPO_ROOT/data/downloads/$base"; done
  echo
  echo "[Hint] Dump from the device, e.g.:"
  echo "  tools/rkdeveloptool ld"
  echo "  tools/rkdeveloptool rl 0 0x4000 workdir/dump/boot_head.img"
  echo "  ./scripts/verify-blobs.sh workdir/dump/*.img"
  echo "  binwalk workdir/dump/boot_head.img   # inspect contents"
fi
