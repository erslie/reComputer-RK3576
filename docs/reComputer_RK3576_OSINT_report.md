# reComputer RK3576 — 現物到着前 OSINT 調査レポート

作成日: 2026-10-28 / 対象: Seeed Studio reComputer RK3576（Rockchip RK3576 SoC）/ 段階: **実機未着（公開情報のみ・非接触）**

> **このレポートの位置づけ:** 実機が手元に来る前に、公開情報（OSINT）だけでどこまで「素性」を割り出せるかをやり切ったもの。ここで確定した基準値・サプライヤ素性・FCC情報は、到着後に実機と突き合わせるための「答え合わせの正解表」になる。各項末尾の `[Sn]` は §8 の一次ソース。断定ではなく、公開情報時点の所見。

---

## 0. 結論（先に3行）
1. **プリインストールOS・ベンダ追加物・ブートブロブは、素性が明確で署名付き／再現可能。** 不審なテレメトリや phone-home パッケージは索引（全192）に見当たらない。
2. **搭載無線は3系統すべて素性判明（HiSiliconは不在）。** Wi-Fi6/BT = Quectel FCS960K（中身は AICsemi AIC8800）、HaLow = Morse Micro MM6108系、有線 = Realtek RTL8211F ×2。いずれもFCC認証を取得できる正規品。
3. **ただし注意点が1つ:** Wi-Fiモジュールの**ブランド元 Quectel 社**は、米国防総省の NDAA 1260H リスト（「中国軍関連企業」）に2025年に掲載され、同社は否認・提訴中。チップ実体（AICsemi）とは別会社だが、「米国が気にしている部品か」という観点では該当する。詳細は §5。

---

## 1. 調査対象ハードウェアの確定（回路図ベース）
公式回路図 `reComputer_RK3576_V1.0_SCH.pdf`（ローカル保存済、38頁）から搭載チップを特定。**HiSilicon は検索ヒット0。**

| 役割 | 部品 | メーカー | 素性メモ |
|---|---|---|---|
| メインSoC | RK3576 | Rockchip（中国・福州） | A72×4+A53×4 / Mali-G52 / 6TOPS NPU |
| PMIC（電源管理） | RK806S-5 | Rockchip | RK3576用標準PMIC |
| 有線LAN PHY ×2 | RTL8211F-CG | Realtek（台湾） | 定番のGbE PHY。枯れた部品 [S9] |
| Wi-Fi6 + BT5.4 | **FCS960K**（モジュール） | Quectel（中国・上海） | 中身は **AICsemi AIC8800**、SDIO 3.0 接続 [S10][S11][S12] |
| Wi-Fi HaLow（sub-GHz） | **MM6108系**（FGH100Mモジュール） | **Morse Micro（豪）** | 802.11ah、850–950MHz [S13] |

---

## 2. プリインストールOS（配布網）— 実機不要で検証可能
- 出荷OSは **Armbian（Platinum対応ボード）**。Seeedのフラッシュ手順も独自イメージを配らず Armbian公式 `armbian.com/boards/recomputer-rk3576-devkit` へ誘導する＝**不透明な自社イメージではない**。[S1][S6]
- 各イメージに `.sha`（チェックサム）と `.asc`（PGP署名）が付き、GitHubの `config/boards/recomputer-rk3576-devkit.conf` が全文公開されているので**自分で同じものをビルドして照合できる**。[S2]
- ボード定義の要点: `BOOT_SCENARIO=spl-blobs` / コンソール=`ttyFIQ0` / 無線=AIC8800(SDIO) / GPU=panfrost（オープンMesa、クローズドMali未使用）/ Fastboot無効 / パッケージに `fail2ban`。[S2]

## 3. ベンダ追加物（Seeed公式APTリポジトリ）— 今回ライブ再取得
`https://seeed-studio.github.io/seeed_armbian_extension stable main`
- **PGP署名が有効**（InRelease / Release.gpg）。鍵 RSA4096、FP `31C1 8788 0FFB 20E2 9D54 BFFA 266A 668B 2BF2 698C`（uid "Seeed Studio x Armbian APT"）。[S4]
- **2026-10-28 再取得: InRelease の Date=`Tue, 27 Oct 2026 08:17:20 UTC`、パッケージ数は前回と同じ192**。ドリフト（勝手な差し替え・増殖）なし。
- 索引192パッケージを通読 → **テレメトリ／解析SDK／phone-home系・不審パターンはゼロ**。中身は GStreamer・カメラ(rkaiq)・glmark2・DKMSドライバ等、正当なマルチメディア／ドライバ群。[S4]
- 無線関連パッケージが素性を裏づけ: `fcs960k-aic-bluez` / `fcs960k-aic-bluez-lib`（＝FCS960K=**AIC**8800 の確証）、`hostapd-morse-tools`（＝Morse Micro HaLow）。
- 到着後に中身を読むべきDKMS: `morse-fgh100m` / `maxio-phy` / `pcie-rkep` / `realtek-r8125` / `wq9201s-wifi-bt`。
- 拡張リポジトリ `Seeed-Studio/seeed_armbian_extension` の実体は **OTA(A/B) / LUKS自動アンロック(OP-TEE) / セキュアブート / hardening** ＝セキュリティ強化側。[S5]
- ビルド時の外部接触先は **`seeed-studio.github.io` と `github.com/MorseMicro/morse-firmware` の2つだけ**。後者は Morse Micro 公式のHaLowファーム配布（BCF＋ファーム、11★/9fork、正規のベンダーリポ）。[S3][S13]

