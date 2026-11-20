#!/usr/bin/env bash
# import-factory.sh — adopt an existing factory from another machine.
#
# Copies role workspaces onto THIS host and registers agents here.
# Does not copy chats, agent sqlite, tokens, or the other host's openclaw.json.
#
# Point it at the other machine's project workspace root:
#   ~/.openclaw/workspaces/<project>/
#     foreman/  (or legacy factory/)
#     spec/ implement/ verify/ ship/   (whichever exist)
#     triage/                          (optional)
#
# Usage:
#   # A copy already on this machine (scp, rsync, extracted tar):
#   FACTORY_PROJECT=my-project \
#   FACTORY_IMPORT_SRC=/path/to/my-project \
#   ./import-factory.sh
#
#   # Pull the workspace over SSH, then import:
#   FACTORY_PROJECT=my-project \
#   FACTORY_IMPORT_SSH=user@other-host \
#   ./import-factory.sh
#
#   # Preview only:
#   FACTORY_IMPORT_DRY_RUN=1 FACTORY_PROJECT=my-project \
#     FACTORY_IMPORT_SRC=/path/to/my-project ./import-factory.sh
#
# Environment:
#   FACTORY_PROJECT            Destination project id / agent prefix.
#                              Defaults to the source directory name for a local src.
#   FACTORY_IMPORT_SRC         Local project workspace root. Not a single role dir.
#   FACTORY_IMPORT_SSH         user@host. Pulls the remote workspace, then imports it.
#                              Do not set both SRC and SSH.
#   FACTORY_IMPORT_REMOTE      Remote workspace path. Default:
#                              ~/.openclaw/workspaces/$FACTORY_PROJECT
#                              A custom value is a literal remote path (~ is not expanded).
#   FACTORY_IMPORT_DRY_RUN     1 = print the plan, write nothing, register nothing.
#   FACTORY_IMPORT_FORCE       1 = required to import openclaw-factory-builder itself,
#                              and to rsync into a destination that already has role dirs.
#                              Never retargets an agent that already points somewhere else.
#   FACTORY_IMPORT_MAP_LEGACY  1 (default) = copy legacy factory/ to foreman/ when
#                              foreman/ is absent. 0 = leave factory/ as-is and refuse
#                              if that is the only coordinator dir.
#
# After a real import, restart the gateway yourself:
#   openclaw gateway restart
#
# Does NOT seed the foreman, open a TUI, or start an interview.
#
set -Eeuo pipefail

script_dir="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"
# shellcheck source=lib/host-env.sh
source "$script_dir/lib/host-env.sh"

dry_run="${FACTORY_IMPORT_DRY_RUN:-0}"
force="${FACTORY_IMPORT_FORCE:-0}"
map_legacy="${FACTORY_IMPORT_MAP_LEGACY:-1}"
ssh_target="${FACTORY_IMPORT_SSH:-}"
src="${FACTORY_IMPORT_SRC:-}"
stage=""

case "$dry_run" in
0 | 1) ;;
*) echo "ERROR: FACTORY_IMPORT_DRY_RUN must be 0 or 1." >&2; exit 2 ;;
esac
case "$force" in
0 | 1) ;;
*) echo "ERROR: FACTORY_IMPORT_FORCE must be 0 or 1." >&2; exit 2 ;;
esac
case "$map_legacy" in
0 | 1) ;;
*) echo "ERROR: FACTORY_IMPORT_MAP_LEGACY must be 0 or 1." >&2; exit 2 ;;
esac

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing command: $1" >&2
    exit 2
  }
}

require jq
require rsync
require python3
if [[ "$dry_run" != "1" ]]; then
  require openclaw
fi

cleanup() {
  if [[ -n "$stage" && -d "$stage" ]]; then
    rm -rf "$stage"
  fi
}
trap cleanup EXIT

# role_dir_name:agent_suffix  (foreman is the coordinator)
worker_roles=(spec implement verify ship triage)
role_dirs=(foreman spec implement verify ship triage)

