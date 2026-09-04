#!/usr/bin/env bash
# Thin wrapper: real script lives in scripts/pause-all-factories.sh
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
exec bash -Eeuo pipefail "$root/scripts/pause-all-factories.sh" "$@"
