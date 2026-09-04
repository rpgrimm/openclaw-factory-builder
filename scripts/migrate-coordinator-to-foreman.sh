#!/usr/bin/env bash
# migrate-coordinator-to-foreman.sh — rename <project>-factory → <project>-foreman.
#
# Preserves the coordinator workspace contents by renaming:
#   ~/.openclaw/workspaces/<project>/factory  →  .../foreman
#
# Then:
#   - deletes the old OpenClaw agent id (config only; workspace already moved)
#   - creates <project>-foreman pointing at the foreman workspace
#   - copies agent session/state dir when possible
#   - sets identity + subagent allow list
#   - rewrites AGENTS.md coordinator id references
#
# Does NOT restart the gateway (prints the command).
#
# Usage:
#   FACTORY_PROJECT=my-project ./migrate-coordinator-to-foreman.sh
#
set -Eeuo pipefail

if [[ -z "${FACTORY_PROJECT:-}" ]]; then
  echo "ERROR: FACTORY_PROJECT is not set." >&2
  exit 2
fi

export FACTORY_PROJECT

project="$FACTORY_PROJECT"
old_agent="${project}-factory"
new_agent="${project}-foreman"
ws_root="$HOME/.openclaw/workspaces/$project"
old_ws="$ws_root/factory"
new_ws="$ws_root/foreman"
old_agent_dir="$HOME/.openclaw/agents/$old_agent"
new_agent_dir="$HOME/.openclaw/agents/$new_agent"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing command: $1" >&2
    exit 2
  }
}

require openclaw
require jq

echo "Migrating factory coordinator → foreman"
echo "  project:    $project"
echo "  old agent:  $old_agent"
echo "  new agent:  $new_agent"
echo "  old ws:     $old_ws"
echo "  new ws:     $new_ws"
echo

if openclaw agents list --json | jq -e --arg id "$new_agent" '.. | objects | select(.id? == $id)' >/dev/null; then
  echo "New agent already exists: $new_agent"
  if [[ -d "$new_ws" ]]; then
    echo "Foreman workspace already present. Nothing to migrate."
    exit 0
  fi
fi

if [[ ! -d "$old_ws" && -d "$new_ws" ]]; then
  echo "Workspace already at foreman path."
elif [[ -d "$old_ws" && ! -e "$new_ws" ]]; then
  echo "Renaming workspace directory..."
  mv "$old_ws" "$new_ws"
elif [[ -d "$old_ws" && -d "$new_ws" ]]; then
  echo "ERROR: both $old_ws and $new_ws exist. Resolve manually." >&2
  exit 1
else
  echo "ERROR: neither old nor new foreman workspace exists under $ws_root" >&2
  exit 1
fi

# Capture allowAgents from old agent if present.
allow_json='[]'
if openclaw agents list --json | jq -e --arg id "$old_agent" '.. | objects | select(.id? == $id)' >/dev/null; then
  allow_json="$(
    openclaw config get agents.list --json |
      jq -c --arg id "$old_agent" '
        .[] | select(.id == $id) | .subagents.allowAgents // []
      '
  )"
  echo "Removing old agent registration: $old_agent"
  # Move agent dir aside first so delete cannot destroy sessions we want to keep.
  if [[ -d "$old_agent_dir" ]]; then
    mkdir -p "$(dirname "$new_agent_dir")"
    if [[ ! -e "$new_agent_dir" ]]; then
      mv "$old_agent_dir" "$new_agent_dir"
      echo "Moved agent state: $old_agent_dir -> $new_agent_dir"
    else
      echo "WARNING: $new_agent_dir already exists; leaving $old_agent_dir in place"
    fi
  fi
  openclaw agents delete "$old_agent" --force || true
fi

if ! openclaw agents list --json | jq -e --arg id "$new_agent" '.. | objects | select(.id? == $id)' >/dev/null; then
  echo "Creating agent: $new_agent"
  # If we already moved agent dir, pass --agent-dir so OpenClaw reuses it.
  if [[ -d "$new_agent_dir" ]]; then
    openclaw agents add "$new_agent" \
      --workspace "$new_ws" \
      --agent-dir "$new_agent_dir/agent" \
      --non-interactive || openclaw agents add "$new_agent" \
      --workspace "$new_ws" \
      --non-interactive
  else
    openclaw agents add "$new_agent" \
      --workspace "$new_ws" \
      --non-interactive
  fi
fi

# Ensure workspace path is correct in config (add should set it).
openclaw agents set-identity \
  --agent "$new_agent" \
  --name "${project}: Foreman" \
  --theme "practical factory floor boss / product coordinator" \
  --emoji "🏭"

idx="$(
  openclaw config get agents.list --json |
    jq -r --arg id "$new_agent" 'to_entries[] | select(.value.id == $id) | .key'
)"

if [[ ! "$idx" =~ ^[0-9]+$ ]]; then
  echo "ERROR: could not find $new_agent after create" >&2
  exit 1
fi

if [[ "$allow_json" == "[]" || -z "$allow_json" ]]; then
  allow_json="$(
    jq -cn \
      --arg spec "${project}-spec" \
      --arg implement "${project}-implement" \
      --arg verify "${project}-verify" \
      --arg ship "${project}-ship" \
      '[$spec,$implement,$verify,$ship]'
  )"
fi

echo "Setting subagents.allowAgents: $allow_json"
openclaw config set \
  "agents.list[$idx].subagents.allowAgents" \
  "$allow_json" \
  --strict-json

# Point workspace explicitly if needed
openclaw config set "agents.list[$idx].workspace" "$new_ws"

openclaw config validate

# Rewrite AGENTS.md role footer if present
agents_md="$new_ws/AGENTS.md"
if [[ -f "$agents_md" ]]; then
  sed -i \
    -e "s/${project}-factory/${project}-foreman/g" \
    -e 's/The factory coordinator is:/The factory foreman is:/' \
    -e 's/You are the main coordinator/You are the **foreman** (main coordinator)/' \
    "$agents_md"
  echo "Updated references in $agents_md"
fi

identity_md="$new_ws/IDENTITY.md"
if [[ -f "$identity_md" ]]; then
  sed -i \
    -e "s/${project}-factory/${project}-foreman/g" \
    -e 's/factory coordinator/foreman/g' \
    "$identity_md" || true
fi

# Migrate seed marker name if present
if [[ -f "$new_ws/.factory-coordinator-seeded" && ! -f "$new_ws/.foreman-seeded" ]]; then
  mv "$new_ws/.factory-coordinator-seeded" "$new_ws/.foreman-seeded"
  # rewrite agent= line inside marker
  if grep -q "agent=${old_agent}" "$new_ws/.foreman-seeded" 2>/dev/null; then
    sed -i "s/agent=${old_agent}/agent=${new_agent}/" "$new_ws/.foreman-seeded"
  fi
fi

echo
echo "Migration complete for $project"
echo "Restart gateway to load the new agent id:"
echo "  openclaw gateway restart"
echo
echo "Open foreman TUI:"
echo "  cd $(printf '%q' "$new_ws")"
echo "  openclaw tui --session $(printf '%q' "agent:${new_agent}:main")"
