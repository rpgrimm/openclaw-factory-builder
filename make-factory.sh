#!/usr/bin/env bash
# Thin wrapper: real script lives in scripts/make-factory.sh
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
exec bash -Eeuo pipefail "$root/scripts/make-factory.sh" "$@"
