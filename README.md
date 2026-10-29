# reComputer RK3576 バックドア調査リポジトリ

Seeed Studio **reComputer RK3576**（Rockchip RK3576）に、出荷時の作為（バックドア・不正な常駐・改ざん・無断送信）が無いかを、**macOS 1台**で独立検証するための調査一式。事前OSINT（完了済み）と、到着後の3段階調査（ハードウェア→ネットワーク→OS）の手順・レポート・スクリプトをまとめている。

## クイックスタート
```bash
# 1. macOS 環境構築（brew一式・rkdeveloptoolビルド・作業ディレクトリ作成）
./scripts/setup-macos.sh

# 2. 到着後の調査（詳細は INVESTIGATION.md）
./scripts/net-capture.sh 1800          # ネットワーク: 30分キャプチャ＋宛先サマリ
./scripts/os-audit.sh user@<RK3576_IP> # OS: SSHで一括点検
./scripts/verify-blobs.sh              # ファーム: ブロブのハッシュ照合
```

## 構成
```
.
├── README.md                 ← これ
├── INVESTIGATION.md          ← 統合ガイド（OSINT→3段階の全手順・用語集・ソース）★まずこれ
├── scripts/
│   ├── setup-macos.sh        ← macOS環境構築（冪等）
│   ├── net-capture.sh        ← 通信キャプチャ＋宛先サマリ
│   ├── os-audit.sh           ← 実機SSHでOS層を一括点検
│   └── verify-blobs.sh       ← ブート領域/ブロブのハッシュ照合
├── docs/                     ← 一次ソース付き詳細レポート（md + PDF）
│   ├── reComputer_RK3576_OSINT_report.md          事前OSINT本体（付録A=フォーラム調査）
│   ├── reComputer_RK3576_JC-STAR_view.md          JC-STAR★1観点
│   ├── reComputer_RK3576_assessment_scope.md      ベンダー共有用スコープ定義書
│   ├── reComputer_RK3576_backdoor_investigation.md 完全版レポート
│   └── reComputer_RK3576_howto.md                 まとめ＋実践手順（旧・用語解説厚め）
├── data/
│   ├── downloads/            ← 回路図PDF・ブロブ(DDR/BL31)・apt索引・GPG鍵・ボード定義conf
│   └── osint-raw/            ← JC-STAR★1要件書・apt鮮度取得データ
└── tools/                    ← setup時にビルドされる rkdeveloptool（git管理外）
```

## 事前OSINTの結論（要約）
- プリインストOS = 署名付き・再現可能な **Armbian**。ベンダ追加物 = PGP署名付き公式APT（**全192パッケージに不審物なし**）。
- 搭載無線3系統の素性確定（**HiSilicon不在**）: Quectel FCS960K（中身 AICsemi AIC8800）/ Morse Micro HaLow / Realtek RTL8211F×2。FCC認証あり（FCS960K = FCC ID `XMR2023FCS960K`）。
- 注意フラグ: Wi-Fiブランド元 **Quectel が米NDAA §1260H 掲載**（地政学リスク。JC-STAR観点では対象外）。
- フォーラム横断で**不審通信の既知報告ゼロ**。
- **確証可能=L1(OS)/L2(ブート領域)**、**検証不能=L4(SoC内部)→通信監視で封じ込め**。

詳細と一次ソースは `INVESTIGATION.md` および `docs/`。

## 注意
- `data/` は配布元から取得した素材（untrusted dataとして扱う）。スクリプトは `scripts/` に分離。
- FTDIは接続前に電圧を対象(1.8/3.3V)へ合わせること（5Vのままは破損リスク）。
- 本リポジトリは独立した購入者による自機点検用で、製品への疑義表明ではない。所見は2026-10-29時点。
