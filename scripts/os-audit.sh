#!/usr/bin/env bash
# os-audit.sh — RK3576 実機に SSH して OS 層を一括点検（ext4マウント不要）
# 使い方: ./scripts/os-audit.sh user@<RK3576_IP> [ssh追加オプション...]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$REPO_ROOT/workdir/logs"; mkdir -p "$LOG_DIR"

[ $# -ge 1 ] || { echo "使い方: $0 user@host [ssh opts]" >&2; exit 1; }
TARGET="$1"; shift || true
TS="$(date +%Y%m%d_%H%M%S)"
OUT="$LOG_DIR/os_audit_${TS}.txt"

# 既知の正規 apt 署名鍵 FP（これ以外の鍵が出たら要確認）
KNOWN_FP="31C1 8788 0FFB 20E2 9D54 BFFA 266A 668B 2BF2 698C"

# 実機側で走らせるスクリプト（sudo が必要な項目あり）
REMOTE_CMDS='
echo "########## HOST ##########"; uname -a; cat /etc/os-release 2>/dev/null | head -3
echo; echo "########## 整合(改ざん検知: 出力があれば差分) ##########"
command -v debsums >/dev/null && sudo debsums -s 2>/dev/null || echo "(debsums未導入: sudo apt install debsums)"
echo "--- dpkg -V (変更されたパッケージファイル) ---"; sudo dpkg -V 2>/dev/null | head -200
echo; echo "########## listen ポート ##########"; sudo ss -tulpn
echo; echo "########## 有効な systemd ユニット ##########"; systemctl list-unit-files --state=enabled --no-pager 2>/dev/null
echo; echo "########## timer / cron ##########"; systemctl list-timers --all --no-pager 2>/dev/null
echo "--- root crontab ---"; sudo crontab -l 2>/dev/null
echo "--- /etc/cron* ---"; ls -la /etc/cron.d /etc/cron.daily /etc/cron.hourly 2>/dev/null
echo; echo "########## アカウント ##########"
echo "--- UID0 のユーザ ---"; awk -F: "\$3==0{print \$1}" /etc/passwd
echo "--- ログイン可能ユーザ(/etc/passwd) ---"; awk -F: "\$7!~/(nologin|false)$/{print \$1\":\"\$7}" /etc/passwd
echo "--- 空パスワードの疑い(/etc/shadow) ---"; sudo awk -F: "\$2==\"\"{print \$1\" <EMPTY>\"}" /etc/shadow 2>/dev/null
echo; echo "########## SSH authorized_keys 全検索 ##########"; sudo find / -name authorized_keys -exec echo "== {} ==" \; -exec cat {} \; 2>/dev/null
echo; echo "########## 自動起動フック ##########"; ls -la /etc/rc.local /etc/profile.d/ 2>/dev/null
echo; echo "########## apt ソース & 署名鍵 ##########"
cat /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null
echo "--- 署名鍵 ---"; (apt-key list 2>/dev/null || for k in /etc/apt/trusted.gpg.d/*; do gpg --show-keys "$k" 2>/dev/null; done)
'

echo "[*] 対象: $TARGET"
echo "[*] 保存先: $OUT"
# shellcheck disable=SC2029
ssh "$@" "$TARGET" "bash -s" <<<"$REMOTE_CMDS" 2>&1 | tee "$OUT"

echo | tee -a "$OUT"
echo "===== 着眼点 =====" | tee -a "$OUT"
cat <<EOF | tee -a "$OUT"
- debsums/dpkg -V に出力 → 配布時と中身が違うファイル（改ざんの疑い）
- ss -tulpn に見覚えのない待受ポート／外部バインド(0.0.0.0)
- enabled ユニット・timer・cron に不審な常駐
- UID0 が root 以外 / 空パスワード / 身に覚えのないログインユーザ
- authorized_keys に知らない公開鍵
- apt 署名鍵が既知FP以外: 既知FP = $KNOWN_FP
EOF
