#!/usr/bin/env bash
# audit-factory-host.sh — check the machine before factory setup.
#
# Fails fast on the problems that usually show up halfway through setup:
#   - openclaw is not on PATH (nvm not loaded)
#   - GitHub token file is missing or empty
#   - gateway auth token is not configured
#   - gateway service is not installed or not running
#
# Never prints token values.
#
# Extra requirements (new-factory sets these):
#   FACTORY_AUDIT_REQUIRE_TMUX=1
#   FACTORY_AUDIT_REQUIRE_VIM=1
#   FACTORY_AUDIT_REQUIRE_PYTHON=1
#   FACTORY_AUDIT_REQUIRE_GH=1
#
# Usage:
#   ./audit-factory-host.sh
#
set -Eeuo pipefail

script_dir="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"
# shellcheck source=lib/host-env.sh
source "$script_dir/lib/host-env.sh"

fail=0

ok() {
  printf '  OK    %s\n' "$1"
}

bad() {
  printf '  FAIL  %s\n' "$1" >&2
  fail=1
}

note() {
  printf '  WARN  %s\n' "$1" >&2
}

check_command() {
  local name="$1"
  local required="$2"
  local hint="$3"
  local path

  path="$(command -v "$name" 2>/dev/null || true)"
  if [[ -n "$path" ]]; then
    ok "$name ($path)"
    return 0
  fi

  if [[ "$required" == "1" ]]; then
    bad "$name is not in PATH. $hint"
  else
    note "$name is not in PATH. $hint"
  fi
}

echo "Factory host audit"
echo "=================================================="

echo
echo "Commands"
check_command git 1 "Install git."
check_command jq 1 "Install jq. Factory scripts parse OpenClaw JSON with it."
check_command node 1 "Install Node 26 (nvm use 26) so the OpenClaw CLI can run."

if command -v openclaw >/dev/null 2>&1; then
  ok "openclaw ($(command -v openclaw))"
else
  bad "openclaw is not in PATH. Install it (npm install -g openclaw) on the Node that nvm selects. scripts/lib/host-env.sh loads nvm for non-interactive shells."
fi

check_command gh "$([[ "${FACTORY_AUDIT_REQUIRE_GH:-0}" == "1" ]] && echo 1 || echo 0)" \
  "Install GitHub CLI. Required when a factory binds a GitHub repo."
check_command tmux "$([[ "${FACTORY_AUDIT_REQUIRE_TMUX:-0}" == "1" ]] && echo 1 || echo 0)" \
  "Install tmux. new-factory runs setup inside a tmux session."
check_command vim "$([[ "${FACTORY_AUDIT_REQUIRE_VIM:-0}" == "1" ]] && echo 1 || echo 0)" \
  "Install vim. new-factory opens the factory idea in vim."
check_command python3 "$([[ "${FACTORY_AUDIT_REQUIRE_PYTHON:-0}" == "1" ]] && echo 1 || echo 0)" \
  "Install python3. new-factory uses it to update factory-env.sh."

echo
echo "GitHub token"
github_token_file="${FACTORY_GITHUB_TOKEN_FILE:-$HOME/.config/openclaw/github_token}"
if [[ ! -f "$github_token_file" ]]; then
  bad "GitHub token file is missing: $github_token_file"
  echo "        Create that file with a GitHub token, chmod 600. Do not commit it." >&2
elif [[ ! -r "$github_token_file" ]]; then
  bad "GitHub token file is not readable: $github_token_file"
elif [[ ! -s "$github_token_file" ]]; then
  bad "GitHub token file is empty: $github_token_file"
