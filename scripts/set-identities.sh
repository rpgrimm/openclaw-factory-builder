#!/usr/bin/env bash
# set-identities.sh — apply display names / themes / emoji for factory roles.
#
# Requires:
#   FACTORY_PROJECT
#   openclaw agents already created (see make-factory.sh)
#
# Usage:
#   FACTORY_PROJECT=my-project ./set-identities.sh
#
set -euo pipefail

if [[ -z "${FACTORY_PROJECT:-}" ]]; then
  echo "ERROR: FACTORY_PROJECT is not set." >&2
  echo "Example: FACTORY_PROJECT=my-project ./set-identities.sh" >&2
  exit 2
fi

export FACTORY_PROJECT

if ! command -v openclaw >/dev/null 2>&1; then
  echo "ERROR: openclaw is not in PATH." >&2
  exit 2
fi

echo "Setting identities for factory project: $FACTORY_PROJECT"

# The factory is the whole system; this agent is the foreman.
openclaw agents set-identity \
  --agent "${FACTORY_PROJECT}-foreman" \
  --name "${FACTORY_PROJECT}: Foreman" \
  --theme "practical factory floor boss / product coordinator" \
  --emoji "🏭"

openclaw agents set-identity \
  --agent "${FACTORY_PROJECT}-spec" \
  --name "${FACTORY_PROJECT}: Specification Engineer" \
  --theme "precise requirements and product designer" \
  --emoji "📐"

openclaw agents set-identity \
  --agent "${FACTORY_PROJECT}-implement" \
  --name "${FACTORY_PROJECT}: Implementation Engineer" \
  --theme "careful software and automation builder" \
  --emoji "🛠️"

# Verify owns independent review and testing in the v0 skeleton.
openclaw agents set-identity \
  --agent "${FACTORY_PROJECT}-verify" \
  --name "${FACTORY_PROJECT}: Verification Engineer" \
  --theme "independent reviewer and tester" \
  --emoji "🔎"

openclaw agents set-identity \
  --agent "${FACTORY_PROJECT}-ship" \
  --name "${FACTORY_PROJECT}: Release Engineer" \
  --theme "conservative release custodian" \
  --emoji "📦"

echo "Identities updated."
