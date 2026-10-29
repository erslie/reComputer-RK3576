# reComputer RK3576 バックドア調査 — まとめ＋実践手順

作成: 2026-10-28 / 対象: Seeed Studio reComputer RK3576（Rockchip RK3576 SoC） / レベル: 実務者向け（専門家でなくても追える粒度）

> **この文書のゴール:** 実機が来る前・来た後に「どこまで・どうやって調べられるか」を、手順・用語・根拠URL付きで1本にまとめる。各節に【用語】と【ソース】を挟む。

---

## 0. 結論（先に3行）
- **ソフトとブート領域までは白黒つけられる。** 出荷OSは再現可能な署名付きArmbianで、ベンダ追加物も署名付きの公式APTに限定、怪しい物は見つかっていない。
- **SoC（RK3576チップ）の中身は原理的に見れない。** そこは「信頼しない前提で通信監視＆ハッシュ比較で封じ込め」。
- **搭載チップは公開回路図で確認済み**＝Rockchip / Realtek / Quectec構成で、**HiSilicon等の制裁対象チップは無し**。

---

## 1. 全体像：調べられる層・調べられない層

| Lv | 層 | 調べること | 実機要否 | 個人で可能か |
|---|---|---|---|---|
| L0 | 配布物（事前） | 公式OS・設定・通信先・部品の素性 | 不要 | ◎（済） |
| L1 | OS（ソフト） | 隠しユーザ・常駐・通信先・ファイル差分 | 要 | ◎ 主戦場 |
| L2 | ブート領域 | ブートローダ/ブロブの改ざん（ハッシュ照合） | 要 | ○ |
| L3 | ハード（軽装備） | UARTログ・基板目視・SPI直読み | 要 | △ |
| L4 | SoC内部（シリコン） | BootROM・OTP・ブロブの内部挙動 | — | ✕ 範囲外 |

> **【用語】層（レイヤー）**: 同じ「バックドア」でも、OSに仕込むのか、起動プログラムに仕込むのか、チップ内部に仕込むのかで、調べ方も難易度も全然違う。だから層で分けて考える。

---

## 2. 事前調査（実機なしでできること）＋手順

### 2-1. 公式OSの素性を確認
- 何をする: 出荷OSが「自分でも同じものを作れる・署名付き」かを確認。これができると、後で出荷品と見比べられる。
- 手順: Armbianのボードページを開き、イメージの版・`.sha`（チェックサム）・`.asc`（PGP署名）・`compile.sh`（ビルド手順）があるか見る。
- 結果: プリインストールOSは **再現可能な署名付きArmbian（Platinum対応）**。独自の不透明イメージではない。

> **【用語】Armbian**: ARM系ボード向けのDebian/Ubuntuベースのディストリ。ソースと設定がGitHubで公開されている。
> **【用語】PGP署名（.asc）**: 配布物が「本物で改ざんされてない」ことを暗号で保証する仕組み。署名を検証すれば偽物を弾ける。

【ソース】Armbianボードカタログ: https://www.armbian.com/boards/recomputer-rk3576-devkit

### 2-2. ボード定義（起動構成）を確認
- 何をする: どのブートローダ・ブロブを使うか、UARTの口、無線は何か、を読む。あとでブート領域やハードを見るときの“答え合わせ”になる。
- 結果: コンソール=`ttyFIQ0`、無線=AIC8800系(SDIO)、GPUはオープンなpanfrost、Fastboot無効、など。L2で照合する**ブロブ名**もここに書いてある。

【ソース】ボード定義conf: https://github.com/armbian/build/blob/main/config/boards/recomputer-rk3576-devkit.conf

### 2-3. 「出荷時にどこへ通信するか」を読む
- 何をする: ビルド/初回起動で接触する外部ホストをソースから洗い出す。これが後で「通信監視の許可リスト」になる。
- 結果: 正規の接触先は実質**2つだけ** → `seeed-studio.github.io`（APT）と `github.com/MorseMicro`（Wi-Fiファーム）。

【ソース】Seeed固有ビルド設定: https://github.com/armbian/build/blob/main/config/sources/vendors/seeed-studio/recomputer-rk35xx-common.inc

### 2-4. Seeed公式APTの中身を確認
- 何をする: ベンダが追加するパッケージを棚卸し。署名の有無と、怪しい物が無いかを見る。
- 手順: APTの索引ファイル（Packages）と署名（InRelease）を取得して中身を読む。
- 結果: **GPG署名あり**（鍵FP `31C1 8788 0FFB 20E2 9D54 BFFA 266A 668B 2BF2 698C`）、**全192パッケージ**、テレメトリ/phone-home系や不審パターンは**検出されず**。中身を要確認なのは実機導入後のDKMS 5本。

