# reComputer RK3576 バックドア調査 — 事前整理と一次調査ログ（完全版）

作成: 2026-10-27 / 対象: Seeed Studio reComputer RK3576（Rockchip RK3576 SoC, 8コア A72x4+A53x4, Mali-G52, 6TOPS NPU, LPDDR5, 2x GbE, Wi-Fi6/BT5.4, M.2 M-key PCIe2.1 x1）

> **総括:** 実機到着前にソフト／ファーム供給網をほぼ完全に可視化できた。プリインストールOSは素性の明確な **Armbian（Platinum対応・GitHubで再現ビルド可能・PGP署名あり）**。ベンダ追加物も **Seeed公式aptリポジトリ（GPG rsa4096署名・GitHub Pages・全192パッケージを列挙済み）** と **GitHub上の公開拡張リポジトリ** に限定され、索引にテレメトリ／解析／phone-home系パッケージや不審パターンは**検出されなかった**。残る不透明部分は **Rockchipのクローズドなブート用バイナリ（DDR訓練・BL31・SoC内BootROM）** のみで、これは個人では中身を検証できない構造的リスク。現実的なゴールは「ソフト/ファーム面を可能な限り白に近づけ（済）、SoC内部はブラックボックスと割り切ってネットワーク挙動で封じ込める」こと。

---

## 1. 現実的なライン（どこまでやるか）

| Lv | 層 | 何を疑うか | 必要なもの | 個人での現実性 |
|----|----|-----------|-----------|--------------|
| **L0** | OSINT/事前 | 公式ファーム・BSP・配布網の素性 | PCのみ（**今回ほぼ完遂**） | ◎ |
| **L1** | プリインストールOS | 隠しユーザ/既定認証情報/phone-home/不審なsystemd・cron・DKMS | 実機＋SSH | ◎ 主戦場 |
| **L2** | ブートチェーン/ファーム | idbloader・u-boot・BL31・DDRブロブ・DTBの改変 | 実機＋`rkdeveloptool`/`dd` | ○ ハッシュ照合可（基準値取得済） |
| **L3** | ハードウェア | UART/JTAG開放、SPIフラッシュ実体、不審チップ、追加NIC | UART変換器・SPI ROMリーダ・ルーペ | △ UARTは容易、直読み/目視は設備次第 |
| **L4** | シリコン/BootROM | SoC内の隠しデバッグ・OTP・クローズドブロブの悪性動作 | ダイ解析ラボ | × 個人では不可＝**スコープ外** |

**線引き:** 確証を出せるのは **L1〜L2**（ここは徹底）。**L3** はUART確認までは即可、SPI直読み・顕微鏡は設備次第。**L4** は範囲外＝「信頼しない前提でL1/L2の封じ込め」で対処。

---

## 2. 脅威面の分解

- **(a) プリインストールOS・サービス** … 既定PW/隠しアカウント/授権キー/常駐/起動時の外部通信。→ L1で検証可。
- **(b) ブートローダ/ファーム** … idbloader/u-boot/BL31の改変・環境変数・DTBの余計なデバイス。→ L2でハッシュ照合可。
- **(c) ハードウェア** … 追加チップ・開放デバッグポート・意図しない管理経路。→ L3、目視と設備。
- **(d) SoC内部/クローズドブロブ** … BootROM/DDR訓練/BL31。中身非公開。→ L4、個人では不可。

---

## 3. 事前調査で判明したこと（L0・一次ソース付き）

### 3.1 プリインストールOSの素性 ― ★最重要の good news
- Seeed自身のフラッシュ手順ページ（SenseCraft AI Lab）は独自イメージを配らず、**Armbian公式ボードページの "Direct download" へ誘導**（sensecraft.seeed.cc）。
- reComputer RK3576 は **Armbian "Platinum" 対応ボード**。公式イメージは vendorカーネル 6.1.172（一部アプリ別イメージ 6.1.115）。各イメージに **`.sha`＋`.asc`（PGP署名）＋`.torrent`** が併記＝**完全性を検証できる**。
- **意味:** プリインストOSは不透明なベンダ独自イメージではなく、**ソースと設定がGitHubにある再現可能ビルド**。公式を自分で焼いたものと出荷状態を**ファイル単位で差分**すれば、出荷時の作為(a)は高確度で検出できる。

