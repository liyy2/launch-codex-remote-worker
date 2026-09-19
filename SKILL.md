---
name: launch-codex-remote-worker
description: Launch, recover, pair, or open projects on a singleton Codex Remote Control worker in a Slurm compute allocation. Use for a persistent launcher/replaceable worker design; not for the master login-node Codex or ordinary batch jobs.
---

# Launch Codex remote worker

Use this architecture:

```text
master Codex on login node -> Slurm allocation -> compute node -> worker Codex
```

The master is a lightweight persistent launcher using `~/.codex`. The worker
does project work on a compute node using persistent state in
`~/.codex-worker`. The worker is a singleton, but its Slurm process and physical
node are replaceable.

## Preserve these invariants

- Keep the worker project-independent; do not create or bind a worktree during
  launch.
- Never start or stop the worker with the master `CODEX_HOME`.
- Run only one app-server against `~/.codex-worker` at a time.
- Reuse `~/.codex-worker` so worker threads, pairing identity, and history
  survive allocation changes.
- Share selected user setup only. Keep worker databases, sessions, memories,
  installation identity, locks, sockets, logs, and caches separate from the
  master.
- Both agents see the same project filesystem. Coordinate edits rather than
  letting master and worker modify the same files concurrently.

## One-time worker home

Create `~/.codex-worker` with mode `700`. Symlink these paths to the master:

```text
~/.codex-worker/auth.json   -> ~/.codex/auth.json
~/.codex-worker/config.toml -> ~/.codex/config.toml
~/.codex-worker/AGENTS.md   -> ~/.codex/AGENTS.md
~/.codex-worker/skills      -> ~/.codex/skills
```

If a worker-local `skills/` directory already exists, move it aside before
creating the link. Do not symlink the entire `~/.codex` directory.

Daemon mode also needs the managed standalone binary at:

```text
~/.codex-worker/packages/standalone/current/codex
```

Link `current` to the resolved master standalone release under
`~/.codex/packages/standalone/releases/`. The worker updater may later replace
that link with a newer worker-local release.

## Inspect before launch

Record the login-node hostname and inspect `tmux` plus `squeue`. Reuse a live
worker and never create a duplicate. Choose resources from current partition
limits and actual work. `devel` is for a short one-off session, not a recurring
service; use `day` or `week` when the intended walltime requires them.

For an unattended allocation, submit the included update-safe helper. Example:

```bash
worker_script="$HOME/.codex/skills/launch-codex-remote-worker/scripts/codex-worker.sbatch"
sbatch \
  --job-name=codex-worker \
  --partition=devel \
  --time=06:00:00 \
  --nodes=1 \
  --ntasks=1 \
  --cpus-per-task=4 \
  --mem=16G \
  --output="$HOME/.codex-worker/slurm-%j.out" \
  --error="$HOME/.codex-worker/slurm-%j.err" \
  "$worker_script"
```

The helper keeps the allocation alive across normal app-server PID rotation
during Codex updates. It rereads the PID file and restarts Remote Control only
when no replacement daemon appears after a grace period. It does not renew an
expired Slurm allocation automatically.

To replace a running worker without sharing state concurrently, pass its job ID
as the helper's sole argument. The new allocation stops and cancels that old job
before starting its daemon:

```bash
sbatch [resource options] "$worker_script" OLD_JOB_ID
```

## Interactive mode

For interactive development, use `$tmux-salloc` with a project-independent
session named `codex-worker`, starting in `$HOME`. Once inside the compute shell:

```bash
export CODEX_HOME="$HOME/.codex-worker"
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK:-1}
export MKL_NUM_THREADS=${SLURM_CPUS_PER_TASK:-1}
export OPENBLAS_NUM_THREADS=${SLURM_CPUS_PER_TASK:-1}
"$HOME/.local/bin/codex" remote-control start
```

Use daemon subcommand `start`, not bare foreground `codex remote-control`, so
the control socket required by `pair` exists.

## Pairing and node changes

Generate a code only when the current app is not already connected:

```bash
CODEX_HOME="$HOME/.codex-worker" \
  "$HOME/.local/bin/codex" remote-control pair
```

The app may retain the hostname label from the first paired compute node after
Slurm moves the worker. If that entry stays connected and shows worker threads,
treat it as the stable logical worker. Use `squeue` to identify the physical
node.

## Open a project

The worker is not tied to a repository. Open any project from the remote app,
or seed a thread from the compute shell:

```bash
cd /absolute/path/to/project
"$HOME/.local/bin/codex"
```

Do not use `exec` for a project TUI if returning from Codex should return to the
compute shell. A new empty TUI may not appear remotely until its first message.

## Stop only the worker

Stop Remote Control with worker state, then release only its allocation:

```bash
CODEX_HOME="$HOME/.codex-worker" \
  "$HOME/.local/bin/codex" remote-control stop
```

Preserve `~/.codex-worker` for the next allocation. Never cancel a different
service merely because it runs on a node that previously hosted the worker.