> **【用語】APTリポジトリ**: Debian/Ubuntu系のソフト配布元。`apt install` が取りに行く倉庫。署名が付いていれば改ざんを弾ける。
> **【用語】DKMS**: インストール時にカーネルモジュールを自分でコンパイルする仕組み。ソースが同梱されるので、実機で中身を読める。

【ソース】Seeed APT（署名）: https://seeed-studio.github.io/seeed_armbian_extension/dists/stable/InRelease

### 2-5. 搭載チップを公開回路図で確認（HiSilicon懸念の答え）
- 何をする: 箱を開ける前に、公式回路図PDFで主要チップのメーカーを確認。
- 結果（回路図より）:

| 役割 | 部品 | メーカー |
|---|---|---|
| SoC | RK3576 | Rockchip |
| 電源(PMIC) | RK806S-5 | Rockchip |
| 有線LAN PHY ×2 | RTL8211F-CG | Realtek |
| WiFi/BT | FCS960K（AIC8800系） | Quectel |
| その他 | RTC / EEPROM | — |

→ 回路図を "HiSilicon"/"Hi3" で検索しても**ヒット0**。**制裁対象チップは入っていない。**

> **【用語】HiSilicon**: Huawei系の半導体メーカー。米国の輸出規制（Entity List）対象。これが入ってないかが懸念だった。
> **【用語】PHY**: 物理層チップ。ここでは有線LANの信号を扱うチップ（RTL8211F）。アンテナは無いので電波は出さない。

【ソース】公式回路図: https://files.seeedstudio.com/wiki/reComputer_RK/Documents/recomputer_rk3576/RECOMPUTER%20RK3576_V1.0_SCH_2026.pdf

---

## 3. 実機でやる手順（詳細）

### 3-0. 準備するもの
- **機材**: 本体＋電源、USB-Cデータケーブル（充電専用でなくデータ線あり）、（任意）USB-UART変換器、ルーペ
- **PC/ソフト**: Linux推奨（WindowsならWSL2＋`usbipd-win`でも可）。`rkdeveloptool`、標準ツール（`tcpdump`/`debsums`/`dpkg`/`sha256sum`）
- **比較用の正解**: 公式Armbianイメージ＋`.sha`/`.asc`（2-1）、ブロブのハッシュ（下記）

### 3-1. OS外も含めた通信の確認（懸念①の答え）
- 考え方: **デバイス本体のOSを信用せず、ネットワーク側から見る。** そうすればOSが隠しても、実際に出たパケットは必ず見える。
- 手順:
  1. 本体を監視できる場所に繋ぐ（ルーター/スイッチのミラーポート、または間にLinux PCを挟む）
  2. 通信を丸ごと記録:
     ```bash
     sudo tcpdump -ni any -w boot.pcap 'not arp and not port 22'
     ```
  3. 記録した宛先を調べ、**2-3の2つ（seeed-studio.github.io / github.com/MorseMicro）とOS標準（NTP/APT/DNS）以外に出ていないか**確認
- 補足: 回路図上**携帯回線モデムは無い**ので、「OSの外で勝手に電波通信するベースバンド」は現実的に無し。WiFi/BTは単体では勝手に繋げない。

> **【用語】pcap / tcpdump**: ネットワークを流れるパケットを記録・表示するツール/形式。あとからWiresharkで中身を見られる。

### 3-2. ソフト監査（L1・非破壊）
- 手順（実機SSHで）:
  ```bash
  systemctl list-unit-files --state=enabled   # 自動起動サービス
  systemctl list-timers --all; crontab -l     # 定期実行
  ss -tulpnw                                   # 待ち受けポートと所有プロセス
  getent passwd | awk -F: '$3>=0'              # 余計なユーザ
  grep -rn '' /root/.ssh /home/*/.ssh/authorized_keys 2>/dev/null  # 勝手な鍵
  debsums -ca; dpkg -V                         # 公式パッケージの改ざん検査
  # 公式パッケージに属さない実行ファイルを炙り出す
  find / -xdev -type f -perm -111 | while read f; do dpkg -S "$f" >/dev/null 2>&1 || echo "UNOWNED: $f"; done
  cat /etc/apt/sources.list.d/seeed.list       # 2-3のURLと一致するか
  ```
- 見るポイント: 既定パスワード・隠しユーザ・勝手なSSH鍵・公式に無いバイナリ・想定外の常駐。

### 3-3. ブート領域のダンプと照合（L2）
これは「起動プログラムがすり替えられてないか」を見る作業。

