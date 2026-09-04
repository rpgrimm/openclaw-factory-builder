#!/usr/bin/env bash
# configure_delegation.sh — allow the foreman to spawn worker agents.
#
# Sets agents.list[N].subagents.allowAgents for <project>-foreman to:
#   <project>-spec
#   <project>-implement
#   <project>-verify
#   <project>-ship
#
# Requires:
#   FACTORY_PROJECT
#   openclaw config access
#   agents already created
#
# After a successful run, restart the gateway so the change is live:
#   openclaw gateway restart
#
# Usage:
#   FACTORY_PROJECT=my-project ./configure_delegation.sh
#
set -euo pipefail

if [[ -z "${FACTORY_PROJECT:-}" ]]; then
  echo "ERROR: FACTORY_PROJECT is not set." >&2
  echo "Example: FACTORY_PROJECT=my-project ./configure_delegation.sh" >&2
  exit 2
fi

export FACTORY_PROJECT

foreman_agent="${FACTORY_PROJECT}-foreman"

if ! command -v openclaw >/dev/null 2>&1; then
  echo "ERROR: openclaw is not in PATH." >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is not in PATH." >&2
  exit 2
fi

idx="$(
  openclaw config get agents.list --json |
    jq -r --arg id "$foreman_agent" '
      to_entries[]
      | select(.value.id == $id)
      | .key
    '
)"

echo "Project:        $FACTORY_PROJECT"
echo "Foreman agent:  $foreman_agent"
echo "Agent-list idx: $idx"

if [[ ! "$idx" =~ ^[0-9]+$ ]]; then
  echo "Could not find $foreman_agent in agents.list" >&2
  exit 1
fi

allow_agents="$(
  jq -cn \
    --arg spec "${FACTORY_PROJECT}-spec" \
    --arg implement "${FACTORY_PROJECT}-implement" \
    --arg verify "${FACTORY_PROJECT}-verify" \
    --arg ship "${FACTORY_PROJECT}-ship" \
    '[$spec, $implement, $verify, $ship]'
)"

echo "Allowed agents:"
echo "$allow_agents" | jq .

openclaw config set \
  "agents.list[$idx].subagents.allowAgents" \
  "$allow_agents" \
  --strict-json

openclaw config validate

echo
echo "Configured delegation:"
openclaw config get \
  "agents.list[$idx].subagents" \
  --json

echo
echo "Restart OpenClaw to activate the change:"
echo "  openclaw gateway restart"
