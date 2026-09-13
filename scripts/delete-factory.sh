#!/usr/bin/env bash
# delete-factory.sh — deregister a project factory without wiping its files.
#
# Why this exists:
#   Renaming ~/.openclaw/workspaces/<project> is not enough. Agents remain in
#   openclaw.json (agents.list), agent state dirs under ~/.openclaw/agents/, and
#   often still appear in other agents' subagents.allowAgents lists.
#
#   `openclaw agents delete` also tries to trash the agent workspace. That is
#   the wrong default for "retire this factory" when you want to keep the tree
#   for manual inspection/removal.
#
# What this script does (safe defaults):
#   1. Discover role agents for FACTORY_PROJECT (foreman/factory + workers,
#      including triage if present, plus any agent whose workspace is under the
#      project tree).
#   2. Move the project workspace aside (default suffix .deleted-<timestamp>).
#      Never rm -rf the project tree.
#   3. Point each agent workspace at a temporary empty directory so a subsequent
#      `openclaw agents delete --force` cannot trash the real project files.
#   4. Delete each agent registration (config + bindings + allow-lists via
#      OpenClaw prune). Agent state/session dirs are moved aside when present
#      (not hard-deleted by this script).
#   5. Validate config and print gateway restart reminder.
#
# Does NOT:
#   - Permanently delete the project workspace (you remove the aside dir by hand)
#   - Restart the gateway
#   - Touch unrelated factories
#   - Delete the product git repo
#
# Usage:
#   FACTORY_PROJECT=kalshi-multiplex-orderbook ./delete-factory.sh
#   FACTORY_PROJECT=my-project FACTORY_DELETE_SUFFIX=.fail0 ./delete-factory.sh
#   FACTORY_PROJECT=my-project FACTORY_DELETE_DRY_RUN=1 ./delete-factory.sh
#   FACTORY_PROJECT=my-project FACTORY_DELETE_KEEP_AGENTS_STATE=1 ./delete-factory.sh
#
# Recovery / already-moved trees:
#   If you already renamed the workspace (e.g. .../kalshi-multiplex-orderbook.fail0)
#   set FACTORY_WORKSPACE_SRC to that path, or leave FACTORY_PROJECT as the
#   original id — the script also looks for common aside names.
#
set -Eeuo pipefail

if [[ -z "${FACTORY_PROJECT:-}" ]]; then
  echo "ERROR: FACTORY_PROJECT is not set." >&2
  echo "Example:" >&2
  echo "  FACTORY_PROJECT=kalshi-multiplex-orderbook ./delete-factory.sh" >&2
  exit 2
fi

export FACTORY_PROJECT

project="$FACTORY_PROJECT"
workspace_root="${OPENCLAW_WORKSPACES:-$HOME/.openclaw/workspaces}"
agents_root="${OPENCLAW_AGENTS:-$HOME/.openclaw/agents}"
suffix="${FACTORY_DELETE_SUFFIX:-.deleted-$(date +%Y%m%d-%H%M%S)}"
dry_run="${FACTORY_DELETE_DRY_RUN:-0}"
keep_agent_state="${FACTORY_DELETE_KEEP_AGENTS_STATE:-1}"
force="${FACTORY_DELETE_FORCE:-0}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing command: $1" >&2
    exit 2
  }
}

require openclaw
require jq

# Refuse to delete this maker / self-hosting factory unless explicitly forced.
if [[ "$project" == "openclaw-factory-builder" && "$force" != "1" ]]; then
  echo "ERROR: refusing to delete openclaw-factory-builder without FACTORY_DELETE_FORCE=1" >&2
  exit 2
fi

if [[ "$project" == "main" || "$project" == "triage" || "$project" == "spec" || "$project" == "implement" ]]; then
  echo "ERROR: '$project' looks like a global agent id, not a factory project." >&2
  exit 2
fi

