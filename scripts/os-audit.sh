#!/usr/bin/env bash
# os-audit.sh - SSH into the RK3576 and audit the OS layer in one shot (no ext4 mount needed).
# Usage: ./scripts/os-audit.sh user@<RK3576_IP> [extra ssh options...]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$REPO_ROOT/workdir/logs"; mkdir -p "$LOG_DIR"

[ $# -ge 1 ] || { echo "Usage: $0 user@host [ssh opts]" >&2; exit 1; }
TARGET="$1"; shift || true
TS="$(date +%Y%m%d_%H%M%S)"
OUT="$LOG_DIR/os_audit_${TS}.txt"

# Known-good apt signing key fingerprint (anything else should be investigated)
KNOWN_FP="31C1 8788 0FFB 20E2 9D54 BFFA 266A 668B 2BF2 698C"

# Script executed on the device (some items require sudo)
REMOTE_CMDS='
echo "########## HOST ##########"; uname -a; cat /etc/os-release 2>/dev/null | head -3
echo; echo "########## Integrity (tamper check: any output = a difference) ##########"
command -v debsums >/dev/null && sudo debsums -s 2>/dev/null || echo "(debsums not installed: sudo apt install debsums)"
echo "--- dpkg -V (changed package files) ---"; sudo dpkg -V 2>/dev/null | head -200
echo; echo "########## Listening ports ##########"; sudo ss -tulpn
echo; echo "########## Enabled systemd units ##########"; systemctl list-unit-files --state=enabled --no-pager 2>/dev/null
echo; echo "########## Timers / cron ##########"; systemctl list-timers --all --no-pager 2>/dev/null
echo "--- root crontab ---"; sudo crontab -l 2>/dev/null
echo "--- /etc/cron* ---"; ls -la /etc/cron.d /etc/cron.daily /etc/cron.hourly 2>/dev/null
echo; echo "########## Accounts ##########"
echo "--- UID 0 users ---"; awk -F: "\$3==0{print \$1}" /etc/passwd
echo "--- Login-capable users (/etc/passwd) ---"; awk -F: "\$7!~/(nologin|false)$/{print \$1\":\"\$7}" /etc/passwd
echo "--- Possible empty passwords (/etc/shadow) ---"; sudo awk -F: "\$2==\"\"{print \$1\" <EMPTY>\"}" /etc/shadow 2>/dev/null
echo; echo "########## SSH authorized_keys (full search) ##########"; sudo find / -name authorized_keys -exec echo "== {} ==" \; -exec cat {} \; 2>/dev/null
echo; echo "########## Autostart hooks ##########"; ls -la /etc/rc.local /etc/profile.d/ 2>/dev/null
echo; echo "########## apt sources & signing keys ##########"
cat /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null
echo "--- signing keys ---"; (apt-key list 2>/dev/null || for k in /etc/apt/trusted.gpg.d/*; do gpg --show-keys "$k" 2>/dev/null; done)
'

echo "[*] Target: $TARGET"
echo "[*] Output: $OUT"
# shellcheck disable=SC2029
ssh "$@" "$TARGET" "bash -s" <<<"$REMOTE_CMDS" 2>&1 | tee "$OUT"

echo | tee -a "$OUT"
echo "===== What to look for =====" | tee -a "$OUT"
cat <<EOF | tee -a "$OUT"
- Output from debsums/dpkg -V -> a file that differs from what was shipped (possible tampering)
- An unfamiliar listening port in ss -tulpn, or a bind to 0.0.0.0
- A suspicious persistent service/timer/cron among the enabled units
- A UID 0 other than root / an empty password / an unexpected login user
- An unknown public key in authorized_keys
- An apt signing key other than the known-good one: KNOWN_FP = $KNOWN_FP
EOF
