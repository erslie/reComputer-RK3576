# reComputer RK3576 バックドア調査 — 統合ガイド（OSINT → 3段階調査）

対象: Seeed Studio reComputer RK3576（Rockchip RK3576 SoC）
ホスト: **macOS 1台**（＋少数の小物）
最終更新: 2026-10-29

> このドキュメント1本で、**実機到着前のOSINT（完了済み）**から、**到着後の3段階調査（ハードウェア→ネットワーク→OS）**までの全手順を通して追えるようにしたもの。コマンドはmacOS前提。詳細な一次ソース付きレポートは `docs/` を参照。

---

## 目次
0. [全体像と脅威モデル](#0-全体像と脅威モデル)
1. [必要機材](#1-必要機材)
2. [事前OSINT（完了済みサマリ）](#2-事前osint完了済みサマリ)
3. [macOS環境構築](#3-macos環境構築)
4. [段階1: ハードウェア調査](#4-段階1-ハードウェア調査)
5. [段階2: ネットワーク調査](#5-段階2-ネットワーク調査)
6. [段階3: OS調査](#6-段階3-os調査)
7. [ブート領域／ファーム照合](#7-ブート領域ファーム照合)
8. [合否判定の考え方](#8-合否判定の考え方)
9. [用語集](#9-用語集)
10. [一次ソース](#10-一次ソース)

---

## 0. 全体像と脅威モデル
「出荷された個体に、意図しない作為（バックドア・不正な常駐・改ざん・無断のデータ送信）が無いか」を独立検証する。**非破壊・再現可能・一次情報ベース**で行い、主観ではなく**差分・ハッシュ照合・通信観測**という客観手段で判定できる範囲に限定する。

層分け（どこまで個人で確証できるか）:
| 層 | 対象 | 到達可否 |
|---|---|---|
| **L0** | 配布網OSINT（事前） | ✅ 完了 |
| **L1** | プリインストOS監査 | ✅ 確証可（主戦場） |
| **L2** | ブートチェーン照合 | ✅ 確証可（ハッシュ） |
| **L3** | ハード（UART目視・SPI直読み） | ◐ 軽装備で可 |
| **L4** | SoC内BootROM/OTP/クローズドブロブ内部 | ❌ 個人では検証不能→封じ込め |

**L4は原理的に検証不能**（中身非公開・ダイ解析が必要）。よって「SoC内部は信頼しない」前提に立ち、**L2のハッシュ照合＋L1/段階2の通信監視**で封じ込める。

---

## 1. 必要機材
| 分類 | 物 | 用途 | 必須 |
|---|---|---|---|
| ホスト | **Mac**（Apple Silicon/Intel、空き数十GB） | 母艦 | ✅ |
| 対象 | reComputer RK3576 本体＋純正電源 | 調査対象 | ✅ |
| ネット | **USB-Ethernetアダプタ** or **LAN付USB-Cハブ** | Macをゲートウェイ化し通信傍受 | ✅ |
| ネット | LANケーブル | RK3576⇔Mac | ✅ |
| ハード | **FTDI USB-UART（1.8/3.3/5V切替・例: DSD TECH SH-U09C5）** ＋ メス-メスジャンパ線 | ブートログ目視 | ✅ |
| ファーム | **USB-Cデータケーブル**（充電専用不可） | rkdeveloptoolでブート領域ダンプ | ◯ |
| ハード | ルーペ or USB顕微鏡 | 部品を回路図照合 | ◯ |
| 任意 | microSD＋リーダ | クリーン版を別起動して挙動比較 | 任意 |
| 任意 | CH341A＋SOIC8クリップ | SPI NOR直読み | 任意 |
| 任意 | 外付けSSD(64GB+) | eMMCフルダンプ時のみ | 任意 |

> **ストレージは基本不要**（pcap/ダンプ/参照イメージはMac本体で足りる）。FTDIは5Vのまま挿すと破損するので**接続前に電圧をRK3576に合わせる**。Arduino Uno/Nanoでの代用は5Vロジック＆1.5Mbaud非対応のため**非推奨**。

---

## 2. 事前OSINT（完了済みサマリ）
実機到着前に、公開情報だけで供給網をほぼ可視化済み。詳細は `docs/reComputer_RK3576_OSINT_report.md`。

- **プリインストOS = Armbian（Platinumボード）**。Seeedも独自イメージを配らずArmbian公式へ誘導＝**再現ビルド可・各イメージに.sha/.asc署名**。
- **ベンダ追加物 = Seeed公式APTリポジトリ**（PGP署名有効・鍵FP `31C1 8788 0FFB 20E2 9D54 BFFA 266A 668B 2BF2 698C`）。**全192パッケージにテレメトリ/phone-home無し**。2026-10-28再取得でドリフト無し。
- **搭載無線3系統の素性確定（HiSilicon不在）:**
  - Wi-Fi6/BT = **Quectel FCS960K**（中身 **AICsemi AIC8800**, SDIO3.0）／ FCC ID **XMR2023FCS960K**
  - HaLow = **Morse Micro MM6108系**（802.11ah、外部接触先 `github.com/MorseMicro` は正規ファーム）
  - 有線 = **Realtek RTL8211F-CG ×2**
- **注意フラグ:** Wi-Fiのブランド元 **Quectel は米DoD NDAA §1260H**（中国軍関連企業リスト）に2025年掲載・同社は否認/提訴中。チップ実体(AICsemi)は別会社で規制対象に見当たらず。※JC-STARの観点ではこの地政学リスクは対象外（`docs/reComputer_RK3576_JC-STAR_view.md`）。
- **フォーラム横断（Armbian/CNX/DietPi/Pine64/OpenWrt/Reddit）**: reComputer RK3576への不審通信/バックドア報告は**ゼロ**。
- **L2照合用の基準ハッシュ（取得済み）:**
  - DDR訓練 `rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.12.bin` = `17f54933f87d22f72a7c7c548b1d0c79cf804824064c626be25d42d6863b831f`
  - BL31 `rk3576_bl31_v1.24.elf` = `e2cf4e0e920dfe1daa6412c05f49dc7e5c0f9888d3a3e8eecc85fbe1e86a23d1`

---

## 3. macOS環境構築
リポジトリ同梱スクリプトで一括。
```bash
cd reComputer-RK3576
./scripts/setup-macos.sh
```
これが行うこと:
- Homebrew確認（無ければ案内）
- `tio picocom libusb pkg-config autoconf automake binwalk gnupg coreutils` を導入
- `wireshark`・`docker`（cask）を導入（ext4操作とArmbian再現ビルド用）
- `rkdeveloptool` をソースビルドして `tools/` に配置
- 作業ディレクトリ `workdir/{ref,dump,pcap,logs}` を作成

手動で入れる場合は `scripts/setup-macos.sh` の中身を参照。

---

## 4. 段階1: ハードウェア調査
**目的:** 搭載部品が公式回路図どおりか、追加・差し替えが無いか。ブートの素性を目視。

1. **目視照合** — 筐体を開け、ルーペ/顕微鏡で主要チップ刻印を読み、`data/downloads/reComputer_RK3576_V1.0_SCH.pdf` と突き合わせる。
   - 期待値: RK3576 / PMIC RK806S-5 / RTL8211F×2 / Quectel FCS960K(AIC8800) / Morse Micro。**回路図に無い謎部品が載っていないか**が着眼点。
2. **ブートログ目視（UART）** — debug UARTのTX/RX/GNDにFTDIを接続。
   - ⚠️ 先に**ユーザーマニュアルで電圧(1.8/3.3V)とピン位置**を確認し、FTDIの電圧ジャンパを合わせる。線はTX/RX/GNDの3本（VCCは繋がない）。
   ```bash
   ls /dev/tty.usbserial-*
   tio -b 1500000 /dev/tty.usbserial-XXXX | tee workdir/logs/bootlog.txt
   ```
   - 着眼点: 想定外のブート段・改変されたブートコマンド・見慣れないネット初期化。
3. **（任意）SPI直読み** — SPI NOR搭載時のみ `flashrom` で吸い出し、§7のハッシュ照合へ。

---

## 5. 段階2: ネットワーク調査
**目的:** 起動直後〜アイドルで、外部へ想定外の通信（phone-home）をしていないか。
**方式:** MacをゲートウェイにしてRK3576の通信を素通しで観測。

1. **Macをゲートウェイ化** — System Settings → General → Sharing → **Internet Sharing**:
   - 共有元 = Wi-Fi、相手に渡すポート = USB-Ethernet(ハブのLAN)。有効化。
2. **RK3576をそのLANポートへ有線接続**し電源ON。
3. **キャプチャ＆要約**（同梱スクリプト）:
   ```bash
   ./scripts/net-capture.sh 1800      # 30分キャプチャ→pcap保存＆宛先サマリ表示
   ```
   手動なら:
   ```bash
   ifconfig | grep -A3 bridge         # 通常 bridge100
   sudo tcpdump -i bridge100 -nn -w workdir/pcap/boot_idle.pcap
   ```
4. **解析** — Wiresharkで宛先一覧化。着眼点: NTP/DNS/apt(HTTPS)/既知正当先（`seeed-studio.github.io`・`github.com/MorseMicro`）**以外**へ、使っていないのに自発的に出る接続。あれば宛先の素性(whois/逆引き)を確認。

---

## 6. 段階3: OS調査
**目的:** 隠しアカウント・既定認証・不審な常駐/cron・想定外の自動通信が無いか、公式イメージと食い違わないか。

### 6-A. 実機上で直接点検（ext4マウント不要）
```bash
./scripts/os-audit.sh user@<RK3576_IP>    # SSHで一括点検→workdir/logs/os_audit.txt
```
点検内容と着眼点:
- `debsums -s` / `dpkg -V` … 改ざん検知（公式パッケージと中身が違うファイル）
- `ss -tulpn` … listenポート（見覚えのない待受）
- `systemctl list-unit-files --state=enabled` / `list-timers` … 常駐サービス・cron/timer
- `/etc/passwd`・`/etc/shadow` … 空パスワード・不明なUID0・隠しアカウント
- `authorized_keys` 全検索 … 身に覚えのないSSH公開鍵
- `apt-key`/sources … 公式FP以外の署名鍵・不審なリポジトリ

### 6-B. 公式イメージとのファイル差分（ext4 → Mac内Docker）
```bash
# 1) 参照イメージ取得（armbian.com の recomputer-rk3576-devkit）＆検証
cd workdir/ref
shasum -a 256 -c Armbian_*.img.sha
gpg --verify Armbian_*.img.asc
# 2) ext4比較は Linux コンテナで（出荷個体のrootfs tar を参照imgと diff -r）
docker run --rm -it --privileged -v "$PWD/..":/work -w /work ubuntu bash
```
> ext4ループマウント／Armbian再現ビルドはLinuxが要るためここだけDocker（“Macだけ”の範囲内で完結）。

---

## 7. ブート領域／ファーム照合
MaskROM/loaderモードでブート領域を吸い、§2の基準ハッシュと照合。
```bash
./scripts/verify-blobs.sh            # 基準ハッシュ表を表示＋ダンプと照合
# 手動:
tools/rkdeveloptool ld               # MaskROMで認識確認
tools/rkdeveloptool rl 0 0x4000 workdir/dump/boot_head.img
shasum -a 256 workdir/dump/*.img
binwalk workdir/dump/boot_head.img   # 中身の素性確認
```
基準値が一致すれば「配布物のまま」。不一致なら要追跡。

---

## 8. 合否判定の考え方
- **クリーン判定ができる範囲（L1/L2/L3）:** OS差分なし ＋ 不審な常駐/listenなし ＋ 想定外通信なし ＋ ブロブのハッシュ一致 ＋ 部品が回路図どおり。
- **検証不能として封じ込める範囲（L4）:** SoC内BootROM/OTP/クローズドブロブ内部 → §7のハッシュ照合＋§5の通信監視で担保。
- **スコープ外（やりすぎ）:** ロジアナ全バス傍受・X線・ダイ開封・サイドチャネル。個人の費用対効果が低く、上記で判断の大半が付く。
- **JC-STARとの対応:** §6-Aの `ss`/サービス確認 ≒ ★1 S1.1-13（攻撃面最小化）、§7のハッシュ照合 ≒ S1.1-08（更新の真正性）。詳細は `docs/reComputer_RK3576_JC-STAR_view.md`。

---

## 9. 用語集
- **ブロブ(blob):** 中身非公開のバイナリ。ここではRockchipのDDR訓練コードやBL31等。ソース非公開なので「ハッシュが配布物と一致するか」でしか真偽を測れない。
- **BL31 / ARM Trusted Firmware:** セキュアワールドで動く低レベルファーム。
- **DDR訓練:** 起動初期にメモリ(LPDDR)の信号調整を行うコード。
- **MaskROM / loaderモード:** SoCが内蔵ROMで待ち受ける回復起動モード。USB経由でブート領域を読み書きできる（物理アクセス前提の仕様＝脅威モデルの前提）。
- **OTPヒューズ:** 一度だけ書ける内部設定領域。secure worldのみアクセス可。
- **phone-home:** 機器が利用者の意図と無関係に外部へ接続・送信する挙動。
- **debsums / dpkg -V:** インストール済みパッケージのファイルが配布時と変わっていないかを検証するDebian標準ツール。
- **ttyFIQ0:** Rockchipのデバッグコンソール（シリアル）。

---

## 10. 一次ソース
`docs/` 配下の各レポートに項目ごとの一次ソース（[S1]〜[S27] / [J1]〜[J7]）を収録。主要なもの:
- Armbian ボード: https://www.armbian.com/boards/recomputer-rk3576-devkit
- ボード定義 conf: https://github.com/armbian/build/blob/main/config/boards/recomputer-rk3576-devkit.conf
- Seeed公式apt: https://seeed-studio.github.io/seeed_armbian_extension/dists/stable/InRelease
- rkbin(ブロブ基準): https://github.com/armbian/rkbin
- rkdeveloptool: https://github.com/rockchip-linux/rkdeveloptool
- FCC ID XMR2023FCS960K: https://fccid.io/XMR2023FCS960K
- JC-STAR ★1要件: https://www.ipa.go.jp/security/jc-star/tekigou-kizyun-guide/label1/begoj90000004zgc-att/star1_requirements.pdf

---
*本ガイドは独立した購入者による自機点検のためのもので、製品への疑義表明ではない。所見は2026-10-29時点の公開情報に基づく。*
