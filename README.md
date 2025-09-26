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

環境変数（任意のチューニング）
- `DISPATCH_COOLDOWN_SECONDS` (default: `600`) — ウォッチャーが直近で `/start` コメント済みの場合、同一 Issue への再ディスパッチをスキップするクールダウン秒数。
- `WATCH_DRY_RUN` (default: `0`) — `1` にするとディスパッチをシミュレーション（`/start` コメントやラベル変更は行わず、ステータスに `dry-run` を記録）。CI 等で安全に動作確認したい場合に便利。

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

コマンドラインオプション
- `--once` — 1サイクルのみ実行して終了（CI やワンショット検証向け）

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

オプション:
- `--mark-done` 成功後に `status:done` を付与し、`status:ready/status:running` を外す（キューをクリーンに保つ）
- `--issue <number>` 既存の Issue を対象にしてスモークを行う（新規作成しない）
- `--timeout <sec>` / `--sleep <sec>` タイムアウトやポーリング間隔を CLI から調整

CI/ワンショット向け:
```bash
# 1サイクルのみのディスパッチ→検証
export GH_REPO="<owner>/<repo>"; export AGENT_ROLE="role:IMPL-MED-1"
scripts/smoke/once.sh --mark-done
```
内部で以下を実行します: ラベル初期化 → スモーク Issue 準備 → `watch.sh --once` → 検証（成功時は `--mark-done` でクリーンアップ）

## 開発
- 進捗・計画: Roadmap (#10), MVP (#1), タスク #2–#9 を参照
- ライセンス: Apache-2.0

## 運用メモ
- Secrets 設定: `docs/secrets.md` を参照し GitHub Actions 用の環境を準備
- ウォッチャー常駐: 上記環境変数を設定し `bash scripts/connector/watch.sh` を tmux/Zellij/systemd で常駐させる。
- `scripts/connector/start-watcher.sh` を使うと環境変数込みで watcher を起動しやすい（KEY=VALUE 指定で上書き可能）。
- ステータス監視: `scripts/telemetry/status-board.sh --watch 10`（テーブル表示）、`--events 50`（イベント tail）
- Autopilot: `CODEX_AUTOPILOT=1` と `CODEX_AUTOPILOT_INTERVAL` / `CODEX_AUTOPILOT_COOLDOWN` を必要に応じて調整
- Autopilot 設定例: `scripts/autopilot.env.example`
- ラベル整備: `DRY_RUN=1 GH_REPO=... scripts/admin/seed-labels.sh` で不足ラベルを確認（DRY_RUN=0 で反映）
- ログメンテナンス: `MAX_LINES=2000 scripts/telemetry/trim-logs.sh` を定期実行し `telemetry/` 下の肥大化を防止
- ローテーション: `scripts/telemetry/archive.sh` でイベント／ログを `telemetry/archive/` に退避（systemd 例: `docs/systemd/ae-telemetry-archive.service/.timer`）
- レポート: `scripts/telemetry/report.sh [events.ndjson]` で `kind` 別集計と最新イベントを確認
- HTML レポート: `scripts/telemetry/report-html.sh [events.ndjson] [output.html]`
- スモーク: `GH_REPO=... AGENT_ROLE=... scripts/smoke/run-periodic.sh` を cron などで実行し READY→RUNNING→DONE を検証（内部で `impl1.sh --mark-done` を呼び出し）
- 定期監視: `scripts/smoke/run-cron-wrapper.sh`（失敗時に Webhook 通知、ログ永続化）
- 認証チェック: `scripts/admin/check-gh-auth.sh`
- Zellij セッション整備: `scripts/runner/ensure-zellij.sh` で状態確認（EXITED なら自動削除）。必要に応じ `zellij attach --create codex-impl-1`
- Codex フォールバック: `CODEX_EXEC=1 AGENT_WORKDIR=... scripts/runner/exec.sh <issue>` または `scripts/runner/exec-healthcheck.sh <issue>`
- テレメトリ: `queue-skip` イベントは `status:running` 済みの READY 課題をスキップしたことを示す。`list-ready exit=<code>` は `gh` 失敗からのリトライログ。
- systemd テンプレート: `docs/systemd/ae-watcher@.service`
- Timer チェック: `scripts/ops/test-timers.sh` で `systemctl --user` の状態を確認
- Timer 有効化: `scripts/ops/enable-timers.sh`（`systemctl --user` が利用可能なら）
- GitHub Actions: `.github/workflows/exec-healthcheck.yml`（`CODEX_TOKEN` などの Secrets 必須）
- Telemetry Actions: `.github/workflows/telemetry-report.yml`（HTML/テキストレポートを生成）
- Maintenance Actions: `.github/workflows/maintenance.yml`（`scripts/ops/run-maintenance.sh` を夜次実行）
- バックログ投入: `scripts/backlog/run-cron-wrapper.sh`（`BACKLOG_GLOB` で対象指定）。テンプレ: `scripts/backlog/template.json`。systemd 例: `docs/systemd/ae-backlog-sync.service/.timer`
- Smoke Actions: `.github/workflows/smoke.yml`（Secrets: `AE_GH_REPO`, `AE_SMOKE_ROLE`, 任意で `AE_SMOKE_ISSUE`, `AE_SMOKE_WEBHOOK`）
- メンテナンス一括: `scripts/ops/run-maintenance.sh`（trim→archive→report→smoke/backlog、`WEBHOOK_URL` 可）

```
├─ scripts/
│  ├─ admin/check-gh-auth.sh
│  ├─ admin/seed-labels.sh
│  ├─ connector/start-watcher.sh
│  ├─ connector/watch.sh
│  ├─ runner/bridge-zellij.sh
│  ├─ runner/exec-healthcheck.sh
│  ├─ runner/exec.sh
│  ├─ runner/ensure-zellij.sh
│  ├─ runner/log-zellij-status.sh
│  ├─ autopilot.sh
│  ├─ telemetry/status-board.sh
│  ├─ telemetry/trim-logs.sh
│  ├─ telemetry/archive.sh
│  ├─ telemetry/report.sh
│  ├─ telemetry/report-html.sh
│  ├─ telemetry/publish-reports.sh
│  ├─ telemetry/upload-archive.sh
│  ├─ ops/run-maintenance.sh
│  ├─ backlog/run-cron-wrapper.sh
│  ├─ backlog/sync.sh
│  ├─ backlog/template.json
│  ├─ backlog/template-impl.json
│  └─ backlog/template-docs.json
├─ scripts/smoke/run-cron-wrapper.sh
├─ scripts/smoke/run-periodic.sh
├─ scripts/autopilot.env.example
├─ docs/runbook.md
├─ docs/systemd/ae-watcher@.service
├─ docs/systemd/ae-smoke@.service
├─ docs/systemd/ae-smoke@.timer
├─ docs/systemd/ae-backlog-sync.service
├─ docs/systemd/ae-backlog-sync.timer
├─ docs/systemd/ae-telemetry-archive.service
├─ docs/systemd/ae-telemetry-archive.timer
├─ .github/workflows/exec-healthcheck.yml
├─ .github/workflows/smoke.yml
│  └─ backlog/sync.sh
│  └─ admin/seed-labels.sh
│  └─ smoke/impl1.sh
│  └─ smoke/once.sh
└─ .github/workflows/lint.yml
```