run() {
  if [[ "$dry_run" == "1" ]]; then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

echo "=================================================="
echo "Delete OpenClaw software factory"
echo "Project:   $project"
echo "Dry run:   $dry_run"
echo "Suffix:    $suffix"
echo "=================================================="
echo

# --- locate project workspace (active or already moved aside) ---------------

resolve_workspace_src() {
  if [[ -n "${FACTORY_WORKSPACE_SRC:-}" ]]; then
    printf '%s\n' "$FACTORY_WORKSPACE_SRC"
    return 0
  fi

  local candidates=(
    "$workspace_root/$project"
    "$workspace_root/${project}.fail0"
    "$workspace_root/${project}.fail"
    "$workspace_root/${project}.deleted"
  )

  # Newest matching .deleted-* / .fail* if any.
  local extra
  while IFS= read -r extra; do
    [[ -n "$extra" ]] && candidates+=("$extra")
  done < <(
    # shellcheck disable=SC2010
    ls -1d "$workspace_root/$project".deleted-* "$workspace_root/$project".fail* 2>/dev/null | sort -r || true
  )

  local c
  for c in "${candidates[@]}"; do
    if [[ -d "$c" ]]; then
      printf '%s\n' "$c"
      return 0
    fi
  done

  return 1
}

workspace_src=""
if workspace_src="$(resolve_workspace_src)"; then
  echo "Workspace source: $workspace_src"
else
  echo "WARNING: no workspace directory found under $workspace_root for $project"
  echo "         Will still attempt to remove matching agent registrations."
  workspace_src=""
fi

workspace_dst=""
if [[ -n "$workspace_src" ]]; then
  base="$(basename "$workspace_src")"
  # If already aside with the exact requested suffix destination, keep it.
  if [[ "$base" == "${project}${suffix}" ]]; then
    workspace_dst="$workspace_src"
    echo "Workspace already at destination: $workspace_dst"
  elif [[ "$base" != "$project" ]]; then
    # Already moved to some other aside name — leave path as-is unless user
    # asked for a specific suffix move.
    if [[ -n "${FACTORY_DELETE_SUFFIX:-}" && "$base" != "${project}${suffix}" ]]; then
      workspace_dst="$workspace_root/${project}${suffix}"
    else
      workspace_dst="$workspace_src"
      echo "Workspace already moved aside: $workspace_dst"
    fi
  else
    workspace_dst="$workspace_root/${project}${suffix}"
  fi
fi

# --- discover agents --------------------------------------------------------

agents_json="$(openclaw agents list --json)"

# Role suffixes we always consider for a factory project.
role_suffixes=(
  foreman
  factory
  triage
  spec
  implement
  verify
  ship
  review
  test
  docs
  release
)

declare -A agent_set=()
ordered_agents=()

add_agent() {
  local id="$1"
  [[ -z "$id" ]] && return 0
  if [[ -n "${agent_set[$id]:-}" ]]; then
    return 0
  fi
  agent_set["$id"]=1
  ordered_agents+=("$id")
}

for role in "${role_suffixes[@]}"; do
  add_agent "${project}-${role}"
done

# Any configured agent whose workspace is under the project tree (active or aside).
while IFS= read -r id; do
  add_agent "$id"
done < <(
  printf '%s\n' "$agents_json" | jq -r --arg project "$project" --arg root "$workspace_root" '
    .. | objects | select(has("id") and has("workspace")) |
    select(
      (.workspace | startswith($root + "/" + $project + "/"))
      or (.workspace | startswith($root + "/" + $project + "."))
      or (.workspace | test("/workspaces/" + $project + "([./]|$)"))
    ) | .id
  ' | sort -u
)

# Filter to agents that actually exist in config (role list may be speculative).
existing_agents=()
missing_role_agents=()
for id in "${ordered_agents[@]}"; do
  if printf '%s\n' "$agents_json" | jq -e --arg id "$id" '
      .. | objects | select(.id? == $id)
    ' >/dev/null 2>&1
  then
    existing_agents+=("$id")
  else
    # Only note missing if it was a primary role we care about for messaging.
    case "$id" in
      "${project}-foreman"|"${project}-factory"|"${project}-spec"|"${project}-implement"|"${project}-verify"|"${project}-ship"|"${project}-triage")
        missing_role_agents+=("$id")
        ;;
    esac
  fi
done

