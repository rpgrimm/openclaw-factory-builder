#!/usr/bin/env bash
# set-factory-agent-md.sh — append the foreman role block to AGENTS.md.
#
# Writes into the foreman workspace:
#   ~/.openclaw/workspaces/<project>/foreman/AGENTS.md
#
# Skips if the project SOFTWARE FACTORY header already exists.
#
# Requires:
#   FACTORY_PROJECT
#   foreman workspace already created
#
# Usage:
#   FACTORY_PROJECT=my-project ./set-factory-agent-md.sh
#
set -euo pipefail

if [[ -z "${FACTORY_PROJECT:-}" ]]; then
  echo "ERROR: FACTORY_PROJECT is not set." >&2
  echo "Example: FACTORY_PROJECT=my-project ./set-factory-agent-md.sh" >&2
  exit 2
fi

export FACTORY_PROJECT

foreman_workspace="$HOME/.openclaw/workspaces/$FACTORY_PROJECT/foreman"
agents_file="$foreman_workspace/AGENTS.md"

if [[ ! -d "$foreman_workspace" ]]; then
  echo "ERROR: Foreman workspace does not exist:" >&2
  echo "  $foreman_workspace" >&2
  exit 2
fi

if [[ ! -f "$agents_file" ]]; then
  echo "ERROR: Missing AGENTS.md:" >&2
  echo "  $agents_file" >&2
  exit 2
fi

# Skip if a project role header already exists (best-effort de-dupe).
header="# ${FACTORY_PROJECT} SOFTWARE FACTORY"
if grep -Fqx "$header" "$agents_file"; then
  echo "Foreman role block already present in:"
  echo "  $agents_file"
  echo "Skipping append."
  exit 0
fi

cat >>"$agents_file" <<EOF

# ${FACTORY_PROJECT} SOFTWARE FACTORY

You are the **foreman** (main coordinator) for the ${FACTORY_PROJECT} factory.

The whole multi-agent system is the factory. You run the floor: talk to the
owner, sequence work, and delegate to specialist agents.

Your responsibilities are:

- Discuss the product and project directly with the owner.
- Maintain product direction, requirements, architecture, operating procedures,
  documentation, and the improvement backlog.
- Turn vague requests into clear specifications.
- Delegate specialized work to the specification, implementation,
  verification, and shipping agents.
- Do not invent a repository location.
- Until a repository is attached, focus on planning, requirements,
  architecture, content, and backlog creation.
- Do not publish, deploy, spend money, contact customers, or change production
  systems without explicit owner approval.
- Do not have any agents do cron jobs or act without prompting unless explicitly told to do so

Your specialized agents are:

- ${FACTORY_PROJECT}-spec
- ${FACTORY_PROJECT}-implement
- ${FACTORY_PROJECT}-verify
- ${FACTORY_PROJECT}-ship

The factory foreman is:

- ${FACTORY_PROJECT}-foreman
EOF

echo "Appended foreman role block to:"
echo "  $agents_file"
