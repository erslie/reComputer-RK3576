#!/usr/bin/env bash
# verify-blobs.sh — ブート領域ダンプ/ブロブを既知の基準ハッシュと照合
# 使い方:
#   ./scripts/verify-blobs.sh                 # 基準ハッシュ表＋data/downloads内ブロブの再確認
#   ./scripts/verify-blobs.sh <file> [file..] # 指定ファイルのsha256を計算し基準と突合
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 既知の基準ハッシュ（armbian/rkbin master より取得, OSINTレポート参照）
declare -A KNOWN=(
  ["rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.12.bin"]="17f54933f87d22f72a7c7c548b1d0c79cf804824064c626be25d42d6863b831f"
  ["rk3576_bl31_v1.24.elf"]="e2cf4e0e920dfe1daa6412c05f49dc7e5c0f9888d3a3e8eecc85fbe1e86a23d1"
)

sha() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

echo "===== 既知の基準ハッシュ (L2照合用) ====="
for k in "${!KNOWN[@]}"; do printf '  %-48s %s\n' "$k" "${KNOWN[$k]}"; done

check_one() {
  local f="$1" base h status
  base="$(basename "$f")"
  [ -f "$f" ] || { printf '  [?] %s (ファイル無し)\n' "$f"; return; }
  h="$(sha "$f")"
  if [ -n "${KNOWN[$base]:-}" ]; then
    if [ "$h" = "${KNOWN[$base]}" ]; then status="[OK 一致=配布物のまま]"; else status="[!! 不一致=要追跡]"; fi
    printf '  %s %s\n      got=%s\n' "$status" "$base" "$h"
  else
    printf '  [i] %s (基準表に無し) sha256=%s\n' "$base" "$h"
  fi
}

echo
if [ $# -ge 1 ]; then
  echo "===== 指定ファイルの照合 ====="
  for f in "$@"; do check_one "$f"; done
else
  echo "===== data/downloads の基準ブロブ再確認 ====="
  for base in "${!KNOWN[@]}"; do check_one "$REPO_ROOT/data/downloads/$base"; done
  echo
  echo "[ヒント] 実機ダンプ例:"
  echo "  tools/rkdeveloptool ld"
  echo "  tools/rkdeveloptool rl 0 0x4000 workdir/dump/boot_head.img"
  echo "  ./scripts/verify-blobs.sh workdir/dump/*.img"
  echo "  binwalk workdir/dump/boot_head.img   # 中身の素性確認"
fi
