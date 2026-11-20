#!/usr/bin/env bash
# new-factory — audit this host, then bootstrap a factory in tmux.
#
# Usage:
#   ./new-factory.sh [project-name]
#
# Environment:
#   FACTORY_BASE_DIR       where project checkouts live (default: ~/code/dev)
#   FACTORY_TEMPLATE_REPO  factory-builder git URL
#
set -Eeuo pipefail

script_dir="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"
# shellcheck source=lib/host-env.sh
source "$script_dir/lib/host-env.sh"

BASE_DIR="${FACTORY_BASE_DIR:-$HOME/code/dev}"
TEMPLATE_REPO="${FACTORY_TEMPLATE_REPO:-https://github.com/rpgrimm/openclaw-factory-builder.git}"

run_audit() {
  FACTORY_AUDIT_REQUIRE_TMUX=1 \
    FACTORY_AUDIT_REQUIRE_VIM=1 \
    FACTORY_AUDIT_REQUIRE_PYTHON=1 \
    FACTORY_AUDIT_REQUIRE_GH=1 \
    bash "$script_dir/audit-factory-host.sh"
}

###############################################################################
# Update or add an exported shell variable in factory-env.sh
###############################################################################
set_env_var() {
  local file="$1"
  local key="$2"
  local value="$3"

  FILE="$file" KEY="$key" VALUE="$value" python3 <<'PY'
import os
import re
import shlex
from pathlib import Path

path = Path(os.environ["FILE"])
key = os.environ["KEY"]
value = os.environ["VALUE"]

quoted = shlex.quote(value)
text = path.read_text()
pattern = re.compile(
    rf"^\s*(?:export\s+)?{re.escape(key)}=.*$",
    re.MULTILINE,
)
replacement = f"export {key}={quoted}"

if pattern.search(text):
    text = pattern.sub(replacement, text)
else:
    if text and not text.endswith("\n"):
        text += "\n"
    text += replacement + "\n"

path.write_text(text)
PY
}

###############################################################################
# This part runs INSIDE tmux
###############################################################################
if [[ "${1:-}" == "--inside" ]]; then
  project="$2"
  dest="${BASE_DIR}/openclaw-factory-builder-${project}"

  echo
  echo "Factory project: $project"
  echo "Directory:       $dest"
  echo

  run_audit

  mkdir -p "$BASE_DIR"

  if [[ ! -d "$dest/.git" ]]; then
    echo "Cloning factory builder..."
    git clone "$TEMPLATE_REPO" "$dest"
  else
    echo "Factory builder tree already exists."
  fi

  cd "$dest"

  if [[ ! -f factory-env.sh ]]; then
    cat > factory-env.sh <<'EOF'
#!/usr/bin/env bash

export FACTORY_PROJECT=""
export FACTORY_GITHUB=""
export FACTORY_IDEA=""
EOF
    chmod +x factory-env.sh
  fi

  set -a
  # shellcheck disable=SC1091
  source ./factory-env.sh
  set +a

  existing_github="${FACTORY_GITHUB:-}"

  echo
  if [[ -n "$existing_github" ]]; then
    read -r -p "GitHub URL [$existing_github]: " github_url
    github_url="${github_url:-$existing_github}"
  else
    read -r -p "GitHub URL: " github_url
  fi

  existing_idea="${FACTORY_IDEA:-}"

  if [[ -n "$existing_idea" ]]; then
    echo
    echo "Existing factory idea:"
    echo "------------------------------------------------------------"
    printf '%s\n' "$existing_idea"
    echo "------------------------------------------------------------"

    read -r -p "Reuse existing idea? [Y/n]: " reuse_idea

    case "$reuse_idea" in
      "" | [Yy] | [Yy][Ee][Ss])
        idea="$existing_idea"
        echo "Reusing existing factory idea."
        ;;
      [Nn] | [Nn][Oo])
        idea_file="$(mktemp)"
        printf '%s\n' "$existing_idea" >"$idea_file"
        echo
        echo "Opening Vim to edit the factory idea..."
        echo "Save and quit with :wq"
        echo
        vim "$idea_file"
        idea="$(cat "$idea_file")"
        rm -f "$idea_file"
        ;;
      *)
        echo "Unrecognized response; reusing existing factory idea."
        idea="$existing_idea"
        ;;
    esac
  else
    idea_file="$(mktemp)"
    echo
    echo "Opening Vim for the factory idea..."
    echo "Save and quit with :wq"
    echo
    vim "$idea_file"
    idea="$(cat "$idea_file")"
    rm -f "$idea_file"
  fi

  set_env_var factory-env.sh FACTORY_PROJECT "$project"
  set_env_var factory-env.sh FACTORY_GITHUB "$github_url"
  set_env_var factory-env.sh FACTORY_IDEA "$idea"

  echo
  echo "------------------------------------------------------------"
  echo "Factory environment"
  echo "------------------------------------------------------------"
  grep -E '^export FACTORY_(PROJECT|GITHUB)=' factory-env.sh || true
  echo "FACTORY_IDEA is set (not printed; it can be long)."
  echo "------------------------------------------------------------"
  echo

  read -r -p "Press Enter to run ./run-factory-setup.sh ..."

  # shellcheck disable=SC1091
  source ./factory-env.sh
  ./run-factory-setup.sh

  echo
  echo "Factory setup finished."
  echo
  echo "Leaving you in:"
  echo "  $dest"
  echo

  exec "${SHELL:-/bin/bash}"
fi

###############################################################################
# OUTER invocation
###############################################################################

run_audit

project="${1:-}"

if [[ -z "$project" ]]; then
  read -r -p "Project name: " project
fi

# "Mention Scout" / "mention_scout" -> mention-scout
project="$(
  printf '%s' "$project" |
    tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
)"

if [[ -z "$project" ]]; then
  echo "Invalid project name." >&2
  exit 1
fi

session="factory-builder-${project}"
mkdir -p "$BASE_DIR"

if tmux has-session -t "$session" 2>/dev/null; then
  echo "Attaching to existing tmux session: $session"
  exec tmux attach-session -t "$session"
fi

echo
echo "Starting tmux session:"
echo "  $session"
echo

tmux new-session \
  -d \
  -s "$session" \
  -c "$BASE_DIR" \
  "$0" --inside "$project"

tmux set-option -t "$session" remain-on-exit on

exec tmux attach-session -t "$session"
