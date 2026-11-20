#!/usr/bin/env bash
# host-env.sh — one PATH setup for every factory script.
#
# Non-interactive bash (tmux, `bash script.sh`) does not load nvm, so
# `openclaw` installed under ~/.nvm is missing. Source this file near the
# top of a script. Do not execute it.
#
#   source "$script_dir/lib/host-env.sh"
#
# Safe to source more than once. Does not print PATH or secrets.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "ERROR: source scripts/lib/host-env.sh; do not execute it." >&2
  exit 2
fi

if [[ "${FACTORY_HOST_ENV_LOADED:-}" == "1" ]]; then
  return 0
fi

_factory_host_env_load() {
  local nounset=0 errexit=0 bin
  local -a bins=()

  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

  case $- in
    *u*) nounset=1 ;;
  esac
  case $- in
    *e*) errexit=1 ;;
  esac

  if ! command -v openclaw >/dev/null 2>&1 && [[ -s "$NVM_DIR/nvm.sh" ]]; then
    set +u
    set +e
    # shellcheck disable=SC1090
    . "$NVM_DIR/nvm.sh"
    if type nvm >/dev/null 2>&1; then
      nvm use default --silent >/dev/null 2>&1
      if ! command -v openclaw >/dev/null 2>&1; then
        nvm use 26 --silent >/dev/null 2>&1
      fi
    fi
    if [[ "$errexit" == "1" ]]; then
      set -e
    fi
    if [[ "$nounset" == "1" ]]; then
      set -u
    fi
  fi

  if ! command -v openclaw >/dev/null 2>&1 && [[ -d "$NVM_DIR/versions/node" ]]; then
    shopt -s nullglob
    bins+=("$NVM_DIR"/versions/node/v26.*/bin)
    bins+=("$NVM_DIR"/versions/node/v*/bin)
    shopt -u nullglob
    for bin in "${bins[@]}"; do
      if [[ -x "$bin/openclaw" ]]; then
        PATH="$bin:${PATH:-/usr/bin:/bin}"
        hash -r
        break
      fi
    done
  fi

  export PATH
  FACTORY_HOST_ENV_LOADED=1
}

_factory_host_env_load
unset -f _factory_host_env_load
