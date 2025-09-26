# Agent Enabled Orchestrator (ae-orchestrator)

GitHub 駆動の複数エージェント協調開発を実現する軽量オーケストレータです。

- Connector: GitHub Issues をポーリングし、役割×`status:ready` を検知して `/start` などのアクションを実行
- Runner:
  - Zellij ブリッジ（write-chars + Enter、自動実行）
  - Exec フォールバック（`codex "<PROMPT>"` を1回実行）
- Autopilot: クールダウン/ラベル制御/ローテーション/ジッタで「続けて」フィードを調整
- Telemetry: `telemetry/{logs,status,events.ndjson}` に出力 + TUI ステータスボード
- Backlog: JSON/YAML から Issues を同期し、段階的に `status:ready` で投入

## Quickstart (WSL/Linux)

1) 依存
- gh CLI / jq / zellij（任意、Execのみなら不要）

2) 環境例
```bash
export GH_REPO="<owner>/<repo>"           # 管理したいGitHubリポ
export AGENT_ROLE="role:IMPL-MED-1"       # 担当ロールラベル
export WATCH_INTERVAL=60                   # ポーリング間隔（秒）
# Zellij ランナー（推奨）
export CODEX_BRIDGE=zellij
export ZELLIJ_SESSION=codex-impl-1         # セッション名
# Exec フォールバック（Zellijが無い場合）
# export CODEX_EXEC=1
# export AGENT_WORKDIR="/path/to/your/repo"
# Autopilot（長時間自走）
export CODEX_AUTOPILOT=1
```

3) 実行
```bash
scripts/connector/watch.sh
```
- READY キューを検知すると `/start` を投下 → Zellij セッションにプロンプト投入 + Enter 送信 → Autopilot が継続投入

4) 可視化
```bash
scripts/telemetry/status-board.sh --watch 10   # 概要
scripts/telemetry/status-board.sh --events 50  # 直近イベント
```

## Smoke Test (IMPL-1)

ウォッチャー/ランナーのスモークテストを実行するには、環境変数を設定した上で以下を実行します。

```bash
export GH_REPO="<owner>/<repo>"
export AGENT_ROLE="role:IMPL-MED-1"

# 別ターミナルでウォッチャーを起動しておく
scripts/connector/watch.sh &

# スモークテスト: 試験用 Issue を作成/再利用し、
# status:ready → watcher が /start コメントと共に status:running へ遷移することを検証
scripts/smoke/impl1.sh
```

期待結果:
- Issue に `/start` コメントが付与される
- ラベルが `status:ready` から `status:running` に切り替わり、再ディスパッチが止まる（冪等化）

## 開発
- 進捗・計画: Roadmap (#10), MVP (#1), タスク #2–#9 を参照
- ライセンス: Apache-2.0

```
├─ scripts/
│  ├─ connector/watch.sh
│  ├─ runner/bridge-zellij.sh
│  ├─ runner/exec.sh
│  ├─ autopilot.sh
│  ├─ telemetry/status-board.sh
│  └─ backlog/sync.sh
└─ .github/workflows/lint.yml
```
