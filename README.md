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
export GH_REPO="itdojp/ae-orchestrator"      # 管理対象リポジトリ
export AGENT_ROLE="role:IMPL-MED-1"          # 担当ロールラベル
export CODEX_BRIDGE=zellij                   # Zellij セッションへ橋渡し
export ZELLIJ_SESSION=codex-impl-1           # 稼働中のセッション名
bash scripts/connector/watch.sh
```
- READY キューを検知すると `/start` を投下し、`status:ready` を外して `status:running` を付与
- `CODEX_BRIDGE=zellij` が有効なら Zellij セッションにプロンプトを投入
- フォールバックとして `CODEX_EXEC=1` + `AGENT_WORKDIR=/path/to/repo` でローカル実行も選択可能（内部では `codex exec` を使用）
- READY だが既に `status:running` の課題は自動的にスキップ（多重 /start 防止）
- Autopilot が有効なら継続投入

4) 可視化
```bash
scripts/telemetry/status-board.sh --watch 10   # 概要
scripts/telemetry/status-board.sh --events 50  # 直近イベント
```

## 開発
- 進捗・計画: Roadmap (#10), MVP (#1), タスク #2–#9 を参照
- ライセンス: Apache-2.0

## 運用メモ
- ウォッチャー常駐: 上記環境変数を設定し `bash scripts/connector/watch.sh` を tmux/Zellij/systemd で常駐させる。
- ステータス監視: `scripts/telemetry/status-board.sh --watch 10`（テーブル表示）、`--events 50`（イベント tail）
- Autopilot: `CODEX_AUTOPILOT=1` と `CODEX_AUTOPILOT_INTERVAL` / `CODEX_AUTOPILOT_COOLDOWN` を必要に応じて調整
- ラベル整備: `DRY_RUN=1 GH_REPO=... scripts/admin/seed-labels.sh` で不足ラベルを確認（DRY_RUN=0 で反映）
- ログメンテナンス: `MAX_LINES=2000 scripts/telemetry/trim-logs.sh` を定期実行し `telemetry/` 下の肥大化を防止
- スモーク: `GH_REPO=... AGENT_ROLE=... scripts/smoke/impl1.sh --mark-done` で READY→RUNNING→DONE の経路を随時検証

```
├─ scripts/
│  ├─ admin/seed-labels.sh
│  ├─ connector/watch.sh
│  ├─ runner/bridge-zellij.sh
│  ├─ runner/exec.sh
│  ├─ autopilot.sh
│  ├─ telemetry/status-board.sh
│  ├─ telemetry/trim-logs.sh
│  └─ backlog/sync.sh
└─ .github/workflows/lint.yml
```
