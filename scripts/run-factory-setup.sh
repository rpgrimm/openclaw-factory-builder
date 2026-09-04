#!/usr/bin/env bash
# run-factory-setup.sh — one-shot factory bootstrap pipeline.
#
# Runs, in order:
#   1. make-factory.sh           create/reuse agents + workspaces
#   2. set-identities.sh         display names / emoji
#   3. set-factory-agent-md.sh   coordinator role block in AGENTS.md
#   4. configure_delegation.sh   allow coordinator to spawn workers
#   5. start-factory.sh          GitHub bind + one-time foreman seed
#
# Required:
#   FACTORY_PROJECT=<project-id>
#
# Optional (passed through to start-factory.sh):
#   FACTORY_GITHUB, FACTORY_IDEA, FACTORY_IDEA_FILE,
#   FACTORY_RESEED_COORDINATOR, FACTORY_GITHUB_REQUIRE_WRITE, FACTORY_SEED_TIMEOUT
#
# TUI behavior:
#   Full setup is usually non-interactive. Default here is FACTORY_OPEN_TUI=0 so
#   the pipeline does not appear to "hang" waiting on an interactive TUI after
#   seeding. Override with FACTORY_OPEN_TUI=1 if you want the TUI at the end.
#
# Usage:
#   FACTORY_PROJECT=my-project \
#   FACTORY_GITHUB=owner/repo \
#   FACTORY_IDEA='build a thing' \
#   ./run-factory-setup.sh
#
set -Eeuo pipefail

if [[ -z "${FACTORY_PROJECT:-}" ]]; then
  echo "ERROR: FACTORY_PROJECT is not set." >&2
  echo "Example:" >&2
  echo "  FACTORY_PROJECT=west-boca-pc-build-lab ./run-factory-setup.sh" >&2
  exit 2
fi

export FACTORY_PROJECT

# Default: do not block the setup pipeline on an interactive TUI.
# start-factory.sh still defaults to TUI=1 when run alone.
export FACTORY_OPEN_TUI="${FACTORY_OPEN_TUI:-0}"

script_dir="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"

scripts=(
  "make-factory.sh"
  "set-identities.sh"
  "set-factory-agent-md.sh"
  "configure_delegation.sh"
  "start-factory.sh"
)

echo "=================================================="
echo "OpenClaw software factory setup"
echo "Project:   $FACTORY_PROJECT"
echo "Directory: $script_dir"
echo "Open TUI:  $FACTORY_OPEN_TUI"
echo "=================================================="

# Validate every script before starting.
for script in "${scripts[@]}"; do
  path="$script_dir/$script"

  if [[ ! -f "$path" ]]; then
    echo "ERROR: Missing required script: $path" >&2
    exit 2
  fi

  if [[ ! -x "$path" ]]; then
    echo "WARNING: Script is not executable (will run via bash): $path" >&2
  fi
done

for script in "${scripts[@]}"; do
  path="$script_dir/$script"

  echo
  echo "--------------------------------------------------"
  echo "Running: $script"
  echo "Project: $FACTORY_PROJECT"
  echo "--------------------------------------------------"

  # Run every child explicitly under strict Bash so permissions are not required.
  if bash -Eeuo pipefail "$path"; then
    echo "Completed: $script"
  else
    rc=$?

    echo >&2
    echo "==================================================" >&2
    echo "FACTORY SETUP FAILED" >&2
    echo "Project: $FACTORY_PROJECT" >&2
    echo "Script:  $script" >&2
    echo "Status:  $rc" >&2
    echo "==================================================" >&2

    exit "$rc"
  fi
done

echo
echo "=================================================="
echo "FACTORY SETUP COMPLETED SUCCESSFULLY"
echo "Project: $FACTORY_PROJECT"
echo "=================================================="
echo
echo "Next steps:"
echo "  1. If delegation config changed: openclaw gateway restart"
echo "  2. Open the foreman TUI when ready:"
echo "       cd \"$HOME/.openclaw/workspaces/$FACTORY_PROJECT/foreman\""
echo "       openclaw tui --session \"agent:${FACTORY_PROJECT}-foreman:main\""
echo "     Or:"
echo "       FACTORY_PROJECT=$FACTORY_PROJECT FACTORY_OPEN_TUI=1 ./start-factory.sh"