### 3.2 Seeed固有のビルドロジック（`recomputer-rk35xx-common.inc`）
Armbianビルドに読み込まれるSeeed専用スクリプトを全確認。接触先・導入物を完全列挙（隠し要素が入りにくい透明な作り）:
- **接触する外部ホスト:** `seeed-studio.github.io`（aptリポジトリ＋GPG鍵）、`github.com`（MorseMicro HaLowファームを固定コミットで clone: `github.com/MorseMicro/morse-firmware.git`）。それ以外の外部宛先なし。
- **追加aptソース:** `/etc/apt/sources.list.d/seeed.list` に `deb [signed-by=/usr/share/keyrings/seeed-repo.gpg] https://seeed-studio.github.io/seeed_armbian_extension stable main`。鍵は同GitHub Pagesから取得・dearmorして設置。
- **既定で有効化されるサービス:** `usbdevice.service`, `dnsmasq.service`, `serial-getty@ttyGS0.service`, `aic-bluetooth.service`。`armbian-hardware-optimize.service` は無効化。
- **USBガジェット既定構成（要注意面）:** `usb0` に **静的 192.168.42.1/24** を割当て、`dnsmasq` が **192.168.42.100-150 をDHCP配布**、`ttyGS0` に **getty（USB経由シリアルログイン）**。→ USB接続だけでネットワーク＋コンソールが生える。バックドアではないが**初期攻撃面として要把握**（不要なら無効化推奨）。
- 書き込むファイル: `/usr/local/bin/{login-ns.sh,usb-automount}`, `/usr/bin/aic-bluetooth`, modprobe/modules-load.d の aic8800 設定, Mali系 udev/xorg 設定, MorseMicroファーム `/lib/firmware/morse/*.bin` 等。GDM自動ログインは**false**に設定。

### 3.3 Seeed公式aptリポジトリ ― 全パッケージを可視化（供給網(a)の本体）
GitHub Pages上の実リポジトリから索引・鍵を取得して解析。
- **署名:** `dists/stable/InRelease` と `Release.gpg` ともに **HTTP 200＝PGP署名あり**（apt が検証）。鍵は **RSA 4096**、uid **"Seeed Studio x Armbian APT \<zuobaozhu@gmail.com\>"**、**フィンガープリント `31C1 8788 0FFB 20E2 9D54 BFFA 266A 668B 2BF2 698C`**。
  - 注: 署名uidが**個人Gmail**（zuobaozhu=Baozhu Zuo／Armbianボードメンテナ Pillar1989 と同一人物）。悪性ではないが「組織鍵ではなく個人鍵」である点は留意。
- **規模:** **192パッケージ**。内訳はすべて素性の分かるもの＝Rockchipマルチメディア（`librockchip-mpp`, `librga`, `camera-engine-rkaiq`, `gstreamer1.0-rockchip`）、GPUクローズドblob（`libmali-*`）、Wayland/Weston/X、Morse Micro HaLow(802.11ah)無線スタック、AIC Bluetooth、各種firmware、ベンダ kernel/u-boot deb。
- **索引の健全性チェック:** `telemetry|analytics|backdoor|.onion|pastebin|curl|sh` 等の不審パターンは **索引上ゼロ**。テレメトリ／解析専用パッケージも**なし**。
- **到着後に“中身”を読むべき優先対象（インストール時にコンパイル／firmware実体）:**
  - DKMS（カーネルモジュールをビルド）: `morse-fgh100m-dkms`, `maxio-phy-dkms`, `pcie-rkep-dkms`, `realtek-r8125-dkms`, `wq9201s-wifi-bt-dkms`
  - firmwareブロブ: `rkwifibt-broadcom-firmware`, `rkwifibt-realtek-firmware`, `/lib/firmware/morse/*`
  - `pcie-rkep-dkms` は RK3576 の **PCIe Endpoint(EP)モード**ドライバ。機能であり不審ではないが、EP化は要把握。