## 4. ブートチェーン照合用の基準ハッシュ（到着後のL2照合の正解表）
armbian/rkbin master から実取得・保存済:
- DDR訓練ブロブ `rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.12.bin` → sha256 `17f54933f87d22f72a7c7c548b1d0c79cf804824064c626be25d42d6863b831f`
- BL31 `rk3576_bl31_v1.24.elf` → sha256 `e2cf4e0e920dfe1daa6412c05f49dc7e5c0f9888d3a3e8eecc85fbe1e86a23d1` [S7]

→ 到着後、実機のブート領域を `rkdeveloptool`/`dd` で吸い出し、この値と一致すればブロブは「配布物のまま」と確証できる。[S7][S8]

---

## 5. 懸念点への回答（ユーザーの3つの問い）

### (a) FCC認証は取れている？ → **取れている（無線モジュール単位で確認可）**
- Quectel FCS960K: **FCC ID `XMR2023FCS960K`**（grantee: Quectel Wireless Solutions Company Limited / grantee code `XMR` / grant 2023-09-04 / OEMインテグレーション用の Single Modular 承認）。試験はSporton(昆山)ラボ。[S14]
  - 変種: `XMR2023FCS960KN`（-N）、`XMR2024FCS960KNL`（-NL）、`XMR25FCS960KE`（-E, 2025-04-02）。
- 製品ページ／再販の記載では reComputer RK3576 全体も **FCC/CE/TELEC/RoHS**（産業版はKC/RCM等も）を標榜。[S15]
- **到着後の確認法:** 基板/筐体ラベルの FCC ID を読み、fccid.io / fcc.report で grant を突き合わせる。モジュールのFCC IDは上記で事前に判明済み。

### (b) 米国が規制している部品は入っている？ → **チップ単位では該当なし。ただしブランド元Quectelに注意フラグ1件**
- SoC(Rockchip)・AIC8800(AICsemi)・Realtek・Morse Micro(豪) は、確認した範囲で**米Entity List等の輸出規制対象に見当たらない**。AICsemiは上海の設計会社（2018設立、出資にXiaomi/AllWinner/Walden等）。[S11]
- **要注意:** Wi-Fiモジュールの**ブランド元 Quectel** は、米議会の要請を受け **FCC Covered List 追加が検討**され（Quectelは「未掲載」と反論）、**米国防総省の NDAA §1260H「中国軍関連企業」リストに2025年1月に掲載**された（Quectelは否認し提訴中）。輸出禁止ではないが、「米政府が安全保障上マークしている企業の部品」には該当する。[S16][S17]
- 実シリコン(AIC8800)はQuectelとは別会社AICsemi製。モジュールのブランドと中身のチップは分けて考える点に注意。

### (c) HiSiliconチップは入っている？ → **入っていない**
- 回路図全文検索で HiSilicon のヒット0。無線3系統の実体も Quectel/AICsemi・Morse Micro・Realtek で、**HiSilicon(華為系)は不在**。[§1]

### (d) OS以外で通信していないか？（＝ハード/ブートが勝手に通信していないか）
- OSINTだけでは「実通信」は観測できない（＝到着後の `tcpdump` マター）。ただし事前に**正当な接触先の母集合**は判明: ビルド時は `seeed-studio.github.io` と `github.com/MorseMicro` のみ。[S3]
- SenseCraft（Seeedのクラウド）はアプリ層で `https://sensecap.seeed.cc/deviceapi` にPOSTする設計＝**ユーザーが明示的に使うセンサ連携**で、裏で常時送る既定テレメトリの記述は見当たらない。到着後にこの宛先が「使ってないのに出ている」かを監視すれば足りる。[S18]

---

## 6. CVE / 既知脆弱性の下見（到着後にカーネル版で要確認）
- **RK3576固有のシリコンCVEは発見できず。** RK3588では Rockchipプロセッサ脆弱性の報告あり（BI.ZONE, BDU:2026-03417, CVSS7.5）だが対象はRK3588。[S19]
- Rockchip系で拾うべきは**Linuxカーネルのドライバ脆弱性**: `rkcif` off-by-one（CVE-2026-52907, 7.8）、RGA(`CVE-2026-43297`) 等。**自ボードのカーネルがこれらを含むかはバージョン依存**＝到着後に `uname -r` とBSP版で確認。[S20]
- AIC8800ドライバは Gentoo セキュリティトラッカー上**未解決セキュリティバグ0**（ただしNVD/MITRE網羅ではない）。[S21]

