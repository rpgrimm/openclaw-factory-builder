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
#   FACTORY_SEED_TIMEOUT=<seconds>       seed timeout (default: 180)
#   FACTORY_START_INTERVIEW=auto|0|1     start interview in TUI when pending (default: auto)
#                                       use 1 to force a new interview
#
# Usability notes:
# - A lightweight model turn confirms readiness. It must NOT start discovery,
#   call ask_user, or implement work during the headless seed.
# - On first TUI launch, the interview begins inside the TUI via --message, so
#   interactive ask_user prompts can actually be answered there.
# - For non-interactive setup, FACTORY_OPEN_TUI=0 leaves interview pending until
#   a later start-factory.sh invocation with FACTORY_OPEN_TUI=1.
# - Ctrl+C during seed leaves the seed marker unwritten. Check agent session
#   state before retrying an interrupted request (Gateway may finish it).
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
FACTORY_SEED_TIMEOUT="${FACTORY_SEED_TIMEOUT:-180}"
FACTORY_START_INTERVIEW="${FACTORY_START_INTERVIEW:-auto}"

case "$FACTORY_OPEN_TUI" in
0 | 1) ;;
*) echo "ERROR: FACTORY_OPEN_TUI must be 0 or 1." >&2; exit 2 ;;
esac
case "$FACTORY_RESEED_COORDINATOR" in
0 | 1) ;;
*) echo "ERROR: FACTORY_RESEED_COORDINATOR must be 0 or 1." >&2; exit 2 ;;
esac
case "$FACTORY_START_INTERVIEW" in
auto | 0 | 1) ;;
*) echo "ERROR: FACTORY_START_INTERVIEW must be auto, 0, or 1." >&2; exit 2 ;;
esac
if [[ ! "$FACTORY_SEED_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: FACTORY_SEED_TIMEOUT must be a positive number of seconds." >&2
  exit 2
fi

github_token_file="$HOME/.config/openclaw/github_token"

foreman_agent="${FACTORY_PROJECT}-foreman"
foreman_workspace="$HOME/.openclaw/workspaces/$FACTORY_PROJECT/foreman"
seed_marker="$foreman_workspace/.foreman-seeded"
legacy_seed_marker="$foreman_workspace/.factory-coordinator-seeded"
kickoff_pending="$foreman_workspace/.foreman-interview-pending"
kickoff_started="$foreman_workspace/.foreman-interview-started"

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

# Keep the ask_user schema constraints in the foreman's durable instructions,
# not just in one chat turn. This does not overwrite user-authored content.
agents_file="$foreman_workspace/AGENTS.md"
upsert_managed_block \
  "$agents_file" \
  "FACTORY INTERVIEW RULES" \
  "## Interactive discovery rules

- Do not start an interview during a headless bootstrap/readiness check.
- Ask project discovery questions only during an interactive session.
- For \`ask_user\`, EVERY \`options[].label\` must contain no more than 64
  characters; prefer 1-5 short words. Put detail in the option description.
- If \`ask_user\` rejects a question, shorten labels and retry at most once;
  otherwise ask a normal conversational question.
- Complete discovery and get the owner's direction before implementation.
- Never publish, push, deploy, or make externally visible changes without
  the owner's explicit approval."

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
# Two separate messages: a short headless readiness probe, and an interactive
# kickoff delivered only AFTER the TUI connects. Do not run discovery in seed.
#
seed_message="$(cat <<EOF
BOOTSTRAP READINESS CHECK for foreman $foreman_agent.

This is a NONINTERACTIVE one-turn health check. Your normal role and workspace
instructions are already provided by OpenClaw. Do NOT call any tools (including
ask_user), interview the owner, inspect files, browse, delegate, write plans, or
start implementation. Do not ask questions.

Reply with exactly the single word READY and nothing else.
EOF
)"

kickoff_message="$(cat <<EOF
Begin INTERACTIVE product discovery for factory $FACTORY_PROJECT.

Read AGENTS.md, TOOLS.md, IDENTITY.md, USER.md and, if present,
STARTING_IDEA.md. Treat the starting idea as a starting point, not a fixed spec.
Interview me in this TUI to determine current project state, goals, constraints,
what already exists and what should happen first. Ask focused questions, then
prepare an initial product plan and prioritized backlog after discovery.

IMPORTANT: For ask_user, each options[].label must be at most 64 characters;
prefer short labels (1-5 words) and move explanations to description. If the
question tool rejects a payload, repair the payload or ask in plain text.

Do not implement code or make externally visible changes without approval.
EOF
)"

if [[ -n "$factory_github_repo" ]]; then
  kickoff_message+="

The configured repository is $factory_github_repo. GitHub access was checked
by the startup script. You may inspect it read-only to learn its current state;
do not push, publish, create releases or change settings without approval."
else
  kickoff_message+="

No GitHub repository is configured. Do not guess a remote repository."
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
echo "Start interview:      $FACTORY_START_INTERVIEW"
echo

if [[ ( ! -f "$seed_marker" && ! -f "$legacy_seed_marker" ) ||
  "$FACTORY_RESEED_COORDINATOR" == "1" ]]; then
  echo "Checking foreman readiness (no interview or tools during seed)..."
  echo "  (Interactive discovery starts in the TUI, not here.)"
  echo

  # CLI JSON separates model output from diagnostics so we can verify READY.
  seed_json="$(mktemp)"
  # IMPORTANT: do not use 'if ! command; then rc=$?' (that produces rc=0).
  if openclaw agent \
    --agent "$foreman_agent" \
    --session-key main \
    --message "$seed_message" \
    --timeout "$FACTORY_SEED_TIMEOUT" \
    --json >"$seed_json"; then
    :
  else
    rc=$?
    rm -f "$seed_json"
    echo >&2
    echo "ERROR: Foreman readiness check failed (exit status $rc)." >&2
    echo "No new seed marker was written. Inspect 'openclaw logs --follow'." >&2
    exit "$rc"
  fi

  # OpenClaw CLI versions may return payloads at the top-level or under result.
  # Don't mark seeded unless the model actually acknowledged readiness.
  if ! jq -e . "$seed_json" >/dev/null 2>&1; then
    echo "ERROR: Foreman seed did not produce valid JSON output." >&2
    rm -f "$seed_json"
    exit 1
  fi
  seed_reply="$(jq -r '
    [ .result.payloads[]?.text,
      .payloads[]?.text,
      .result.final?,
      .final? ]
    | map(select(type == "string"))
    | join("\n")
  ' "$seed_json")"
  if [[ "${seed_reply//[[:space:]]/}" != "READY" ]]; then
    echo "ERROR: Foreman did not acknowledge readiness with READY." >&2
    if [[ -n "$seed_reply" ]]; then
      echo "Response (truncated): ${seed_reply:0:400}" >&2
    else
      echo "No text reply found in the CLI JSON payload." >&2
    fi
    rm -f "$seed_json"
    exit 1
  fi
  rm -f "$seed_json"

  {
    printf 'project=%s\n' "$FACTORY_PROJECT"
    printf 'agent=%s\n' "$foreman_agent"
    printf 'github_token_file=%s\n' "$github_token_file"
    printf 'github_repository=%s\n' "${factory_github_repo:-}"
    printf 'seeded_at=%s\n' "$(date --iso-8601=seconds)"
  } >"$seed_marker"
  if [[ -f "$legacy_seed_marker" && "$legacy_seed_marker" != "$seed_marker" ]]; then
    rm -f "$legacy_seed_marker"
  fi
  # Defer real discovery until a client capable of interactive questions exists.
  printf 'pending_at=%s\n' "$(date --iso-8601=seconds)" >"$kickoff_pending"
  rm -f "$kickoff_started"

  echo
  echo "Foreman ready. Interactive interview queued for TUI."
  echo "Seed marker: $seed_marker"
else
  echo "Foreman was already initialized:"
  if [[ -f "$seed_marker" ]]; then
    echo "  $seed_marker"
  else
    echo "  $legacy_seed_marker"
  fi
  echo
  echo "To repeat readiness check:"
  echo "  FACTORY_RESEED_COORDINATOR=1 FACTORY_PROJECT=$FACTORY_PROJECT ./start-factory.sh"
fi

#
# Open the TUI by default (interactive; blocks until TUI exits)
#

if [[ "$FACTORY_OPEN_TUI" == "0" ]]; then
  echo
  echo "TUI launch disabled (FACTORY_OPEN_TUI=0)."
  if [[ -f "$kickoff_pending" ]]; then
    echo "Interactive interview is pending and will start at the next TUI launch."
  fi
  echo
  echo "To launch later with pending interview support:"
  echo "  FACTORY_PROJECT=$(printf '%q' "$FACTORY_PROJECT") ./start-factory.sh"
  echo
  echo "Or to launch the TUI manually (without automatic interview):"
  echo "  openclaw tui --session $(printf '%q' "agent:${foreman_agent}:main")"
  exit 0
fi

echo
echo "Opening the foreman TUI (interactive; blocks until you exit)..."
echo "Working directory: $foreman_workspace"
echo "Session:           agent:${foreman_agent}:main"
echo "Tip: skip this step next time with FACTORY_OPEN_TUI=0"
echo

cd "$foreman_workspace"

start_interview=0
case "$FACTORY_START_INTERVIEW" in
1) start_interview=1 ;;
auto) [[ -f "$kickoff_pending" ]] && start_interview=1 ;;
esac

if [[ "$start_interview" == "1" ]]; then
  echo "Starting the project interview *inside* the interactive TUI."
  echo "  (ask_user prompts will now be visible and answerable.)"
  echo

  # Record launch once, not every time a factory session is reopened. If the
  # TUI cannot connect, force the interview on retry with START_INTERVIEW=1.
  if [[ -f "$kickoff_pending" ]]; then
    mv "$kickoff_pending" "$kickoff_started"
  fi
  exec openclaw tui \
    --session "agent:${foreman_agent}:main" \
    --message "$kickoff_message"
fi

exec openclaw tui \
  --session "agent:${foreman_agent}:main"
