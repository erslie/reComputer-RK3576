#!/usr/bin/env bash
# setup-macos.sh — reComputer RK3576 調査用の macOS 環境構築
# 使い方: ./scripts/setup-macos.sh
# 冪等。既に入っているものはスキップする。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$REPO_ROOT/tools"
WORK_DIR="$REPO_ROOT/workdir"

info() { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "このスクリプトは macOS 専用です。"

# --- 1. Homebrew ---
if ! command -v brew >/dev/null 2>&1; then
  warn "Homebrew が見つかりません。先に導入してください:"
  echo '    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  die "Homebrew 導入後に再実行してください。"
fi
ok "Homebrew あり: $(brew --version | head -1)"

# --- 2. CLI ツール ---
FORMULAE=(tio picocom libusb pkg-config autoconf automake binwalk gnupg coreutils wget)
info "CLIツールを確認/導入: ${FORMULAE[*]}"
for f in "${FORMULAE[@]}"; do
  if brew list --formula "$f" >/dev/null 2>&1; then
    ok "$f は導入済み"
  else
    info "$f を導入..."; brew install "$f"
  fi
done

# --- 3. GUI/大物 (cask) ---
for c in wireshark docker; do
  if brew list --cask "$c" >/dev/null 2>&1; then
    ok "$c (cask) は導入済み"
  else
    info "$c を導入 (管理者パスワードを求められる場合あり)..."
    brew install --cask "$c" || warn "$c の導入に失敗。手動で: brew install --cask $c"
  fi
done

# --- 4. rkdeveloptool をソースビルド ---
mkdir -p "$TOOLS_DIR"
if [ -x "$TOOLS_DIR/rkdeveloptool" ]; then
  ok "rkdeveloptool は既にビルド済み: $TOOLS_DIR/rkdeveloptool"
else
  info "rkdeveloptool をソースビルド..."
  SRC="$TOOLS_DIR/rkdeveloptool-src"
  rm -rf "$SRC"
  git clone --depth 1 https://github.com/rockchip-linux/rkdeveloptool "$SRC"
  (
    cd "$SRC"
    # Apple Silicon の Homebrew パスを通す
    export PKG_CONFIG_PATH="$(brew --prefix libusb)/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
    export CPPFLAGS="-I$(brew --prefix libusb)/include ${CPPFLAGS:-}"
    export LDFLAGS="-L$(brew --prefix libusb)/lib ${LDFLAGS:-}"
    autoreconf -i
    ./configure
    make
  )
  cp "$SRC/rkdeveloptool" "$TOOLS_DIR/rkdeveloptool"
  ok "rkdeveloptool: $TOOLS_DIR/rkdeveloptool"
fi

# --- 5. 作業ディレクトリ ---
mkdir -p "$WORK_DIR"/{ref,dump,pcap,logs}
ok "作業ディレクトリ: $WORK_DIR/{ref,dump,pcap,logs}"

cat <<EOF

================= 完了 =================
次の手順:
  1) ハード : ./scripts/... は不要。FTDI接続後  tio -b 1500000 /dev/tty.usbserial-XXXX
  2) ネット : System Settings > Sharing > Internet Sharing を有効化 → ./scripts/net-capture.sh 1800
  3) OS     : ./scripts/os-audit.sh user@<RK3576_IP>
  4) ファーム: ./scripts/verify-blobs.sh
ツール: $TOOLS_DIR/rkdeveloptool
参照イメージは workdir/ref/ に置いてください (armbian.com の recomputer-rk3576-devkit)。
=======================================
EOF
