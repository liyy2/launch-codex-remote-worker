#!/bin/bash
set -euo pipefail

export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
codex_bin="${CODEX_BIN:-$HOME/.local/bin/codex}"

stop_server() {
    "$codex_bin" app-server daemon stop || true
}

trap stop_server EXIT
trap 'exit 0' TERM INT

"$codex_bin" app-server daemon bootstrap --remote-control

while true; do
    # Waiting on a background sleep lets TERM interrupt the wait immediately.
    sleep 60 &
    wait "$!"
    "$codex_bin" app-server daemon start >/dev/null
done
