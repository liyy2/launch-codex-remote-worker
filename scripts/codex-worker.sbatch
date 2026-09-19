#!/bin/bash

set -euo pipefail

old_job_id="${1:-}"
worker_home="${CODEX_WORKER_HOME:-$HOME/.codex-worker}"
codex_bin="${CODEX_BIN:-$HOME/.local/bin/codex}"

export CODEX_HOME="$worker_home"
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK:-1}
export MKL_NUM_THREADS=${SLURM_CPUS_PER_TASK:-1}
export OPENBLAS_NUM_THREADS=${SLURM_CPUS_PER_TASK:-1}

if [[ ! -x "$codex_bin" ]]; then
    codex_bin=$(command -v codex)
fi

if [[ -n "$old_job_id" ]] && squeue -h -j "$old_job_id" | grep -q .; then
    "$codex_bin" remote-control stop >/dev/null 2>&1 || true
    scancel "$old_job_id"
    while squeue -h -j "$old_job_id" | grep -q .; do
        sleep 2
    done
fi

stop_server() {
    "$codex_bin" remote-control stop >/dev/null 2>&1 || true
}

start_server() {
    if "$codex_bin" remote-control start; then
        return 0
    fi
    sleep 3
    "$codex_bin" remote-control start
}

server_is_alive() {
    local pid_file="$worker_home/app-server-daemon/app-server.pid"
    local server_pid

    [[ -f "$pid_file" ]] || return 1
    server_pid=$(sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p' "$pid_file")
    [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null
}

trap stop_server EXIT TERM INT
stop_server
start_server

while sleep 60; do
    if server_is_alive; then
        continue
    fi

    # The updater can replace the app-server and rotate its PID.
    sleep 15
    if server_is_alive; then
        continue
    fi

    echo "Codex app-server is down; restarting it."
    if ! start_server; then
        echo "Codex restart failed; watchdog will retry in 60 seconds." >&2
    fi
done
