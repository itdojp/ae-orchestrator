# AE Orchestrator Ops Runbook

## Watcher
- Launch via `scripts/connector/start-watcher.sh`（Key=Value 指定で上書き可。実行前に `check-gh-auth` と `ensure-zellij` を呼び出す）。
- 常駐化は tmux/Zellij/systemd で行う。systemd 雛形: `docs/systemd/ae-watcher@.service`
  ```bash
  systemctl --user enable --now ae-watcher@role:IMPL-MED-1.service
  ```
- Timer 確認: `scripts/ops/test-timers.sh` で `systemctl --user` の有無と有効化手順をチェック
- Timer 有効化: `scripts/ops/enable-timers.sh`（`systemctl --user` が使える環境で実行）

## Zellij session
- Check status: `scripts/runner/ensure-zellij.sh`
- If session is exited, the script cleans it up; re-create via `zellij attach --create codex-impl-1`
- Keep a dedicated Codex pane open and monitored.

## Codex Exec fallback
- Health-check via `scripts/runner/exec-healthcheck.sh <issue>` (requires `CODEX_EXEC=1` path).
- Use for environments without Zellij.

## Smoke tests
- Cron 実行: `scripts/smoke/run-cron-wrapper.sh`（失敗時 WEBHOOK 通知オプションあり）。
- 手動/CI: `scripts/smoke/run-periodic.sh`（`MARK_DONE=0` で ready を残す）。
- Crontab 例: `0 * * * * GH_REPO=... AGENT_ROLE=... WEBHOOK_URL=https://hooks.example scripts/smoke/run-cron-wrapper.sh`

## GitHub Actions
- Secrets 一覧: `docs/secrets.md` を参照
- ナイトリー fallback 監視: `.github/workflows/exec-healthcheck.yml`
- Smoke 監視: `.github/workflows/smoke.yml`
- Secrets: `CODEX_TOKEN`, `AE_HEALTHCHECK_ISSUE`, `AE_GH_REPO`, `AE_SMOKE_ROLE`、任意で `AE_SMOKE_ISSUE`, `AE_SMOKE_WEBHOOK`, `AE_BACKLOG_GLOB`, `CODEX_API_BASE`

## Labels
- Check/apply labels: `DRY_RUN=1 GH_REPO=... scripts/admin/seed-labels.sh`
- Run with `DRY_RUN=0` to apply.

## Telemetry
- Trim logs: `MAX_LINES=2000 scripts/telemetry/trim-logs.sh`
- アーカイブ: `scripts/telemetry/archive.sh` で `telemetry/archive/` 配下に退避（systemd: `ae-telemetry-archive.service/.timer`）
- レポート: `scripts/telemetry/report.sh` / `scripts/telemetry/report-html.sh`
- 公開: `scripts/telemetry/publish-reports.sh`（S3/WEBHOOK へ転送）
- アーカイブ転送: `scripts/telemetry/upload-archive.sh`（S3_BUCKET が必要）
- Monitor: `scripts/telemetry/status-board.sh --watch 10`

## Autopilot
- Optional env template: `scripts/autopilot.env.example`
- Tune intervals as needed per role.

## Auth
- Verify credentials: `scripts/admin/check-gh-auth.sh`

## Backlog
- 手動同期: `scripts/backlog/sync.sh` (backlog JSON/YAML 指定)。テンプレ: `scripts/backlog/template.json`, `scripts/backlog/template-impl.json`, `scripts/backlog/template-docs.json`
- Cron 実行: `scripts/backlog/run-cron-wrapper.sh`（`BACKLOG_GLOB` で対象ファイルを指定、成功/失敗をテレメトリ記録）。
- systemd 例: `docs/systemd/ae-backlog-sync.service` + `.timer`

## メンテナンス
- 定期運用: `scripts/ops/run-maintenance.sh` で trim → archive → report → smoke/backlog を一括実行（`WEBHOOK_URL` 指定可）

## Heartbeat
- Send periodic prompts (manual): `zellij --session codex-impl-1 action write-chars -- 'heartbeat'`
- Consider a cron job that checks `ensure-zellij.sh` and notifies if restart needed.

## Incident response
1. Check `status-board` for queue/backlog anomalies.
2. Inspect `telemetry/logs/<role>.log` for repeated errors.
3. Validate auth (`check-gh-auth.sh`).
4. Recreate Zellij session if needed and restart watcher.

## FAQ / トラブルシュート
- **Zellij セッションが EXITED になった**: `scripts/runner/ensure-zellij.sh` でステータス確認。自動再生成は不可のため、ターミナルで `zellij attach --create codex-impl-1` を実行して Codex ペインを再度立ち上げる。
- **Codex CLI が `cursor position` エラーで落ちる**: フォールバック実行は `scripts/runner/exec.sh`（内部で `codex exec`）を利用する。旧バージョンの `codex` コマンドは使用しない。
- **スモークが失敗する**: `telemetry/logs/<role>.log` の `/start` 直後のログを確認し、GitHub ラベルが `status:running` に変わっているか検証。必要に応じ `scripts/smoke/run-cron-wrapper.sh` のログを参照。