> **【用語】ブート領域**: SoCの外にあるフラッシュ（eMMC/SPI）に入った、起動プログラムやOSのデータ。**読み書きできるストレージ**。
> **【用語】MaskROMモード**: Rockchip機を「PCから中身を読み書きできる状態」にする起動モード。ボタン操作で入る。

- 吸い出し手順:
  ```bash
  sudo rkdeveloptool ld                          # デバイス認識（Maskrom/Loader表示）
  # MaskROMで出たら、ストレージにアクセスするためUSBローダを流し込む
  sudo rkdeveloptool db rk3576_spl_loader_vX.bin
  sudo rkdeveloptool rl 0 34 gpt.img             # まずGPT(区画表)を読む
  sudo rkdeveloptool rl 0 0x8000 boot_dump.img   # 先頭16MB(=ブート領域)を吸い出し
  sha256sum boot_dump.img
  ```
  MaskROMの入り方: 電源OFF→MaskROMボタンを押しながらUSB-C接続（ボタン位置はユーザーマニュアル）。

- 照合のしかた（ここが要注意）:
  - **ブロブ単体ファイルと直接ハッシュ比較しても一致しません。** ブロブは起動イメージの中に“梱包”されて再配置されるため。
  - 正しいやり方（簡単）: 同じボード設定＋同じブロブで**正規の起動イメージを自分で作り**、吸い出したものと**同じ領域をバイト比較**する。
  - 入力ブロブの正しさは、単体ファイルのハッシュで確認:
    - DDR訓練ブロブ `…_v1.12.bin` = `17f54933f87d22f72a7c7c548b1d0c79cf804824064c626be25d42d6863b831f`
    - BL31ブロブ `…_v1.24.elf` = `e2cf4e0e920dfe1daa6412c05f49dc7e5c0f9888d3a3e8eecc85fbe1e86a23d1`

> **【用語】ブロブ**: ソース非公開で、**コンパイル済みバイナリだけ**で配られるプログラムの塊。動かせるが中身は読めない。ここではRockchip製の起動用プログラム（下記）。
> **【用語】DDR訓練ブロブ**: 起動直後にメモリ(LPDDR5)を使える状態に調整するプログラム。
> **【用語】BL31ブロブ**: ARMの“secure world”(TrustZone)を仕切る土台プログラム（ARM Trusted Firmware）。

【ソース】rkdeveloptool: https://github.com/rockchip-linux/rkdeveloptool ／ ブロブ配布(rkbin): https://github.com/armbian/rkbin

### 3-4. ハード目視・UART（L3・軽装備）
- **UART**: デバッグUART（`ttyFIQ0`, 1500000bps想定）にUSB-UARTを当て、起動ログを素読み。余計なコマンドや挙動が無いか。
- **目視**: 基板の石の**刻印をルーペで確認**し、2-5の表＆回路図と一致するか。Huaweiロゴや "Hi" で始まる型番が無いか。
- **（任意）SPI直読み**: SPIフラッシュを `flashrom`＋CH341Aでオフライン吸い出し→3-3と照合。

> **【用語】UART**: 基板に出ている簡易シリアル通信の口。起動ログがそのまま流れてくるので、様子を覗くのに便利。

---

## 4. 懸念点チェック（3つの質問の答え）

| 懸念 | 確認できる？ | どうやって |
|---|---|---|
| ① OS以外で通信してる？ | できる | ネットワーク側で丸ごとキャプチャ（3-1）。隠れモデムは回路図上なし |
| ② FCC規制部品／認証は？ | できる | 無線部品だけFCC IDを照合（下記）。SeeedはFCC/CE/TELEC/RoHS表示 |
| ③ HiSilicon入ってる？ | できる | 回路図で確認済み＝入っていない（2-5） |

### ②のやり方（FCC）
- **絞り方**: FCC IDが要るのは**電波を出す無線部品だけ**。この基板では **Quectec FCS960K（WiFi/BT）** が対象。SoC・PMIC・有線PHY・RTC・EEPROMは対象外。
- **検索手順（fccid.io）**:
  1. IDが手元にあるなら、そのIDを検索ボックスにそのまま入力
  2. まだ無いなら**会社名で検索**（例 `Quectel`）→ 製品一覧から `FCS960K` を探す
- **ページで見る所**: Grantee(取得者)／周波数・区分(WiFi+BTだけか)／**内部写真**(実機の石と一致するか)／Test Report／ラベル位置
- **実機での答え合わせ**: 基板のFCC ID印字 → fccid.ioのページ → 内部写真の石、が3つ揃えば正規。

