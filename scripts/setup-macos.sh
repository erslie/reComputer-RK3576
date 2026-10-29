#!/usr/bin/env bash
# setup-macos.sh - set up the macOS environment for the reComputer RK3576 investigation.
# Usage: ./scripts/setup-macos.sh
# Idempotent: anything already installed is skipped.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$REPO_ROOT/tools"
WORK_DIR="$REPO_ROOT/workdir"

info() { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "This script is for macOS only."

# --- 1. Homebrew ---
if ! command -v brew >/dev/null 2>&1; then
  warn "Homebrew not found. Install it first:"
  echo '    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  die "Re-run this script after installing Homebrew."
fi
ok "Homebrew present: $(brew --version | head -1)"

# --- 2. CLI tools ---
FORMULAE=(tio picocom libusb pkg-config autoconf automake binwalk gnupg coreutils wget)
info "Checking/installing CLI tools: ${FORMULAE[*]}"
for f in "${FORMULAE[@]}"; do
  if brew list --formula "$f" >/dev/null 2>&1; then
    ok "$f already installed"
  else
    info "Installing $f ..."; brew install "$f"
  fi
done

# --- 3. GUI / large casks ---
for c in wireshark docker; do
  if brew list --cask "$c" >/dev/null 2>&1; then
    ok "$c (cask) already installed"
  else
    info "Installing $c (may prompt for admin password) ..."
    brew install --cask "$c" || warn "Failed to install $c. Install manually: brew install --cask $c"
  fi
done

# --- 4. Build rkdeveloptool from source ---
mkdir -p "$TOOLS_DIR"
if [ -x "$TOOLS_DIR/rkdeveloptool" ]; then
  ok "rkdeveloptool already built: $TOOLS_DIR/rkdeveloptool"
else
  info "Building rkdeveloptool from source ..."
  SRC="$TOOLS_DIR/rkdeveloptool-src"
  rm -rf "$SRC"
  git clone --depth 1 https://github.com/rockchip-linux/rkdeveloptool "$SRC"
  (
    cd "$SRC"
    # Make the Homebrew libusb visible (Apple Silicon prefix differs from Intel)
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

# --- 5. Working directories ---
mkdir -p "$WORK_DIR"/{ref,dump,pcap,logs}
ok "Working directories: $WORK_DIR/{ref,dump,pcap,logs}"

cat <<EOF

================= DONE =================
Next steps:
  1) Hardware : no script needed. After wiring the FTDI adapter:
                tio -b 1500000 /dev/tty.usbserial-XXXX
  2) Network  : enable System Settings > Sharing > Internet Sharing, then:
                ./scripts/net-capture.sh 1800
  3) OS       : ./scripts/os-audit.sh user@<RK3576_IP>
  4) Firmware : ./scripts/verify-blobs.sh
Tool: $TOOLS_DIR/rkdeveloptool
Place the reference image in workdir/ref/ (armbian.com recomputer-rk3576-devkit).
========================================
EOF
