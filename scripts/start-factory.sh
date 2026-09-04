#!/usr/bin/env bash
# start-factory.sh — bind GitHub context, seed the factory foreman once, optionally open TUI.
#
# Required:
#   FACTORY_PROJECT=<project-id>
#
# Optional:
#   FACTORY_GITHUB=<owner/repo or URL>   attach a GitHub repo (verified via gh)
#   FACTORY_IDEA='...'                   initial product idea (inline)
#   FACTORY_IDEA_FILE=/path/to/idea.txt  initial product idea (file)
#   FACTORY_OPEN_TUI=0|1                 open interactive TUI after seed (default: 1)
#   FACTORY_RESEED_COORDINATOR=0|1       force re-send of init prompt (default: 0)
#   FACTORY_GITHUB_REQUIRE_WRITE=0|1     require WRITE/MAINTAIN/ADMIN (default: 0)
#   FACTORY_SEED_TIMEOUT=<seconds>       timeout for openclaw agent seed (default: 1800)
#
# Usability notes:
# - Seeding runs `openclaw agent ...` and can take a long time while the model thinks.
#   Progress is not always visible; that is not the same as "waiting for TUI".
# - The TUI step is interactive and blocks until you exit the TUI. For non-interactive
#   setup pipelines, set FACTORY_OPEN_TUI=0 (run-factory-setup.sh does this by default).
# - Ctrl+C during seed may leave work partially done; the seed marker is written only
#   after a successful seed. See docs/issues/FM-0100-seed-hang-usability.md.
#
# Naming:
#   The multi-agent system is the factory.
#   The coordinator agent id is <project>-foreman.
#   Foreman workspace: ~/.openclaw/workspaces/<project>/foreman
#
# Token:
#   Reads ~/.config/openclaw/github_token into GH_TOKEN. Never prints the token.
#
set -Eeuo pipefail

#
# Required configuration
#

if [[ -z "${FACTORY_PROJECT:-}" ]]; then
  echo "ERROR: FACTORY_PROJECT is not set." >&2
  echo >&2
  echo "Example:" >&2
  echo "  FACTORY_PROJECT=west-boca-pc-build-lab \\" >&2
  echo "      ./start-factory.sh" >&2
  exit 2
fi

export FACTORY_PROJECT

FACTORY_IDEA="${FACTORY_IDEA:-}"
FACTORY_IDEA_FILE="${FACTORY_IDEA_FILE:-}"

if [[ -n "$FACTORY_IDEA" && -n "$FACTORY_IDEA_FILE" ]]; then
  echo "ERROR: Set FACTORY_IDEA or FACTORY_IDEA_FILE, not both." >&2
  exit 2
fi

if [[ -n "$FACTORY_IDEA_FILE" ]]; then
  if [[ ! -r "$FACTORY_IDEA_FILE" ]]; then
    echo "ERROR: FACTORY_IDEA_FILE is not readable:" >&2
    echo "  $FACTORY_IDEA_FILE" >&2
    exit 2
  fi

  FACTORY_IDEA="$(cat "$FACTORY_IDEA_FILE")"
fi

export FACTORY_IDEA

foreman_workspace="$HOME/.openclaw/workspaces/$FACTORY_PROJECT/foreman"
starting_idea_file="$foreman_workspace/STARTING_IDEA.md"

# Persist the starting idea into the coordinator workspace when provided.
if [[ -n "$FACTORY_IDEA" ]]; then
  if [[ ! -d "$foreman_workspace" ]]; then
    echo "ERROR: Foreman workspace does not exist yet:" >&2
    echo "  $foreman_workspace" >&2
    echo "Run make-factory.sh first (creates the foreman workspace)." >&2
    exit 2
  fi

  cat >"$starting_idea_file" <<EOF
# Starting Idea

Project: $FACTORY_PROJECT

## Original concept

$FACTORY_IDEA

## Factory instruction

Treat this as the initial product concept, not as an immutable specification.

Interview the owner to understand the current state, goals, constraints, and
what already exists. Refine this concept into a product plan and prioritized
backlog before implementation begins.

Do not create code, publish anything, push changes, or otherwise take externally
visible actions until explicitly instructed.
EOF

  echo "Starting idea saved:"
  echo "  $starting_idea_file"
fi

#
# Optional configuration
#
# FACTORY_GITHUB may be any of:
#
#   owner/repo
#   github.com/owner/repo
#   https://github.com/owner/repo
#   https://github.com/owner/repo.git
#   git@github.com:owner/repo.git
#
# Optional behavior:
#
#   FACTORY_OPEN_TUI=0
#       Seed/check the factory without opening the TUI.
#
#   FACTORY_RESEED_COORDINATOR=1
#       Send the initial foreman prompt again.
#
#   FACTORY_GITHUB_REQUIRE_WRITE=1
#       Fail unless GitHub reports WRITE, MAINTAIN, or ADMIN permission.
#

