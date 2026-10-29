# reComputer RK3576 サプライチェーン／バックドア調査 — 調査スコープ定義書

作成日: 2026-10-28 / 対象機: Seeed Studio reComputer RK3576（Rockchip RK3576 SoC）/ 文書種別: 独立調査のスコープ（ベンダー共有用）

> **目的:** 購入した reComputer RK3576 1台について、出荷状態のソフトウェア／ファームウェア／ハードウェアに意図しない作為（バックドア・不正な常駐・改ざん・無断のデータ送信）が無いかを、独立した立場で確認する。本書は**何をどこまで調べるか（スコープ）と、何を調べないか（スコープ外）**を事前に明確化し、認識を揃えるためのもの。特定の疑義を主張する文書ではない。各項目の末尾 [Sn] は根拠ソース（§7）を指す。

---

## 1. 調査の方針
- **非破壊・再現可能・一次情報ベース**で行う。公開されている公式ソース（Armbian [S1][S2] ／Seeed [S3][S4][S5] ／Rockchip [S7]）を基準に、出荷個体を照合する方式を基本とする。
- 判定は「主観」ではなく **差分・ハッシュ照合・通信観測という客観手段**で行える範囲に限定する。
- 検証不能な領域（SoC内部等 [S12][S13]）は結論を断定せず、「検証不能」と明記したうえで運用側の封じ込めで対処する。

## 2. スコープ内（実施する）

| # | 層 | 具体的に確認する内容 | 手段 | 参照 |
|---|----|--------------------|------|------|
| 2-1 | 配布網（実機不要） | 公式OSが再現可能ビルドか／署名の有無、ベンダ追加パッケージの棚卸し、外部接触先、照合用の基準値取得 | 公開ソース・apt索引・署名鍵の確認（**実施済み**） | [S1][S2][S3][S4] |
| 2-2 | ソフトウェア | 隠しアカウント・既定認証情報・`authorized_keys`、listenポート・常駐サービス・cron、**出荷品と公式イメージのファイル差分**、カーネルモジュール(DKMS)のソース確認 | 実機＋SSH、`debsums`／`dpkg -V`／apt管理外ELF抽出（標準ツール）、追加物の基準は [S3][S4] | [S3][S4] |
| 2-3 | 通信挙動 | 起動直後〜アイドル時に外部へ出る通信先の確認（想定外の宛先の有無）。既知の正当な接触先＝`seeed-studio.github.io`／`github.com/MorseMicro` | `tcpdump`＋宛先の素性確認（既知先の根拠は [S3]） | [S3] |
| 2-4 | ファーム／ブート | ブートローダ・BL31・DDR訓練ブロブ・DTB を吸い出し、**公式配布物とのハッシュ照合**／余計なデバイス有効化の有無。基準ブロブ名はボード定義に明記、実体ハッシュは rkbin から取得済み | 実機＋`rkdeveloptool` [S8]／`dd`、基準＝[S2][S7] | [S2][S7][S8] |
| 2-5 | ハードウェア（軽装備のみ） | UARTでのブートログ目視（コンソール＝`ttyFIQ0`系）、基板のルーペ／顕微鏡での目視比較、（必要時）SPIフラッシュの直読み照合。想定無線＝AIC8800(SDIO) | USB-UART変換器（ピン配置は [S17]）、ルーペ、（任意）CH341A＋`flashrom` [S10]、無線の素性は [S9] | [S2][S9][S10][S17] |

## 3. スコープ外（実施しない）＋理由

| 除外項目 | 理由 | 参照 |
|---|---|---|
| ロジックアナライザ／オシロによる全バス傍受・信号解析 | 個人の費用対効果が低く、2-2〜2-5で判断の大半が付くため不要 | — |
| X線撮影・ダイ開封(decap)・半導体顕微鏡解析 | ラボ専用設備が必須。個人の現実的範囲外 | — |
| 電力／電磁波サイドチャネル解析、USBファジング | 専門設備・時間が過大で、今回の目的に不釣り合い | — |
| **SoC内BootROM／OTPヒューズ／Rockchipクローズドブロブ（DDR訓練・BL31）の内部動作検証** | **原理的に個人では検証不能**。中身は非公開でダイ解析が必要。OTPはsecure worldのみアクセス可。→「検証不能なブラックボックス」として扱い、2-3の通信監視と2-4のハッシュ照合で封じ込める | [S12][S13][S14][S15] |

## 4. 前提・制約（結論の限界）
- 本調査で「クリーン」と言えるのは **ソフト／ファーム層（2-2〜2-4）まで**。ハッシュ一致・差分なし・想定外通信なし、で該当範囲の作為を否定できる。
- **SoC内部とクローズドブロブは検証対象外**であり、「問題なし」とは断定しない（§3の理由による）。これはRK3576固有ではなくRockchip SoC全般に共通する構造的前提。[S12]
- maskrom/downloadモードによる再フラッシュは物理アクセス前提の仕様であり、脅威モデルの前提として扱う（バックドアではない）。[S13]
- 対象は**出荷時のLinux(Armbian)構成**。別途提供されるAndroid等の別イメージを使用する場合は、そのイメージを別スコープで監査する必要がある（出荷時マルウェア事例は不透明なAndroidイメージが温床）。[S19]

