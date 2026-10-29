#!/usr/bin/env bash
# net-capture.sh - capture RK3576 traffic and print a summary of destinations.
# Prerequisite: enable System Settings > Sharing > Internet Sharing and wire the
#               RK3576 to the Mac's USB-Ethernet (or a hub's LAN port).
# Usage: ./scripts/net-capture.sh [seconds (default 1800)] [interface (default: auto-detect)]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PCAP_DIR="$REPO_ROOT/workdir/pcap"; mkdir -p "$PCAP_DIR"

DURATION="${1:-1800}"
IFACE="${2:-}"

# Auto-detect the Internet Sharing bridge (usually bridge100)
if [ -z "$IFACE" ]; then
  IFACE="$(ifconfig -l | tr ' ' '\n' | grep -E '^bridge[0-9]+' | head -1 || true)"
  [ -n "$IFACE" ] || { echo "[x] No bridge interface found. Is Internet Sharing enabled?" >&2; exit 1; }
fi

TS="$(date +%Y%m%d_%H%M%S)"
PCAP="$PCAP_DIR/capture_${TS}.pcap"

echo "[*] Interface: $IFACE / duration: ${DURATION}s"
echo "[*] Output: $PCAP"
echo "[*] Starting (power on the RK3576 and leave it idle; Ctrl-C to stop early)"

# -G/-W writes a single file for the given number of seconds, then exits
sudo tcpdump -i "$IFACE" -nn -G "$DURATION" -W 1 -w "$PCAP" || true

echo
echo "===== Destination summary (SYN targets = outbound connections) ====="
sudo tcpdump -nn -r "$PCAP" 'tcp[tcpflags] & tcp-syn != 0 and tcp[tcpflags] & tcp-ack == 0' 2>/dev/null \
  | awk '{print $5}' | sed 's/\.[0-9]*:$//' | sort | uniq -c | sort -rn | head -40

echo
echo "===== DNS query names ====="
sudo tcpdump -nn -r "$PCAP" 'udp port 53' 2>/dev/null \
  | grep -oE 'A\? [^ ]+' | awk '{print $2}' | sort | uniq -c | sort -rn | head -40

echo
echo "[OK] Analyze in Wireshark too: open -a Wireshark '$PCAP'"
echo "[Focus] Look for connections other than NTP/DNS/apt(HTTPS) and the known-good"
echo "        endpoints (seeed-studio.github.io / github.com/MorseMicro) that the device"
echo "        initiates on its own without being used. If found, check whois/reverse DNS."