copy_excludes=(
  --exclude '/github_token'
  --exclude '/openclaw.json'
  --exclude '/sessions/'
  --exclude '/agents/'
  --exclude 'github_token'
  --exclude 'openclaw.json'
  --exclude 'id_rsa'
  --exclude 'id_ed25519'
  --exclude 'id_rsa.pub'
  --exclude 'id_ed25519.pub'
  --exclude '*.pem'
  --exclude 'openclaw-agent.sqlite'
  --exclude 'openclaw-agent.sqlite-shm'
  --exclude 'openclaw-agent.sqlite-wal'
)

note_skipped_secrets() {
  local root="$1"
  local found=0
  local path rel

  while IFS= read -r -d '' path; do
    rel="${path#"$root"/}"
    echo "SKIP: $rel"
    found=1
  done < <(find "$root" \
    \( -name 'github_token' -o -name 'openclaw.json' -o -name 'id_rsa' \
       -o -name 'id_ed25519' -o -name 'id_rsa.pub' -o -name 'id_ed25519.pub' \
       -o -name '*.pem' -o -name 'openclaw-agent.sqlite' \
       -o -name 'openclaw-agent.sqlite-shm' -o -name 'openclaw-agent.sqlite-wal' \
       -o -name sessions -o -name agents \) -print0)

  if [[ "$found" == "0" ]]; then
    echo "SKIP: no token, session, sqlite, or openclaw.json paths in source"
  fi
}

warn_env_files() {
  local root="$1"
  local path rel count=0

  while IFS= read -r -d '' path; do
    rel="${path#"$root"/}"
    echo "WARNING: env file will be copied as workspace content: $rel" >&2
    count=$((count + 1))
  done < <(find "$root" \( -name '.env' -o -name '*.env' \) -print0)

  if [[ "$count" != "0" ]]; then
    echo "WARNING: review those env files. Import does not strip them." >&2
  fi
}