## 7. OSINTでできたこと / できないことの線引き
**できた（事前確定）:** OS素性・署名/再現性、ベンダ追加物の棚卸し、外部接触先の母集合、ブロブ基準ハッシュ、搭載チップ特定、各無線のFCC ID・サプライヤ素性・米規制状況、CVE下見。
**できない（到着後 or 原理的に不可）:** 実機の実通信観測（tcpdump）、出荷個体と公式イメージの実ファイル差分、ブート領域の実ハッシュ照合、基板の目視改ざん確認 → いずれも到着後。**SoC内BootROM/OTP/クローズドブロブの内部動作**は個人では原理的に検証不能（スコープ外、ネットワーク封じ込めで対処）。

---

## 8. 一次ソース
- **[S1]** Armbian ボードカタログ: https://www.armbian.com/boards/recomputer-rk3576-devkit
- **[S2]** ボード定義 conf: https://github.com/armbian/build/blob/main/config/boards/recomputer-rk3576-devkit.conf
- **[S3]** Seeed固有ビルドinc（接触先）: https://github.com/armbian/build/blob/main/config/sources/vendors/seeed-studio/recomputer-rk35xx-common.inc
- **[S4]** Seeed公式apt InRelease: https://seeed-studio.github.io/seeed_armbian_extension/dists/stable/InRelease
- **[S5]** 拡張リポジトリ: https://github.com/Seeed-Studio/seeed_armbian_extension
- **[S6]** Seeedフラッシュ手順: https://sensecraft.seeed.cc/ai-lab/en/tutorials/rk/getting-start/flash-os/install-system-microsd
- **[S7]** rkbin（ブロブ基準）: https://github.com/armbian/rkbin ／ https://github.com/rockchip-linux/rkbin
- **[S8]** rkdeveloptool: https://github.com/rockchip-linux/rkdeveloptool
- **[S9]** Realtek RTL8211F（GbE PHY）製品ページ: https://www.realtek.com/products/communications-network-ics/item/rtl8211f-cg
- **[S10]** Quectel FCS960K 製品ページ（Wi-Fi6/BT5.4, SDIO3.0）: https://www.quectel.com/product/wi-fi-bluetooth-fcs960k/
- **[S11]** AICsemi 企業概要（上海/2018/出資者）: https://www.cbinsights.com/company/aicsemi
- **[S12]** AIC8800 mainline化のlinux-wireless議論: https://lwn.net/Articles/1084468/
- **[S13]** Morse Micro MM6108 データシート／firmwareリポ: https://morsemicro.com/wp-content/uploads/2025/06/MM6108_Data_Sheet.pdf ／ https://github.com/MorseMicro/morse-firmware
- **[S14]** FCC ID XMR2023FCS960K（Quectel FCS960K）: https://fccid.io/XMR2023FCS960K ／ RF試験報告: https://fcc.report/FCC-ID/XMR2023FCS960K/6772349.pdf
- **[S15]** reComputer RK3576 製品/認証記載（CNX Software）: https://www.cnx-software.com/2026/05/21/recomputer-rk3576-rk3588-edge-ai-computers-are-supported-by-recomputer-ai-lab-one-click-deployment-platform/
- **[S16]** FCC Covered List検討（Reuters経由報道）: https://insidetowers.com/rosenworcel-seeks-to-add-two-chinese-iot-module-makers-to-covered-list
- **[S17]** Quectel NDAA 1260H掲載・提訴: https://finance.yahoo.com/sectors/technology/articles/chinese-wireless-firm-quectel-sues-190614808.html
- **[S18]** Seeed SenseCraft データ報告仕様／プライバシー: https://wiki.seeedstudio.com/sensecraft-data-platform/ ／ https://sensecap.seeed.cc/portal/public/html/user-privacy-agreement-en.html
- **[S19]** BI.ZONE Rockchip(RK3588)脆弱性: https://bi.zone/eng/news/my-obnaruzhili-uyazvimost-v-protsessore-rockchip/
- **[S20]** CVE-2026-52907（rkcif off-by-one）: https://cveawg.mitre.org/api/cve/CVE-2026-52907 ／ CVE-2026-43297(RGA): https://feedly.com/cve/CVE-2026-43297
- **[S21]** Gentoo AIC8800 セキュリティ: https://packages.gentoo.org/packages/net-wireless/aic8800/security

---

