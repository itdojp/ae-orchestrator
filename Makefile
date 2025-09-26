.PHONY: watch watch-once smoke smoke-done smoke-once status events seed-labels

# Expect GH_REPO and AGENT_ROLE to be exported in the environment
# Example:
#   export GH_REPO=owner/repo
#   export AGENT_ROLE=role:IMPL-MED-1

WATCH_INTERVAL ?= 60
EVENT_LINES ?= 50

watch:
	@WATCH_INTERVAL=$(WATCH_INTERVAL) scripts/connector/watch.sh

watch-once:
	@WATCH_INTERVAL=$(WATCH_INTERVAL) scripts/connector/watch.sh --once

smoke:
	@scripts/smoke/impl1.sh

smoke-done:
	@scripts/smoke/impl1.sh --mark-done

smoke-once:
	@WATCH_INTERVAL=$(WATCH_INTERVAL) scripts/smoke/once.sh --mark-done

status:
	@scripts/telemetry/status-board.sh --summary

events:
	@scripts/telemetry/status-board.sh --events $(EVENT_LINES)

seed-labels:
	@DRY_RUN=0 scripts/admin/seed-labels.sh