- **衛生面（findingではない）:** 一部再パッケージdebのMaintainerが `John Doe <john.doe@somewhere.on.planet>` や `pss@localhost` のプレースホルダ。Rockchip系debで散見される雑さで、悪性ではない。

### 3.4 ブートチェーンと基準ブロブハッシュ（L2照合の基準値）
Armbianボード定義 `config/boards/recomputer-rk3576-devkit.conf`（全文ローカル保存）より:
- `BOOT_SCENARIO="spl-blobs"`、GPT、SPIローダ対応。ブート順 mmc0→nvme→usb→pxe→dhcp。mainline u-boot は RockUSBガジェット有効・**Fastboot明示無効**。vendor u-boot は Radxa由来 2017.09。
- **使用ブロブ（rkbin由来）を取得してハッシュ確定:**
  | ブロブ | ファイル | SHA256 |
  |---|---|---|
  | DDR訓練 | `rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.12.bin` | `17f54933f87d22f72a7c7c548b1d0c79cf804824064c626be25d42d6863b831f` |
  | BL31(ATF) | `rk3576_bl31_v1.24.elf` | `e2cf4e0e920dfe1daa6412c05f49dc7e5c0f9888d3a3e8eecc85fbe1e86a23d1` |
  → 実機から吸い出したローダをこの値と照合すれば、ブート領域の改変(b)を検出できる。
- 無線は **AIC8800（SDIO）**（ドライバ=Radxa `radxa-pkg/aic8800`、firmwareは別deb）、BT=`/dev/ttyS4`。GPUは closed Mali ではなく **panfrost/Mesa**（クローズドblob不使用の選択）。

### 3.5 Seeed拡張リポジトリ `seeed_armbian_extension`（ファーム/OTA/暗号化）
- 提供機能: **OTA（recovery/A-B・自動ロールバック）**, **LUKSディスク暗号化（OP-TEE＋セキュリティパーティションで自動アンロック）**, **Rockchipセキュアブート対応**, **security-hardening / ssh-protect（常時有効）**。
- いずれも**セキュリティ強化側**の機能。ダウンロードはGitHub Releases、チェックサムはOneDrive、OTAはローカルパッケージ例＝**索引上は常時phone-homeする記述なし**。
- 到着後に実ファイルを読む価値がある箇所: `initramfs/scripts/init-top`（最初期起動）, `security-hardening/`, `ssh-protect/`, `rk_secure-disk-encryption/`（パスフレーズ/自動アンロック）。

### 3.6 Rockchip共通の構造的リスク（検証不能ゾーン＝L4の輪郭）
- RockchipのSoCは **DDR訓練blobとBL31blobがクローズド**。RK3588ではTF-A由来のオープンBL31で置換可能になったが、**DDR訓練blobのオープン代替は無い**。loaderはrkbinに実体がなく、DDR init＋usbplugから生成と推定（Bootlin）。
- **maskrom/downloadモード**は物理アクセスでの再フラッシュ手段＝"物理アクセス前提の改ざん"は防げない（脅威モデルの前提）。セキュアブートはBootROMがOTPヒューズ内の公開鍵ハッシュで署名検証する方式だが、**BSPは既定で未署名/ヒューズ未焼き**が通常（OTPはsecure worldのみアクセス可）。
- **RK3576のTRMは一般非公開**（パートナー配布）。BootROM/OTP詳細は読めない＝L4が個人で不可な根拠。

### 3.7 比較: 「出荷時マルウェア」事例との対比（Androidを使うなら要注意）
- 中華Android TVボックス（T95/X88/Q9等）が **BadBox/Triada を出荷時プリインストール**して C2 へ phone-home した事例群がある（Human Security 2023〜, Google 2019）。ただしこれは**不透明なAndroidシステムイメージ**が温床で、**本機のArmbian(Linux)経路とは別系統**。
- 含意: **本機でArmbian/Debian/Ubuntuを使う限りBadBox級リスクは低い**（イメージが再現可能・署名付きのため）。一方 **Seeedが別途提供するAndroid 14イメージを使う場合は、そのシステムイメージの素性検証が別途必要**（最も疑うべき経路はこちら）。

