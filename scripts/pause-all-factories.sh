#!/usr/bin/env bash
# pause-all-factories.sh — send a freeze instruction to every project foreman.
#
# Discovers factories under ~/.openclaw/workspaces/* and messages the foreman.
# Prefers modern layout:
#   workspace .../<project>/foreman  + agent <project>-foreman
# Falls back to legacy:
#   workspace .../<project>/factory  + agent <project>-factory
#
# Usage:
#   ./pause-all-factories.sh
#
set -Eeuo pipefail

workspace_root="${OPENCLAW_WORKSPACES:-$HOME/.openclaw/workspaces}"

message="Pause all agent activity and GitHub checking for now. Do not delegate new work, inspect or modify GitHub, run implementation or verification tasks, publish anything, or perform scheduled/project activity until I explicitly tell you to resume. Preserve the current project state and wait."

shopt -s nullglob

# Collect unique project directories that look like factories.
declare -A seen_projects=()
project_dirs=()

for candidate in "$workspace_root"/*/foreman "$workspace_root"/*/factory; do
  [[ -d "$candidate" ]] || continue
  project="$(basename "$(dirname "$candidate")")"
  if [[ -n "${seen_projects[$project]:-}" ]]; then
    continue
  fi
  seen_projects["$project"]=1
  project_dirs+=("$workspace_root/$project")
done

if ((${#project_dirs[@]} == 0)); then
  echo "ERROR: No factory workspaces found under:" >&2
  echo "  $workspace_root/*/{foreman,factory}/" >&2
  exit 2
fi

if ! command -v openclaw >/dev/null 2>&1; then
  echo "ERROR: openclaw is not in PATH." >&2
  exit 2
fi

echo "Found ${#project_dirs[@]} software factories under $workspace_root"
echo

failed=0

for project_dir in "${project_dirs[@]}"; do
  project="$(basename "$project_dir")"

  # Prefer foreman agent/workspace; fall back to legacy factory naming.
  if [[ -d "$project_dir/foreman" ]]; then
    agent="${project}-foreman"
  else
    agent="${project}-factory"
  fi

  # If both exist, prefer whatever agent is registered.
  if openclaw agents list --json |
    jq -e --arg id "${project}-foreman" '.. | objects | select(.id? == $id)' >/dev/null 2>&1
  then
    agent="${project}-foreman"
  elif openclaw agents list --json |
    jq -e --arg id "${project}-factory" '.. | objects | select(.id? == $id)' >/dev/null 2>&1
  then
    agent="${project}-factory"
  fi

  echo "=================================================="
  echo "Project: $project"
  echo "Agent:   $agent"
  echo "=================================================="

  if openclaw agent \
    --agent "$agent" \
    --message "$message" \
    --timeout 300
  then
    echo
    echo "PAUSED: $agent"
  else
    rc=$?
    echo >&2
    echo "ERROR: Could not send pause message to $agent (status $rc)" >&2
    failed=1
  fi

  echo
done

if ((failed)); then
  echo "One or more factories could not be contacted." >&2
  exit 1
fi

echo "All factory foremen were sent the pause instruction."
