#!/usr/bin/env bash
set -euo pipefail
: "${GH_REPO:?}"; : "${AGENT_WORKDIR:?}"; issue="${1:?issue-number required}"
for c in gh jq codex; do command -v "$c" >/dev/null 2>&1 || { echo "Required: $c" >&2; exit 2; }; done
json=$(gh issue view "$issue" --repo "$GH_REPO" --json number,title,body,url,labels,author,createdAt)
number=$(jq -r '.number' <<<"$json"); url=$(jq -r '.url' <<<"$json"); title=$(jq -r '.title' <<<"$json")
body=$(jq -r '.body // "(no body)"' <<<"$json"); labels=$(jq -r '[.labels[].name] | join(", ")' <<<"$json")
author=$(jq -r '.author.login' <<<"$json"); created=$(jq -r '.createdAt' <<<"$json")
prompt=$(cat <<PROMPT
You are an agent. Work in this repository workspace.
Task: Drive Issue #${number}: ${title}
URL: ${url}
Labels: ${labels}
Author: ${author}  Created: ${created}

Context (issue body):
---
${body}
---

Instructions (Marathon):
- Pick next minimal step; implement → test → commit → update Draft PR → post progress to the Issue.
- Keep scope tight; avoid unrelated changes; keep diffs ≤ 300 LOC per PR.
- If blocked, record cause and unblock conditions; otherwise continue.
- Stop when labeled status:review/done/blocked.
PROMPT
)
(
  cd "$AGENT_WORKDIR"
  codex exec "$prompt"
)