### 3.8 データシート入手状況
- 公開ミラー（armdesigner.com）の RK3576 Datasheet **V1.5/V1.3/Brief V1.2 は現在いずれも 404、ルートは 403**。RockchipはRK3588で公開データシートを削除させた前例あり。TRMはパートナー限定。
- 手動で試す価値のあるURL / 公式一次資料は §6 に記載。

---

## 4. 実機到着後の手順（レベル別・実行コマンド付き）

### L1 ソフト監査（最初・非破壊）
```bash
# 0) 出荷状態を保全（別PCで）: SD=dd / eMMC=rkdeveloptool rl で丸ごとイメージ化
# 1) 起動直後〜アイドルの外部通信を外側から観測
sudo tcpdump -ni any -w boot.pcap 'not arp and not port 22'   # 宛先をdig/whois。seeed-studio.github.io/MorseMicro以外の外部宛先を要注意化
# 2) 常駐・起動・認証まわり
systemctl list-unit-files --state=enabled; systemctl list-timers --all; crontab -l; ls -la /etc/cron.*
ss -tulpnw                                  # listenポートと所有プロセス（usb0の192.168.42.1/dnsmasqは既定機能）
getent passwd | awk -F: '$3>=0'             # 隠しUID
awk -F: '($2!="*"&&$2!="!"){print}' /etc/shadow
grep -rn '' /root/.ssh /home/*/.ssh/authorized_keys 2>/dev/null
cat /etc/apt/sources.list.d/seeed.list      # §3.2のURLと一致するか
apt-key list 2>/dev/null; gpg --show-keys /usr/share/keyrings/seeed-repo.gpg  # FPが 31C1 8788... と一致するか
# 3) 公式Armbianとのファイル差分（作為(a)検出の本命）
debsums -ca; dpkg -V
find / -xdev -type f -perm -111 | while read f; do dpkg -S "$f" >/dev/null 2>&1 || echo "UNOWNED: $f"; done
# 4) DKMSソースを読む（§3.3の5つ）
ls /usr/src/*-dkms*/ ; # 各 .c のネットワーク/exec呼び出しを確認
```

### L2 ブートチェーン照合（改変(b)検出）
```bash
sudo rkdeveloptool rl 0x0 0x4000 idbloader.img   # ブート先頭領域を吸い出し
sha256sum idbloader.img
# 基準: DDR=17f54933...b831f / BL31=e2cf4e0e...23d1（§3.4）と、該当領域内のblobを照合
fdtget /boot/dtb/rockchip/rk3576-*.dtb /         # DTBで余計なデバイスが有効化されていないか
```

### L3 ハードウェア（設備次第）
- **UARTコンソール（推奨・容易）**: デバッグUART（`ttyFIQ0`系, 1500000bps想定）にUSB-UARTを当て、BootROM→u-boot→カーネルのログを素読み。autobootの細工・余計なコマンドを確認。
- **SPIフラッシュ直読み（本格）**: SPI NOR を CH341A/`flashrom` で**オフライン吸い出し**→ L2と照合。
- **目視**: 公式ボード写真と比較し、未実装フットプリントへの追加部品・素性不明チップ・余計な無線/管理経路の有無。想定無線は AIC8800(SDIO) と（devkitは）Morse Micro HaLow。

### L4（スコープ外）
- SoC内BootROM/OTP/クローズドブロブの悪性動作検証はダイ解析ラボが必要＝個人では不可。対処は「信頼しない前提のL1/L2封じ込め」。

### Androidを使う場合（別経路・最優先で疑う）
- SeeedのAndroid 14イメージを使うなら、`system`/`vendor`パーティションを展開し、プリインストールAPK・`init.rc`・常駐サービス・証明書ストア・phone-home先を監査（BadBox級の温床はこちら）。

---