FACTORY_OPEN_TUI="${FACTORY_OPEN_TUI:-1}"
FACTORY_RESEED_COORDINATOR="${FACTORY_RESEED_FOREMAN:-${FACTORY_RESEED_COORDINATOR:-0}}"
FACTORY_GITHUB_REQUIRE_WRITE="${FACTORY_GITHUB_REQUIRE_WRITE:-0}"
FACTORY_SEED_TIMEOUT="${FACTORY_SEED_TIMEOUT:-1800}"

github_token_file="$HOME/.config/openclaw/github_token"

foreman_agent="${FACTORY_PROJECT}-foreman"
foreman_workspace="$HOME/.openclaw/workspaces/$FACTORY_PROJECT/foreman"
seed_marker="$foreman_workspace/.foreman-seeded"
legacy_seed_marker="$foreman_workspace/.factory-coordinator-seeded"

#
# Helpers
#

require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "ERROR: Required command is not in PATH: $command_name" >&2
    exit 2
  fi
}

normalize_github_repo() {
  local value="$1"

  value="${value%/}"
  value="${value%.git}"

  case "$value" in
  https://github.com/*)
    value="${value#https://github.com/}"
    ;;
  http://github.com/*)
    value="${value#http://github.com/}"
    ;;
  github.com/*)
    value="${value#github.com/}"
    ;;
  git@github.com:*)
    value="${value#git@github.com:}"
    ;;
  ssh://git@github.com/*)
    value="${value#ssh://git@github.com/}"
    ;;
  esac

  if [[ ! "$value" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
    echo "ERROR: Invalid FACTORY_GITHUB value: $1" >&2
    echo >&2
    echo "Expected one of:" >&2
    echo "  owner/repository" >&2
    echo "  https://github.com/owner/repository" >&2
    echo "  git@github.com:owner/repository.git" >&2
    exit 2
  fi

  printf '%s\n' "$value"
}

# Insert or replace a managed "# BEGIN name" ... "# END name" block in a file.
upsert_managed_block() {
  local file="$1"
  local block_name="$2"
  local block_content="$3"

  local begin="# BEGIN $block_name"
  local end="# END $block_name"
  local temporary

  temporary="$(mktemp "${file}.tmp.XXXXXX")"

  if [[ -f "$file" ]] && grep -Fqx "$begin" "$file"; then
    awk \
      -v begin="$begin" \
      -v end="$end" \
      -v replacement="$block_content" '
                $0 == begin {
                    print begin
                    print replacement
                    skipping = 1
                    next
                }

                $0 == end && skipping {
                    print end
                    skipping = 0
                    next
                }

                !skipping {
                    print
                }
            ' "$file" >"$temporary"
  else
    if [[ -f "$file" ]]; then
      cat "$file" >"$temporary"

      if [[ -s "$file" ]]; then
        printf '\n' >>"$temporary"
      fi
    fi

    {
      printf '%s\n' "$begin"
      printf '%s\n' "$block_content"
      printf '%s\n' "$end"
    } >>"$temporary"
  fi

  mv "$temporary" "$file"
}

check_github_access() {
  local repository="$1"
  local repository_json
  local repository_name
  local repository_url
  local permission

  echo "Checking GitHub access to: $repository"

  if ! repository_json="$(
    gh repo view "$repository" \
      --json nameWithOwner,url,viewerPermission 2>&1
  )"; then
    echo "ERROR: GitHub access check failed for $repository." >&2
    echo >&2
    echo "$repository_json" >&2
    echo >&2
    echo "Check that:" >&2
    echo "  1. The repository name is correct." >&2
    echo "  2. The token can access the repository." >&2
    echo "  3. The token has not expired." >&2
    exit 1
  fi

  repository_name="$(
    jq -r '.nameWithOwner // empty' <<<"$repository_json"
  )"

  repository_url="$(
    jq -r '.url // empty' <<<"$repository_json"
  )"

  permission="$(
    jq -r '.viewerPermission // "UNKNOWN"' <<<"$repository_json"
  )"

  if [[ -z "$repository_name" ]]; then
    echo "ERROR: GitHub returned no repository identity." >&2
    exit 1
  fi

  echo "GitHub repository: $repository_name"
  echo "GitHub URL:        $repository_url"
  echo "Token permission:  $permission"

  if [[ "$FACTORY_GITHUB_REQUIRE_WRITE" == "1" ]]; then
    case "$permission" in
    WRITE | MAINTAIN | ADMIN) ;;
    *)
      echo >&2
      echo "ERROR: Write access is required, but permission is:" >&2
      echo "  $permission" >&2
      exit 1
      ;;
    esac
  fi
}

#
# Validate local requirements
#

require_command openclaw
require_command jq

if [[ ! -d "$foreman_workspace" ]]; then
  echo "ERROR: Foreman workspace does not exist:" >&2
  echo "  $foreman_workspace" >&2
  echo >&2
  echo "Run the factory creation scripts first (make-factory.sh creates foreman workspace)." >&2
  exit 2
fi

if ! openclaw agents list --json |
  jq -e --arg id "$foreman_agent" '
        .. | objects | select(.id? == $id)
    ' >/dev/null; then
  echo "ERROR: OpenClaw agent does not exist:" >&2
  echo "  $foreman_agent" >&2
  exit 2
fi

#
# Load the GitHub token
#

if [[ ! -f "$github_token_file" ]]; then
  echo "ERROR: GitHub token file does not exist:" >&2
  echo "  $github_token_file" >&2
  exit 2
fi

if [[ ! -r "$github_token_file" ]]; then
  echo "ERROR: GitHub token file is not readable:" >&2
  echo "  $github_token_file" >&2
  exit 2
fi

GH_TOKEN="$(
  tr -d '\r\n' <"$github_token_file"
)"

if [[ -z "$GH_TOKEN" ]]; then
  echo "ERROR: GitHub token file is empty:" >&2
  echo "  $github_token_file" >&2
  exit 2
fi

export GH_TOKEN
export GH_HOST=github.com

token_permissions="$(
  stat -c '%a' "$github_token_file" 2>/dev/null || true
)"

case "$token_permissions" in
600 | 400) ;;
*)
  echo "WARNING: GitHub token permissions are $token_permissions." >&2
  echo "Consider restricting them with:" >&2
  echo "  chmod 600 $(printf '%q' "$github_token_file")" >&2
  echo >&2
  ;;
esac

#
# Normalize and check the optional GitHub repository
#

factory_github_repo=""

if [[ -n "${FACTORY_GITHUB:-}" ]]; then
  require_command gh

  factory_github_repo="$(
    normalize_github_repo "$FACTORY_GITHUB"
  )"

  FACTORY_GITHUB="$factory_github_repo"
  GH_REPO="$factory_github_repo"

  export FACTORY_GITHUB
  export GH_REPO

  check_github_access "$factory_github_repo"
fi

#
# Record GitHub information for the foreman agent (TOOLS.md managed block)
#

tools_file="$foreman_workspace/TOOLS.md"

github_tools_block="$(
  cat <<EOF
## GitHub access

GitHub token file:

\`$github_token_file\`

Rules:

- Never print, display, log, copy, or commit the token.
- Never place the token inside a Git remote URL.
- Never copy the token into a repository, specification, task, or report.
- Read the token only when GitHub authentication is needed.
- The factory startup script exports the token as \`GH_TOKEN\`.
- Use GitHub CLI or another noninteractive credential mechanism.
EOF
)"

if [[ -n "$factory_github_repo" ]]; then
  github_tools_block+="

Configured GitHub repository:

\`$factory_github_repo\`

The startup script exports this repository as both:

- \`FACTORY_GITHUB\`
- \`GH_REPO\`

Verify the target before creating branches, issues, pull requests, releases,
or pushing changes. Publishing or changing GitHub still requires the owner's
explicit approval."
else
  github_tools_block+="

No GitHub repository is currently configured through \`FACTORY_GITHUB\`.
Do not guess a repository name or push destination."
fi

upsert_managed_block \
  "$tools_file" \
  "FACTORY GITHUB ACCESS" \
  "$github_tools_block"

#
# Verify Gateway
#

if ! openclaw gateway status >/dev/null 2>&1; then
  echo "ERROR: The OpenClaw Gateway is not running." >&2
  echo "Start or restart it with:" >&2
  echo "  openclaw gateway restart" >&2
  exit 1
fi

#
# Build the initial foreman prompt
#
if [[ -n "$FACTORY_IDEA" ]]; then
  initial_message="$(
    cat <<EOF
Begin as the foreman (main coordinator) for this factory.

The owner's starting idea is:

--- STARTING IDEA ---

$FACTORY_IDEA

--- END STARTING IDEA ---

This idea has also been saved in:

$starting_idea_file

Read that file along with your AGENTS.md, TOOLS.md, IDENTITY.md, and USER.md.

Interview me about the current state of the project. Determine what already
exists, what I actually want to build, important constraints, and what should
happen first.

Then create an initial product plan and prioritized backlog.

Do not create code or publish anything yet.
EOF
  )"
else
  initial_message="$(
    cat <<EOF
Begin as the foreman (main coordinator) for this factory.

Read your AGENTS.md, TOOLS.md, IDENTITY.md, and USER.md.

Interview me about the project's starting idea and current state. Determine
what already exists, what I want to build, important constraints, and what
should happen first.

Then create an initial product plan and prioritized backlog.

Do not create code or publish anything yet.
EOF
  )"
fi

if [[ -n "$factory_github_repo" ]]; then
  initial_message+="

The configured GitHub repository is:

$factory_github_repo

You have verified access to it. You may inspect it to understand the current
state of the project.

Do not push, publish, create releases, modify repository settings, or perform
other externally visible actions without my explicit approval."
else
  initial_message+="

No GitHub repository has been configured yet. Do not guess one."
fi

#
# Seed foreman once
#

echo
echo "Project:           $FACTORY_PROJECT"
echo "Foreman agent:      $foreman_agent"
echo "Workspace:         $foreman_workspace"
echo "GitHub token file:  $github_token_file"

if [[ -n "$factory_github_repo" ]]; then
  echo "GitHub repository:  $factory_github_repo"
else
  echo "GitHub repository:  not configured"
fi

echo "Open TUI after seed:  $FACTORY_OPEN_TUI"
echo "Seed timeout (sec):   $FACTORY_SEED_TIMEOUT"
echo

if [[ ( ! -f "$seed_marker" && ! -f "${legacy_seed_marker:-}" ) ||
  "$FACTORY_RESEED_COORDINATOR" == "1" ]]; then
  echo "Seeding the factory foreman..."
  echo "  (This runs the model once and can take several minutes.)"
  echo "  (It is not waiting for the TUI. Ctrl+C aborts seeding.)"
  echo "  (For setup pipelines without interaction: FACTORY_OPEN_TUI=0)"
  echo

  # Run seed in a way that surfaces timeout clearly. Marker is written only on success.
  if ! openclaw agent \
    --agent "$foreman_agent" \
    --session-key main \
    --message "$initial_message" \
    --timeout "$FACTORY_SEED_TIMEOUT"; then
    rc=$?
    echo >&2
    echo "ERROR: Foreman seeding failed or timed out (status $rc)." >&2
    echo "Seed marker was NOT written. You can retry with:" >&2
    echo "  FACTORY_PROJECT=$(printf '%q' "$FACTORY_PROJECT") \\" >&2
    if [[ -n "$factory_github_repo" ]]; then
      echo "  FACTORY_GITHUB=$(printf '%q' "$factory_github_repo") \\" >&2
    fi
    echo "  FACTORY_OPEN_TUI=0 ./start-factory.sh" >&2
    exit "$rc"
  fi

  {
    printf 'project=%s\n' "$FACTORY_PROJECT"
    printf 'agent=%s\n' "$foreman_agent"
    printf 'github_token_file=%s\n' "$github_token_file"
    printf 'github_repository=%s\n' "${factory_github_repo:-}"
    printf 'seeded_at=%s\n' "$(date --iso-8601=seconds)"
  } >"$seed_marker"
  if [[ -n "${legacy_seed_marker:-}" && -f "$legacy_seed_marker" && "$legacy_seed_marker" != "$seed_marker" ]]; then
    rm -f "$legacy_seed_marker"
  fi

  echo
  echo "Foreman initialization completed."
  echo "Seed marker: $seed_marker"
else
  echo "Foreman was already initialized:"
  if [[ -f "$seed_marker" ]]; then
    echo "  $seed_marker"
  else
    echo "  $legacy_seed_marker"
  fi
  echo
  echo "To send the initialization prompt again:"
  echo "  FACTORY_RESEED_COORDINATOR=1 FACTORY_PROJECT=$FACTORY_PROJECT ./start-factory.sh"
fi

#
# Open the TUI by default (interactive; blocks until TUI exits)
#

if [[ "$FACTORY_OPEN_TUI" == "0" ]]; then
  echo
  echo "TUI launch disabled (FACTORY_OPEN_TUI=0)."
  echo
  echo "Open it manually with:"
  echo "  cd $(printf '%q' "$foreman_workspace")"
  echo "  openclaw tui --session \\"
  echo "      $(printf '%q' "agent:${foreman_agent}:main")"
  exit 0
fi

echo
echo "Opening the foreman TUI (interactive; blocks until you exit)..."
echo "Working directory: $foreman_workspace"
echo "Session:           agent:${foreman_agent}:main"
echo "Tip: skip this step next time with FACTORY_OPEN_TUI=0"
echo

cd "$foreman_workspace"

exec openclaw tui \
  --session "agent:${foreman_agent}:main"
