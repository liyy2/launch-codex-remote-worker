---
name: launch-codex-remote-worker
description: Set up, pair, and manage a persistent Codex Remote Control server on a Linux devbox using a systemd user service. Use for startup after reboot, recovery after a server exit, and remote access to projects.
---

# Launch Codex on a Linux devbox

Run one Codex daemon for the user's persistent Codex home. The bundled systemd
user service starts it at boot, checks it periodically, and stops it cleanly.
The server is independent of any project or worktree.

## Inspect the devbox

- Check the installed Codex version, `codex app-server daemon --help`, and
  `codex remote-control --help`. The commands below were checked with 0.154.0.
- Confirm `systemctl --user` works. This skill requires systemd user services;
  a detached process alone does not establish startup after reboot.
- Identify the current Codex home, binary, and any existing service before
  installing another supervisor. Reuse an existing service for that home.
- The examples use `~/.codex` and `~/.local/bin/codex`. If the user already uses
  a different home or binary, use those paths consistently in the service,
  login, pairing, and verification commands.

## Installation and login

Use a complete standalone Codex installation. If Codex is missing or its
managed daemon package is unavailable, use the official installer:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

Run as the devbox user, not root. Check authentication in the selected home:

```bash
CODEX_HOME="$HOME/.codex" "$HOME/.local/bin/codex" login status
```

If needed, start the headless ChatGPT login flow and let the user complete it:

```bash
CODEX_HOME="$HOME/.codex" "$HOME/.local/bin/codex" login --device-auth
```

Account login and remote pairing are separate steps. Preserve the selected
Codex home across restarts so authentication, pairing identity, and threads
survive. Do not copy another machine's databases or installation identity.

## Install the persistent service

Use the bundled [supervisor](scripts/codex-worker.sh) and
[user service](assets/codex-worker.service). From this skill's directory:

```bash
install -Dm755 scripts/codex-worker.sh "$HOME/.local/libexec/codex-worker.sh"
install -Dm644 assets/codex-worker.service \
  "$HOME/.config/systemd/user/codex-worker.service"
```

Before starting, adjust `CODEX_HOME` and `CODEX_BIN` in the installed unit if
they differ from the defaults. Include any environment variables needed by the
user's tools; a systemd service does not read the interactive shell's startup
files. Preserve unrelated existing configuration.

For startup without an interactive login and survival after logout, enable
lingering for this user:

```bash
loginctl enable-linger "$USER"
loginctl show-user "$USER" -p Linger
systemctl --user daemon-reload
systemctl --user enable --now codex-worker.service
```

If enabling linger needs administrator privileges, report that specific
requirement; do not claim reboot persistence until it is enabled.

The supervisor calls `app-server daemon bootstrap --remote-control` at startup,
then the idempotent `app-server daemon start` every minute. Codex manages its
own daemon identity and serializes lifecycle changes, including updates. No
PID-file parsing or separate foreground app-server is needed. Manage this
instance through systemd so a manual stop is not undone by the next check.

## Pair and open a project

Once the service is healthy, generate a code if the app is not already paired:

```bash
CODEX_HOME="$HOME/.codex" "$HOME/.local/bin/codex" remote-control pair
```

Give the short-lived code to the user to enter in the app. Keep it out of
committed files and persistent setup notes. Confirm the app connects to this
devbox, then open any project folder through the remote app.

For a local terminal session using the same state:

```bash
cd /absolute/path/to/project
CODEX_HOME="$HOME/.codex" "$HOME/.local/bin/codex"
```

## Verify and manage

```bash
systemctl --user is-enabled codex-worker.service
systemctl --user status codex-worker.service --no-pager
journalctl --user -u codex-worker.service -n 50 --no-pager
CODEX_HOME="$HOME/.codex" "$HOME/.local/bin/codex" app-server daemon version
```

An active supervisor alone does not prove remote connectivity. Confirm the
daemon responds and a project or saved thread opens from the paired app.
Reconnect after closing the setup SSH session and check it again. Report boot
configuration separately from an actual reboot test; reboot only when asked.

```bash
systemctl --user restart codex-worker.service
systemctl --user stop codex-worker.service
# To also prevent startup on future boots:
systemctl --user disable --now codex-worker.service
```

Restarting interrupts active work. Preserve the Codex home when stopping or
disabling the service; the next start should retain pairing and threads.