> **【用語】FCC ID**: 米国で電波を出す機器に付く認証番号。「メーカーコード＋製品コード」。FCCのDBで試験内容や内部写真まで公開されている。
> **【補足】規制は2種類**: FCC=電波の技術基準（無線部品が対象）／Entity List(米商務省)=HiSilicon等の制裁対象メーカー。別物なので分けて考える。

【ソース】FCC ID検索: https://fccid.io ／ 公式DB: https://apps.fcc.gov/oetcf/eas/reports/GenericSearch.cfm

---

## 5. できないこと（SoC内部＝シリコン）
- **SoC(RK3576)の中身**は読み出す口が無く、個人では無理:
  - BootROM（製造時に焼かれた最初のコード）＝読み出し不可
  - OTPヒューズ（鍵）＝secure worldからしか触れない
  - ブロブが**中で何をしているか**（挙動）＝ソース非公開で検証不能
- チップを開けて顕微鏡で見る、X線、電力解析…は**ラボ案件**で費用対効果が悪く、今回は対象外。

> **【用語】ブート領域ダンプ と SoCダンプの違い**: 前者は“基板上の別チップ(フラッシュ)のデータ”を読む＝できる・比較できる。後者は“SoCチップの中身”を読む＝口が無い・基本できない。本棚の本（取り出せる）と、壁に埋め込まれた金庫の中（開けられない）の違い。
> **【用語】OTPヒューズ**: 一度だけ書き込める記憶領域。鍵などを焼く。外から中身は読めない。

**→ 戦略:** 読めるブート領域はハッシュ照合で改ざんを潰す／読めないSoC内部は通信監視で封じ込める。

---

## 6. 用語集（早見）
- **Armbian** … ARMボード向けの公開ディストリ（Debian/Ubuntuベース）
- **BSP** … そのボードを動かすためのメーカー提供の一式（カーネル・u-boot等）
- **ブロブ** … ソース非公開のバイナリだけのプログラム
- **ブート領域** … 外部フラッシュ上の起動プログラム/OSデータ（読める）
- **SoC** … CPU等を1つにまとめたチップ（ここではRK3576、中身は読めない）
- **MaskROM** … Rockchip機をPCから読み書きできるようにする起動モード
- **DKMS** … インストール時にカーネルモジュールをビルドする仕組み（ソース同梱）
- **PHY** … 物理層チップ（ここでは有線LAN、電波は出さない）
- **FCC ID** … 米国の電波機器の認証番号
- **HiSilicon** … Huawei系の半導体メーカー（米制裁対象）

---

## 7. ソース一覧（一次情報）
- Armbianボードカタログ: https://www.armbian.com/boards/recomputer-rk3576-devkit
- ボード定義conf: https://github.com/armbian/build/blob/main/config/boards/recomputer-rk3576-devkit.conf
- Seeed固有ビルド設定(通信先): https://github.com/armbian/build/blob/main/config/sources/vendors/seeed-studio/recomputer-rk35xx-common.inc
- Seeed公式APT(署名/索引): https://seeed-studio.github.io/seeed_armbian_extension/dists/stable/InRelease
- Seeed APT拡張リポジトリ(ソース): https://github.com/Seeed-Studio/seeed_armbian_extension
- 公式回路図(搭載チップ): https://files.seeedstudio.com/wiki/reComputer_RK/Documents/recomputer_rk3576/RECOMPUTER%20RK3576_V1.0_SCH_2026.pdf
- rkdeveloptool(ダンプ): https://github.com/rockchip-linux/rkdeveloptool
- rkbin(ブロブ/ハッシュ基準): https://github.com/armbian/rkbin
- Wi-Fiファーム(Morse Micro): https://github.com/MorseMicro/morse-firmware
- Wi-Fiドライバ(AIC8800/Radxa): https://github.com/radxa-pkg/aic8800
- FCC ID検索: https://fccid.io ／ https://apps.fcc.gov/oetcf/eas/reports/GenericSearch.cfm
- Quectel FCS960K(WiFi/BTモジュール): https://www.quectel.com/product/wi-fi-bluetooth-fcs960k/
- ユーザーマニュアル(ボタン/ピン): https://files.seeedstudio.com/wiki/reComputer_RK/Documents/recomputer_rk3576/recomputer_rk3576_user_manual.pdf
- (参考)Rockchipクローズドブロブ事情: https://www.collabora.com/news-and-blog/blog/2024/02/21/almost-a-fully-open-source-boot-chain-for-rockchips-rk3588/

---
*本書は購入者自身による自機点検の手引きです。所見は調査時点のもので、製品への疑義を主張するものではありません。*