else
  ok "GitHub token file is present (value not shown)"
  token_permissions="$(stat -c '%a' "$github_token_file" 2>/dev/null || true)"
  case "$token_permissions" in
    600 | 400) ok "GitHub token file mode is $token_permissions" ;;
    "") note "Could not read GitHub token file mode." ;;
    *)
      note "GitHub token file mode is $token_permissions. Prefer: chmod 600 $github_token_file"
      ;;
  esac

  if command -v gh >/dev/null 2>&1; then
    gh_login="$(mktemp)"
    gh_err="$(mktemp)"
    if GH_TOKEN="$(tr -d '\r\n' <"$github_token_file")" GH_HOST=github.com \
      gh api user --jq .login >"$gh_login" 2>"$gh_err"; then
      ok "GitHub token accepted for $(tr -d '\r\n' <"$gh_login")"
    else
      bad "GitHub token was not accepted by api.github.com. Check the token in $github_token_file (it is not printed here)."
    fi
    rm -f "$gh_login" "$gh_err"
  fi
fi

echo
echo "Gateway token"
config_file="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"
if [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
  ok "OPENCLAW_GATEWAY_TOKEN is set in the environment (value not shown)"
elif [[ ! -f "$config_file" ]]; then
  bad "Gateway config is missing: $config_file"
  echo "        Run openclaw onboard, or set gateway.auth.token. Do not paste the token into the repo." >&2
elif ! command -v jq >/dev/null 2>&1; then
  bad "Cannot check gateway.auth.token because jq is missing."
else
  token_state="$(
    jq -r '
      .gateway.auth as $auth
      | ($auth.mode // "token") as $mode
      | if $mode == "none" then "none"
        elif $mode == "trusted-proxy" then "trusted-proxy"
        elif $mode == "password" then
          if (($auth.password // "") | length) > 0 then "password-set" else "password-missing" end
        else
          if (($auth.token // "") | length) > 0 then "token-set" else "token-missing" end
        end
    ' "$config_file" 2>/dev/null || echo "unreadable"
  )"
  case "$token_state" in
    token-set) ok "gateway.auth.token is set in $config_file (value not shown)" ;;
    password-set) ok "gateway.auth.password is set (value not shown)" ;;
    trusted-proxy) ok "gateway auth mode is trusted-proxy" ;;
    none) note "gateway auth mode is none. Token auth is not configured." ;;
    token-missing)
      bad "gateway.auth.token is empty in $config_file. Set a gateway token (openclaw gateway auth-token) or export OPENCLAW_GATEWAY_TOKEN."
      ;;
    password-missing)
      bad "gateway auth mode is password but gateway.auth.password is empty."
      ;;
    *)
      bad "Could not read gateway auth from $config_file."
      ;;
  esac
fi

echo
echo "Gateway service"
unit="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/openclaw-gateway.service"
if [[ "$(uname -s)" == "Linux" ]]; then
  if [[ -f "$unit" ]]; then
    ok "gateway unit installed ($unit)"
    if systemctl --user is-active --quiet openclaw-gateway.service; then
      ok "gateway service is active"
    else
      bad "gateway service is installed but not running. Start it: openclaw gateway start"
    fi
  else
    bad "gateway service is not installed ($unit missing). Install it: openclaw gateway install"
  fi
fi

if command -v openclaw >/dev/null 2>&1; then
  status_out="$(mktemp)"
  if openclaw gateway status >"$status_out" 2>&1; then
    if grep -q "Runtime: running" "$status_out"; then
      ok "openclaw gateway status: runtime running"
    else
      bad "openclaw gateway status did not report a running runtime. Start it: openclaw gateway start"
    fi
    if grep -q "Connectivity check: ok" "$status_out"; then
      ok "openclaw gateway status: connectivity ok"
    else
      bad "openclaw gateway status did not report connectivity ok. Check: openclaw gateway status"
    fi
  else
    bad "openclaw gateway status failed. Install and start the gateway: openclaw gateway install && openclaw gateway start"
  fi
  rm -f "$status_out"
fi

echo
echo "=================================================="
if [[ "$fail" -ne 0 ]]; then
  echo "HOST AUDIT FAILED" >&2
  echo "Fix the FAIL lines above, then run factory setup again." >&2
  exit 1
fi

echo "HOST AUDIT PASSED"
exit 0