## 付録A. フォーラム横断調査 —「不審な通信」の報告は出ているか
**問い:** reComputer RK3576（およびRK3576チップ全般）について、「勝手に外部へ通信する／phone-home／バックドア」といった報告がコミュニティに上がっていないか。

### A-1. 探した場所と探し方（方法の記録）
SBC（シングルボードPC）界隈で不具合・不審挙動が最初に共有される主要フォーラムを横断。検索語は英語で「製品名／チップ名 × (suspicious traffic / phone home / backdoor / telemetry / unexpected network connection / privacy)」を組み合わせ、各サイトに絞って実施。

| フォーラム/サイト | 位置づけ | 絞り込み方 |
|---|---|---|
| **forum.armbian.com** | 出荷OS(Armbian)本家。ボード固有バグの一次報告先 | 「RK3576 / recomputer」＋ネットワーク・unexpected connection |
| **cnx-software.com** | 組込みSBCニュースの定番。製品の初報・コメント欄 | 「reComputer RK3576」「Rockchip telemetry」 |
| **dietpi.com/forum** | 派生OSユーザの実運用報告 | 「Seeed reComputer RK3576」 |
| **forum.pine64.org** | Rockchip系SBCの濃いユーザ層 | 「RK3576 / RK3588 phone home」 |
| **forum.openwrt.org** | ルータ化ユーザ（通信挙動に敏感） | 「RK3576」 |
| **Reddit / Lemmy** | 一般ユーザの“体感”報告 | 「Rockchip phone home / china telemetry」 |

### A-2. 結果 — 不審通信の報告は見つからず（クリーンな空振り）
- **reComputer RK3576 に対する「不審な通信・phone-home・バックドア」報告は、いずれのフォーラムにも無し。** [S22][S23]
- 見つかったRK3576関連スレは**ハード/ドライバの不具合**のみで、セキュリティ/通信の作為とは無関係:
  - vendorカーネル更新後にNIC（ネットワーク）を見失う→旧版へ戻すと復帰（RK35xx一般、RK3576固有ではない）[S23]
  - NanoPi R76S(RK3576) の U-Boot warm-reboot/eMMC不具合 [S23]
  - DietPiで miniPCIeの4GモデムがUSBを巻き込んで不動（オーバーレイ起因の駆動問題）[S24]
- **紛らわしい“近いが別物”の事例（混同しないよう明記）:**
  - *ENDLESSDOORS*：The Register報道の**Zbtlink製ルータ**のphone-home/バックドア疑い。**別ベンダ・別製品**でRK3576とは無関係。[S25]
  - mikrocontroller.net：「RockchipがRK3588のコードをアップストリームに出さなくなった」という**透明性の指摘**（データ収集の証拠ではない）。[S26]
  - H96 Max系 RK3576 **TVボックス**のファーム作成スレ：Androidの野良TVボックスはBadBox級リスクの温床だが、**本件の正規Linux製品とは系統が別**。[S27]

### A-3. 読み取り
- **「無い」ことは「安全の証明」ではない**（報告が少ない＝新しめの製品で母数が小さい可能性も含む）。ただし、**出荷時マルウェアは通常コミュニティで早期に露見する**（BadBox等は検知→拡散した）ことを踏まえると、**現時点で既知の不審通信報告ゼロ**は弱いながらポジティブ材料。
- 最終判断は §5(d) のとおり**到着後の `tcpdump` 実測**で確定させる。フォーラムは「既知の地雷が踏まれていないか」の事前確認として機能した。

### A-4. 追加の一次ソース
- **[S22]** OpenWrt Forum（NanoPi R76S/RK3576・通信不審報告なし）: https://forum.openwrt.org/t/nanopi-r76s-rk3576-a-new-openwrt-device/239826
- **[S23]** Armbian Forum（RK3576系の不具合＝NIC消失/eMMC、セキュリティ無関係）: https://forum.armbian.com/topic/60938-nanopi-r76s-u-boot-202604-warm-reboot-mmc-failure/
- **[S24]** DietPi Forum（Seeed reComputer RK3576・4Gモデム駆動問題）: https://dietpi.com/forum/t/seeed-studio-recomputer-rk3576/25306
- **[S25]** The Register（Zbtlinkルータ ENDLESSDOORS＝別ベンダの事例）: https://www.theregister.com/a/5283794
- **[S26]** mikrocontroller.net（RK3588アップストリーム非提供の透明性指摘）: https://www.mikrocontroller.net/part/RK3588
- **[S27]** Armbian Forum（H96 Max M9 RK3576 **TVボックス**ファーム・別系統）: https://forum.armbian.com/topic/40483-efforts-to-develop-firmware-for-h96-max-m9-rk3576-tv-box-8g128g/

---
*本レポートは独立した購入者による到着前OSINTの記録であり、製品への疑義表明ではない。所見は2026-10-28時点の公開情報に基づく。生データは同ディレクトリ `raw/` に保存。*
