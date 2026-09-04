#!/usr/bin/env bash
# make-factory.sh — create (or reuse) the skeleton OpenClaw agents for a project factory.
#
# The whole multi-agent system is the "factory".
# The coordinator agent is the "foreman".
#
# Roles created:
#   <project>-foreman     coordinator / floor boss
#   <project>-spec        specification
#   <project>-implement   implementation
#   <project>-verify      verification (includes testing)
#   <project>-ship        release / ship (human-gated)
#
# Workspaces:
#   ~/.openclaw/workspaces/<project>/{foreman,spec,implement,verify,ship}
#
# Note: triage is not provisioned by this skeleton yet. test is part of verify.
#
# Usage:
#   FACTORY_PROJECT=my-project ./make-factory.sh
#
set -euo pipefail

# Prefer an explicit project; fall back only for legacy convenience.
FACTORY_PROJECT="${FACTORY_PROJECT:-west-boca-pc-build-lab}"
export FACTORY_PROJECT

workspace_base="$HOME/.openclaw/workspaces/$FACTORY_PROJECT"

echo "Factory project: $FACTORY_PROJECT"
echo "Workspace root:  $workspace_base"
echo

if ! command -v openclaw >/dev/null 2>&1; then
  echo "ERROR: openclaw is not in PATH." >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is not in PATH." >&2
  exit 2
fi

# role_name:workspace_subdir
roles=(
  "foreman:foreman"
  "spec:spec"
  "implement:implement"
  "verify:verify"
  "ship:ship"
)

for entry in "${roles[@]}"; do
  role="${entry%%:*}"
  subdir="${entry##*:}"
  agent="${FACTORY_PROJECT}-${role}"
  workspace="${workspace_base}/${subdir}"

  if openclaw agents list --json |
    jq -e --arg id "$agent" \
      '.. | objects | select(.id? == $id)' >/dev/null
  then
    echo "REUSE:  $agent"
  else
    echo "CREATE: $agent -> $workspace"
    openclaw agents add "$agent" \
      --workspace "$workspace" \
      --non-interactive
  fi
done

echo
echo "Agent roster ready for factory: $FACTORY_PROJECT"
echo "Foreman agent: ${FACTORY_PROJECT}-foreman"