## 5. 事前所見（現時点・good faith）
事前調査の範囲では、supply-chainの透明性は良好と評価している（断定ではなく現時点の所見）:
- プリインストールOSは**再現ビルド可能な署名付き Armbian（Platinum対応）**。独自の不透明イメージではない。[S1][S6]
- ベンダ追加物は**GPG署名付きの公式aptリポジトリ**（InRelease/Release.gpg有効、鍵RSA4096 FP `31C1 8788 0FFB 20E2 9D54 BFFA 266A 668B 2BF2 698C`）に限定され、索引（全192パッケージ）に**テレメトリ／解析／phone-home系や不審パターンは検出されず**。[S4]
- ビルド時の外部接触先は公式GitHub資産に限定。拡張機能はOTA・ディスク暗号化・セキュアブート等の**セキュリティ強化側**。[S3][S5]

## 6. ベンダーへの確認・依頼（任意）
調査精度を上げるため、可能であれば以下を共有いただけると助かる:
- (a) RK3576 の **データシート／TRM** の入手経路（現在、公開ミラー [S18] は取得不可、公式マニュアル [S17] のみ）。
- (b) ブート用ブロブ（DDR訓練・BL31）の**提供元・バージョン対応表**（出荷個体のハッシュ照合の裏取り用、現基準は [S7]）。
- (c) 出荷イメージの **チェックサム／署名の公式な配布場所**（Armbian側 [S1] 以外にベンダ提供があるか）。
- (d) **Androidイメージ提供の有無**と、そのビルドの透明性（再現可否・署名）。

## 7. 参照ソース（一次情報）
- **[S1]** Armbian ボードカタログ（イメージ/sha/asc/kernel/maintainer）: https://www.armbian.com/boards/recomputer-rk3576-devkit
- **[S2]** Armbian ボード定義 conf（ブート構成・ブロブ名・コンソール・無線）: https://github.com/armbian/build/blob/main/config/boards/recomputer-rk3576-devkit.conf
- **[S3]** Seeed固有ビルド共通inc（apt追加・接触先・導入物）: https://github.com/armbian/build/blob/main/config/sources/vendors/seeed-studio/recomputer-rk35xx-common.inc
- **[S4]** Seeed公式apt（配布・署名 InRelease／索引）: https://seeed-studio.github.io/seeed_armbian_extension/dists/stable/InRelease
- **[S5]** Seeed apt拡張リポジトリ（ソース：OTA/暗号化/セキュアブート）: https://github.com/Seeed-Studio/seeed_armbian_extension
- **[S6]** Seeed フラッシュ手順（Armbian公式へ誘導）: https://sensecraft.seeed.cc/ai-lab/en/tutorials/rk/getting-start/flash-os/install-system-microsd
- **[S7]** rkbin（ブロブ配布・ハッシュ基準）: https://github.com/armbian/rkbin ／ https://github.com/rockchip-linux/rkbin
- **[S8]** rkdeveloptool（ローダ吸い出し/フラッシュ）: https://github.com/rockchip-linux/rkdeveloptool
- **[S9]** radxa-pkg/aic8800（無線ドライバ・firmware）: https://github.com/radxa-pkg/aic8800
- **[S10]** flashrom（SPI直読み）: https://www.flashrom.org/
- **[S12]** Collabora（Rockchipブートチェーンのクローズドブロブ事情）: https://www.collabora.com/news-and-blog/blog/2024/02/21/almost-a-fully-open-source-boot-chain-for-rockchips-rk3588/
- **[S13]** Bootlin（loader/maskromの素性）: https://bootlin.com/blog/recovery-boot-on-rockchip-socs/
- **[S14]** 3mdeb（Rockchipセキュアブート/OTP署名検証）: https://blog.3mdeb.com/2021/2021-12-03-rockchip-secure-boot/
- **[S15]** Pengutronix（RK3588セキュアブート/OTP=secure worldのみ）: https://www.pengutronix.de/de/blog/2026-06-19-rk3588-secure-boot.html
- **[S16]** Seeed User Privacy Agreement（SenseCraft/デバイス報告情報）: https://sensecap.seeed.cc/portal/public/html/user-privacy-agreement-en.html
- **[S17]** Seeed reComputer RK3576 ユーザーマニュアル（基板・ピン配置）: https://files.seeedstudio.com/wiki/reComputer_RK/Documents/recomputer_rk3576/recomputer_rk3576_user_manual.pdf
- **[S18]** RK3576 データシート公開ミラー（現在404、要手動再試行）: https://www.armdesigner.com/download/Rockchip_RK3576_Datasheet_V1.5-20241216.pdf
- **[S19]** BadBox/Triada 出荷時マルウェア事例（Androidイメージ対比）: https://thehackernews.com/2025/04/triada-malware-preloaded-on-counterfeit.html

---
*本書は独立した購入者による自機の点検スコープを示すもので、製品への疑義の表明ではありません。所見は事前調査時点のものです。*