## 5. 入手済みの資料・ツール（ローカル保存、`scratchpad/rk3576-downloads/`）

| ファイル | 内容 | SHA256(先頭) |
|---|---|---|
| `armbian_recomputer-rk3576-devkit.conf` | Armbianボード定義全文（L2基準） | `173ab2fa…cf0b2d` |
| `rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.12.bin` | DDR訓練blob（照合基準） | `17f54933…b831f` |
| `rk3576_bl31_v1.24.elf` | BL31/ATF blob（照合基準） | `e2cf4e0e…23d1` |
| `seeed_dists_stable_main_binary-arm64_Packages` | Seeed apt 全192パッケージ索引 | `7aaafcae…7991` |
| `seeed_dists_stable_Release` | apt Release（SHA256署名対象） | `e9267f8e…fa99` |
| `seeed_seeed-repo.gpg` | Seeed apt 署名鍵（FP 31C1 8788…698C） | `995b6e38…2016` |

**到着までに各自用意推奨:** 公式Armbianイメージ＋`.sha`/`.asc`（差分参照元）/ `rkdeveloptool` / `rkbin`（ハッシュ基準）/ USB-UART変換器 /（本格なら）CH341A+`flashrom`・USBマイクロスコープ。
**入手保留:** RK3576 データシート/TRM（ミラー404/403、TRMはパートナー限定）。

---

## 6. 一次ソース一覧

- Seeed フラッシュ手順（Armbian公式へ誘導）: https://sensecraft.seeed.cc/ai-lab/en/tutorials/rk/getting-start/flash-os/install-system-microsd
- Seeed AI Lab 紹介（プリインストール=Armbian）: https://sensecraft.seeed.cc/ai-lab/en/tutorials/rk/introduction
- Armbian ボードカタログ（イメージ/sha/asc/kernel/maintainer）: https://www.armbian.com/boards/recomputer-rk3576-devkit
- Armbian ボード定義 conf: https://github.com/armbian/build/blob/main/config/boards/recomputer-rk3576-devkit.conf
- Seeed固有ビルド共通inc: https://github.com/armbian/build/blob/main/config/sources/vendors/seeed-studio/recomputer-rk35xx-common.inc
- Seeed apt拡張リポジトリ（ソース）: https://github.com/Seeed-Studio/seeed_armbian_extension
- Seeed apt（配布・署名）: https://seeed-studio.github.io/seeed_armbian_extension/dists/stable/InRelease
- AIC8800 無線ドライバ（Radxa）: https://github.com/radxa-pkg/aic8800
- rkbin（ブロブ配布）: https://github.com/rockchip-linux/rkbin / https://github.com/armbian/rkbin
- Seeed reComputer RK3576 ユーザーマニュアル: https://files.seeedstudio.com/wiki/reComputer_RK/Documents/recomputer_rk3576/recomputer_rk3576_user_manual.pdf
- Collabora（Rockchipブートチェーンのクローズドブロブ事情）: https://www.collabora.com/news-and-blog/blog/2024/02/21/almost-a-fully-open-source-boot-chain-for-rockchips-rk3588/
- Bootlin（loader/maskromの素性）: https://bootlin.com/blog/recovery-boot-on-rockchip-socs/
- 3mdeb（Rockchipセキュアブート/OTP署名検証）: https://blog.3mdeb.com/2021/2021-12-03-rockchip-secure-boot/
- Pengutronix（RK3588セキュアブート/OTP=secure worldのみ）: https://www.pengutronix.de/de/blog/2026-06-19-rk3588-secure-boot.html
- Seeed User Privacy Agreement（SenseCraft/デバイス報告情報）: https://sensecap.seeed.cc/portal/public/html/user-privacy-agreement-en.html
- BadBox/Triada 出荷時マルウェア事例（対比）: https://thehackernews.com/2025/04/triada-malware-preloaded-on-counterfeit.html / https://securityaffairs.com/152124/
- データシートミラー(現在404、要手動再試行): https://www.armdesigner.com/download/Rockchip_RK3576_Datasheet_V1.5-20241216.pdf