if ((${#existing_agents[@]} == 0)) && [[ -z "$workspace_src" ]]; then
  echo "ERROR: no agents and no workspace found for project '$project'." >&2
  exit 1
fi

echo "Agents to remove (${#existing_agents[@]}):"
if ((${#existing_agents[@]} == 0)); then
  echo "  (none registered)"
else
  for id in "${existing_agents[@]}"; do
    ws="$(printf '%s\n' "$agents_json" | jq -r --arg id "$id" '
      .. | objects | select(.id? == $id) | .workspace // empty
    ' | head -n1)"
    echo "  - $id"
    echo "      workspace: ${ws:-"(none)"}"
  done
fi
echo

if ((${#missing_role_agents[@]} > 0)); then
  echo "Note: common role agents not registered (ok):"
  for id in "${missing_role_agents[@]}"; do
    echo "  - $id"
  done
  echo
fi

# Deletion order: workers first, coordinators last (foreman/factory).
delete_order=()
coordinators=()
for id in "${existing_agents[@]}"; do
  case "$id" in
    "${project}-foreman"|"${project}-factory")
      coordinators+=("$id")
      ;;
    *)
      delete_order+=("$id")
      ;;
  esac
done
for id in "${coordinators[@]}"; do
  delete_order+=("$id")
done

# --- move project workspace aside -------------------------------------------

if [[ -n "$workspace_src" && -n "$workspace_dst" && "$workspace_src" != "$workspace_dst" ]]; then
  if [[ -e "$workspace_dst" ]]; then
    echo "ERROR: destination already exists: $workspace_dst" >&2
    echo "       Choose a different FACTORY_DELETE_SUFFIX or remove/rename it." >&2
    exit 1
  fi
  echo "Moving project workspace aside (no rm):"
  echo "  $workspace_src"
  echo "  -> $workspace_dst"
  run mv -- "$workspace_src" "$workspace_dst"
  workspace_src="$workspace_dst"
  echo
elif [[ -n "$workspace_dst" ]]; then
  echo "Project workspace left at: $workspace_dst"
  echo
fi

# --- staging dir so agents delete cannot trash real files -------------------

staging_root=""
cleanup_staging() {
  if [[ -n "${staging_root:-}" && -d "${staging_root:-}" ]]; then
    rm -rf -- "$staging_root" 2>/dev/null || true
  fi
}
trap cleanup_staging EXIT

if ((${#delete_order[@]} > 0)); then
  if [[ "$dry_run" == "1" ]]; then
    staging_root="/tmp/openclaw-factory-delete-dry-run-${project}"
    echo "DRY-RUN: would create staging workspaces under $staging_root"
  else
    staging_root="$(mktemp -d "${TMPDIR:-/tmp}/openclaw-factory-delete.${project}.XXXXXX")"
    echo "Staging empty workspaces under: $staging_root"
  fi
fi

# --- per-agent: retarget workspace, move agent state, delete registration ---

deleted=0
failed=0

for id in "${delete_order[@]}"; do
  echo "--------------------------------------------------"
  echo "Removing agent: $id"

  # Capture current paths from live config.
  entry_json="$(openclaw config get agents.list --json | jq -c --arg id "$id" '
    map(select(.id == $id)) | .[0] // empty
  ')"
  if [[ -z "$entry_json" || "$entry_json" == "null" ]]; then
    echo "  skip: not in agents.list anymore"
    continue
  fi

  agent_dir="$(printf '%s\n' "$entry_json" | jq -r '.agentDir // empty')"
  if [[ -z "$agent_dir" ]]; then
    agent_dir="$agents_root/$id"
  fi
  # agentDir often points at .../agents/<id>/agent — state root is parent.
  agent_state_root="$agent_dir"
  if [[ "$(basename "$agent_dir")" == "agent" ]]; then
    agent_state_root="$(dirname "$agent_dir")"
  fi

  # 1) Point workspace at empty staging dir so delete cannot remove real tree.
  staged_ws="$staging_root/$id-workspace"
  if [[ "$dry_run" == "1" ]]; then
    echo "  DRY-RUN: mkdir staging workspace + config set workspace"
  else
    mkdir -p -- "$staged_ws"
    # Best-effort index lookup + workspace rewrite.
    idx="$(
      openclaw config get agents.list --json |
        jq -r --arg id "$id" 'to_entries[] | select(.value.id == $id) | .key'
    )"
    if [[ "$idx" =~ ^[0-9]+$ ]]; then
      openclaw config set "agents.list[$idx].workspace" "$staged_ws" || {
        echo "  WARNING: could not retarget workspace for $id" >&2
      }
    else
      echo "  WARNING: could not find list index for $id" >&2
    fi
  fi

  # 2) Move agent state aside (sessions, agent dir) before delete trashes it.
  #    Keep by default so the operator can inspect; they can remove later.
  if [[ "$keep_agent_state" == "1" ]]; then
    if [[ -d "$agent_state_root" ]]; then
      aside_state="${agent_state_root}${suffix}"
      if [[ -e "$aside_state" ]]; then
        aside_state="${agent_state_root}${suffix}.$(date +%s)"
      fi
      echo "  Moving agent state aside:"
      echo "    $agent_state_root -> $aside_state"
      run mv -- "$agent_state_root" "$aside_state"
    else
      echo "  Agent state dir absent (ok): $agent_state_root"
    fi
  else
    echo "  Leaving agent state in place for openclaw agents delete to trash: $agent_state_root"
  fi

  # 3) Delete registration (prunes bindings + allow lists when OpenClaw does).
  if [[ "$dry_run" == "1" ]]; then
    echo "  DRY-RUN: openclaw agents delete $id --force"
    deleted=$((deleted + 1))
  else
    if openclaw agents delete "$id" --force; then
      echo "  Deleted registration: $id"
      deleted=$((deleted + 1))
    else
      rc=$?
      echo "  ERROR: agents delete failed for $id (status $rc)" >&2
      failed=1
    fi
  fi
done

echo
echo "--------------------------------------------------"
echo "Scrubbing residual allowAgents references (best-effort)"

# OpenClaw pruneAgentConfig removes the agent entry and top-level allow/bindings,
# but other agents may still list deleted ids in subagents.allowAgents.
if [[ "$dry_run" == "1" ]]; then
  echo "DRY-RUN: would scrub subagents.allowAgents entries for removed ids"
else
  list_json="$(openclaw config get agents.list --json)"
  # Build JSON array of removed ids for jq.
  removed_json="$(printf '%s\n' "${delete_order[@]}" | jq -R . | jq -s .)"
  scrubbed="$(printf '%s\n' "$list_json" | jq --argjson removed "$removed_json" '
    map(
      if (.subagents.allowAgents | type) == "array" then
        .subagents.allowAgents |= map(select(. as $a | $removed | index($a) | not))
      else
        .
      end
    )
  ')"

  if [[ "$(printf '%s\n' "$list_json" | jq -c .)" != "$(printf '%s\n' "$scrubbed" | jq -c .)" ]]; then
    # Write back via a temp file + openclaw config set if supported; else jq file edit is unsafe.
    # Use per-index sets for only changed allow lists to avoid clobbering unrelated fields.
    length="$(printf '%s\n' "$scrubbed" | jq 'length')"
    for ((i = 0; i < length; i++)); do
      old_allow="$(printf '%s\n' "$list_json" | jq -c --argjson i "$i" '.[$i].subagents.allowAgents // empty')"
      new_allow="$(printf '%s\n' "$scrubbed" | jq -c --argjson i "$i" '.[$i].subagents.allowAgents // empty')"
      if [[ -n "$old_allow" && "$old_allow" != "$new_allow" ]]; then
        id_at="$(printf '%s\n' "$scrubbed" | jq -r --argjson i "$i" '.[$i].id')"
        echo "  Updating allowAgents on $id_at"
        openclaw config set "agents.list[$i].subagents.allowAgents" "$new_allow" --strict-json || {
          echo "  WARNING: failed to scrub allowAgents on $id_at" >&2
          failed=1
        }
      fi
    done
  else
    echo "  No residual allowAgents references found."
  fi
fi

echo
if [[ "$dry_run" == "1" ]]; then
  echo "DRY-RUN complete. No changes written."
else
  if openclaw config validate; then
    echo "Config validated."
  else
    echo "WARNING: openclaw config validate reported issues." >&2
    failed=1
  fi
fi

# Optional: factory-worktrees aside (do not delete).
worktrees_src="$HOME/.openclaw/factory-worktrees/$project"
if [[ -d "$worktrees_src" ]]; then
  worktrees_dst="${worktrees_src}${suffix}"
  if [[ ! -e "$worktrees_dst" ]]; then
    echo
    echo "Found factory-worktrees for project:"
    echo "  $worktrees_src"
    if [[ "${FACTORY_DELETE_MOVE_WORKTREES:-1}" == "1" ]]; then
      echo "Moving aside (set FACTORY_DELETE_MOVE_WORKTREES=0 to skip):"
      echo "  -> $worktrees_dst"
      run mv -- "$worktrees_src" "$worktrees_dst"
    else
      echo "Leaving factory-worktrees in place (FACTORY_DELETE_MOVE_WORKTREES=0)."
    fi
  fi
fi

echo
echo "=================================================="
if ((failed)); then
  echo "FACTORY DELETE FINISHED WITH ERRORS"
else
  echo "FACTORY DELETE COMPLETE"
fi
echo "Project:          $project"
echo "Agents removed:   $deleted"
if [[ -n "${workspace_dst:-}" ]]; then
  echo "Workspace aside:  $workspace_dst"
fi
echo "=================================================="
echo
echo "Next steps:"
echo "  1. Restart gateway so runtime drops the agents:"
echo "       openclaw gateway restart"
echo "  2. Confirm gone:"
echo "       openclaw agents list | grep -F $(printf '%q' "$project") || echo 'no agents left'"
echo "  3. When ready, remove the aside directories yourself (script never rm -rf's them):"
if [[ -n "${workspace_dst:-}" ]]; then
  echo "       # inspect first, then e.g. trash or rm -rf"
  echo "       ls $(printf '%q' "$workspace_dst")"
fi
echo "       ls $(printf '%q' "$agents_root") | grep -F $(printf '%q' "$project") || true"
echo
echo "Note: product git repos are not touched."

if ((failed)); then
  exit 1
fi
