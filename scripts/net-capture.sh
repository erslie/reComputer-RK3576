#!/usr/bin/env bash
# net-capture.sh — RK3576 の通信をキャプチャし、宛先サマリを出す
# 前提: System Settings > Sharing > Internet Sharing を有効化し、
#       RK3576 を Mac の USB-Ethernet(ハブLAN) に有線接続していること。
# 使い方: ./scripts/net-capture.sh [秒数(既定1800)] [インターフェース(既定 自動検出)]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PCAP_DIR="$REPO_ROOT/workdir/pcap"; mkdir -p "$PCAP_DIR"

DURATION="${1:-1800}"
IFACE="${2:-}"

# Internet Sharing のブリッジを自動検出（通常 bridge100）
if [ -z "$IFACE" ]; then
  IFACE="$(ifconfig -l | tr ' ' '\n' | grep -E '^bridge[0-9]+' | head -1 || true)"
  [ -n "$IFACE" ] || { echo "[x] bridgeインターフェースが見つかりません。Internet Sharing が有効か確認してください。" >&2; exit 1; }
fi

TS="$(date +%Y%m%d_%H%M%S)"
PCAP="$PCAP_DIR/capture_${TS}.pcap"

echo "[*] インターフェース: $IFACE / 時間: ${DURATION}s"
echo "[*] 保存先: $PCAP"
echo "[*] 開始（RK3576 を起動して放置してください。Ctrl-C で早期終了可）"

# -G/-W で指定秒数で1ファイルにして終了
sudo tcpdump -i "$IFACE" -nn -G "$DURATION" -W 1 -w "$PCAP" || true

echo
echo "===== 宛先サマリ (SYN送信先 = 外向き接続の相手) ====="
sudo tcpdump -nn -r "$PCAP" 'tcp[tcpflags] & tcp-syn != 0 and tcp[tcpflags] & tcp-ack == 0' 2>/dev/null \
  | awk '{print $5}' | sed 's/\.[0-9]*:$//' | sort | uniq -c | sort -rn | head -40

echo
echo "===== DNS 問い合わせ先ドメイン ====="
sudo tcpdump -nn -r "$PCAP" 'udp port 53' 2>/dev/null \
  | grep -oE 'A\? [^ ]+' | awk '{print $2}' | sort | uniq -c | sort -rn | head -40

echo
echo "[OK] 解析は Wireshark でも: open -a Wireshark '$PCAP'"
echo "[着眼点] NTP/DNS/apt(HTTPS) と既知正当先(seeed-studio.github.io / github.com/MorseMicro) 以外へ"
echo "         使っていないのに自発的に出る接続が無いか。あれば whois/逆引きで素性確認。"