refuse_escaping_symlinks() {
  local root="$1"
  local root_real link target

  root_real="$(readlink -f "$root")"
  while IFS= read -r -d '' link; do
    target="$(readlink -f "$link" || true)"
    if [[ -z "$target" ]]; then
      echo "WARNING: broken symlink left as-is: ${link#"$root"/}" >&2
      continue
    fi
    case "$target" in
      "$root_real" | "$root_real"/*) ;;
      *)
        echo "ERROR: symlink points outside the factory workspace:" >&2
        echo "  ${link#"$root"/} -> $target" >&2
        echo "Refusing to import escaped host state." >&2
        exit 1
        ;;
    esac
  done < <(find "$root" -type l -print0)
}

looks_like_openclaw_home() {
  local root="$1"
  [[ -f "$root/openclaw.json" ]] && return 0
  [[ -d "$root/agents" && -d "$root/workspaces" ]] && return 0
  return 1
}

discover_layout() {
  local root="$1"
  has_foreman=0
  has_legacy=0
  declare -g -a present_roles=()

  if [[ -d "$root/foreman" ]]; then
    has_foreman=1
    present_roles+=(foreman)
  fi
  if [[ -d "$root/factory" ]]; then
    has_legacy=1
  fi

  local role
  for role in "${worker_roles[@]}"; do
    if [[ -d "$root/$role" ]]; then
      present_roles+=("$role")
    fi
  done
}

agent_workspace() {
  local id="$1"
  openclaw agents list --json | jq -r --arg id "$id" '
    [ .. | objects | select(.id? == $id) | .workspace // empty ] | first // empty
  '
}

default_identity() {
  local role="$1"
  local project="$2"
  case "$role" in
    foreman)
      printf '%s\n' "${project}: Foreman" "practical factory floor boss / product coordinator" "🏭"
      ;;
    spec)
      printf '%s\n' "${project}: Specification Engineer" "precise requirements and product designer" "📐"
      ;;
    implement)
      printf '%s\n' "${project}: Implementation Engineer" "careful software and automation builder" "🛠️"
      ;;
    verify)
      printf '%s\n' "${project}: Verification Engineer" "independent reviewer and tester" "🔎"
      ;;
    ship)
      printf '%s\n' "${project}: Release Engineer" "conservative release custodian" "📦"
      ;;
    triage)
      printf '%s\n' "${project}: Triage" "intake and routing" "🧭"
      ;;
    *)
      echo "ERROR: no default identity for role: $role" >&2
      exit 2
      ;;
  esac
}

copy_tree() {
  local from="$1"
  local to="$2"
  local -a args=(-a "${copy_excludes[@]}")

  echo "COPY: $from -> $to"
  if [[ "$dry_run" == "1" ]]; then
    # Stats only. Do not touch the real destination, and do not rely on
    # rsync --dry-run, which can still create the destination directory.
    local tmp
    tmp="$(mktemp -d)"
    rsync -a -n --stats "${copy_excludes[@]}" "$from/" "$tmp/" || true
    rm -rf "$tmp"
    return 0
  fi

  mkdir -p "$to"
  rsync "${args[@]}" "$from/" "$to/"
}

rewrite_seed_markers() {
  local foreman_dir="$1"
  local project="$2"
  local token_file="$3"
  local marker old_token old_home

  for marker in "$foreman_dir/.foreman-seeded" "$foreman_dir/.factory-coordinator-seeded"; do
    [[ -f "$marker" ]] || continue
    old_token="$(grep -E '^github_token_file=' "$marker" | head -n 1 | cut -d= -f2- || true)"
    if [[ -n "$old_token" ]]; then
      old_home="${old_token%%/.config/openclaw/github_token}"
      if [[ "$old_home" != "$old_token" && "$old_home" != "$HOME" ]]; then
        echo "NOTE: seed marker had another home ($old_home)."
        if [[ "$dry_run" == "1" ]]; then
          echo "      A real import would point github_token_file at this host."
        else
          echo "      Token path updated to this host. Workspace files were not rewritten."
        fi
      fi
    fi

    if [[ "$dry_run" == "1" ]]; then
      echo "WOULD rewrite seed marker: $marker"
      continue
    fi

    MARKER="$marker" PROJECT="$project" TOKEN_FILE="$token_file" AGENT="${project}-foreman" \
      python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["MARKER"])
project = os.environ["PROJECT"]
token_file = os.environ["TOKEN_FILE"]
agent = os.environ["AGENT"]
lines = path.read_text().splitlines()
out = []
for line in lines:
    if line.startswith("github_token_file="):
        out.append(f"github_token_file={token_file}")
    elif line.startswith("project="):
        out.append(f"project={project}")
    elif line.startswith("agent="):
        out.append(f"agent={agent}")
    else:
        out.append(line)
text = "\n".join(out)
if lines and path.read_text().endswith("\n"):
    text += "\n"
path.write_text(text)
PY
    echo "Rewrote seed marker paths: $marker"
    if grep -E '^github_repository=.+' "$marker" >/dev/null; then
      echo "Recorded GitHub repository: $(grep -E '^github_repository=' "$marker" | head -n 1 | cut -d= -f2-)"
    fi
  done
}

if [[ -n "$ssh_target" && -n "$src" ]]; then
  echo "ERROR: Set FACTORY_IMPORT_SRC or FACTORY_IMPORT_SSH, not both." >&2
  exit 2
fi

if [[ -z "$ssh_target" && -z "$src" ]]; then
  echo "ERROR: Set FACTORY_IMPORT_SRC or FACTORY_IMPORT_SSH." >&2
  echo "Example:" >&2
  echo "  FACTORY_PROJECT=my-project FACTORY_IMPORT_SRC=/path/to/my-project ./import-factory.sh" >&2
  exit 2
fi

if [[ -n "$ssh_target" && -z "${FACTORY_PROJECT:-}" ]]; then
  echo "ERROR: FACTORY_PROJECT is required when pulling over SSH." >&2
  exit 2
fi

if [[ -n "$ssh_target" ]]; then
  require ssh
  project_for_remote="${FACTORY_PROJECT}"
  if [[ ! "$project_for_remote" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$ ]] || [[ "$project_for_remote" == *..* ]]; then
    echo "ERROR: Invalid FACTORY_PROJECT: $project_for_remote" >&2
    exit 2
  fi

  if [[ -n "${FACTORY_IMPORT_REMOTE:-}" ]]; then
    remote_shell="$(
      FACTORY_IMPORT_REMOTE="$FACTORY_IMPORT_REMOTE" python3 - <<'PY'
import os, shlex
print(shlex.quote(os.environ["FACTORY_IMPORT_REMOTE"]))
PY
    )"
    remote_rsync="$ssh_target:$FACTORY_IMPORT_REMOTE"
  else
    remote_shell="~/.openclaw/workspaces/$project_for_remote"
    remote_rsync="$ssh_target:~/.openclaw/workspaces/$project_for_remote"
  fi

  echo "Remote workspace: $ssh_target:$remote_shell"
  stage="$(mktemp -d "${TMPDIR:-/tmp}/import-factory.XXXXXX")"
  echo "Staging pull: $stage"
  if [[ "$dry_run" == "1" ]]; then
    echo "DRY RUN: downloading into a temp dir for inspection. Destination is not written."
  fi
  mkdir -p "$stage"
  rsync -a "${copy_excludes[@]}" "$remote_rsync/" "$stage/"
  src="$stage"
fi

if [[ ! -d "$src" ]]; then
  echo "ERROR: FACTORY_IMPORT_SRC is not a directory:" >&2
  echo "  $src" >&2
  exit 2
fi

src="$(readlink -f "$src")"

if looks_like_openclaw_home "$src"; then
  echo "ERROR: source looks like an OpenClaw home directory, not one factory." >&2
  echo "  $src" >&2
  echo "Point FACTORY_IMPORT_SRC at ~/.openclaw/workspaces/<project>." >&2
  exit 2
fi

if [[ -z "${FACTORY_PROJECT:-}" ]]; then
  FACTORY_PROJECT="$(basename "$src")"
fi

project="$FACTORY_PROJECT"
export FACTORY_PROJECT

if [[ ! "$project" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$ ]] || [[ "$project" == *..* ]]; then
  echo "ERROR: Invalid FACTORY_PROJECT: $project" >&2
  exit 2
fi

if [[ "$project" == "openclaw-factory-builder" && "$force" != "1" ]]; then
  echo "ERROR: Refusing to import onto openclaw-factory-builder without FACTORY_IMPORT_FORCE=1." >&2
  exit 2
fi

discover_layout "$src"

if [[ "$has_foreman" == "1" && "$has_legacy" == "1" ]]; then
  echo "ERROR: source has both foreman/ and factory/. Resolve that on the source first." >&2
  exit 1
fi

if [[ "$has_foreman" == "0" && "$has_legacy" == "1" && "$map_legacy" != "1" ]]; then
  echo "ERROR: source coordinator is legacy factory/ and FACTORY_IMPORT_MAP_LEGACY=0." >&2
  exit 1
fi

if [[ "$has_foreman" == "0" && "$has_legacy" == "0" ]]; then
  echo "ERROR: source is not a factory workspace root." >&2
  echo "  $src" >&2
  echo "Expected a project directory containing foreman/ or legacy factory/." >&2
  echo "Do not point this at a single role directory." >&2
  exit 1
fi

if [[ ${#present_roles[@]} -eq 0 && "$has_legacy" == "0" ]]; then
  echo "ERROR: no role directories found in $src" >&2
  exit 1
fi

dest_root="$HOME/.openclaw/workspaces/$project"
if [[ -d "$dest_root" ]] && [[ "$(readlink -f "$dest_root")" == "$src" ]]; then
  echo "ERROR: source and destination are the same directory." >&2
  exit 1
fi

echo "Import factory"
echo "  project:     $project"
echo "  source:      $src"
echo "  destination: $dest_root"
echo "  dry run:     $dry_run"
if [[ "$has_legacy" == "1" && "$map_legacy" == "1" ]]; then
  echo "  legacy:      factory/ -> foreman/"
fi
echo

refuse_escaping_symlinks "$src"
note_skipped_secrets "$src"
warn_env_files "$src"
echo

# Destination collisions and existing registrations are checked before any copy.
dest_conflicts=()
if [[ -d "$dest_root" ]]; then
  for role in "${role_dirs[@]}"; do
    if [[ -d "$dest_root/$role" ]]; then
      dest_conflicts+=("$role")
    fi
  done
  if [[ "$has_legacy" == "1" && -d "$dest_root/factory" ]]; then
    dest_conflicts+=(factory)
  fi
fi

if [[ ${#dest_conflicts[@]} -gt 0 && "$force" != "1" ]]; then
  echo "ERROR: destination already has role dirs (${dest_conflicts[*]})." >&2
  echo "  $dest_root" >&2
  echo "Import will not merge or overwrite without FACTORY_IMPORT_FORCE=1." >&2
  exit 1
fi

declare -A role_dest_dir=()
if [[ "$has_foreman" == "1" ]]; then
  role_dest_dir[foreman]="$dest_root/foreman"
elif [[ "$has_legacy" == "1" && "$map_legacy" == "1" ]]; then
  role_dest_dir[foreman]="$dest_root/foreman"
fi
for role in "${worker_roles[@]}"; do
  if [[ -d "$src/$role" ]]; then
    role_dest_dir[$role]="$dest_root/$role"
  fi
done

if [[ "$dry_run" != "1" ]]; then
  require openclaw
fi

if command -v openclaw >/dev/null 2>&1; then
  for role in "${!role_dest_dir[@]}"; do
    agent="${project}-${role}"
    expected="${role_dest_dir[$role]}"
    existing="$(agent_workspace "$agent")"
    if [[ -n "$existing" && "$(readlink -f "$existing")" != "$(readlink -f "$expected" 2>/dev/null || printf '%s' "$expected")" ]]; then
      # expected may not exist yet; compare the configured path string too
      if [[ "$existing" != "$expected" ]]; then
        echo "ERROR: agent $agent already points at a different workspace:" >&2
        echo "  $existing" >&2
        echo "Import will not retarget it." >&2
        exit 1
      fi
    fi
  done
elif [[ "$dry_run" == "1" ]]; then
  echo "WARNING: openclaw is not on PATH. Dry run cannot check existing agents." >&2
fi

echo "Plan:"
if [[ "$has_foreman" == "1" ]]; then
  copy_tree "$src/foreman" "$dest_root/foreman"
elif [[ "$has_legacy" == "1" ]]; then
  copy_tree "$src/factory" "$dest_root/foreman"
fi
for role in "${worker_roles[@]}"; do
  if [[ -d "$src/$role" ]]; then
    copy_tree "$src/$role" "$dest_root/$role"
  fi
done

# Top-level extras (docs next to role dirs). Never the role dirs themselves.
while IFS= read -r -d '' entry; do
  base="$(basename "$entry")"
  case "$base" in
    foreman | factory | spec | implement | verify | ship | triage) continue ;;
    github_token | openclaw.json | agents | sessions) continue ;;
  esac
  echo "COPY extra: $entry -> $dest_root/$base"
  if [[ "$dry_run" == "1" ]]; then
    continue
  fi
  mkdir -p "$dest_root"
  if [[ -d "$entry" ]]; then
    mkdir -p "$dest_root/$base"
    rsync -a "${copy_excludes[@]}" "$entry/" "$dest_root/$base/"
  else
    rsync -a "${copy_excludes[@]}" "$entry" "$dest_root/$base"
  fi
done < <(find "$src" -mindepth 1 -maxdepth 1 -print0)

token_file="$HOME/.config/openclaw/github_token"
foreman_dest="${role_dest_dir[foreman]:-$dest_root/foreman}"
marker_dir="$foreman_dest"
if [[ "$dry_run" == "1" ]]; then
  if [[ "$has_foreman" == "1" ]]; then
    marker_dir="$src/foreman"
  else
    marker_dir="$src/factory"
  fi
fi
if [[ -f "$marker_dir/.foreman-seeded" || -f "$marker_dir/.factory-coordinator-seeded" ]]; then
  rewrite_seed_markers "$marker_dir" "$project" "$token_file"
fi

allow_json="$(
  python3 - "$project" ${present_roles[@]+"${present_roles[@]}"} <<'PY'
import json, sys
project = sys.argv[1]
roles = sys.argv[2:]
order = ["spec", "implement", "verify", "ship", "triage"]
agents = [f"{project}-{role}" for role in order if role in roles]
print(json.dumps(agents))
PY
)"

echo
echo "Agents:"
for role in foreman "${worker_roles[@]}"; do
  [[ -n "${role_dest_dir[$role]:-}" ]] || continue
  agent="${project}-${role}"
  workspace="${role_dest_dir[$role]}"
  # During dry-run the dest file does not exist; look at the source file.
  if [[ "$has_legacy" == "1" && "$role" == "foreman" && "$has_foreman" == "0" ]]; then
    src_identity="$src/factory/IDENTITY.md"
  else
    src_identity="$src/$role/IDENTITY.md"
  fi

  if [[ "$dry_run" == "1" ]]; then
    echo "WOULD register: $agent -> $workspace"
  elif command -v openclaw >/dev/null 2>&1 && [[ -n "$(agent_workspace "$agent")" ]]; then
    echo "REUSE: $agent"
  else
    echo "CREATE: $agent -> $workspace"
    openclaw agents add "$agent" \
      --workspace "$workspace" \
      --non-interactive
  fi

  if [[ -f "$src_identity" ]]; then
    echo "IDENTITY: $agent from IDENTITY.md"
    if [[ "$dry_run" != "1" ]]; then
      openclaw agents set-identity \
        --agent "$agent" \
        --workspace "$workspace" \
        --from-identity
    fi
  else
    echo "IDENTITY: $agent defaults (no IDENTITY.md)"
    if [[ "$dry_run" != "1" ]]; then
      mapfile -t ident < <(default_identity "$role" "$project")
      openclaw agents set-identity \
        --agent "$agent" \
        --name "${ident[0]}" \
        --theme "${ident[1]}" \
        --emoji "${ident[2]}"
    fi
  fi
done

echo
echo "Delegation allowAgents: $allow_json"
if [[ "$dry_run" != "1" ]]; then
  openclaw config set \
    "agents.entries.${project}-foreman.subagents.allowAgents" \
    "$allow_json" \
    --strict-json
  openclaw config validate
fi

src_agents=""
if [[ "$has_foreman" == "1" ]]; then
  src_agents="$src/foreman/AGENTS.md"
elif [[ "$has_legacy" == "1" ]]; then
  src_agents="$src/factory/AGENTS.md"
fi

if [[ -n "$src_agents" && -f "$src_agents" ]] && grep -F "SOFTWARE FACTORY" "$src_agents" >/dev/null; then
  echo "Foreman AGENTS.md already has a SOFTWARE FACTORY block. Leaving it."
elif [[ -n "$src_agents" && -f "$src_agents" ]]; then
  if [[ "$dry_run" == "1" ]]; then
    echo "WOULD append foreman role block if SOFTWARE FACTORY is absent."
  else
    bash -Eeuo pipefail "$script_dir/set-factory-agent-md.sh"
  fi
else
  echo "WARNING: no foreman AGENTS.md in source. Role block not added." >&2
fi

echo
if [[ "$dry_run" == "1" ]]; then
  echo "DRY RUN complete. No files copied, no agents registered."
else
  echo "Import complete: $project"
  echo "Chats, agent sqlite, and the other host's openclaw.json were not copied."
  echo "No seed was sent."
fi
echo
echo "Next:"
echo "  openclaw gateway restart"
echo "  cd \"$dest_root/foreman\""
echo "  openclaw tui --session \"agent:${project}-foreman:main\""
