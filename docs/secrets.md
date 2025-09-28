# GitHub Secrets Setup

| Secret | Description | Used By |
| --- | --- | --- |
| `AE_GH_REPO` | Target repository (owner/name) | maintenance.yml, exec-healthcheck.yml, smoke.yml |
| `AE_SMOKE_ROLE` | Default agent role for smoke/maintenance | maintenance.yml, smoke.yml |
| `AE_SMOKE_ISSUE` | Issue number for smoke failures (optional) | smoke.yml |
| `AE_SMOKE_WEBHOOK` | Webhook URL for smoke cron wrapper (optional) | smoke.yml |
| `AE_HEALTHCHECK_ISSUE` | Issue number for exec fallback failures | exec-healthcheck.yml |
| `AE_TELEMETRY_BUCKET` | S3 bucket for telemetry reports | telemetry-report.yml, maintenance.yml |
| `AE_TELEMETRY_PREFIX` | Prefix within the S3 bucket | telemetry-report.yml, maintenance.yml |
| `AE_TELEMETRY_WEBHOOK` | Webhook for telemetry report notifications | telemetry-report.yml |
| `AE_MAINTENANCE_WEBHOOK` | Notification endpoint after maintenance run | maintenance.yml |
| `AE_RUN_BACKLOG_SYNC` | "1" to enable backlog sync in maintenance | maintenance.yml |
| `AE_BACKLOG_GLOB` | Optional glob for backlog files | smoke.yml |
| `CODEX_TOKEN` | Codex CLI token | exec-healthcheck.yml |
| `CODEX_API_BASE` | Codex API endpoint (optional) | exec-healthcheck.yml |

Use `gh secret set <NAME> --body <value>` (or the GitHub UI) to configure each secret before enabling the workflows.
